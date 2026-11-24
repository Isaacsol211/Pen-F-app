import Foundation
import UIKit

// Nikon over the camera's own Wi-Fi: PTP/IP on TCP 15740 (see PTPIP.swift), with Nikon's vendor
// operations, the same ones Nikon's apps and libgphoto2 use over USB.
//
//   Session: OpenSession, GetDeviceInfo (model, supported operations and properties).
//   Live view: StartLiveView 0x9201, poll DeviceReady 0x90C8 until it stops answering Busy, then
//              GetLiveViewImg 0x9203 in a loop (a model-specific header, then the JPEG).
//   Shooting: InitiateCaptureRecInMedia 0x9207 (to the card, live view stays on) or
//             InitiateCaptureRecInSdram 0x90C0 / InitiateCapture 0x100E on older bodies.
//   Settings: GetDevicePropDesc / SetDevicePropValue on FNumber 0x5007 (f × 100),
//             ExposureTime 0x500D, ExposureIndex 0x500F (ISO), ExposureBiasCompensation 0x5010
//             (1/1000 EV), WhiteBalance 0x5005, ExposureProgramMode 0x500E, Nikon auto ISO 0xD054.
//   Card: GetStorageIDs, GetObjectHandles, GetObjectInfo, GetThumb, GetObject.

enum PTPOp {
    static let getDeviceInfo: UInt16 = 0x1001
    static let openSession: UInt16 = 0x1002
    static let closeSession: UInt16 = 0x1003
    static let getStorageIDs: UInt16 = 0x1004
    static let getObjectHandles: UInt16 = 0x1007
    static let getObjectInfo: UInt16 = 0x1008
    static let getObject: UInt16 = 0x1009
    static let getThumb: UInt16 = 0x100A
    static let initiateCapture: UInt16 = 0x100E
    static let getPartialObject: UInt16 = 0x101B
    static let getDevicePropDesc: UInt16 = 0x1014
    static let getDevicePropValue: UInt16 = 0x1015
    static let setDevicePropValue: UInt16 = 0x1016

    static let nikonCaptureToSDRAM: UInt16 = 0x90C0
    static let nikonAfDrive: UInt16 = 0x90C1
    static let nikonChangeCameraMode: UInt16 = 0x90C2
    static let nikonGetLargeThumb: UInt16 = 0x90C4
    static let nikonGetEvent: UInt16 = 0x90C7
    static let nikonDeviceReady: UInt16 = 0x90C8
    static let nikonStartLiveView: UInt16 = 0x9201
    static let nikonEndLiveView: UInt16 = 0x9202
    static let nikonGetLiveViewImage: UInt16 = 0x9203
    static let nikonMfDrive: UInt16 = 0x9204
    static let nikonChangeAfArea: UInt16 = 0x9205
    static let nikonCaptureToCard: UInt16 = 0x9207
    static let nikonStartMovie: UInt16 = 0x920A
    static let nikonEndMovie: UInt16 = 0x920B
    static let nikonGetEventEx: UInt16 = 0x941C
    static let nikonGetLiveViewImageEx: UInt16 = 0x9428
}

enum PTPProp {
    static let batteryLevel: UInt16 = 0x5001
    static let whiteBalance: UInt16 = 0x5005
    static let fNumber: UInt16 = 0x5007
    static let focalLength: UInt16 = 0x5008
    static let exposureTime: UInt16 = 0x500D
    static let exposureProgram: UInt16 = 0x500E
    static let iso: UInt16 = 0x500F
    static let exposureBias: UInt16 = 0x5010
    static let nikonAutoISO: UInt16 = 0xD054
    /// Nikon's own exposure time, numerator << 16 | denominator (0x500D is in 1/10000 s).
    static let nikonExposureTime: UInt16 = 0xD100
}

enum NikonResponse {
    static let outOfFocus: UInt16 = 0xA002
    static let changeCameraModeFailed: UInt16 = 0xA003
    static let invalidStatus: UInt16 = 0xA004
    static let notLiveView: UInt16 = 0xA00B
    static let mfDriveStepEnd: UInt16 = 0xA00C
    static let mfDriveStepInsufficiency: UInt16 = 0xA00E
    static let bulbReleaseBusy: UInt16 = 0xA200
    static let silentReleaseBusy: UInt16 = 0xA201
    static let mediaFull: UInt16 = 0xA207

    /// Answers that mean "not yet, ask again".
    static func isBusy(_ code: UInt16) -> Bool {
        [PTPError.deviceBusy, invalidStatus, bulbReleaseBusy, mediaFull].contains(code)
    }
}

@MainActor
final class NikonDriver: CameraDriver {
    unowned let camera: CameraModel
    private let ptp: PTPIPClient
    private var info: PTPDeviceInfo?
    private var descs: [UInt16: PTPPropDesc] = [:]
    /// UI value → raw camera value, per property name.
    private var valueMap: [String: [String: Int64]] = [:]
    private var liveTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init(camera: CameraModel) {
        self.camera = camera
        let (host, port) = PTPIPClient.split(camera.connectionHost, defaultPort: 15740)
        ptp = PTPIPClient(host: host, port: port)
    }

    var liveViewFormat: LiveViewFormat { .pushed }

    private func supports(_ op: UInt16) -> Bool { info?.operations.contains(op) ?? false }
    private func hasProperty(_ code: UInt16) -> Bool { info?.properties.contains(code) ?? false }

    var capabilities: CameraCapabilities {
        CameraCapabilities(liveViewSizes: [], tapToFocus: supports(PTPOp.nikonAfDrive),
                           openEndedExposure: false,
                           movie: supports(PTPOp.nikonStartMovie), videoSwitch: true,
                           lastShotReview: supports(PTPOp.nikonGetEvent) || supports(PTPOp.nikonGetEventEx),
                           clockSync: false, highResShot: false, cardBrowser: supports(PTPOp.getObjectHandles),
                           powerOff: false, focusDrive: supports(PTPOp.nikonMfDrive))
    }

    /// Stable per-install id: cameras that remember paired devices know us by it.
    static var guid: [UInt8] {
        let key = "nikon.guid"
        if let saved = UserDefaults.standard.data(forKey: key), saved.count == 16 { return [UInt8](saved) }
        let fresh = (0..<16).map { _ in UInt8.random(in: 0...255) }
        UserDefaults.standard.set(Data(fresh), forKey: key)
        return fresh
    }

    // MARK: - Connect

    func connect() async throws {
        let model = camera
        await ptp.setLogger { line in
            debugLog(line)
            Task { @MainActor in
                model.appendLog(LogEntry(date: Date(), method: "PTP", path: line, status: 200, millis: 0, summary: ""))
            }
        }
        camera.status = "Connecting (PTP/IP)…"
        var failure: Error?
        for attempt in 1...3 {
            do {
                try await ptp.connect(guid: Self.guid, name: UIDevice.current.name.isEmpty ? Platform.device : UIDevice.current.name)
                failure = nil
                break
            } catch {
                failure = error
                await ptp.close()
                guard attempt < 3, !(error is CameraError) else { break }
                camera.status = "No answer yet, retrying (\(attempt + 1)/3)…"
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
        if let failure { throw failure }

        try await ptp.run(PTPOp.openSession, [1])
        camera.status = "Reading camera info…"
        let deviceInfo = PTPDeviceInfo(try await ptp.run(PTPOp.getDeviceInfo).data)
        info = deviceInfo
        let name = await ptp.cameraName
        camera.cameraName = deviceInfo.model.isEmpty ? (name.isEmpty ? "Nikon" : name) : Self.displayName(deviceInfo.model)
        camera.rawCommandList = "Model: \(deviceInfo.model) \(deviceInfo.version)\nOperations: "
            + deviceInfo.operations.sorted().map { String(format: "0x%04X", $0) }.joined(separator: " ")
            + "\nProperties: " + deviceInfo.properties.sorted().map { String(format: "0x%04X", $0) }.joined(separator: " ")
        debugLog("NIKON \(camera.rawCommandList)")
        // Don't touch RecordingMedia (0xD10B): writing it hung a D600 over Wi-Fi (libgphoto2 bug 959).
        startStatus()
    }

    func disconnect() async {
        _ = try? await ptp.transaction(PTPOp.closeSession, timeout: 3)
    }

    func teardown() {
        liveTask?.cancel()
        liveTask = nil
        statusTask?.cancel()
        statusTask = nil
        let ptp = ptp
        Task { await ptp.close() }
    }

    /// Battery every few seconds; also keeps the session alive (Nikon drops one idle for ~30 s)
    /// and notices when the camera has gone.
    private func startStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                if let level = try? await self.readRaw(PTPProp.batteryLevel) {
                    failures = 0
                    if self.camera.liveInfo.battery != Int(level) { self.camera.liveInfo.battery = Int(level) }
                } else if self.hasProperty(PTPProp.batteryLevel) {
                    failures += 1
                    if failures == 3 {
                        self.camera.lastError = "Lost contact with the camera. Check that this \(Platform.device) is still on the camera's Wi-Fi."
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Helpers

    private func readRaw(_ code: UInt16) async throws -> Int64 {
        guard hasProperty(code) else { throw CameraError("No such property.") }
        let desc = PTPPropDesc(try await ptp.run(PTPOp.getDevicePropDesc, [UInt32(code)], timeout: 5).data)
        descs[code] = desc
        return desc.current
    }

    private func setRaw(_ code: UInt16, _ value: Int64) async throws {
        let desc: PTPPropDesc
        if let known = descs[code] { desc = known } else {
            desc = PTPPropDesc(try await ptp.run(PTPOp.getDevicePropDesc, [UInt32(code)]).data)
            descs[code] = desc
        }
        try await ptp.run(PTPOp.setDevicePropValue, [UInt32(code)], dataOut: desc.encode(value))
    }

    /// Polls DeviceReady until the camera stops answering Busy (after live view start, capture, AF).
    @discardableResult
    private func waitUntilReady(timeout: TimeInterval = 10) async -> UInt16 {
        guard supports(PTPOp.nikonDeviceReady) else {
            try? await Task.sleep(for: .milliseconds(500))
            return PTPError.ok
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let response = try? await ptp.transaction(PTPOp.nikonDeviceReady, timeout: 5) else { break }
            if response.code == NikonResponse.silentReleaseBusy { return PTPError.ok }
            if response.code != PTPError.deviceBusy && response.code != NikonResponse.bulbReleaseBusy { return response.code }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return PTPError.deviceBusy
    }

    // MARK: - Focus stacking

    /// MfDrive (0x9204): direction 1 = towards the closest point, 2 = towards infinity, then an amount
    /// (1–32767). Only works in live view and with the lens's AF/MF switch on AF (the camera drives it).
    func driveFocus(farther: Bool, step: FocusStepSize) async throws -> FocusDriveResult {
        let amount: UInt32 = switch step {
        case .fine: 40
        case .medium: 120
        case .coarse: 400
        }
        for attempt in 0..<2 {
            let response = try await ptp.transaction(PTPOp.nikonMfDrive, [farther ? 2 : 1, amount], timeout: 10)
            switch response.code {
            case PTPError.ok:
                await waitUntilReady()
                return .moved
            case NikonResponse.mfDriveStepEnd, NikonResponse.mfDriveStepInsufficiency:
                return .endOfTravel
            case NikonResponse.notLiveView where attempt == 0:
                // Live view pauses around each capture; give it a moment to come back.
                try? await Task.sleep(for: .milliseconds(800))
            case NikonResponse.notLiveView:
                throw CameraError("The camera only moves focus while live view is on.")
            default:
                throw PTPError(code: response.code, operation: PTPOp.nikonMfDrive)
            }
        }
        return .moved
    }

    // MARK: - Live view

    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        camera.mode = .rec
        await camera.refreshProperties()
        await camera.startLiveView()
    }

    private var liveViewOp: UInt16 {
        supports(PTPOp.nikonGetLiveViewImage) || !supports(PTPOp.nikonGetLiveViewImageEx)
            ? PTPOp.nikonGetLiveViewImage : PTPOp.nikonGetLiveViewImageEx
    }

    func startLiveView() async {
        guard supports(PTPOp.nikonStartLiveView) else {
            camera.liveViewRunning = false
            camera.lastError = "This Nikon doesn't offer live view over Wi-Fi. You can still change settings and shoot."
            return
        }
        do {
            // Remote ("PC") mode first, as libgphoto2 does; bodies that are already there say 0xA003.
            if supports(PTPOp.nikonChangeCameraMode) {
                _ = try? await ptp.transaction(PTPOp.nikonChangeCameraMode, [1])
            }
            try await ptp.run(PTPOp.nikonStartLiveView)
            await waitUntilReady(timeout: 5)
        } catch {
            camera.liveViewRunning = false
            camera.report(error)
            return
        }
        let ptp = ptp
        let op = liveViewOp
        liveTask?.cancel()
        liveTask = camera.pullLiveView(every: .milliseconds(15)) {
            // A header (128 or 384 bytes, by model) comes before the JPEG; the receiver finds FF D8.
            let response = try await ptp.transaction(op, timeout: 5)
            switch response.code {
            case PTPError.ok: return response.data
            case PTPError.deviceBusy, NikonResponse.invalidStatus:
                try? await Task.sleep(for: .milliseconds(30))
                return nil
            case NikonResponse.notLiveView:
                // The camera left live view (e.g. after a shot or on its own): start it again.
                _ = try? await ptp.transaction(PTPOp.nikonStartLiveView)
                try? await Task.sleep(for: .milliseconds(300))
                return nil
            default:
                throw PTPError(code: response.code, operation: op)
            }
        }
    }

    func stopLiveView() async {
        liveTask?.cancel()
        liveTask = nil
        _ = try? await ptp.transaction(PTPOp.nikonEndLiveView, timeout: 5)
    }

    // MARK: - Settings

    func refreshProperties() async {
        var result: [String: CameraProperty] = [:]
        valueMap = [:]

        func desc(_ code: UInt16) async -> PTPPropDesc? {
            guard hasProperty(code),
                  let data = try? await ptp.run(PTPOp.getDevicePropDesc, [UInt32(code)], timeout: 5).data else { return nil }
            let d = PTPPropDesc(data)
            descs[code] = d
            return d
        }
        func add(_ name: String, _ d: PTPPropDesc, label: (Int64) -> String?) {
            var map: [String: Int64] = [:]
            var options: [String] = []
            for raw in d.allowed {
                guard let text = label(raw), map[text] == nil else { continue }
                map[text] = raw
                options.append(text)
            }
            let value = label(d.current) ?? String(d.current)
            map[value] = map[value] ?? d.current
            valueMap[name] = map
            if !options.contains(value) { options.append(value) }
            result[name] = CameraProperty(name: name, settable: d.settable && options.count > 1, value: value, options: options)
        }

        if let d = await desc(PTPProp.exposureProgram) { add("takemode", d, label: Self.modeLabel) }
        if let d = await desc(PTPProp.fNumber), d.current > 0 {
            add("focalvalue", d) { $0 > 0 ? ExposureText.aperture(Double($0) / 100) : nil }
            let fs = d.allowed.filter { $0 > 0 }.map { Double($0) / 100 }
            if let lo = fs.min(), let hi = fs.max(), hi > lo { camera.liveInfo.apertureRange = lo...hi }
        }
        if hasProperty(PTPProp.nikonExposureTime), let d = await desc(PTPProp.nikonExposureTime) {
            add("shutspeedvalue", d) { Self.shutterLabel($0, packed: true) }
        } else if let d = await desc(PTPProp.exposureTime) {
            add("shutspeedvalue", d) { Self.shutterLabel($0, packed: false) }
        }
        if let d = await desc(PTPProp.iso) {
            let auto = await desc(PTPProp.nikonAutoISO)
            add("isospeedvalue", d) { $0 > 0 ? String($0) : nil }
            if let auto, auto.settable, var iso = result["isospeedvalue"] {
                // Nikon's auto ISO is a separate on/off switch; show it as one more ISO choice.
                iso.options.insert("auto", at: 0)
                if auto.current != 0 { iso.value = "auto" }
                iso.settable = true
                result["isospeedvalue"] = iso
            }
        }
        if let d = await desc(PTPProp.exposureBias) {
            add("expcomp", d) { ExposureText.ev(Double($0) / 1000) }
        }
        if let d = await desc(PTPProp.whiteBalance) { add("wbvalue", d, label: Self.whiteBalanceCode) }
        if let d = await desc(PTPProp.focalLength), d.current > 0 { camera.liveInfo.focalLength = Int(d.current / 100) }
        camera.properties = result
    }

    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        let code: UInt16?
        switch name {
        case "takemode": code = PTPProp.exposureProgram
        case "focalvalue": code = PTPProp.fNumber
        case "shutspeedvalue":
            code = hasProperty(PTPProp.nikonExposureTime) ? PTPProp.nikonExposureTime : PTPProp.exposureTime
        case "isospeedvalue": code = PTPProp.iso
        case "expcomp": code = PTPProp.exposureBias
        case "wbvalue": code = PTPProp.whiteBalance
        default: code = nil
        }
        guard let code else {
            if reportErrors { camera.lastError = "This setting can't be changed on a Nikon from the app." }
            return false
        }
        let previous = camera.properties[name]?.value
        camera.properties[name]?.value = value
        do {
            if name == "isospeedvalue", hasProperty(PTPProp.nikonAutoISO) {
                try await setRaw(PTPProp.nikonAutoISO, value == "auto" ? 1 : 0)
                if value == "auto" { await refreshProperties(); return true }
            }
            guard let raw = valueMap[name]?[value] else { throw CameraError("The camera doesn't offer \(value).") }
            try await setRaw(code, raw)
        } catch {
            if let previous { camera.properties[name]?.value = previous }
            if reportErrors { camera.report(error) }
            await refreshProperties()
            return false
        }
        await refreshProperties()
        return true
    }

    /// Nikon reports Mark II/III bodies as "Z 6_2", "Z 7_3": show them as people write them.
    static func displayName(_ model: String) -> String {
        model.replacingOccurrences(of: "_2", with: " II").replacingOccurrences(of: "_3", with: " III")
    }

    static func modeLabel(_ raw: Int64) -> String? {
        switch raw {
        case 1: "M"
        case 2: "P"
        case 3: "A"
        case 4: "S"
        case 0x8010, 0x8012: "iAuto"
        case 0x8050: "U1"
        case 0x8051: "U2"
        case 0x8052: "U3"
        case 0x8011...0x804F: "SCN"
        default: String(format: "0x%X", raw)
        }
    }

    /// Exposure time: Nikon's 0xD100 packs numerator << 16 | denominator (0x00010FA0 = 1/4000 s,
    /// 0x001E0001 = 30 s); PTP's 0x500D is in 1/10000 s. Bulb and Time are 0xFFFFFFFF / 0xFFFFFFFD.
    static func shutterSeconds(_ raw: Int64, packed: Bool) -> Double? {
        let value = UInt32(truncatingIfNeeded: raw)
        if value >= 0xFFFF_FFFC || value == 0 { return nil }
        if packed {
            let numerator = Double(value >> 16), denominator = Double(value & 0xFFFF)
            return denominator > 0 ? numerator / denominator : nil
        }
        return Double(value) / 10000
    }

    static func shutterLabel(_ raw: Int64, packed: Bool) -> String? {
        let value = UInt32(truncatingIfNeeded: raw)
        if value == 0xFFFF_FFFF { return "bulb" }
        if value == 0xFFFF_FFFD { return "time" }
        if value == 0xFFFF_FFFE || value == 0xFFFF_FFFC { return nil }   // flash sync / auto: not offered
        return shutterSeconds(raw, packed: packed).map(ExposureText.shutter(seconds:))
    }

    static func whiteBalanceCode(_ raw: Int64) -> String? {
        switch raw {
        case 2: "0"            // auto
        case 4: "18"           // daylight
        case 5: "35"           // fluorescent
        case 6: "20"           // incandescent
        case 7: "23"           // flash
        case 0x8010: "17"      // cloudy
        case 0x8011: "16"      // shade
        case 0x8012: "512"     // colour temperature
        case 0x8013: "256"     // preset manual
        case 0x8016: "natural_light_auto"
        default: "wb_\(raw)"
        }
    }

    // MARK: - Focus & shooting

    func focus(at normalized: CGPoint) async {
        let p = camera.pixelPoint(normalized)
        if supports(PTPOp.nikonChangeAfArea) {
            _ = try? await ptp.transaction(PTPOp.nikonChangeAfArea, [UInt32(max(0, p.x)), UInt32(max(0, p.y))])
        }
        do {
            try await ptp.run(PTPOp.nikonAfDrive)
            let result = await waitUntilReady(timeout: 6)
            camera.showAFResult(result == PTPError.ok, at: normalized)
        } catch {
            camera.showAFResult(false, at: normalized)
            debugLog("Nikon AF: \(error.localizedDescription)")
        }
    }

    func shutterPressed() async {
        camera.isShooting = true
        let seconds = PropertyFormat.seconds(fromShutter: camera.properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            camera.exposureStartedAt = Date()
            camera.exposureDuration = seconds
        }
        defer {
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.exposureDuration = nil
        }
        do {
            // 0x9207 (0xFFFFFFFF = no AF in live view, 0 = to the card) keeps live view running;
            // older bodies fall back to PTP's InitiateCapture, which also saves to the card.
            let (op, params): (UInt16, [UInt32]) = supports(PTPOp.nikonCaptureToCard)
                ? (PTPOp.nikonCaptureToCard, [0xFFFF_FFFF, 0]) : (PTPOp.initiateCapture, [0, 0])
            var attempts = 0
            while true {
                let response = try await ptp.transaction(op, params, timeout: max(30, seconds + 20))
                if response.code == PTPError.ok { break }
                attempts += 1
                guard NikonResponse.isBusy(response.code), attempts < 20 else {
                    throw PTPError(code: response.code, operation: op)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            await waitUntilReady(timeout: seconds * 2 + 20)
            camera.shotCounter += 1
            await showNewestCapture()
        } catch {
            camera.report(error)
        }
    }

    /// Bulb and Time need the shutter held, which Nikon's Wi-Fi commands don't offer.
    func toggleOpenExposure() async {
        camera.lastError = "Bulb and Time can't be run from the app on a Nikon. Pick a shutter speed (up to 30 s) or use the camera's own interval timer."
    }

    func toggleMovie() async {
        if camera.isRecordingMovie {
            _ = try? await ptp.transaction(PTPOp.nikonEndMovie)
            camera.isRecordingMovie = false
            camera.movieStartedAt = nil
            camera.shotCounter += 1
            return
        }
        do {
            try await ptp.run(PTPOp.nikonStartMovie)
            camera.isRecordingMovie = true
            camera.movieStartedAt = Date()
        } catch let error as PTPError {
            camera.lastError = error.code == 0xA00B || error.code == 0xA002
                ? "The camera won't record now. Set its photo/video switch to video, then try again."
                : error.localizedDescription
        } catch {
            camera.report(error)
        }
    }

    /// ObjectAdded handles from Nikon's event queue: GetEventEx (Z bodies: u16 count, then from
    /// offset 4 entries of u16 code, u16 parameter count, u32 parameters) or GetEvent (u16 count,
    /// then u16 code + u32 parameter).
    private func addedObjects() async -> [UInt32]? {
        var added: [UInt32] = []
        if supports(PTPOp.nikonGetEventEx) {
            guard let data = try? await ptp.run(PTPOp.nikonGetEventEx, timeout: 5).data else { return nil }
            var r = PTPReader(data)
            let count = Int(r.u16())
            r.offset = 4
            for _ in 0..<min(count, 512) {
                let code = r.u16(), n = Int(r.u16())
                let params = (0..<min(n, 16)).map { _ in r.u32() }
                if code == 0x4002, let handle = params.first { added.append(handle) }
            }
            return added
        }
        guard supports(PTPOp.nikonGetEvent), let data = try? await ptp.run(PTPOp.nikonGetEvent, timeout: 5).data else {
            return nil
        }
        var r = PTPReader(data)
        let count = Int(r.u16())
        for _ in 0..<min(count, 512) {
            let code = r.u16(), param = r.u32()
            if code == 0x4002 { added.append(param) }   // ObjectAdded
        }
        return added
    }

    /// Shows the thumbnail of the picture just taken.
    private func showNewestCapture() async {
        for _ in 0..<10 {
            guard let objects = await addedObjects() else { return }
            let added = objects.last
            if let handle = added {
                let op = supports(PTPOp.nikonGetLargeThumb) ? PTPOp.nikonGetLargeThumb : PTPOp.getThumb
                if let thumb = try? await ptp.run(op, [handle], timeout: 10).data, let image = UIImage(data: thumb) {
                    camera.lastShot = image.preparingForDisplay() ?? image
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: - Card

    /// Object handles by path, so previews and downloads can find them again.
    private var handles: [String: UInt32] = [:]

    func openGallery() async {
        do {
            camera.mode = .play
            handles = [:]
            var found: [CameraImage] = []
            var folderCounts: [String: Int] = [:]
            let storages = PTPReader(try await ptp.run(PTPOp.getStorageIDs).data).u32ArrayCopy()
            for storage in storages where storage & 0xFFFF != 0 {   // skip empty slots
                var list = PTPReader(try await ptp.run(PTPOp.getObjectHandles, [storage, 0, 0], timeout: 30).data).u32ArrayCopy()
                // Over Wi-Fi each file's info is a round trip; show the newest 300.
                list = Array(list.sorted().suffix(300))
                var folders: [UInt32: String] = [:]
                for handle in list.reversed() {
                    guard let data = try? await ptp.run(PTPOp.getObjectInfo, [handle], timeout: 5).data else { continue }
                    let object = PTPObjectInfo(data)
                    if object.isFolder { folders[handle] = object.filename; continue }
                    var folder = folders[object.parent]
                    if folder == nil { folder = await folderName(object.parent) }
                    let folderPath = folder ?? "DCIM"
                    folders[object.parent] = folderPath
                    let image = CameraImage(directory: folderPath, name: object.filename, size: Int(object.size),
                                            attributes: 0, date: object.date)
                    handles[image.path] = handle
                    found.append(image)
                    folderCounts[folderPath, default: 0] += 1
                }
            }
            camera.images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
            camera.cardFolders = folderCounts.map { CardFolder(path: $0.key, name: $0.key, count: $0.value,
                                                               isForeign: !$0.key.uppercased().contains("NIKON") && !$0.key.uppercased().contains("NZ")) }
                .sorted { $0.name > $1.name }
        } catch {
            camera.galleryError = CameraModel.describe(error, host: camera.connectionHost)
        }
    }

    private func folderName(_ handle: UInt32) async -> String? {
        guard handle != 0, handle != 0xFFFF_FFFF,
              let data = try? await ptp.run(PTPOp.getObjectInfo, [handle], timeout: 5).data else { return nil }
        return PTPObjectInfo(data).filename
    }

    func thumbnail(for image: CameraImage) async -> UIImage? {
        guard let handle = handles[image.path],
              let data = try? await ptp.run(PTPOp.getThumb, [handle], timeout: 10).data else { return nil }
        return UIImage(data: data)
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        guard let handle = handles[image.path] else { throw CameraError("The camera no longer lists this file.") }
        if supports(PTPOp.nikonGetLargeThumb), let data = try? await ptp.run(PTPOp.nikonGetLargeThumb, [handle], timeout: 20).data,
           let picture = UIImage(data: data) {
            return picture
        }
        if ["JPG", "JPEG"].contains(image.fileExtension) {
            let data = try await ptp.run(PTPOp.getObject, [handle], timeout: 120).data
            if let full = UIImage(data: data) { return full.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? full }
        }
        let data = try await ptp.run(PTPOp.getThumb, [handle], timeout: 10).data
        guard let thumb = UIImage(data: data) else { throw CameraError("Couldn't decode the preview.") }
        return thumb
    }

    /// Big transfers stall Nikon's Wi-Fi, so originals come in 1 MB pieces when the size is known.
    func downloadOriginal(_ image: CameraImage) async throws -> Data {
        guard let handle = handles[image.path] else { throw CameraError("The camera no longer lists this file.") }
        guard supports(PTPOp.getPartialObject), image.size > 0 else {
            return try await ptp.run(PTPOp.getObject, [handle], timeout: 600).data
        }
        let chunk = 1 << 20
        var data = Data(capacity: image.size)
        while data.count < image.size {
            try Task.checkCancellation()
            let piece = try await ptp.run(PTPOp.getPartialObject, [handle, UInt32(data.count), UInt32(chunk)], timeout: 60).data
            if piece.isEmpty { break }
            data.append(piece)
        }
        return data
    }
}

extension PTPReader {
    /// A UInt32 array dataset (GetStorageIDs, GetObjectHandles).
    func u32ArrayCopy() -> [UInt32] {
        var copy = self
        return copy.u32Array()
    }
}
