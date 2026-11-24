package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Request
import okio.Buffer
import java.util.concurrent.TimeUnit

/**
 * Reads an HTTP response that never ends (Sony's live-view stream) and hands out complete frames as
 * `parse` finds them in the bytes received so far (port of LiveStreams.swift's HTTPStreamReader).
 *
 * `parse` removes complete frames from the front of the buffer and returns them. `onFrame` and
 * `onEnd` are called on a background thread. `onEnd` is not called after `stop()`.
 */
class HttpStreamReader(
    private val url: String,
    private val parse: (Buffer) -> List<ByteArray>,
) {
    var onFrame: ((ByteArray) -> Unit)? = null
    var onEnd: ((Throwable?) -> Unit)? = null

    private var job: Job? = null
    @Volatile private var call: Call? = null

    fun start(scope: CoroutineScope) {
        job = scope.launch(Dispatchers.IO) {
            val error: Throwable? = try {
                val c = client.newCall(Request.Builder().url(url).build())
                call = c
                c.execute().use { response ->
                    if (!response.isSuccessful) throw CameraHttpException(response.code, url, "")
                    val source = response.body?.source() ?: throw CameraException("The live-view stream had no body.")
                    val buffer = Buffer()
                    while (isActive) {
                        if (source.read(buffer, 64L * 1024) == -1L) break
                        val frames = parse(buffer)
                        if (buffer.size > (8L shl 20)) buffer.clear()   // lost sync; start over
                        for (frame in frames) onFrame?.invoke(frame)
                    }
                }
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                e
            }
            if (isActive) onEnd?.invoke(error)
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        call?.cancel()
        call = null
    }

    private companion object {
        /** Its own pool, so a stream never holds the connection commands need; 10 s without data ends it. */
        val client: OkHttpClient by lazy {
            Http.base.newBuilder()
                .readTimeout(10, TimeUnit.SECONDS)
                .connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS))
                .build()
        }
    }
}
