import Foundation

// HTTP client shared by the HTTP-based drivers (Olympus, Panasonic, Canon CCAPI, Sony).
// It serialises requests (cameras handle one at a time), logs them for the Request log, and
// turns non-2xx replies into CameraHTTPError.
//
// Olympus OI.Share specifics: the camera is an access point at 192.168.0.10 and answers plain HTTP/1.1 on port 80:
//   GET  /<command>.cgi?opt1=v1&opt2=v2      (option order matters)
//   POST /set_camprop.cgi?com=set&propname=X  body: <?xml version="1.0"?><set><value>…</value></set>
// It wants a Host header and an OI.Share-style User-Agent on every request.
// 200/202 = success, 520 = "camera refused" (wrong mode, bad value…), 404 = no such file.

struct CameraError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct CameraHTTPError: LocalizedError {
    let status: Int
    let path: String
    let body: String

    var command: String { path.split(separator: "?").first.map(String.init) ?? path }

    var errorDescription: String? {
        var text = "\(command) → HTTP \(status)"
        if let code = MiniXML.parse(Data(body.utf8))?.firstDescendant(named: ["errorcode", "Errorcode"])?.trimmedText {
            text += " (camera error \(code))"
        } else if let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let message = json["message"] as? String {
            text += " (\(message))"   // Canon CCAPI
        }
        switch status {
        case 520: text += ". The camera refused it; it may be in the wrong mode or the value isn't allowed right now."
        case 503: text += ". The camera is busy."
        default: break
        }
        return text
    }
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let method: String
    let path: String
    let status: Int?
    let millis: Int
    let summary: String

    var ok: Bool { (200...204).contains(status ?? 0) }

    var line: String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        return "\(time) \(method) \(path) → \(status.map(String.init) ?? "ERR") (\(millis) ms) \(summary)"
    }
}

/// Serialises requests: the camera handles one command at a time.
actor SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

final class CameraHTTPClient: @unchecked Sendable {
    let host: String
    let userAgent: String
    var onLog: (@Sendable (LogEntry) -> Void)?

    private let session: URLSession
    /// Separate connection that skips the queue, for stopping a running exposure.
    private let urgentSession: URLSession
    private let gate = SerialGate()
    private let headerLock = NSLock()
    private var _extraHeaders: [String: String] = [:]
    /// Sent with every command to the camera's own path (not absolute URLs), e.g. LUMIX's X-SESSION_ID.
    var extraHeaders: [String: String] {
        get { headerLock.withLock { _extraHeaders } }
        set { headerLock.withLock { _extraHeaders = newValue } }
    }
    /// Statuses that count as success (Canon CCAPI answers 200-204).
    let allowedStatus: ClosedRange<Int>

    init(host: String, userAgent: String, allowedStatus: ClosedRange<Int> = 200...202) {
        self.host = host
        self.userAgent = userAgent
        self.allowedStatus = allowedStatus
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        // The camera is only reachable over Wi-Fi; never try cellular.
        config.allowsCellularAccess = false
        session = URLSession(configuration: config)
        urgentSession = URLSession(configuration: config)
    }

    /// Bypasses the one-at-a-time queue (used for stoptake while a starttake may still be open).
    func getUrgent(_ cgi: String, _ params: [(String, String)] = []) async throws -> Data {
        try await perform(using: urgentSession, method: "GET", path: Self.path(cgi, params), body: nil, timeout: 10, log: true)
    }

    func get(_ cgi: String, _ params: [(String, String)] = [], timeout: TimeInterval = 10, log: Bool = true) async throws -> Data {
        try await send(method: "GET", path: Self.path(cgi, params), body: nil, timeout: timeout, log: log)
    }

    func post(_ cgi: String, _ params: [(String, String)], xml: String) async throws -> Data {
        try await send(method: "POST", path: Self.path(cgi, params), body: Data(xml.utf8), timeout: 10, log: true)
    }

    /// Full-size file straight off the card, e.g. /DCIM/100OLYMP/P1010001.JPG
    func download(path: String) async throws -> Data {
        try await send(method: "GET", path: path, body: nil, timeout: 180, log: true)
    }

    /// GET an absolute URL (Panasonic serves photos from its UPnP server on another port).
    func fetch(_ url: URL?, timeout: TimeInterval = 30, log: Bool = true) async throws -> Data {
        guard let url else { throw CameraError("The camera gave no address for this file.") }
        return try await send(method: "GET", path: url.absoluteString, body: nil, timeout: timeout, log: log)
    }

    /// POST a SOAP request (UPnP ContentDirectory).
    func soap(_ url: URL, action: String, body: String) async throws -> Data {
        try await send(method: "POST", path: url.absoluteString, body: Data(body.utf8), timeout: 20, log: true,
                       headers: ["Content-Type": "text/xml; charset=\"utf-8\"", "SOAPACTION": "\"\(action)\""])
    }

    /// Any method, path (or absolute URL) and body, e.g. Canon CCAPI's JSON PUTs and Sony's JSON-RPC.
    func request(_ method: String, _ path: String, json: Any? = nil, timeout: TimeInterval = 10,
                 log: Bool = true, urgent: Bool = false) async throws -> Data {
        var body: Data?
        var headers: [String: String] = [:]
        if let json {
            body = try JSONSerialization.data(withJSONObject: json)
            headers["Content-Type"] = "application/json"
        }
        return try await urgent
            ? perform(using: urgentSession, method: method, path: path, body: body, timeout: timeout, log: log, headers: headers)
            : send(method: method, path: path, body: body, timeout: timeout, log: log, headers: headers)
    }

    /// Like `request`, decoding a JSON object reply ([:] for an empty body).
    func requestJSON(_ method: String, _ path: String, json: Any? = nil, timeout: TimeInterval = 10,
                     log: Bool = true) async throws -> [String: Any] {
        let data = try await request(method, path, json: json, timeout: timeout, log: log)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CameraError("The camera's reply to \(path) wasn't JSON.")
        }
        return object
    }

    static func path(_ cgi: String, _ params: [(String, String)]) -> String {
        "/\(cgi).cgi" + (params.isEmpty ? "" : "?" + params.map { "\($0.0)=\($0.1)" }.joined(separator: "&"))
    }

    private func send(method: String, path: String, body: Data?, timeout: TimeInterval, log: Bool,
                      headers: [String: String] = [:]) async throws -> Data {
        await gate.acquire()
        do {
            let data = try await perform(using: session, method: method, path: path, body: body, timeout: timeout,
                                         log: log, headers: headers)
            await gate.release()
            return data
        } catch {
            await gate.release()
            throw error
        }
    }

    private func perform(using session: URLSession, method: String, path: String, body: Data?,
                         timeout: TimeInterval, log: Bool, headers: [String: String] = [:]) async throws -> Data {
        try Task.checkCancellation()
        let address = path.hasPrefix("http") ? path : "http://\(host)\(path)"
        guard let url = URL(string: address) else { throw CameraError("Bad camera address: \(host)") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if !path.hasPrefix("http") {
            for (field, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: field) }
        }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            debugLog("\(method) \(url.absoluteString) FAILED after \(Self.ms(since: started)) ms: \(error)")
            if log {
                onLog?(LogEntry(date: started, method: method, path: path, status: nil,
                                millis: Self.ms(since: started), summary: error.localizedDescription))
            }
            throw error
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        debugLog("\(method) \(url.absoluteString) → \(status) (\(Self.ms(since: started)) ms, \(data.count) bytes) \(data.count < 4000 ? Self.summarize(data, response) : "")")
        if log || !allowedStatus.contains(status) {
            onLog?(LogEntry(date: started, method: method, path: path, status: status,
                            millis: Self.ms(since: started), summary: Self.summarize(data, response)))
        }
        guard allowedStatus.contains(status) else {
            throw CameraHTTPError(status: status, path: path, body: String(decoding: data.prefix(600), as: UTF8.self))
        }
        return data
    }

    private static func ms(since date: Date) -> Int { Int(Date().timeIntervalSince(date) * 1000) }

    private static func summarize(_ data: Data, _ response: URLResponse) -> String {
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if type.hasPrefix("image/") || type.contains("octet-stream") || type.hasPrefix("video/") {
            return "\(type) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
        if data.isEmpty { return "(empty)" }
        var text = String(decoding: data.prefix(800), as: UTF8.self)
        text = text.replacingOccurrences(of: #"<\?xml[^>]*\?>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespaces).prefix(240))
    }
}

/// One line of get_imglist.cgi: "/DCIM/100OLYMP,P1010001.JPG,5824512,0,19312,40061"
/// (directory, name, size, attribute bits, FAT date, FAT time). The first line is a "VER_100" header.
enum ImageListParser {
    static func parse(_ text: String) -> [CameraImage] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 6, let size = Int(f[2]), let attr = Int(f[3]),
                  let date = Int(f[4]), let time = Int(f[5]) else { return nil }
            if attr & 2 != 0 { return nil } // hidden
            return CameraImage(directory: f[0], name: f[1], size: size, attributes: attr,
                               date: fatDate(date, time))
        }
    }

    static func fatDate(_ d: Int, _ t: Int) -> Date {
        var c = DateComponents()
        c.year = 1980 + (d >> 9)
        c.month = (d >> 5) & 15
        c.day = d & 31
        c.hour = t >> 11
        c.minute = (t >> 5) & 63
        c.second = (t & 31) * 2
        return Calendar.current.date(from: c) ?? .distantPast
    }
}
