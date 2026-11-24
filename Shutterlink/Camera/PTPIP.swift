import Foundation
import Network

// PTP over TCP/IP (CIPA DC-005, "PTP/IP"), as Nikon cameras speak it over their own Wi-Fi.
//
// Two TCP connections to port 15740: a command channel and an event channel. Every packet is
//   [UInt32 length, including these 8 bytes][UInt32 type][payload], little-endian.
// Handshake: Init Command Request (our GUID, name, version) → Init Command Ack (connection number,
// camera GUID, camera name) on the command channel, then Init Event Request (connection number)
// → Init Event Ack on the event channel. After that, PTP operations run one at a time:
//   Operation Request → [Start Data, Data…, End Data] (either direction) → Operation Response.

enum PTPIPPacket: UInt32 {
    case initCommandRequest = 1, initCommandAck, initEventRequest, initEventAck, initFail
    case operationRequest, operationResponse, event, startData, data, cancel, endData
    case probeRequest, probeResponse
}

struct PTPError: LocalizedError {
    let code: UInt16
    let operation: UInt16

    static let ok: UInt16 = 0x2001
    static let deviceBusy: UInt16 = 0x2019

    var errorDescription: String? {
        let what = String(format: "0x%04X", operation)
        switch code {
        case 0x2019: return "The camera is busy (operation \(what))."
        case 0x2005: return "The camera doesn't support operation \(what) over Wi-Fi."
        case 0x200A: return "The camera refused operation \(what): no card or the card is full."
        case 0x201C, 0x201D: return "The camera refused operation \(what): the value isn't allowed now."
        case 0x200E: return "The camera won't let that be changed now (operation \(what))."
        case 0x2002: return "The camera reported a general error for operation \(what)."
        case 0xA002: return "The camera isn't in a mode that allows this (operation \(what))."
        default: return String(format: "The camera answered 0x%04X to operation %@.", code, what)
        }
    }
}

/// One TCP connection with exact-length async reads.
final class TCPChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ptpip.channel")

    init(host: String, port: UInt16) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        params.prohibitedInterfaceTypes = [.cellular]
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 15740,
                                  using: params)
    }

    func open(timeout: TimeInterval = 5) async throws {
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: CameraError("Connection cancelled.")) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(throwing: URLError(.timedOut)) }
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else if isComplete { continuation.resume(throwing: URLError(.networkConnectionLost)) }
                else { continuation.resume(throwing: CameraError("Short read from the camera.")) }
            }
        }
    }

    func close() { connection.cancel() }
}

/// Runs `body`, throwing URLError.timedOut if it takes longer than `seconds`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw URLError(.timedOut) }
        return first
    }
}

/// A PTP/IP session: the handshake, then one operation at a time.
actor PTPIPClient {
    struct Response: Sendable {
        let code: UInt16
        let data: Data
    }

    let host: String
    let port: UInt16
    private var command: TCPChannel?
    private var event: TCPChannel?
    /// OpenSession must use transaction ID 0; the first increment wraps to it.
    private var transactionID: UInt32 = .max
    private var eventTask: Task<Void, Never>?
    private(set) var cameraName = ""
    /// Actors are re-entrant at every await: this keeps a second operation from starting mid-way.
    private let gate = SerialGate()
    private var logger: (@Sendable (String) -> Void)?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func setLogger(_ logger: (@Sendable (String) -> Void)?) { self.logger = logger }

    /// "192.168.1.1" → (host, default), "127.0.0.1:15741" → (127.0.0.1, 15741).
    nonisolated static func split(_ address: String, defaultPort: UInt16) -> (String, UInt16) {
        let parts = address.split(separator: ":")
        if parts.count == 2, let port = UInt16(parts[1]) { return (String(parts[0]), port) }
        return (address, defaultPort)
    }

    /// Opens both channels. `guid` identifies this phone (cameras that remember paired devices use it).
    func connect(guid: [UInt8], name: String) async throws {
        let command = TCPChannel(host: host, port: port)
        try await command.open()
        self.command = command

        var payload = Data(guid.prefix(16))
        if payload.count < 16 { payload.append(Data(repeating: 0, count: 16 - payload.count)) }
        payload.append(Self.utf16z(name))
        payload.appendLE(UInt32(0x0001_0000))   // protocol version 1.0
        try await command.send(Self.packet(.initCommandRequest, payload))

        let (type, reply) = try await withTimeout(30) { try await Self.readPacket(command) }
        if type == PTPIPPacket.initFail.rawValue {
            let reason = reply.count >= 4 ? reply.le32(0) : 0
            throw CameraError(String(format: "The camera turned the connection down (PTP/IP Init Fail 0x%X). On the camera, allow this \(Platform.device) or start its Wi-Fi connection again.", reason))
        }
        guard type == PTPIPPacket.initCommandAck.rawValue, reply.count >= 20 else {
            throw CameraError("The camera didn't answer the PTP/IP handshake (packet type \(type)).")
        }
        let connectionNumber = reply.le32(0)
        var nameReader = PTPReader(reply, at: 20)
        cameraName = nameReader.utf16zString()
        logger?("PTP/IP init ack: connection \(connectionNumber), camera \"\(cameraName)\"")

        let event = TCPChannel(host: host, port: port)
        try await event.open()
        self.event = event
        var eventPayload = Data()
        eventPayload.appendLE(connectionNumber)
        try await event.send(Self.packet(.initEventRequest, eventPayload))
        let (eventType, _) = try await withTimeout(10) { try await Self.readPacket(event) }
        guard eventType == PTPIPPacket.initEventAck.rawValue else {
            throw CameraError("The camera didn't open its event channel (packet type \(eventType)).")
        }
        startEventLoop(event)
    }

    private func startEventLoop(_ channel: TCPChannel) {
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let (type, payload) = try? await Self.readPacket(channel) else { return }
                if type == PTPIPPacket.event.rawValue, payload.count >= 6 {
                    let params = stride(from: 6, through: payload.count - 4, by: 4).map { String(format: "0x%X", payload.le32($0)) }
                    await self?.log(String(format: "PTP event 0x%04X %@", payload.le16(0), params.joined(separator: " ")))
                } else if type == PTPIPPacket.probeRequest.rawValue {
                    try? await channel.send(Self.packet(.probeResponse, Data()))
                }
            }
        }
    }

    private func log(_ line: String) { logger?(line) }

    func close() {
        eventTask?.cancel()
        command?.close()
        event?.close()
        command = nil
        event = nil
    }

    /// One PTP operation. `dataOut` is sent to the camera (e.g. SetDevicePropValue); data the
    /// camera sends back is in the response's `data`.
    func transaction(_ opcode: UInt16, _ params: [UInt32] = [], dataOut: Data? = nil,
                     timeout: TimeInterval = 15) async throws -> Response {
        await gate.acquire()
        defer { Task { await gate.release() } }
        guard let command else { throw CameraError("Not connected.") }
        transactionID &+= 1
        let tid = transactionID
        var request = Data()
        request.appendLE(UInt32(dataOut == nil ? 1 : 2))
        request.appendLE(opcode)
        request.appendLE(tid)
        for p in params.prefix(5) { request.appendLE(p) }
        let started = Date()
        try await command.send(Self.packet(.operationRequest, request))

        if let dataOut {
            var start = Data()
            start.appendLE(tid)
            start.appendLE(UInt64(dataOut.count))
            try await command.send(Self.packet(.startData, start))
            var end = Data()
            end.appendLE(tid)
            end.append(dataOut)
            try await command.send(Self.packet(.endData, end))
        }

        let response: Response = try await withTimeout(timeout) {
            var incoming = Data()
            while true {
                let (type, payload) = try await Self.readPacket(command)
                switch PTPIPPacket(rawValue: type) {
                case .startData:
                    incoming.reserveCapacity(payload.count >= 12 ? Int(min(payload.le64(4), 64 << 20)) : 0)
                case .data, .endData:
                    if payload.count > 4 { incoming.append(payload[(payload.startIndex + 4)...]) }
                case .operationResponse:
                    guard payload.count >= 6 else { throw CameraError("Short PTP response.") }
                    return Response(code: payload.le16(0), data: incoming)
                case .probeRequest:
                    try await command.send(Self.packet(.probeResponse, Data()))
                default:
                    continue
                }
            }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        logger?(String(format: "PTP 0x%04X %@ → 0x%04X (%d ms, %d bytes)", opcode,
                       params.map { String(format: "0x%X", $0) }.joined(separator: " "), response.code, ms, response.data.count))
        return response
    }

    /// Like `transaction`, throwing PTPError unless the camera answered OK.
    @discardableResult
    func run(_ opcode: UInt16, _ params: [UInt32] = [], dataOut: Data? = nil, timeout: TimeInterval = 15) async throws -> Response {
        let response = try await transaction(opcode, params, dataOut: dataOut, timeout: timeout)
        guard response.code == PTPError.ok else { throw PTPError(code: response.code, operation: opcode) }
        return response
    }

    // MARK: - Framing

    static func packet(_ type: PTPIPPacket, _ payload: Data) -> Data {
        var data = Data()
        data.appendLE(UInt32(8 + payload.count))
        data.appendLE(type.rawValue)
        data.append(payload)
        return data
    }

    static func readPacket(_ channel: TCPChannel) async throws -> (UInt32, Data) {
        let header = try await channel.receive(exactly: 8)
        let length = Int(header.le32(0))
        guard length >= 8, length < 128 << 20 else { throw CameraError("Bad PTP/IP packet length \(length).") }
        let payload = try await channel.receive(exactly: length - 8)
        return (header.le32(4), payload)
    }

    static func utf16z(_ text: String) -> Data {
        var data = Data()
        for unit in text.utf16 { data.appendLE(unit) }
        data.appendLE(UInt16(0))
        return data
    }
}

// MARK: - PTP datasets

/// Reads PTP's little-endian fields and strings (UInt8 length in UTF-16 units, including the null).
struct PTPReader {
    let data: Data
    var offset: Int

    init(_ data: Data, at offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    /// The offset of the next `size` bytes, moving past them; nil (and at the end) if they aren't all there.
    private mutating func take(_ size: Int) -> Int? {
        guard remaining >= size else { offset = data.count; return nil }
        defer { offset += size }
        return offset
    }

    mutating func u8() -> UInt8 { take(1).map { data[data.startIndex + $0] } ?? 0 }
    mutating func u16() -> UInt16 { take(2).map(data.le16) ?? 0 }
    mutating func u32() -> UInt32 { take(4).map(data.le32) ?? 0 }
    mutating func u64() -> UInt64 { take(8).map(data.le64) ?? 0 }

    mutating func string() -> String {
        let count = Int(u8())
        guard count > 0 else { return "" }
        var units: [UInt16] = []
        for _ in 0..<count { units.append(u16()) }
        if units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }

    /// A null-terminated UTF-16 string with no length prefix (PTP/IP init packets).
    mutating func utf16zString() -> String {
        var units: [UInt16] = []
        while remaining >= 2 {
            let unit = u16()
            if unit == 0 { break }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    mutating func u16Array() -> [UInt16] {
        let count = Int(u32())
        guard count <= remaining / 2 else { offset = data.count; return [] }
        return (0..<count).map { _ in u16() }
    }

    mutating func u32Array() -> [UInt32] {
        let count = Int(u32())
        guard count <= remaining / 4 else { offset = data.count; return [] }
        return (0..<count).map { _ in u32() }
    }

    /// A value of PTP data type `type`, widened to Int64 (strings and arrays are skipped and give 0).
    mutating func value(ofType type: UInt16) -> Int64 {
        switch type {
        case 0x0001: return Int64(Int8(bitPattern: u8()))
        case 0x0002: return Int64(u8())
        case 0x0003: return Int64(Int16(bitPattern: u16()))
        case 0x0004: return Int64(u16())
        case 0x0005: return Int64(Int32(bitPattern: u32()))
        case 0x0006: return Int64(u32())
        case 0x0007, 0x0008: return Int64(bitPattern: u64())
        case 0xFFFF: _ = string(); return 0
        default:
            if type & 0x4000 != 0 {   // arrays: UInt32 count then elements
                let element = type & 0x0FFF
                let count = Int(u32())
                for _ in 0..<min(count, 4096) { _ = value(ofType: element) }
            }
            return 0
        }
    }
}

struct PTPDeviceInfo {
    var operations: Set<UInt16> = []
    var properties: Set<UInt16> = []
    var model = ""
    var version = ""

    init(_ data: Data) {
        var r = PTPReader(data)
        _ = r.u16()                       // standard version
        _ = r.u32()                       // vendor extension ID
        _ = r.u16()                       // vendor extension version
        _ = r.string()                    // vendor extension description
        _ = r.u16()                       // functional mode
        operations = Set(r.u16Array())
        _ = r.u16Array()                  // events
        properties = Set(r.u16Array())
        _ = r.u16Array()                  // capture formats
        _ = r.u16Array()                  // image formats
        _ = r.string()                    // manufacturer
        model = r.string()
        version = r.string()
    }
}

struct PTPPropDesc {
    var dataType: UInt16 = 0
    var settable = false
    var current: Int64 = 0
    /// Allowed values, from an enumeration form or expanded from a range form.
    var allowed: [Int64] = []

    init(_ data: Data) {
        var r = PTPReader(data)
        _ = r.u16()                       // property code
        dataType = r.u16()
        settable = r.u8() == 1
        _ = r.value(ofType: dataType)     // factory default
        current = r.value(ofType: dataType)
        let form = r.u8()
        if form == 1 {                    // range
            let lo = r.value(ofType: dataType), hi = r.value(ofType: dataType), step = r.value(ofType: dataType)
            if step > 0, (hi - lo) / step < 2000 {
                allowed = Array(stride(from: lo, through: hi, by: Int(step)))
            }
        } else if form == 2 {             // enumeration
            let count = Int(r.u16())
            for _ in 0..<min(count, 4096) { allowed.append(r.value(ofType: dataType)) }
        }
    }

    /// Encodes `value` in this property's data type, for SetDevicePropValue.
    func encode(_ value: Int64) -> Data {
        var d = Data()
        switch dataType {
        case 0x0001, 0x0002: d.append(UInt8(truncatingIfNeeded: value))
        case 0x0003, 0x0004: d.appendLE(UInt16(truncatingIfNeeded: value))
        case 0x0005, 0x0006: d.appendLE(UInt32(truncatingIfNeeded: value))
        default: d.appendLE(UInt64(bitPattern: value))
        }
        return d
    }
}

struct PTPObjectInfo {
    var format: UInt16 = 0
    var size: UInt32 = 0
    var parent: UInt32 = 0
    var filename = ""
    var captureDate = ""

    /// Association (folder) objects have format 0x3001.
    var isFolder: Bool { format == 0x3001 }

    init(_ data: Data) {
        var r = PTPReader(data)
        _ = r.u32()                       // storage ID
        format = r.u16()
        _ = r.u16()                       // protection
        size = r.u32()
        _ = r.u16(); _ = r.u32(); _ = r.u32(); _ = r.u32()   // thumb format, size, width, height
        _ = r.u32(); _ = r.u32(); _ = r.u32()                // image width, height, depth
        parent = r.u32()
        _ = r.u16(); _ = r.u32(); _ = r.u32()                // association type, desc, sequence
        filename = r.string()
        captureDate = r.string()
    }

    /// "20261120T153012" (PTP dates) → Date.
    var date: Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.date(from: String(captureDate.prefix(15))) ?? .distantPast
    }
}

// MARK: - Little-endian helpers

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }

    func le16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func le32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    func le64(_ offset: Int) -> UInt64 {
        UInt64(le32(offset)) | UInt64(le32(offset + 4)) << 32
    }
}
