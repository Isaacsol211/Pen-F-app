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
        // A design screen (106): Cancel top right, a big heading, the camera feed in a framed square,
        // and, when the code can't be read, a note and "Type It Instead".
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("") { HeaderButton("Cancel") { dismiss() } }
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan the camera's code")
                    .font(.num(40))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Point at the QR code on the camera's screen.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 20)
            // A square: the feed inside, the accent corners just outside it (106).
            ZStack {
                QRScanner { text in
                    if onCode(text) {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { unreadable = true }
                    }
                }
                .frame(width: 220, height: 220)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                ViewfinderCorners()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 260, height: 260)
            }
            .frame(width: 260, height: 260)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Camera viewfinder")
            Spacer(minLength: 20)
            VStack(spacing: 12) {
                if unreadable {
                    Text("Shutterlink can't read this camera's code yet. Close this and type the network name and password shown next to the code.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background.opacity(0.86)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent, lineWidth: 1))
                        .transition(.blurReplace)
                }
                // Always there, as designed: back to typing the network's name and password.
                Button("Type It Instead") { dismiss() }
                    .buttonStyle(.outline)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(hex: 0x141412).ignoresSafeArea())
    }
}

/// The four corner brackets round the scanner's square (106).
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 34
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 8))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 8, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 8), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 8))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 8, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 8), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
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
