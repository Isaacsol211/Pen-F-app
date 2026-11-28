package com.apexcommerce.shutterlink.camera

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// One-tap Wi-Fi joining (port of CameraWiFi.swift): read the QR code on the camera's screen (or the
// typed name and password), join the camera's Wi-Fi from the app, connect, and remember the network
// with the camera so its card joins and connects in one go next time.

/** A camera's own Wi-Fi network: what the camera shows under its QR code. */
data class WifiCredentials(val ssid: String, val password: String)

/**
 * Reads a camera's Wi-Fi QR code. Most brands don't document the code's contents, so this reads the
 * formats that are known and otherwise leaves the user to type what the camera shows under the code.
 */
object WifiQrCode {
    /** The brand a code's format gives away (Olympus' OIS codes, Sony's W01 codes). */
    fun brand(text: String): CameraBrand? {
        val upper = text.trim().uppercase()
        return if (upper.startsWith("OIS")) CameraBrand.OLYMPUS else if (upper.startsWith("W01:")) CameraBrand.SONY else null
    }

    fun parse(text: String): WifiCredentials? {
        val trimmed = text.trim()
        val upper = trimmed.uppercase()
        // The common Wi-Fi QR format: WIFI:S:<name>;T:WPA;P:<password>;;
        if (upper.startsWith("WIFI:")) {
            val f = fields(trimmed.drop(5))
            val ssid = f["S"]?.takeIf { it.isNotEmpty() } ?: return null
            return WifiCredentials(ssid, f["P"] ?: "")
        }
        // Olympus / OM System: OIS1,<name>,<password>, each scrambled (see `olympusDecode`).
        if (upper.startsWith("OIS")) {
            val parts = trimmed.split(",").takeIf { it.size >= 3 } ?: return null
            val ssid = olympusDecode(parts[1]).trim().ifEmpty { return null }
            return WifiCredentials(ssid, olympusDecode(parts[2]).trim())
        }
        // Sony bodies: W01:S:<name>;P:<password>;C:<model>;M:<MAC>; with the name given without its
        // DIRECT- prefix. Not yet checked on a real Sony camera; the fields stay editable.
        if (upper.startsWith("W01:")) {
            val f = fields(trimmed.drop(4))
            var ssid = f["S"]?.takeIf { it.isNotEmpty() } ?: return null
            val password = f["P"] ?: return null
            if (!ssid.uppercase().startsWith("DIRECT-")) ssid = "DIRECT-$ssid"
            return WifiCredentials(ssid, password)
        }
        return null
    }

    /**
     * Olympus scrambles the name and password by mirroring each character in this alphabet (first ↔
     * last, second ↔ second-to-last…). Worked out from a real PEN-F's code against the name and password
     * it shows (PEN-F-P-BHNA17694 → GRI1Q1G1UOIV-YZW%; the self-test checks the password too). Characters outside the
     * alphabet are kept as they are.
     */
    private const val OLYMPUS_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\$%*+-/"

    fun olympusDecode(text: String): String = text.map { c ->
        val index = OLYMPUS_ALPHABET.indexOf(c)
        if (index < 0) c else OLYMPUS_ALPHABET[OLYMPUS_ALPHABET.length - 1 - index]
    }.joinToString("")

    /** `K:value;K:value;` with `\` escaping `;`, `:`, `,`, `"` and `\`. */
    private fun fields(text: String): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        val key = StringBuilder()
        val value = StringBuilder()
        var readingKey = true
        var escaped = false
        fun finish() {
            if (key.isNotEmpty() && key.toString() !in result) result[key.toString()] = value.toString()
            key.clear(); value.clear(); readingKey = true
        }
        for (c in text) {
            when {
                escaped -> {
                    (if (readingKey) key else value).append(c)
                    escaped = false
                }
                c == '\\' -> escaped = true
                c == ';' -> finish()
                c == ':' && readingKey -> readingKey = false
                readingKey -> key.append(c)
                else -> value.append(c)
            }
        }
        finish()
        return result
    }
}

/**
 * Camera Wi-Fi passwords, keyed by network name: encrypted with an AES key that lives in the Android
 * Keystore (it never leaves the device's secure hardware), the ciphertext kept in the app's preferences.
 */
object CameraWifiPasswords {
    private const val KEY_ALIAS = "shutterlink.camera-wifi"
    private const val PREFIX = "wifi.pw."

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    fun save(camera: CameraModel, password: String, ssid: String) {
        runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(password.toByteArray())
            camera.prefs.edit().putString(PREFIX + ssid, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
        }.onFailure { debugLog("keystore: couldn't save the password for $ssid ($it)") }
    }

    fun password(camera: CameraModel, ssid: String): String? = runCatching {
        val sealed = Base64.decode(camera.prefs.getString(PREFIX + ssid, null) ?: return null, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed.copyOfRange(0, 12)))
        String(cipher.doFinal(sealed.copyOfRange(12, sealed.size)))
    }.getOrNull()

    fun delete(camera: CameraModel, ssid: String) {
        camera.prefs.edit().remove(PREFIX + ssid).apply()
    }
}

// MARK: - Joining, then connecting

/** Joins `network`, showing progress like a connection does. Returns false (with `lastError` set) when it couldn't. */
suspend fun CameraModel.join(network: WifiCredentials): Boolean {
    if (phase != ConnectionPhase.DISCONNECTED) return true
    val ssid = network.ssid.trim()
    if (ssid.isEmpty()) {
        lastError = "Type the camera's Wi-Fi name first."
        return false
    }
    if (network.password.isNotEmpty() && network.password.length !in 8..63) {
        lastError = "That password isn't one Wi-Fi accepts (8–63 characters). Check it on the camera."
        return false
    }
    // Already on it (joined in Settings, or still held from last time): nothing to ask Android for.
    if (CameraNetwork.wifiSsid() == ssid) {
        debugLog("wifi: already on $ssid")
        joinedNetwork = network.copy(ssid = ssid)
        return true
    }
    phase = ConnectionPhase.CONNECTING
    lastError = null
    status = "Joining $ssid…"
    debugLog("wifi: joining $ssid")
    try {
        val error = CameraNetwork.join(ssid, network.password.ifEmpty { null })
        if (error != null) {
            debugLog("wifi: $error")
            lastError = error
            return false
        }
        joinedNetwork = network.copy(ssid = ssid)
        return true
    } finally {
        phase = ConnectionPhase.DISCONNECTED
        status = null
    }
}

/** Add a camera's Connect: joins the typed or scanned network first when there is one. */
suspend fun CameraModel.joinAndConnect() {
    joinAndConnect(WifiCredentials(wifiSsid.trim(), wifiPassword).takeIf { it.ssid.isNotEmpty() })
}

/** Joins `network` first when there is one, then connects, giving the phone 30 s to get onto it. */
suspend fun CameraModel.joinAndConnect(network: WifiCredentials?) {
    if (network == null) connect()
    else if (join(network)) connect(waitUntil = System.currentTimeMillis() + 30_000)
}

/** The network saved with this camera, if Shutterlink joined it before. (The Keystore is slow: off the main thread.) */
suspend fun CameraModel.savedNetwork(saved: SavedCamera): WifiCredentials? {
    val ssid = saved.ssid?.takeIf { it.isNotEmpty() } ?: return null
    val password = withContext(Dispatchers.IO) { CameraWifiPasswords.password(this@savedNetwork, ssid) }
    return WifiCredentials(ssid, password ?: "")
}

/** Fills Add a camera from a scanned QR code. Returns false when the code isn't one Shutterlink reads. */
fun CameraModel.applyScannedCode(text: String): Boolean {
    // The request log shows the code's format (so a brand's format can be added from a real camera),
    // never the code itself: it holds the camera's Wi-Fi password, and the log can be copied.
    val network = WifiQrCode.parse(text)
    val trimmed = text.trim()
    val format = trimmed.takeWhile { it != ':' && it != ',' }.take(12)
    appendLog(LogEntry(System.currentTimeMillis(), "QR", "$format code, ${trimmed.length} characters (contents hidden)",
        if (network == null) null else 200, 0,
        network?.let { "Wi-Fi ${it.ssid}" } ?: "not a code Shutterlink reads yet"))
    network ?: return false
    wifiSsid = network.ssid
    wifiPassword = network.password
    WifiQrCode.brand(text)?.let { selectBrand(it) }
    return true
}

/**
 * Scan to connect: reads the code, joins the camera's Wi-Fi and connects, all in one go. Codes that
 * don't say the brand use automatic detection. Returns false when the code isn't readable.
 */
fun CameraModel.connectFromScannedCode(text: String): Boolean {
    if (phase != ConnectionPhase.DISCONNECTED) return false
    if (WifiQrCode.brand(text) == null) selectBrand(null)
    if (!applyScannedCode(text)) return false
    scope.launch { joinAndConnect() }
    return true
}
