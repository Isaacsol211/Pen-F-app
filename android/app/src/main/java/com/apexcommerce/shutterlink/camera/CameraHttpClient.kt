package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// HTTP client shared by the HTTP-based drivers (Olympus, Panasonic, Canon CCAPI, Sony); port of
// CameraHTTPClient.swift. It serialises requests (cameras handle one at a time), logs them for the
// Request log, and turns non-2xx replies into CameraHttpException.
//
// Olympus OI.Share specifics: the camera is an access point at 192.168.0.10 and answers plain
// HTTP/1.1 on port 80:  GET /<command>.cgi?opt1=v1&opt2=v2 (option order matters), and
// POST /set_camprop.cgi?com=set&propname=X with body <?xml version="1.0"?><set><value>…</value></set>.
// It wants an OI.Share-style User-Agent. 200/202 = success, 520 = refused (wrong mode, bad value…).

class CameraHttpException(val status: Int, val path: String, val body: String) : IOException() {
    override val message: String
        get() {
            var text = "${path.substringBefore('?')} → HTTP $status"
            val code = MiniXml.parse(body)?.firstDescendant("errorcode", "Errorcode")?.trimmedText
            if (code != null) {
                text += " (camera error $code)"
            } else {
                runCatching { JSONObject(body).optString("message").takeIf { it.isNotEmpty() } }.getOrNull()?.let {
                    text += " ($it)"   // Canon CCAPI
                }
            }
            when (status) {
                520 -> text += ". The camera refused it; it may be in the wrong mode or the value isn't allowed right now."
                503 -> text += ". The camera is busy."
            }
            return text
        }
}

/**
 * Whether [host] is on the local network: a private, link-local or loopback IP address, an unqualified
 * name or a .local name. Cameras only speak plain HTTP (and PTP/IP) on their own Wi-Fi, so every
 * connection is checked against this and nothing unencrypted goes to the internet, even if a typed
 * address or a camera's reply points elsewhere. Same rule as NetworkInfo.isLocal on iOS.
 */
fun isLocalHost(host: String): Boolean {
    val name = host.trim('[', ']').lowercase()
    if (name == "localhost" || name.endsWith(".local")) return true
    val octets = name.split(".").map { it.toIntOrNull() }
    if (octets.size == 4 && octets.all { it != null && it in 0..255 }) {
        val a = octets[0]!!
        val b = octets[1]!!
        return a == 10 || a == 127 || (a == 172 && b in 16..31) || (a == 192 && b == 168) || (a == 169 && b == 254)
    }
    if (name.contains(':')) { // IPv6: loopback, link-local (fe80::/10), unique local (fc00::/7)
        return name == "::1" || listOf("fe8", "fe9", "fea", "feb", "fc", "fd").any { name.startsWith(it) }
    }
    // An unqualified name (no dots) can only be resolved on the local network.
    return name.isNotEmpty() && !name.contains('.') && name.all { it.isLetterOrDigit() || it == '-' }
}

/** Shared OkHttp pools: one for queued commands, one that skips the queue for urgent stops. */
object Http {
    val base: OkHttpClient by lazy {
        OkHttpClient.Builder()
            // Every client is built from this one, so this covers commands, probes and Sony's live view.
            .addInterceptor { chain ->
                val host = chain.request().url.host
                if (!isLocalHost(host)) {
                    throw IOException("$host isn't on a local network. Shutterlink only connects to cameras over their own Wi-Fi.")
                }
                chain.proceed(chain.request())
            }
            .connectTimeout(5, TimeUnit.SECONDS)
            // Long exposures hold the reply open; each call sets its own overall timeout.
            .readTimeout(0, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
            .followRedirects(false)
            .connectionPool(ConnectionPool(2, 30, TimeUnit.SECONDS))
            .build()
    }

    /** Short probes (auto-detect). */
    val probe: OkHttpClient by lazy {
        base.newBuilder().connectTimeout(3, TimeUnit.SECONDS).callTimeout(3, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS)).build()
    }
}

/** Runs an OkHttp call without blocking a thread; cancelling the coroutine cancels the call. */
suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { runCatching { cancel() } }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (cont.isActive) cont.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            if (cont.isActive) cont.resume(response) else response.close()
        }
    })
}

class CameraHttpClient(
    val host: String,
    val userAgent: String,
    /** Statuses that count as success (Canon CCAPI answers 200-204). */
    val allowedStatus: IntRange = 200..202,
    private val onLog: (LogEntry) -> Unit = {},
) {
    private val client = Http.base.newBuilder().connectionPool(ConnectionPool(1, 30, TimeUnit.SECONDS)).build()
    /** Separate connection that skips the queue, for stopping a running exposure. */
    private val urgentClient = Http.base.newBuilder().connectionPool(ConnectionPool(1, 30, TimeUnit.SECONDS)).build()
    private val gate = Mutex()

    /** Sent with every command to the camera's own path (not absolute URLs), e.g. LUMIX's X-SESSION_ID. */
    @Volatile
    var extraHeaders: Map<String, String> = emptyMap()

    /** Bypasses the one-at-a-time queue (stoptake while a starttake may still be open). */
    suspend fun getUrgent(cgi: String, params: List<Pair<String, String>> = emptyList()): ByteArray =
        perform(urgentClient, "GET", path(cgi, params), null, null, 10.0, true, emptyMap())

    suspend fun get(cgi: String, params: List<Pair<String, String>> = emptyList(), timeout: Double = 10.0, log: Boolean = true): ByteArray =
        send("GET", path(cgi, params), null, null, timeout, log)

    suspend fun post(cgi: String, params: List<Pair<String, String>>, xml: String): ByteArray =
        send("POST", path(cgi, params), xml.toByteArray(), "text/plain;charset=utf-8", 10.0, true)

    /** Full-size file straight off the card, e.g. /DCIM/100OLYMP/P1010001.JPG */
    suspend fun download(path: String, timeout: Double = 180.0): ByteArray = send("GET", path, null, null, timeout, true)

    /** GET an absolute URL (Panasonic serves photos from its UPnP server on another port). */
    suspend fun fetch(url: String?, timeout: Double = 30.0, log: Boolean = true): ByteArray {
        if (url == null) throw CameraException("The camera gave no address for this file.")
        return send("GET", url, null, null, timeout, log)
    }

    /** Thumbnail of a card file served by URL (LUMIX UPnP, Sony avContent), or null. */
    suspend fun fetchThumbnail(image: CameraImage): Bitmap? =
        image.urls?.let { u -> attempt { fetch(u.thumbnail ?: u.preview ?: u.original, log = false) } }?.let { decodeImage(it) }

    suspend fun fetchPreview(image: CameraImage): Bitmap =
        decodeImage(fetch(image.urls?.let { it.preview ?: it.thumbnail ?: it.original }))
            ?: throw CameraException("Couldn't decode the preview.")

    /** POST a SOAP request (UPnP ContentDirectory). */
    suspend fun soap(url: String, action: String, body: String): ByteArray =
        send("POST", url, body.toByteArray(), "text/xml; charset=\"utf-8\"", 20.0, true,
            mapOf("SOAPACTION" to "\"$action\""))

    /** Any method, path (or absolute URL) and JSON body: Canon CCAPI's PUTs, Sony's JSON-RPC. */
    suspend fun request(
        method: String, path: String, json: Any? = null, timeout: Double = 10.0,
        log: Boolean = true, urgent: Boolean = false,
    ): ByteArray {
        val body = json?.let { (if (it is Map<*, *>) JSONObject(it) else it).toString().toByteArray() }
        val type = if (json != null) "application/json" else null
        // OkHttp insists on a body for POST/PUT.
        val sendBody = body ?: if (method == "POST" || method == "PUT") ByteArray(0) else null
        return if (urgent) perform(urgentClient, method, path, sendBody, type, timeout, log, emptyMap())
        else send(method, path, sendBody, type, timeout, log)
    }

    /** Like `request`, decoding a JSON object reply (empty for an empty body). */
    suspend fun requestJson(
        method: String, path: String, json: Any? = null, timeout: Double = 10.0,
        log: Boolean = true, urgent: Boolean = false,
    ): JSONObject {
        val data = request(method, path, json, timeout, log, urgent)
        if (data.isEmpty()) return JSONObject()
        return try {
            JSONObject(String(data))
        } catch (ignored: Exception) {
            throw CameraException("The camera's reply to $path wasn't JSON.")
        }
    }

    private suspend fun send(
        method: String, path: String, body: ByteArray?, contentType: String?, timeout: Double, log: Boolean,
        headers: Map<String, String> = emptyMap(),
    ): ByteArray = gate.withLock { perform(client, method, path, body, contentType, timeout, log, headers) }

    private suspend fun perform(
        http: OkHttpClient, method: String, path: String, body: ByteArray?, contentType: String?,
        timeout: Double, log: Boolean, headers: Map<String, String>,
    ): ByteArray {
        val absolute = path.startsWith("http")
        val address = if (absolute) path else "http://$host$path"
        val builder = try {
            Request.Builder().url(address)
        } catch (ignored: IllegalArgumentException) {
            throw CameraException("Bad camera address: $host")
        }
        builder.header("User-Agent", userAgent)
        if (!absolute) extraHeaders.forEach { (k, v) -> builder.header(k, v) }
        headers.forEach { (k, v) -> builder.header(k, v) }
        val requestBody = body?.toRequestBody(contentType?.toMediaType())
        builder.method(method, requestBody)
        val call = http.newCall(builder.build())
        call.timeout().timeout((timeout * 1000).toLong(), TimeUnit.MILLISECONDS)

        val started = System.currentTimeMillis()
        val (status, type, data) = try {
            // The body is read off the main thread (Android forbids network reads there).
            withContext(Dispatchers.IO) {
                call.await().use { response ->
                    Triple(response.code, response.header("Content-Type") ?: "", response.body?.bytes() ?: ByteArray(0))
                }
            }
        } catch (e: IOException) {
            debugLog("$method $address FAILED after ${System.currentTimeMillis() - started} ms: $e")
            if (log) onLog(LogEntry(started, method, path, null, System.currentTimeMillis() - started, describeIo(e)))
            throw e
        }
        val ms = System.currentTimeMillis() - started
        debugLog("$method $address → $status ($ms ms, ${data.size} bytes) ${if (data.size < 4000) summarize(data, type) else ""}")
        if (log || status !in allowedStatus) onLog(LogEntry(started, method, path, status, ms, summarize(data, type)))
        if (status !in allowedStatus) throw CameraHttpException(status, path, String(data.copyOf(minOf(600, data.size))))
        return data
    }

    companion object {
        fun path(cgi: String, params: List<Pair<String, String>>): String =
            "/$cgi.cgi" + if (params.isEmpty()) "" else "?" + params.joinToString("&") { "${it.first}=${it.second}" }

        fun summarize(data: ByteArray, type: String): String {
            if (type.startsWith("image/") || type.contains("octet-stream") || type.startsWith("video/")) {
                return "$type · ${byteCount(data.size.toLong())}"
            }
            if (data.isEmpty()) return "(empty)"
            var text = String(data.copyOf(minOf(800, data.size)))
            text = text.replace(Regex("""<\?xml[^>]*\?>"""), "").replace(Regex("""\s+"""), " ")
            return text.trim().take(240)
        }

        fun describeIo(e: IOException): String = when (e) {
            is SocketTimeoutException -> "timed out"
            is ConnectException -> "connection refused"
            is NoRouteToHostException -> "no route to host"
            is UnknownHostException -> "unknown host"
            else -> e.message ?: e.javaClass.simpleName
        }
    }
}

fun byteCount(bytes: Long): String = when {
    bytes >= 1_000_000_000 -> fmt("%.1f GB", bytes / 1e9)
    bytes >= 1_000_000 -> fmt("%.1f MB", bytes / 1e6)
    bytes >= 1_000 -> fmt("%.0f KB", bytes / 1e3)
    else -> "$bytes bytes"
}

/** Debug output, visible with `adb logcat -s Shutterlink`. */
fun debugLog(message: String) {
    android.util.Log.d("Shutterlink", message)
}

fun JSONArray.toList(): List<Any?> = (0 until length()).map { opt(it).let { v -> if (v == JSONObject.NULL) null else v } }
fun JSONObject.stringList(key: String): List<String> =
    optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.opt(it) as? String } } ?: emptyList()

/**
 * One line of get_imglist.cgi: "/DCIM/100OLYMP,P1010001.JPG,5824512,0,19312,40061"
 * (directory, name, size, attribute bits, FAT date, FAT time). The first line is a "VER_100" header.
 */
object ImageListParser {
    fun parse(text: String): List<CameraImage> = text.lines().mapNotNull { line ->
        val f = line.split(",").map { it.trim() }
        if (f.size < 6) return@mapNotNull null
        val size = f[2].toLongOrNull() ?: return@mapNotNull null
        val attr = f[3].toIntOrNull() ?: return@mapNotNull null
        val date = f[4].toIntOrNull() ?: return@mapNotNull null
        val time = f[5].toIntOrNull() ?: return@mapNotNull null
        if (attr and 2 != 0) return@mapNotNull null   // hidden
        CameraImage(f[0], f[1], size, attr, fatDate(date, time))
    }

    fun fatDate(d: Int, t: Int): Long {
        val c = Calendar.getInstance()
        c.clear()
        c.set(1980 + (d shr 9), ((d shr 5) and 15) - 1, d and 31, t shr 11, (t shr 5) and 63, (t and 31) * 2)
        return c.timeInMillis
    }
}
