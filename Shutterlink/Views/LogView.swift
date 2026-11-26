import SwiftUI

/// Every request the app sent and what the camera answered. This is a test app,
/// so this is where to look when something doesn't work.
struct LogView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Model", value: camera.cameraName ?? "–")
                    LabeledContent("Support", value: camera.profile?.support.rawValue ?? "Not in Shutterlink's model table")
                        .foregroundStyle(Theme.text)
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
                } header: { CapsLabel("Camera").padding(.top, 8) }
                Section {
                    if camera.log.isEmpty {
                        Text("Nothing yet.").foregroundStyle(Theme.secondary)
                    }
                    ForEach(camera.log.reversed()) { entry in
                        LogRow(entry: entry)
                    }
                } header: { CapsLabel("Requests (newest first)").padding(.top, 8) }
            }
            .font(.system(size: 15))
            .listStyle(.plain)
            .listRowBackgroundClear()
            .navigationTitle("Camera log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.sharedBackgroundVisibility(.hidden)
                // 407: "Copy log · Clear log" as plain text on the left.
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Button("Copy log") {
                            UIPasteboard.general.string = camera.log.map(\.line).joined(separator: "\n")
                        }
                        Text("·").foregroundStyle(Theme.tertiary)
                        Button("Clear log") { camera.clearLog() }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize()
                }.sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Theme.text)
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        if entry.note {
            // A line from the app itself (live view's frame rates): no status or time, and it wraps.
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.method).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(entry.path).font(.system(size: 13)).foregroundStyle(Theme.text).textSelection(.enabled)
            }
            .padding(.vertical, 2)
        } else {
            request
        }
    }

    private var request: some View {
        // 407: status in Barlow (green, or red ERR), method, time, then the path, on one line.
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(entry.status.map(String.init) ?? "ERR")
                    .font(.num(16))
                    .foregroundStyle(entry.ok ? Theme.green : Theme.red)
                    .frame(width: 34, alignment: .leading)
                Text(entry.method).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .frame(width: 38, alignment: .leading)
                Text("\(entry.millis) ms").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.secondary)
                    .frame(width: 50, alignment: .leading)
                Text(entry.path)
                    .font(.system(size: 13, weight: .semibold).monospaced())
                    .lineLimit(1).truncationMode(.tail)
                    .textSelection(.enabled)
            }
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
