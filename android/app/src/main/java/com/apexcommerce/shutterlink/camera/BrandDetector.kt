package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Works out which brand of camera is on the other end, so friends don't have to pick (port of
 * BrandDetector.swift). Each brand's access point uses its own subnet, so the phone's Wi-Fi address
 * narrows it down; then the app asks each candidate a harmless read-only question in its own
 * protocol. Nothing here takes a picture or changes a setting.
 */
object BrandDetector {
    /** The brands whose camera networks use this phone address's subnet, most likely first. */
    fun candidates(wifi: String?): List<CameraBrand> {
        if (wifi == null) return CameraBrand.entries
        return when {
            wifi.startsWith("192.168.0.") -> listOf(CameraBrand.OLYMPUS)
            wifi.startsWith("192.168.54.") -> listOf(CameraBrand.PANASONIC)
            wifi.startsWith("192.168.122.") -> listOf(CameraBrand.SONY)
            wifi.startsWith("192.168.1.") -> listOf(CameraBrand.NIKON, CameraBrand.CANON)
            else -> CameraBrand.entries
        }
    }

    /** A short hint for the Connect screen ("Looks like a Nikon network"). */
    fun hint(wifi: String?): String? {
        val brands = candidates(wifi)
        if (brands.size >= CameraBrand.entries.size) return null
        return brands.joinToString(" or ") { it.shortTitle }
    }

    /**
     * With `host` empty: probe each candidate brand at its usual address. With a host (a mock, or a
     * camera on another network): ask that address in every protocol.
     */
    suspend fun detect(host: String): Pair<CameraBrand, String>? {
        detectOnce(host)?.let { return it }
        delay(1500)
        return detectOnce(host)
    }

    private suspend fun detectOnce(host: String): Pair<CameraBrand, String>? = coroutineScope {
        val trimmed = host.trim()
        val targets = if (trimmed.isEmpty()) {
            candidates(CameraNetwork.wifiAddress()).flatMap { brand -> brand.likelyHosts.map { brand to it } }
        } else {
            CameraBrand.entries.map { it to trimmed }
        }
        // Ask everyone at once; prefer the HTTP brands' specific answers over Nikon's bare
        // "something listens on the PTP/IP port".
        val results = targets.mapIndexed { index, target ->
            async(Dispatchers.IO) { if (probe(target.first, target.second)) index to target else null }
        }.awaitAll().filterNotNull()
        results.sortedWith(compareBy({ it.second.first == CameraBrand.NIKON }, { it.first })).firstOrNull()?.second
    }

    fun notFoundMessage(wifi: String?): String {
        if (wifi == null) {
            return "This phone isn't on Wi-Fi. Turn on the camera's smartphone Wi-Fi, join its network in Settings ▸ Wi-Fi (or with Join camera Wi-Fi below), then tap Connect."
        }
        return "No camera answered (this phone is at $wifi). Check that Settings ▸ Wi-Fi shows the camera's network, or pick your brand above."
    }

    // MARK: - Probes

    suspend fun probe(brand: CameraBrand, host: String): Boolean = withContext(Dispatchers.IO) {
        when (brand) {
            CameraBrand.OLYMPUS -> {
                val body = get("http://$host/get_caminfo.cgi", "OI.Share v2")
                body?.contains("<model>") == true || body?.contains("<caminfo>") == true
            }
            CameraBrand.PANASONIC -> {
                val body = get("http://$host/cam.cgi?mode=getinfo&type=capability", "LUMIX Sync")
                body != null && (body.contains("camrply") || body.startsWith("ok,") || body.startsWith("err_"))
            }
            CameraBrand.CANON -> get("http://$host/ccapi", "Shutterlink")?.contains("\"ver100\"") == true
            CameraBrand.SONY -> {
                val json = JSONObject().put("method", "getVersions").put("params", JSONArray()).put("id", 1).put("version", "1.0")
                post("http://$host/sony/camera", json.toString())?.contains("\"result\"") == true
            }
            CameraBrand.NIKON -> {
                val (name, port) = splitHost(host, 15740)
                tcpOpens(name, port)
            }
        }
    }

    private fun get(url: String, userAgent: String): String? = runCatching {
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        Http.probe.newCall(request).execute().use { r ->
            if (r.code >= 500) null else r.body?.string()?.take(4000)
        }
    }.getOrNull()

    private fun post(url: String, json: String): String? = runCatching {
        val request = Request.Builder().url(url).post(json.toRequestBody("application/json".toMediaType())).build()
        Http.probe.newCall(request).execute().use { r -> r.body?.string()?.take(4000) }
    }.getOrNull()

    /** Whether a TCP connection opens within 3 s (and then closes it again without sending anything). */
    fun tcpOpens(host: String, port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress(host, port), 3000) }
        true
    }.getOrDefault(false)
}

/** "192.168.1.1" → (host, default), "127.0.0.1:15741" → (127.0.0.1, 15741). */
fun splitHost(address: String, defaultPort: Int): Pair<String, Int> {
    val parts = address.split(":")
    if (parts.size == 2) parts[1].toIntOrNull()?.let { return parts[0] to it }
    return address to defaultPort
}
