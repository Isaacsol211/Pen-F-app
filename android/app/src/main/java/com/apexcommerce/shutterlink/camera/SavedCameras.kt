package com.apexcommerce.shutterlink.camera

import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** A camera this phone has connected to, for one-tap reconnecting from the home screen. */
data class SavedCamera(
    val brand: CameraBrand,
    /** What the camera called itself (or its model-table name), e.g. "PEN-F", "LUMIX GH5". */
    val name: String,
    /** The address it answered at; empty for the brand's usual one. */
    val host: String,
    val lastUsed: Long,
    /** The camera's Wi-Fi network when Shutterlink joined it itself (password in CameraWifiPasswords). */
    val ssid: String? = null,
) {
    /** Brand and model, e.g. "olympus|PEN-F". */
    val id: String get() = brand.id + "|" + name
}

object SavedCameras {
    private const val KEY = "savedCameras"

    fun load(prefs: SharedPreferences): List<SavedCamera> = runCatching {
        val array = JSONArray(prefs.getString(KEY, null) ?: return emptyList())
        (0 until array.length()).mapNotNull { i ->
            val o = array.getJSONObject(i)
            val brand = CameraBrand.fromId(o.optString("brand")) ?: return@mapNotNull null
            SavedCamera(brand, o.optString("name"), o.optString("host"), o.optLong("lastUsed"),
                o.optString("ssid").takeIf { it.isNotEmpty() })
        }.sortedByDescending { it.lastUsed }
    }.getOrDefault(emptyList())

    fun save(prefs: SharedPreferences, cameras: List<SavedCamera>) {
        val array = JSONArray(cameras.map {
            // putOpt leaves out a null ssid.
            JSONObject().put("brand", it.brand.id).put("name", it.name).put("host", it.host).put("lastUsed", it.lastUsed).putOpt("ssid", it.ssid)
        })
        prefs.edit().putString(KEY, array.toString()).apply()
    }
}

/**
 * Called once a connection succeeds: adds the camera to the home screen, or moves it to the top, with
 * the Wi-Fi network it's on.
 */
suspend fun CameraModel.rememberConnectedCamera() {
    val name = cameraName?.takeIf { it.isNotEmpty() } ?: brand.title
    val address = activeHost ?: host
    val base = SavedCamera(brand, name, if (address == brand.defaultHost) "" else address, System.currentTimeMillis())
    // `joinedNetwork` is the last network Shutterlink joined, but the phone may have moved to another
    // camera's network in Settings since. It belongs to this camera only if the phone is on it now or,
    // when Android won't say (no location permission), if this is the camera it was joined for.
    val current = CameraNetwork.wifiSsid()
    val joined = joinedNetwork?.takeIf { network ->
        if (current != null) current == network.ssid else connectingTo?.let { it.id == base.id } ?: true
    }
    val ssid = when {
        joined != null -> {
            // The Keystore can take a second or two: not on the main thread.
            scope.launch(Dispatchers.IO) { CameraWifiPasswords.save(this@rememberConnectedCamera, joined.password, joined.ssid) }
            joined.ssid
        }
        current != null -> {
            // Joined in Settings: Shutterlink can rejoin it if it's open or the password is known.
            val known = withContext(Dispatchers.IO) { CameraWifiPasswords.password(this@rememberConnectedCamera, current) } != null
            current.takeIf { known || CameraNetwork.wifiIsOpen() == true }
        }
        else -> savedCameras.firstOrNull { it.id == base.id }?.ssid
    }
    val saved = base.copy(ssid = ssid)
    val list = listOf(saved) + savedCameras.filter { it.id != saved.id }
    savedCameras = list
    SavedCameras.save(prefs, list)
}

fun CameraModel.forget(saved: SavedCamera) {
    val ssid = saved.ssid
    if (ssid != null && savedCameras.none { it.id != saved.id && it.ssid == ssid }) CameraWifiPasswords.delete(this, ssid)
    savedCameras = savedCameras.filter { it.id != saved.id }
    SavedCameras.save(prefs, savedCameras)
}

/**
 * Reconnects to a camera from the home screen: its brand and address, no auto-detect. When Shutterlink
 * joined the camera's Wi-Fi before, it joins it again first, so one tap does it all.
 */
suspend fun CameraModel.connect(saved: SavedCamera) {
    if (phase != ConnectionPhase.DISCONNECTED) return
    brand = saved.brand
    autoDetectBrand = false
    host = saved.host.ifEmpty { saved.brand.defaultHost }
    capabilities = saved.brand.defaultCapabilities
    connectingTo = saved
    try {
        joinAndConnect(savedNetwork(saved))
    } finally {
        connectingTo = null
    }
    // Without a network to join, whichever camera of that brand the phone is on answers.
    val other = savedCameras.firstOrNull()
    if (phase == ConnectionPhase.CONNECTED && other != null && other.id != saved.id) {
        showToast("This is the ${other.name}, not the ${saved.name}")
    }
}
