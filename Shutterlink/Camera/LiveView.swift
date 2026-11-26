import UIKit

// Live view arrives as RTP over UDP: after `exec_takemisc.cgi?com=startliveview&port=N`
// the camera streams JPEG frames to port N on the phone that asked.
//
//   RTP header (12 bytes): V=2, X=1 on a frame's first packet only, M=1 on its last packet,
//   PT=96, sequence +1 per packet, timestamp = frame number.
//   Extension (first packet only): 2-byte version, 2-byte length in 32-bit words, then fields
//   of [2-byte id][2-byte length in words][data] — AF frame, shutter, F-number, EV, ISO…
//   Payload: JPEG bytes; the first chunk starts FFD8, the last ends FFD9.

struct LiveInfo: Equatable {
    /// 0 = no AF, 1 = focused, 2 = failed
    var afState = 0
    /// AF frame in live-view coordinates (e.g. 0…639 × 0…479).
    var afRect: CGRect = .zero
    var shutter: String?
    var aperture: String?
    /// Lens aperture limits (e.g. 1.8…22), nil if the lens reports none (manual lens).
    var apertureRange: ClosedRange<Double>?
    var expComp: String?
    var iso: String?
    /// Shots left on the card (field 5).
    var shotsRemaining: Int?
    /// Battery level 0–100 (field 7; matched the camera's reading on a real PEN-F).
    var battery: Int?
    /// Camera too hot (field 6).
    var temperatureWarning = false
    /// Lens focal length in mm (field 18), when the lens reports it.
    var focalLength: Int?
    /// Image aspect ratio, e.g. "4:3" (field 14).
    var aspectRatio: String?
}

struct RTPFrameAssembler {
    enum Output {
        case frame(Data, Data?)
        case infoOnly(Data)
        /// A frame ended but was incomplete (lost packet) or not a JPEG.
        case dropped
    }

    private var payload = Data()
    private var ext: Data?
    private var lastSeq: UInt16?
    private var broken = false
    private var inFrame = false

    mutating func push(_ p: UnsafeBufferPointer<UInt8>) -> Output? {
        let n = p.count
        guard n >= 12, p[0] >> 6 == 2 else { return nil }
        let hasPadding = p[0] & 0x20 != 0
        let hasExtension = p[0] & 0x10 != 0
        let csrcCount = Int(p[0] & 0x0F)
        let marker = p[1] & 0x80 != 0
        let seq = UInt16(p[2]) << 8 | UInt16(p[3])

        var start = 12 + 4 * csrcCount
        var end = n
        if hasPadding { end -= Int(p[n - 1]) }
        guard start <= end else { return nil }

        var extData: Data?
        if hasExtension {
            guard start + 4 <= end else { return nil }
            let words = Int(p[start + 2]) << 8 | Int(p[start + 3])
            let extStart = start + 4
            let extEnd = extStart + 4 * words
            guard extEnd <= end else { return nil }
            extData = Data(UnsafeBufferPointer(rebasing: p[extStart..<extEnd]))
            start = extEnd
        }

        if hasExtension || !inFrame {
            payload.removeAll(keepingCapacity: true)
            ext = extData
            broken = false
            inFrame = true
        } else if let lastSeq, seq != lastSeq &+ 1 {
            broken = true // lost a packet; drop this frame
        }
        lastSeq = seq

        if start < end { payload.append(UnsafeBufferPointer(rebasing: p[start..<end])) }
        guard marker else { return nil }

        inFrame = false
        if !broken, payload.count > 4, payload.first == 0xFF, payload[payload.startIndex + 1] == 0xD8 {
            return .frame(payload, ext)
        }
        if payload.isEmpty, let ext { return .infoOnly(ext) }
        return .dropped
    }
}

/// Live-view counters, written to the debug console every couple of seconds and summed into a
/// plain-language line for the Request log.
struct LiveViewStats {
    var packets = 0
    var completed = 0
    var dropped = 0
    var skippedByUI = 0
    /// Frames passed over because a newer one was already waiting behind them.
    var stale = 0
    var jpegBytes = 0
    var frameSize = CGSize.zero
    var lastExtension: Data?
    var since = CACurrentMediaTime()

    func summary(info: LiveInfo) -> String {
        let seconds = max(CACurrentMediaTime() - since, 0.001)
        let avgKB = completed > 0 ? jpegBytes / completed / 1024 : 0
        return String(format: "LV %.1fs: completed %.1f/s, dropped %.1f/s, skippedByUI %.1f/s, stale %.1f/s, packets %.0f/s, avg %d KB, frame %dx%d, af=%d %@, fields %@",
                      seconds, Double(completed) / seconds, Double(dropped) / seconds, Double(skippedByUI) / seconds,
                      Double(stale) / seconds, Double(packets) / seconds, avgKB, Int(frameSize.width), Int(frameSize.height),
                      info.afState, NSCoder.string(for: info.afRect), Self.decodeFields(lastExtension ?? Data()))
    }

    mutating func add(_ other: LiveViewStats) {
        // Time counts from the first frame, not from when the receiver opened.
        if packets == 0 { since = other.since }
        packets += other.packets
        completed += other.completed
        dropped += other.dropped
        skippedByUI += other.skippedByUI
        stale += other.stale
        jpegBytes += other.jpegBytes
        if other.frameSize != .zero { frameSize = other.frameSize }
    }

    /// For the Request log, e.g. "320×240 · 24.1 frames/s from the camera, 23.9/s shown, 0 unreadable,
    /// 0 stale, 9 KB each (last 15 s)".
    func plainSummary(until end: CFTimeInterval) -> String {
        let seconds = max(end - since, 0.001)
        func rate(_ n: Int) -> String { String(format: "%.1f", Double(n) / seconds) }
        let size = frameSize == .zero ? "no picture" : "\(Int(frameSize.width))×\(Int(frameSize.height))"
        let kb = completed > 0 ? jpegBytes / completed / 1024 : 0
        return "\(size) · \(rate(completed + stale)) frames/s from the camera, \(rate(completed - skippedByUI))/s shown, "
            + "\(dropped) unreadable, \(stale) stale, \(kb) KB each (last \(Int(seconds.rounded())) s)"
    }

    /// "id=[word, word…]" for every metadata field, signed 32-bit words.
    static func decodeFields(_ ext: Data) -> String {
        let b = [UInt8](ext)
        var parts: [String] = []
        var i = 0
        while i + 4 <= b.count {
            let id = Int(b[i]) << 8 | Int(b[i + 1])
            let words = Int(b[i + 2]) << 8 | Int(b[i + 3])
            var values: [String] = []
            for w in 0..<words {
                let o = i + 4 + w * 4
                guard o + 4 <= b.count else { break }
                let v = Int32(bitPattern: UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]))
                values.append(String(v))
            }
            parts.append("\(id)=[\(values.joined(separator: ","))]")
            i += 4 + words * 4
        }
        return parts.joined(separator: " ")
    }
}

enum LiveInfoParser {
    static func parse(_ ext: Data, into info: inout LiveInfo) {
        let b = [UInt8](ext)
        func u32(_ o: Int) -> UInt32 {
            UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
        }
        var i = 0
        while i + 4 <= b.count {
            let id = Int(b[i]) << 8 | Int(b[i + 1])
            let length = (Int(b[i + 2]) << 8 | Int(b[i + 3])) * 4
            let d = i + 4
            guard d + length <= b.count else { break }
            switch id {
            case 2 where length >= 20: // AF frame: color, x, y, w, h
                // Coordinates are signed 16-bit: the box can hang off the frame edge.
                func s16(_ o: Int) -> Double { Double(Int16(truncatingIfNeeded: u32(o))) }
                info.afState = Int(u32(d))
                info.afRect = CGRect(x: s16(d + 4), y: s16(d + 8), width: s16(d + 12), height: s16(d + 16))
            case 8 where length >= 24: // shutter (OPC spec): min n/d, max n/d, current n/d as full words
                info.shutter = formatShutter(numerator: u32(d + 16), denominator: u32(d + 20))
            case 8 where length >= 12: // shutter (PEN-F): min, max, current, each packed numerator<<16 | denominator
                let current = u32(d + 8)
                info.shutter = formatShutter(numerator: current >> 16, denominator: current & 0xFFFF)
            case 9 where length >= 12: // F-number ×10: max, min, current
                let maxF = Double(u32(d)) / 10, minF = Double(u32(d + 4)) / 10
                info.apertureRange = (minF > 0 && maxF >= minF) ? minF...maxF : nil
                let v = u32(d + 8)
                info.aperture = v == 0 ? nil : (v >= 100 ? "F\(v / 10)" : String(format: "F%.1f", Double(v) / 10))
            case 10 where length >= 12: // EV ×10, signed: max, min, current
                let v = Int32(bitPattern: u32(d + 8))
                info.expComp = v == 0 ? "±0.0" : String(format: "%+.1f", Double(v) / 10)
            case 12 where length >= 8: // ISO: value, auto flag
                let v = u32(d)
                let auto = (u32(d + 4) >> 16) != 0
                info.iso = "ISO " + (v == 0xFFFE ? "LOW" : "\(v)") + (auto ? " A" : "")
            case 5 where length >= 4: // shots remaining
                info.shotsRemaining = Int(u32(d))
            case 6 where length >= 4: // temperature error
                info.temperatureWarning = u32(d) != 0
            case 7 where length >= 4: // battery level
                let v = Int(u32(d))
                info.battery = (0...100).contains(v) ? v : nil
            case 14 where length >= 4: // aspect ratio, packed width<<16 | height
                let v = u32(d)
                info.aspectRatio = (v >> 16 > 0 && v & 0xFFFF > 0) ? "\(v >> 16):\(v & 0xFFFF)" : nil
            case 18 where length >= 8: // zoom info: focal lengths packed as 16-bit halves
                let v = Int(u32(d + 4) & 0xFFFF)
                info.focalLength = v > 0 ? v : nil
            default:
                break
            }
            i = d + length
        }
    }

    static func formatShutter(numerator: UInt32, denominator: UInt32) -> String? {
        guard numerator > 0, denominator > 0 else { return nil }
        if numerator >= denominator {
            let s = Double(numerator) / Double(denominator)
            return s == s.rounded() ? "\(Int(s))\"" : String(format: "%.1f\"", s)
        }
        let d = Double(denominator) / Double(numerator)
        return d == d.rounded() ? "1/\(Int(d))" : String(format: "1/%.1f", d)
    }
}

/// How a camera packs live view into UDP.
enum LiveViewFormat {
    /// Olympus: RTP, one JPEG split over several packets, metadata in an RTP extension.
    case olympusRTP
    /// Panasonic: one complete JPEG per datagram after a camera-specific header.
    case jpegPerDatagram
    /// Nikon, Canon, Sony: the driver fetches frames itself and hands them to `submit(jpeg:)`.
    case pushed
}

/// A complete JPEG inside a datagram: from the first SOI marker (FF D8 FF) to the end.
/// Used for Panasonic, whose header length varies by model and firmware.
func jpegInDatagram(_ p: UnsafeBufferPointer<UInt8>) -> Data? {
    let n = p.count
    guard n > 4 else { return nil }
    var i = 0
    // LUMIX: a 32-byte header whose last two bytes give the length of a second header.
    if n > 34 {
        let offset = 32 + (Int(p[30]) << 8 | Int(p[31]))
        if offset + 2 < n, p[offset] == 0xFF, p[offset + 1] == 0xD8 { i = offset }
    }
    // Otherwise look for the JPEG start marker.
    while i + 2 < n {
        if p[i] == 0xFF && p[i + 1] == 0xD8 && p[i + 2] == 0xFF { break }
        i += 1
    }
    guard i + 2 < n else { return nil }
    var end = n
    // Trim anything after the last EOI marker (FF D9).
    var j = n - 2
    while j > i {
        if p[j] == 0xFF && p[j + 1] == 0xD9 { end = j + 2; break }
        j -= 1
    }
    return Data(UnsafeBufferPointer(rebasing: p[i..<end]))
}

/// Listens on a UDP port for the whole connection and hands decoded frames to the main actor.
/// Frames that arrive while the UI is still busy with the previous one are dropped.
final class LiveViewReceiver: @unchecked Sendable {
    let port: UInt16
    let format: LiveViewFormat
    var onFrame: (@MainActor (UIImage?, LiveInfo?, [Float]?, Double?) -> Void)?
    /// Focus-peaking overlays, when peaking is on (nil clears it).
    var onPeaking: (@MainActor (CGImage?) -> Void)?
    /// A plain-language summary while frames are arriving (after 5 s, then every 15 s), so a copied
    /// Request log shows how live view ran.
    var onSummary: (@MainActor (String) -> Void)?
    private var logWindow = LiveViewStats()
    private var logWindowEnd = CACurrentMediaTime()
    private var summariesSent = 0
    private let peaker = FocusPeaker()
    private var peakingOn = false

    func setPeaking(_ on: Bool) { lock.withLock { peakingOn = on } }

    private var fd: Int32 = -1
    private let lock = NSLock()
    private var running = false
    private var deliveryPending = false
    private var info = LiveInfo()
    private var framesSinceHistogram = 0
    /// Normalised area to measure sharpness in (the loupe's view), or nil when the loupe is closed.
    private var meterRegion: CGRect?

    func setMeterRegion(_ region: CGRect?) { lock.withLock { meterRegion = region } }

    init(port: UInt16, format: LiveViewFormat = .olympusRTP) {
        self.port = port
        self.format = format
    }

    func start() throws {
        if format == .pushed {
            lock.withLock { running = true }
            // The UDP thread checks the counters on every pass; pushed frames need a clock of their own
            // so a pause in frames closes the window instead of stretching it.
            let timer = DispatchSource.makeTimerSource(queue: pushQueue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self, self.isRunning else { return }
                self.reportStats()
            }
            timer.resume()
            pushTimer = timer
            return
        }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw CameraError("Couldn't create a UDP socket (errno \(errno)).") }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var bufferSize: Int32 = 2 * 1024 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw CameraError("Couldn't listen on UDP port \(port) (errno \(code)).")
        }

        self.fd = fd
        lock.withLock { running = true }
        let thread = Thread { [self] in run() }
        thread.name = "Shutterlink live view"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        lock.withLock { running = false }
        pushTimer?.cancel()
        pushTimer = nil
    }

    private var isRunning: Bool { lock.withLock { running } }
    /// Pushed frames are decoded one at a time here, like the UDP thread does for its own.
    private let pushQueue = DispatchQueue(label: "live view (pushed)", qos: .userInteractive)
    private var pushTimer: DispatchSourceTimer?

    deinit { pushTimer?.cancel() }

    /// A complete JPEG fetched by the driver (pushed formats). Dropped if the UI is still busy
    /// with the previous frame.
    func submit(jpeg: Data) {
        guard isRunning else { return }
        // Some cameras put a header before the JPEG: start at the first FF D8.
        guard let start = jpeg.range(of: Data([0xFF, 0xD8]))?.lowerBound else { return }
        let frame = start == jpeg.startIndex ? jpeg : jpeg[start...]
        pushQueue.async { [self] in
            stats.packets += 1
            stats.completed += 1
            stats.jpegBytes += frame.count
            deliver(jpeg: Data(frame), ext: nil)
        }
    }

    private var stats = LiveViewStats()

    /// Every 2 s: the detailed line to the debug console, and the totals towards the Request log line.
    private func reportStats() {
        let now = CACurrentMediaTime()
        guard now - stats.since >= 2 else { return }
        let idle = stats.packets == 0
        if !idle {
            debugLog(stats.summary(info: info))
            logWindow.add(stats)
            logWindowEnd = now
        }
        stats = LiveViewStats()
        if logWindow.packets == 0 {
            logWindow = LiveViewStats()
        } else if idle || now - logWindow.since >= (summariesSent == 0 ? 5 : 15) {
            // Also when frames stop (live view paused, gallery open), so the rates only cover streaming.
            // A frame or two on their own (a single preview fetch) isn't live view: no line for those.
            let window = logWindow
            logWindow = LiveViewStats()
            guard window.completed + window.stale >= 5 else { return }
            let line = window.plainSummary(until: logWindowEnd)
            debugLog("LIVE \(line)")
            summariesSent += 1
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onSummary?(line) }
            }
        }
    }

    private func run() {
        let fd = self.fd
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var newer = [UInt8](repeating: 0, count: 65_536)
        var assembler = RTPFrameAssembler()
        while isRunning {
            // Each frame's decoded image is autoreleased. Without a pool per pass this thread, which
            // runs as long as live view does, keeps every frame: gigabytes after a few minutes.
            autoreleasepool {
                var count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
                if count > 0, format == .jpegPerDatagram {
                    // One frame per datagram: if more are already waiting, this one is old news. Show the
                    // newest so the picture never falls behind the camera (slow bodies, busy moments).
                    while true {
                        let next = newer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
                        guard next > 0 else { break }
                        swap(&buffer, &newer)
                        count = next
                        stats.packets += 1
                        stats.stale += 1
                    }
                    stats.packets += 1
                    if let jpeg = buffer.withUnsafeBufferPointer({ jpegInDatagram(UnsafeBufferPointer(rebasing: $0[0..<count])) }) {
                        stats.completed += 1
                        stats.jpegBytes += jpeg.count
                        deliver(jpeg: jpeg, ext: nil)
                    } else {
                        stats.dropped += 1
                    }
                } else if count > 0 {
                    stats.packets += 1
                    let output = buffer.withUnsafeBufferPointer {
                        assembler.push(UnsafeBufferPointer(rebasing: $0[0..<count]))
                    }
                    switch output {
                    case .frame(let jpeg, let ext)?:
                        stats.completed += 1
                        stats.jpegBytes += jpeg.count
                        if let ext { stats.lastExtension = ext }
                        deliver(jpeg: jpeg, ext: ext)
                    case .infoOnly(let ext)?:
                        stats.lastExtension = ext
                        deliver(jpeg: nil, ext: ext)
                    case .dropped?:
                        stats.dropped += 1
                    case nil:
                        break
                    }
                }
                reportStats()
            }
        }
        close(fd)
    }

    private func deliver(jpeg: Data?, ext: Data?) {
        let accept: Bool = lock.withLock {
            if deliveryPending { return false }
            deliveryPending = true
            return true
        }
        guard accept else {
            stats.skippedByUI += 1
            return
        }

        var newInfo: LiveInfo?
        if let ext {
            LiveInfoParser.parse(ext, into: &info)
            newInfo = info
        }
        let image = jpeg.flatMap { UIImage(data: $0)?.preparingForDisplay() }
        if let image { stats.frameSize = image.size }
        // A luminance histogram a few times a second is plenty.
        var histogram: [Float]?
        framesSinceHistogram += 1
        if let cg = image?.cgImage, framesSinceHistogram >= 5 {
            framesSinceHistogram = 0
            histogram = Self.histogram(of: cg)
        }

        var sharpness: Double?
        if let region = lock.withLock({ meterRegion }), let cg = image?.cgImage {
            sharpness = Self.sharpness(of: cg, region: region)
        }

        // Peaking runs on its own queue and skips frames while busy, so live view keeps its frame rate.
        if lock.withLock({ peakingOn }), let cg = image?.cgImage {
            peaker.submit(cg) { [weak self] overlay in
                DispatchQueue.main.async {
                    guard let self else { return }
                    MainActor.assumeIsolated { self.onPeaking?(overlay) }
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.deliveryPending = false }
            MainActor.assumeIsolated { self.onFrame?(image, newInfo, histogram, sharpness) }
        }
    }

    /// 64-bin luminance histogram from a small greyscale copy of the frame, normalised to 0…1.
    static func histogram(of image: CGImage, bins: Int = 64) -> [Float] {
        guard let pixels = grey(image, width: 80, height: 60, quality: .low) else { return [] }
        var counts = [Float](repeating: 0, count: bins)
        for p in pixels { counts[Int(p) * bins / 256] += 1 }
        let peak = max(counts.max() ?? 1, 1)
        return counts.map { $0 / peak }
    }

    /// Focus measure: mean squared brightness gradient inside the region. It rises as stars and
    /// edges get crisper, so the peak is the sharpest focus.
    static func sharpness(of image: CGImage, region: CGRect) -> Double? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let crop = CGRect(x: region.minX * w, y: region.minY * h, width: region.width * w, height: region.height * h)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard crop.width >= 8, crop.height >= 8, let part = image.cropping(to: crop) else { return nil }
        let width = min(Int(crop.width), 200), height = min(Int(crop.height), 150)
        guard let pixels = grey(part, width: width, height: height, quality: .medium) else { return nil }
        var sum = 0.0
        for y in 0..<(height - 1) {
            let row = y * width
            for x in 0..<(width - 1) {
                let p = Double(pixels[row + x])
                let dx = Double(pixels[row + x + 1]) - p
                let dy = Double(pixels[row + width + x]) - p
                sum += dx * dx + dy * dy
            }
        }
        return sum / Double((width - 1) * (height - 1))
    }

    /// `image` scaled into an 8-bit greyscale bitmap of this size.
    private static func grey(_ image: CGImage, width: Int, height: Int, quality: CGInterpolationQuality) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = quality
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
