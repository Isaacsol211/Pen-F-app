import Foundation
import Photos

/// "Save new photos to Photos": each photo taken while connected goes to Photos as it's taken,
/// like the camera makers' auto transfer. Drivers report a new photo with a way to download it during
/// live view; cameras that can't send files during live view (LUMIX) have it saved from the card the
/// next time it's opened. The JPEG (or HEIF) is saved; RAW files stay on the card for the card browser.
/// Interval, bracketing and focus-stack sequences aren't auto-saved, so a time-lapse doesn't fill Photos.
extension CameraModel {
    var autoSaveApplies: Bool {
        autoSaveNewPhotos && !interval.running && !bracket.running
    }

    /// A photo was just taken and `fetch` downloads it without leaving live view. Saves run one at a
    /// time, after one another, so they never hold up the shutter.
    func autoSave(name: String, fetch: @escaping @MainActor () async throws -> Data) {
        guard autoSaveApplies else { return }
        let previous = autoSaveChain
        autoSaveChain = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, await self.photosAccessForAutoSave() else { return }
            do {
                let data = try await fetch()
                guard Self.isPhotoFile(data) else {
                    debugLog("auto-save \(name): not a JPEG or HEIF (\(data.count) bytes), skipped")
                    return
                }
                let image = CameraImage(directory: "", name: name, size: data.count, attributes: 0, date: Date())
                try await self.addToPhotos(data, for: image)
                debugLog("auto-save \(name): saved (\(data.count / 1024) KB)")
                self.showToast("Saved to Photos")
            } catch {
                debugLog("auto-save \(name): \(error.localizedDescription)")
                self.showToast("Couldn't save the new photo to Photos")
            }
        }
    }

    /// A photo was just taken but the camera can't send it during live view: save it from the card later.
    func autoSaveLater() {
        guard autoSaveApplies else { return }
        autoSavePending += 1
    }

    /// After the card opens: saves the newest photos that auto-save couldn't fetch during live view.
    func savePendingAutoSaves() async {
        guard autoSavePending > 0 else { return }
        let count = autoSavePending
        autoSavePending = 0
        guard autoSaveNewPhotos, await photosAccessForAutoSave() else { return }
        let newest = images
            .filter { !$0.isDirectory && Self.autoSaveExtensions.contains($0.fileExtension) }
            .sorted { ($0.date, $0.name) > ($1.date, $1.name) }
            .prefix(count)
        var saved = 0
        for image in newest.reversed() {
            do {
                try await saveOriginalToPhotos(image)
                saved += 1
            } catch {
                debugLog("auto-save \(image.name): \(error.localizedDescription)")
            }
        }
        if saved > 0 { showToast(saved == 1 ? "Saved the new photo to Photos" : "Saved \(saved) new photos to Photos") }
    }

    private static let autoSaveExtensions: Set<String> = ["JPG", "JPEG", "HIF", "HEIF", "HEIC"]

    /// JPEG starts FF D8; HEIF has "ftyp" at byte 4.
    static func isPhotoFile(_ data: Data) -> Bool {
        (data.count > 3 && data.starts(with: [0xFF, 0xD8])) || (data.count > 12 && data.dropFirst(4).starts(with: "ftyp".utf8))
    }

    /// Asks for add-only Photos access the first time; turns auto-save off if it's refused.
    private func photosAccessForAutoSave() async -> Bool {
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            autoSaveNewPhotos = false
            showToast("Photos access is off, so auto-save is off")
            return false
        }
        return true
    }

    /// A name for a photo the camera sends without its card file name (Olympus' last JPEG).
    func autoSaveName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let model = (cameraName ?? brand.title).replacingOccurrences(of: " ", with: "-")
        return "\(model)-\(stamp).JPG"
    }
}
