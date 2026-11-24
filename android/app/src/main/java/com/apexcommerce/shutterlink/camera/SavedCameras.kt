package com.apexcommerce.shutterlink.camera

import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
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

    fun load(prefs: SharedPreferences): List<SavedCamera> {
        val text = prefs.getString(KEY, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(text)
            (0 until array.length()).mapNotNull { i ->
                val o = array.getJSONObject(i)
                val brand = CameraBrand.fromId(o.optString("brand")) ?: return@mapNotNull null
                SavedCamera(brand, o.optString("name"), o.optString("host"), o.optLong("lastUsed"),
                    o.optString("ssid").takeIf { it.isNotEmpty() })
            }.sortedByDescending { it.lastUsed }
        }.getOrDefault(emptyList())
    }

    fun save(prefs: SharedPreferences, cameras: List<SavedCamera>) {
        val array = JSONArray()
        cameras.forEach {
            val o = JSONObject().put("brand", it.brand.id).put("name", it.name).put("host", it.host).put("lastUsed", it.lastUsed)
            it.ssid?.let { ssid -> o.put("ssid", ssid) }
            array.put(o)
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }
}

/** Called once a connection succeeds: adds the camera to the home screen, or moves it to the top. */
fun CameraModel.rememberConnectedCamera() {
    val name = cameraName?.takeIf { it.isNotEmpty() } ?: brand.title
    val address = activeHost ?: host
    var saved = SavedCamera(brand, name, if (address == brand.defaultHost) "" else address, System.currentTimeMillis())
    val network = joinedNetwork
    saved = if (network != null) {
        // The Keystore can take a second or two: not on the main thread.
        scope.launch(Dispatchers.IO) { CameraWifiPasswords.save(this@rememberConnectedCamera, network.password, network.ssid) }
        saved.copy(ssid = network.ssid)
    } else {
        saved.copy(ssid = savedCameras.firstOrNull { it.id == saved.id }?.ssid)
    }
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
    val network = savedNetwork(saved)
    if (network != null) {
        if (!join(network)) return
        connect(waitUntil = System.currentTimeMillis() + 30_000)
    } else {
        connect()
    }
}
