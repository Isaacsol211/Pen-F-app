import AVFoundation
import SwiftUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// Scans the Wi-Fi QR code on the camera's screen (iPhone and iPad; a Mac joins in System Settings).
@MainActor
enum CameraCodeScanner {
    #if targetEnvironment(macCatalyst)
    static var isSupported: Bool { false }
    #else
    static var isSupported: Bool { DataScannerViewController.isSupported }
    #endif

    /// Asks for the camera once; false when it's refused or restricted.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

#if !targetEnvironment(macCatalyst)
struct QRScannerSheet: View {
    /// Returns whether the code was one Shutterlink could read; the sheet closes when it was.
    let onCode: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var unreadable = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRScanner { text in
                    if onCode(text) {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { unreadable = true }
                    }
                }
                .ignoresSafeArea()
                Text(unreadable
                     ? "Shutterlink can't read this camera's code yet. Close this and type the network name and password shown next to the code."
                     : "Point at the QR code on the camera's screen.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .surface(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                    .padding(20)
            }
            .navigationTitle("Scan the camera's code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(unreadable ? "Type It Instead" : "Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// VisionKit's live scanner, reporting each new QR code once.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var lastCode: String?

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let code) in addedItems {
                guard let text = code.payloadStringValue, text != lastCode else { continue }
                lastCode = text
                onCode(text)
                return
            }
        }
    }
}
#endif
