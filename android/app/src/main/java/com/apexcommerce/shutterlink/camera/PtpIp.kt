package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.text.SimpleDateFormat
import java.util.Locale

// PTP over TCP/IP (CIPA DC-005, "PTP/IP"), as Nikon cameras speak it over their own Wi-Fi.
// Port of PTPIP.swift.
//
// Two TCP connections to port 15740: a command channel and an event channel. Every packet is
//   [UInt32 length, including these 8 bytes][UInt32 type][payload], little-endian.
// Handshake: Init Command Request (our GUID, name, version) → Init Command Ack (connection number,
// camera GUID, camera name) on the command channel, then Init Event Request (connection number)
// → Init Event Ack on the event channel. After that, PTP operations run one at a time:
//   Operation Request → [Start Data, Data…, End Data] (either direction) → Operation Response.

object PtpIpPacket {
    const val INIT_COMMAND_REQUEST = 1
    const val INIT_COMMAND_ACK = 2
    const val INIT_EVENT_REQUEST = 3
    const val INIT_EVENT_ACK = 4
    const val INIT_FAIL = 5
    const val OPERATION_REQUEST = 6
    const val OPERATION_RESPONSE = 7
    const val EVENT = 8
    const val START_DATA = 9
    const val DATA = 10
    const val CANCEL = 11
    const val END_DATA = 12
    const val PROBE_REQUEST = 13
    const val PROBE_RESPONSE = 14
}

/** A PTP response code other than OK. Not an IOException: the camera answered, it just said no. */
class PtpException(val code: Int, val operation: Int) : Exception() {
    override val message: String
        get() {
            val what = fmt("0x%04X", operation)
            return when (code) {
                0x2019 -> "The camera is busy (operation $what)."
                0x2005 -> "The camera doesn't support operation $what over Wi-Fi."
                0x200A -> "The camera refused operation $what: no card or the card is full."
                0x201C, 0x201D -> "The camera refused operation $what: the value isn't allowed now."
                0x200E -> "The camera won't let that be changed now (operation $what)."
                0x2002 -> "The camera reported a general error for operation $what."
                0xA002 -> "The camera isn't in a mode that allows this (operation $what)."
                else -> fmt("The camera answered 0x%04X to operation %s.", code, what)
            }
        }

    companion object {
        const val OK = 0x2001
        const val DEVICE_BUSY = 0x2019
    }
}

/**
 * One TCP connection with exact-length blocking reads. Reads take a deadline (ms since 1970, or
 * null to wait forever) and throw SocketTimeoutException when it passes.
 */
class TcpChannel(private val host: String, private val port: Int) {
    private val socket = Socket()
    private lateinit var input: InputStream
    private lateinit var output: OutputStream
    private val writeLock = Any()

    /** A read timed out half-way through a packet: the stream no longer starts at a packet boundary. */
    @Volatile var broken = false

    fun open(timeoutMs: Int = 5000) {
        socket.tcpNoDelay = true
        socket.keepAlive = true
        socket.connect(InetSocketAddress(host, port), timeoutMs)
        input = BufferedInputStream(socket.getInputStream(), 64 * 1024)
        output = socket.getOutputStream()
    }

    fun send(data: ByteArray) {
        synchronized(writeLock) {
            output.write(data)
            output.flush()
        }
    }

    fun receiveExactly(count: Int, deadline: Long?): ByteArray {
        if (count <= 0) return ByteArray(0)
        val out = ByteArray(count)
        var read = 0
        while (read < count) {
            if (deadline != null) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) {
                    if (read > 0) broken = true
                    throw SocketTimeoutException("No reply from the camera in time.")
                }
                socket.soTimeout = remaining.coerceIn(1L, Int.MAX_VALUE.toLong()).toInt()
            } else {
                socket.soTimeout = 0
            }
            val n = try {
                input.read(out, read, count - read)
            } catch (e: SocketTimeoutException) {
                if (read > 0) broken = true
                throw e
            }
            if (n < 0) throw EOFException("The camera closed the connection.")
            read += n
        }
        return out
    }

    fun close() {
        runCatching { socket.close() }
    }
}

/** A PTP/IP session: the handshake, then one operation at a time. */
class PtpIpClient(val host: String, val port: Int) {
    class Response(val code: Int, val params: List<Long>, val data: ByteArray)

    class Event(val code: Int, val params: List<Long>)

    @Volatile private var command: TcpChannel? = null
    @Volatile private var event: TcpChannel? = null
    /** OpenSession must use transaction ID 0; the first increment takes it there. */
    private var transactionId = -1
    private var eventScope: CoroutineScope? = null
    private var eventJob: Job? = null
    @Volatile var cameraName = ""
        private set
    /** Keeps a second operation from starting before the first has its response. */
    private val gate = Mutex()

    /** Called on a background thread with one line per operation and event. */
    @Volatile var logger: ((String) -> Unit)? = null
    /** Called on a background thread for every event from the camera. */
    @Volatile var onEvent: ((Event) -> Unit)? = null

    /** Opens both channels. `guid` identifies this phone (cameras that remember paired devices use it). */
    suspend fun connect(guid: ByteArray, name: String) = withContext(Dispatchers.IO) {
        transactionId = -1
        val command = TcpChannel(host, port)
        this@PtpIpClient.command = command
        command.open()

        val payload = ByteArrayOutputStream()
        payload.write(guid.copyOf(16))
        payload.write(utf16z(name))
        payload.writeLe32(0x0001_0000L)   // protocol version 1.0
        command.send(packet(PtpIpPacket.INIT_COMMAND_REQUEST, payload.toByteArray()))

        val (type, reply) = readPacket(command, System.currentTimeMillis() + 30_000)
        if (type == PtpIpPacket.INIT_FAIL) {
            val reason = if (reply.size >= 4) reply.readLe32(0) else 0L
            throw CameraException(fmt("The camera turned the connection down (PTP/IP Init Fail 0x%X). On the camera, allow this phone or start its Wi-Fi connection again.", reason))
        }
        if (type != PtpIpPacket.INIT_COMMAND_ACK || reply.size < 20) {
            throw CameraException("The camera didn't answer the PTP/IP handshake (packet type $type).")
        }
        val connectionNumber = reply.readLe32(0)
        cameraName = PtpReader(reply, 20).utf16zString()
        logger?.invoke("PTP/IP init ack: connection $connectionNumber, camera \"$cameraName\"")

        val event = TcpChannel(host, port)
        this@PtpIpClient.event = event
        event.open()
        val eventPayload = ByteArrayOutputStream()
        eventPayload.writeLe32(connectionNumber)
        event.send(packet(PtpIpPacket.INIT_EVENT_REQUEST, eventPayload.toByteArray()))
        val (eventType, _) = readPacket(event, System.currentTimeMillis() + 10_000)
        if (eventType != PtpIpPacket.INIT_EVENT_ACK) {
            throw CameraException("The camera didn't open its event channel (packet type $eventType).")
        }
        startEventLoop(event)
    }

    private fun startEventLoop(channel: TcpChannel) {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        eventScope = scope
        eventJob = scope.launch {
            while (isActive) {
                val (type, payload) = try {
                    readPacket(channel, null)
                } catch (ignored: Exception) {
                    return@launch
                }
                if (type == PtpIpPacket.EVENT && payload.size >= 6) {
                    val params = mutableListOf<Long>()
                    var offset = 6
                    while (offset + 4 <= payload.size) {
                        params.add(payload.readLe32(offset))
                        offset += 4
                    }
                    deliver(Event(payload.readLe16(0), params))
                } else if (type == PtpIpPacket.PROBE_REQUEST) {
                    runCatching { channel.send(packet(PtpIpPacket.PROBE_RESPONSE, ByteArray(0))) }
                }
            }
        }
    }

    private fun deliver(event: Event) {
        logger?.invoke(fmt("PTP event 0x%04X %s", event.code, event.params.joinToString(" ") { fmt("0x%X", it) }))
        onEvent?.invoke(event)
    }

    /** Closes both channels; a running operation fails with an IOException. */
    fun close() {
        eventJob?.cancel()
        eventScope?.cancel()
        eventJob = null
        eventScope = null
        command?.close()
        event?.close()
        command = null
        event = null
    }

    /**
     * One PTP operation. `dataOut` is sent to the camera (e.g. SetDevicePropValue); data the camera
     * sends back is in the response's `data`. `timeout` is in seconds, for the whole exchange.
     */
    suspend fun transaction(opcode: Int, params: List<Long> = emptyList(), dataOut: ByteArray? = null,
                            timeout: Double = 15.0): Response = gate.withLock {
        val command = command ?: throw CameraException("Not connected.")
        if (command.broken) throw IOException("lost step with the camera; reconnect")
        transactionId += 1
        val tid = transactionId.toLong() and 0xFFFF_FFFFL
        val started = System.currentTimeMillis()
        val response = withContext(Dispatchers.IO) {
            val request = ByteArrayOutputStream()
            request.writeLe32(if (dataOut == null) 1L else 2L)
            request.writeLe16(opcode)
            request.writeLe32(tid)
            for (p in params.take(5)) request.writeLe32(p)
            command.send(packet(PtpIpPacket.OPERATION_REQUEST, request.toByteArray()))

            if (dataOut != null) {
                val start = ByteArrayOutputStream()
                start.writeLe32(tid)
                start.writeLe64(dataOut.size.toLong())
                command.send(packet(PtpIpPacket.START_DATA, start.toByteArray()))
                val end = ByteArrayOutputStream()
                end.writeLe32(tid)
                end.write(dataOut)
                command.send(packet(PtpIpPacket.END_DATA, end.toByteArray()))
            }

            val deadline = started + (timeout * 1000).toLong()
            var incoming = ByteArrayOutputStream()
            var result: Response? = null
            while (result == null) {
                val (type, payload) = readPacket(command, deadline)
                // Packets for an earlier operation that timed out are skipped by transaction ID.
                when (type) {
                    PtpIpPacket.START_DATA -> if (payload.size >= 12 && payload.readLe32(0) == tid) {
                        val length = payload.readLe64(4).coerceIn(0L, 64L shl 20)
                        incoming = ByteArrayOutputStream(length.toInt().coerceAtLeast(32))
                    }
                    PtpIpPacket.DATA, PtpIpPacket.END_DATA ->
                        if (payload.size > 4 && payload.readLe32(0) == tid) incoming.write(payload, 4, payload.size - 4)
                    PtpIpPacket.OPERATION_RESPONSE -> {
                        if (payload.size < 6) throw CameraException("Short PTP response.")
                        if (payload.readLe32(2) == tid) {
                            val responseParams = mutableListOf<Long>()
                            var offset = 6
                            while (offset + 4 <= payload.size) {
                                responseParams.add(payload.readLe32(offset))
                                offset += 4
                            }
                            result = Response(payload.readLe16(0), responseParams, incoming.toByteArray())
                        }
                    }
                    PtpIpPacket.PROBE_REQUEST -> command.send(packet(PtpIpPacket.PROBE_RESPONSE, ByteArray(0)))
                }
            }
            checkNotNull(result)
        }
        val ms = System.currentTimeMillis() - started
        logger?.invoke(fmt("PTP 0x%04X %s → 0x%04X (%d ms, %d bytes)", opcode,
            params.joinToString(" ") { fmt("0x%X", it) }, response.code, ms, response.data.size))
        response
    }

    /** Like `transaction`, throwing PtpException unless the camera answered OK. */
    suspend fun run(opcode: Int, params: List<Long> = emptyList(), dataOut: ByteArray? = null,
                    timeout: Double = 15.0): Response {
        val response = transaction(opcode, params, dataOut, timeout)
        if (response.code != PtpException.OK) throw PtpException(response.code, opcode)
        return response
    }

    companion object {
        fun packet(type: Int, payload: ByteArray): ByteArray {
            val data = ByteArrayOutputStream(8 + payload.size)
            data.writeLe32(8L + payload.size)
            data.writeLe32(type.toLong())
            data.write(payload)
            return data.toByteArray()
        }

        /** One packet: its type and payload. Blocking; call on an IO thread. */
        fun readPacket(channel: TcpChannel, deadline: Long?): Pair<Int, ByteArray> {
            val header = channel.receiveExactly(8, deadline)
            val length = header.readLe32(0)
            if (length < 8 || length >= (128L shl 20)) {
                channel.broken = true
                throw IOException("Bad PTP/IP packet length $length.")
            }
            val payload = try {
                channel.receiveExactly((length - 8).toInt(), deadline)
            } catch (e: SocketTimeoutException) {
                channel.broken = true
                throw e
            }
            return header.readLe32(4).toInt() to payload
        }

        fun utf16z(text: String): ByteArray {
            val data = ByteArrayOutputStream()
            for (unit in text) data.writeLe16(unit.code)
            data.writeLe16(0)
            return data.toByteArray()
        }
    }
}

/** Swallows failures (not cancellation): for best-effort PTP calls. */
internal suspend fun <T> ptpOrNull(block: suspend () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (ignored: Exception) {
    null
}

// MARK: - PTP datasets

/** Reads PTP's little-endian fields and strings (UInt8 length in UTF-16 units, including the null). */
class PtpReader(val data: ByteArray, var offset: Int = 0) {
    val remaining: Int get() = data.size - offset

    fun u8(): Int {
        if (remaining < 1) { offset = data.size; return 0 }
        return (data[offset++].toInt() and 0xFF)
    }

    fun u16(): Int {
        if (remaining < 2) { offset = data.size; return 0 }
        val v = data.readLe16(offset)
        offset += 2
        return v
    }

    fun u32(): Long {
        if (remaining < 4) { offset = data.size; return 0 }
        val v = data.readLe32(offset)
        offset += 4
        return v
    }

    fun u64(): Long {
        if (remaining < 8) { offset = data.size; return 0 }
        val v = data.readLe64(offset)
        offset += 8
        return v
    }

    fun string(): String {
        val count = u8()
        if (count == 0) return ""
        val units = CharArray(count) { u16().toChar() }
        val length = if (units.last() == '\u0000') count - 1 else count
        return String(units, 0, length)
    }

    /** A null-terminated UTF-16 string with no length prefix (PTP/IP init packets). */
    fun utf16zString(): String {
        val sb = StringBuilder()
        while (remaining >= 2) {
            val unit = u16()
            if (unit == 0) break
            sb.append(unit.toChar())
        }
        return sb.toString()
    }

    fun u16Array(): List<Int> {
        val count = u32()
        if (count > remaining / 2) { offset = data.size; return emptyList() }
        return List(count.toInt()) { u16() }
    }

    fun u32Array(): List<Long> {
        val count = u32()
        if (count > remaining / 4) { offset = data.size; return emptyList() }
        return List(count.toInt()) { u32() }
    }

    /** A value of PTP data type `type`, widened to Long (strings and arrays are skipped and give 0). */
    fun value(type: Int): Long = when (type) {
        0x0001 -> u8().toByte().toLong()
        0x0002 -> u8().toLong()
        0x0003 -> u16().toShort().toLong()
        0x0004 -> u16().toLong()
        0x0005 -> u32().toInt().toLong()
        0x0006 -> u32()
        0x0007, 0x0008 -> u64()
        0xFFFF -> {
            string()
            0L
        }
        else -> {
            if (type and 0x4000 != 0) {   // arrays: UInt32 count then elements
                val element = type and 0x0FFF
                val count = u32()
                repeat(minOf(count, 4096L).toInt()) { value(element) }
            }
            0L
        }
    }
}

class PtpDeviceInfo(data: ByteArray) {
    val vendorExtensionId: Long
    val operations: Set<Int>
    val events: Set<Int>
    val properties: Set<Int>
    val manufacturer: String
    val model: String
    val version: String
    val serial: String

    init {
        val r = PtpReader(data)
        r.u16()                          // standard version
        vendorExtensionId = r.u32()
        r.u16()                          // vendor extension version
        r.string()                       // vendor extension description
        r.u16()                          // functional mode
        operations = r.u16Array().toSet()
        events = r.u16Array().toSet()
        properties = r.u16Array().toSet()
        r.u16Array()                     // capture formats
        r.u16Array()                     // image formats
        manufacturer = r.string()
        model = r.string()
        version = r.string()
        serial = r.string()
    }
}

class PtpPropDesc(data: ByteArray) {
    val code: Int
    val dataType: Int
    val settable: Boolean
    val current: Long
    /** Allowed values, from an enumeration form or expanded from a range form. */
    val allowed: List<Long>

    init {
        val r = PtpReader(data)
        code = r.u16()
        dataType = r.u16()
        settable = r.u8() == 1
        r.value(dataType)                // factory default
        current = r.value(dataType)
        val values = mutableListOf<Long>()
        when (r.u8()) {
            1 -> {                       // range
                val lo = r.value(dataType)
                val hi = r.value(dataType)
                val increment = r.value(dataType)
                if (increment > 0 && hi >= lo && (hi - lo) / increment < 2000) values.addAll((lo..hi).step(increment))
            }
            2 -> {                       // enumeration
                val count = r.u16()
                repeat(minOf(count, 4096)) { values.add(r.value(dataType)) }
            }
        }
        allowed = values
    }

    /** Encodes `value` in this property's data type, for SetDevicePropValue. */
    fun encode(value: Long): ByteArray {
        val d = ByteArrayOutputStream()
        when (dataType) {
            0x0001, 0x0002 -> d.write(value.toInt() and 0xFF)
            0x0003, 0x0004 -> d.writeLe16(value.toInt())
            0x0005, 0x0006 -> d.writeLe32(value)
            else -> d.writeLe64(value)
        }
        return d.toByteArray()
    }
}

class PtpObjectInfo(data: ByteArray) {
    val storageId: Long
    val format: Int
    val size: Long
    val parent: Long
    val filename: String
    val captureDate: String

    /** Association (folder) objects have format 0x3001. */
    val isFolder: Boolean get() = format == 0x3001

    init {
        val r = PtpReader(data)
        storageId = r.u32()
        format = r.u16()
        r.u16()                                   // protection
        size = r.u32()
        r.u16(); r.u32(); r.u32(); r.u32()        // thumb format, size, width, height
        r.u32(); r.u32(); r.u32()                 // image width, height, depth
        parent = r.u32()
        r.u16(); r.u32(); r.u32()                 // association type, desc, sequence
        filename = r.string()
        captureDate = r.string()
    }

    /** "20261120T153012" (PTP dates) → ms since 1970; 0 when unknown. */
    val date: Long
        get() = runCatching {
            SimpleDateFormat("yyyyMMdd'T'HHmmss", Locale.US).parse(captureDate.take(15))?.time
        }.getOrNull() ?: 0L
}

// MARK: - Little-endian helpers

fun ByteArrayOutputStream.writeLe16(value: Int) {
    write(value and 0xFF)
    write((value shr 8) and 0xFF)
}

fun ByteArrayOutputStream.writeLe32(value: Long) {
    for (i in 0 until 4) write(((value shr (8 * i)) and 0xFF).toInt())
}

fun ByteArrayOutputStream.writeLe64(value: Long) {
    for (i in 0 until 8) write(((value shr (8 * i)) and 0xFF).toInt())
}

fun ByteArray.readLe16(offset: Int): Int =
    (this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)

/** Unsigned 32-bit value as a Long. */
fun ByteArray.readLe32(offset: Int): Long =
    readLe16(offset).toLong() or (readLe16(offset + 2).toLong() shl 16)

fun ByteArray.readLe64(offset: Int): Long = readLe32(offset) or (readLe32(offset + 4) shl 32)
