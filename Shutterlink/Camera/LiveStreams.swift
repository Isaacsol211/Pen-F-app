import UIKit

/// Reads an HTTP response that never ends (Sony's live-view stream) and hands out complete frames
/// as `parse` finds them in the bytes received so far.
final class HTTPStreamReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var buffer = Data()
    private let lock = NSLock()
    private let url: URL
    /// Removes complete frames from the front of the buffer and returns them.
    private let parse: (inout Data) -> [Data]
    var onFrame: (@Sendable (Data) -> Void)?
    var onEnd: (@Sendable (Error?) -> Void)?

    init(url: URL, parse: @escaping (inout Data) -> [Data]) {
        self.url = url
        self.parse = parse
    }

    func start() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 24 * 3600
        config.allowsCellularAccess = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: url).resume()
    }

    func stop() {
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let frames: [Data] = lock.withLock {
            buffer.append(data)
            let frames = parse(&buffer)
            if buffer.count > 8 << 20 { buffer.removeAll() }   // lost sync; start over
            return frames
        }
        for frame in frames { onFrame?(frame) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onEnd?(error)
    }
}

extension CameraModel {
    /// Shows the AF result box around a tapped point (for cameras that only say focused / not).
    func showAFResult(_ focused: Bool, at normalized: CGPoint) {
        let space = frameSpace
        let side = min(space.width, space.height) * 0.14
        liveInfo.afRect = CGRect(x: normalized.x * space.width - side / 2, y: normalized.y * space.height - side / 2,
                                 width: side, height: side)
        liveInfo.afState = focused ? 1 : 2
    }

    /// Repeatedly fetches one live-view frame and hands it over, for cameras that only offer
    /// frame-by-frame live view (Nikon, Canon). Stops when live view stops or after 15 failures in a row.
    func pullLiveView(every interval: Duration, fetch: @escaping @MainActor () async throws -> Data?) -> Task<Void, Never> {
        Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.liveViewRunning else { return }
                do {
                    if let jpeg = try await fetch() {
                        self.submitLiveViewJPEG(jpeg)
                        failures = 0
                    }
                } catch {
                    failures += 1
                    debugLog("live view fetch failed (\(failures)): \(error.localizedDescription)")
                    if failures >= 15 {
                        self.liveViewRunning = false
                        self.report(error)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200 * min(failures, 5)))
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
