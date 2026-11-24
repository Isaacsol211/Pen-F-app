package com.apexcommerce.shutterlink.camera

import android.content.SharedPreferences
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
                SavedCamera(brand, o.optString("name"), o.optString("host"), o.optLong("lastUsed"))
            }.sortedByDescending { it.lastUsed }
        }.getOrDefault(emptyList())
    }

    fun save(prefs: SharedPreferences, cameras: List<SavedCamera>) {
        val array = JSONArray()
        cameras.forEach {
            array.put(JSONObject().put("brand", it.brand.id).put("name", it.name).put("host", it.host).put("lastUsed", it.lastUsed))
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }
}

/** Called once a connection succeeds: adds the camera to the home screen, or moves it to the top. */
fun CameraModel.rememberConnectedCamera() {
    val name = cameraName?.takeIf { it.isNotEmpty() } ?: brand.title
    val address = activeHost ?: host
    val saved = SavedCamera(brand, name, if (address == brand.defaultHost) "" else address, System.currentTimeMillis())
    val list = listOf(saved) + savedCameras.filter { it.id != saved.id }
    savedCameras = list
    SavedCameras.save(prefs, list)
}

fun CameraModel.forget(saved: SavedCamera) {
    savedCameras = savedCameras.filter { it.id != saved.id }
    SavedCameras.save(prefs, savedCameras)
}

/** Reconnects to a camera from the home screen: its brand and address, no auto-detect. */
suspend fun CameraModel.connect(saved: SavedCamera) {
    if (phase != ConnectionPhase.DISCONNECTED) return
    brand = saved.brand
    autoDetectBrand = false
    host = saved.host.ifEmpty { saved.brand.defaultHost }
    capabilities = saved.brand.defaultCapabilities
    connect()
}
