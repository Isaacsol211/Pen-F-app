import SwiftUI

/// Every request the app sent and what the camera answered. This is a test app,
/// so this is where to look when something doesn't work.
struct LogView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Camera") {
                    LabeledContent("Model", value: camera.cameraName ?? "–")
                    LabeledContent("Support", value: camera.profile?.support.rawValue ?? "Not in Shutterlink's model table")
                    ForEach(camera.profile?.notes ?? [], id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    LabeledContent("Connect mode", value: camera.connectMode ?? "–")
                    LabeledContent("Protocol version", value: camera.commands.version ?? "–")
                    LabeledContent("Live view port", value: "UDP \(camera.udpPort)")
                    NavigationLink("Command list") {
                        RawTextView(title: "get_commandlist", text: camera.rawCommandList)
                    }
                    NavigationLink("Settings (desclist)") {
                        RawTextView(title: "desclist", text: camera.rawDescList)
                    }
                }
                Section("Requests (newest first)") {
                    if camera.log.isEmpty {
                        Text("Nothing yet.").foregroundStyle(Theme.secondary)
                    }
                    ForEach(camera.log.reversed()) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
            .listStyle(.plain)
            .listRowBackgroundClear()
            .navigationTitle("Camera log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Copy log") {
                            UIPasteboard.general.string = camera.log.map(\.line).joined(separator: "\n")
                        }
                        Button("Clear log", role: .destructive) { camera.clearLog() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }.sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.status.map(String.init) ?? "ERR")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(entry.ok ? Theme.green : Theme.red)
                Text(entry.method).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(entry.millis) ms").font(.caption2.monospaced()).foregroundStyle(Theme.secondary)
            }
            Text(entry.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RawTextView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "(nothing received)" : text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Copy") { UIPasteboard.general.string = text }
        }
    }
}
