import MessageUI
import SwiftUI

/// Report a problem: what happened in the tester's words, plus the camera log and this device's
/// details, by email (or the share sheet where Mail isn't set up).
struct ReportProblemView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var showMail = false
    @State private var copied = false

    static let address = "isaacsolomon211@gmail.com"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened? What did you tap, and what did you expect?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                } footer: {
                    Text("The report adds the camera log, the camera's model, your \(Platform.device) model and \(Platform.os) version. Wi-Fi passwords are left out.")
                }
                Section {
                    if MFMailComposeViewController.canSendMail() {
                        Button("Email the report") { showMail = true }
                    } else {
                        ShareLink(item: report, subject: Text(subject)) {
                            Label("Send the report", systemImage: "square.and.arrow.up")
                        }
                        Button(copied ? "Copied" : "Copy the report") {
                            UIPasteboard.general.string = report
                            copied = true
                        }
                        LabeledContent("Send it to", value: Self.address).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showMail) {
                MailView(subject: subject, body: note, report: report) { sent in
                    showMail = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var subject: String {
        "Shutterlink problem: \(camera.cameraName ?? camera.brand.title) (\(Self.appVersion))"
    }

    private var report: String { camera.problemReport(note: note) }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

extension CameraModel {
    /// Everything a problem report carries, as plain text.
    func problemReport(note: String) -> String {
        var lines = [
            "Shutterlink problem report",
            "",
            note.isEmpty ? "(no description)" : note,
            "",
            "App: \(ReportProblemView.appVersion), Pro: \(ShutterlinkPro.shared.statusText)",
            "Device: \(Self.deviceModel), \(Platform.os) \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Camera: \(cameraName ?? "not connected"), brand \(autoDetectBrand ? "automatic (\(brand.rawValue))" : brand.rawValue), address \(host.isEmpty ? "default" : host)",
            "Model table: \(profile?.name ?? "not in the table")",
            "Connection: \(phase), protocol \(commands.version ?? "–"), connect mode \(connectMode ?? "–"), live view \(liveViewQuality)",
        ]
        if let lastError { lines.append("Last error: \(lastError)") }
        lines += ["", "Camera log, oldest first:"]
        // A scanned QR code can hold the camera's Wi-Fi password.
        lines += log.map { entry in
            guard entry.method == "QR" else { return entry.line }
            return LogEntry(date: entry.date, method: "QR", path: "(code left out)", status: entry.status,
                            millis: 0, summary: entry.summary).line
        }
        if !rawCommandList.isEmpty { lines += ["", "Command list:", rawCommandList] }
        if !rawDescList.isEmpty { lines += ["", "Settings:", rawDescList] }
        return lines.joined(separator: "\n")
    }

    /// e.g. "iPhone18,1"; the Simulator says which device it's standing in for.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// Mail's compose sheet with the report attached.
private struct MailView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let report: String
    let finished: (_ sent: Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([ReportProblemView.address])
        mail.setSubject(subject)
        mail.setMessageBody(body, isHTML: false)
        mail.addAttachmentData(Data(report.utf8), mimeType: "text/plain", fileName: "shutterlink-report.txt")
        return mail
    }

    func updateUIViewController(_ mail: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    /// Mail calls back on the main thread.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let finished: (Bool) -> Void

        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result == .sent)
        }
    }
}
