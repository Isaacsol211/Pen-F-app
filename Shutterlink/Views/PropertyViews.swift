import SwiftUI

/// One setting's dial: the curved ruler across the bottom of the remote. The value is sent to the
/// camera when you let go.
struct ValueDial: View {
    let property: CameraProperty
    var readoutLabel: String?
    let onCommit: (String) -> Void

    @State private var selection: String

    init(property: CameraProperty, readoutLabel: String? = nil, onCommit: @escaping (String) -> Void) {
        self.property = property
        self.readoutLabel = readoutLabel
        self.onCommit = onCommit
        _selection = State(initialValue: property.value)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let readoutLabel {
                DialReadout(label: readoutLabel, value: Self.readoutText(property.name, selection))
            }
            dial
        }
        // The camera may adjust or reject a value (or a preset changed it): follow it.
        .onChange(of: property.value) { _, new in selection = new }
    }

    private var dial: some View {
        CurvedDial(options: property.options,
                   label: { Self.shortLabel(property.name, $0) },
                   isMajor: { Self.isMajor(property.name, $0) },
                   selection: $selection,
                   onCommit: { if $0 != property.value { onCommit($0) } })
    }

    /// The selected value as the big readout shows it.
    static func readoutText(_ name: String, _ value: String) -> String {
        switch name {
        case "focalvalue": return "f/" + shortLabel(name, value)
        case "takemode": return ModeCarousel.title(value)
        default: return PropertyFormat.display(name, value)
        }
    }

    /// Full stops get a tall, labelled tick; third stops a short one.
    static func isMajor(_ name: String, _ value: String) -> Bool {
        func nearWhole(_ x: Double, _ tolerance: Double) -> Bool { abs(x - x.rounded()) < tolerance }
        switch name {
        case "shutspeedvalue":
            guard let s = PropertyFormat.seconds(fromShutter: value) else { return true }
            return nearWhole(log2(s), 0.12)          // …1/250, 1/125, 1/60… 1", 2", 4", 8", 15"…
        case "isospeedvalue":
            // Only Auto gets a label among the named values: iAuto (LUMIX) and Low (PEN-F) sit right
            // next to it and the labels would overlap. The header still names the selected value.
            guard let iso = Double(value) else { return value.lowercased() == "auto" }
            return nearWhole(log2(iso / 100), 0.1)   // 200, 400, 800, 1600…
        case "focalvalue":
            guard let f = Double(value) else { return true }
            return nearWhole(2 * log2(f), 0.1)       // 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22
        case "expcomp":
            guard let ev = Double(value) else { return true }
            return nearWhole(ev, 0.05)               // −3 … +3 whole stops
        default:
            return true
        }
    }

    static func shortLabel(_ name: String, _ value: String) -> String {
        switch name {
        case "takemode": return ModeCarousel.title(value)
        case "focalvalue": return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
        case "expcomp":
            guard let ev = Double(value) else { return value }
            return ev == 0 ? "0" : String(format: "%+d", Int(ev.rounded()))
        default: return PropertyFormat.display(name, value)
        }
    }
}

/// List picker for one property, used from the full settings list.
struct PropertyOptionsList: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    let property: CameraProperty

    private var current: CameraProperty { camera.properties[property.name] ?? property }

    var body: some View {
        ScrollViewReader { proxy in
            List(current.options, id: \.self) { option in
                Button {
                    Task { await camera.setProperty(property.name, to: option) }
                    dismiss()
                } label: {
                    HStack {
                        let label = PropertyFormat.display(property.name, option)
                        Text(label).foregroundStyle(Theme.text)
                        Spacer()
                        if !label.contains(option) {
                            Text(option).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                        }
                        if option == current.value {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .disabled(!current.settable)
                .id(option)
            }
            .onAppear { proxy.scrollTo(current.value, anchor: .center) }
        }
        .navigationTitle(PropertyFormat.title(for: property.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every property the camera reports, for poking at things the main screen doesn't show.
struct AllSettingsView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let sorted = camera.properties.values.sorted {
                    PropertyFormat.title(for: $0.name).localizedCaseInsensitiveCompare(PropertyFormat.title(for: $1.name)) == .orderedAscending
                }
                Section {
                    ForEach(sorted) { property in
                        if property.settable && !property.options.isEmpty {
                            NavigationLink {
                                PropertyOptionsList(property: property)
                            } label: {
                                row(property)
                            }
                        } else {
                            row(property)
                        }
                    }
                } footer: {
                    Text("Everything the camera lets the app read or change over Wi-Fi. Locked rows can't be changed in the current mode.")
                }
            }
            .navigationTitle("Camera settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await camera.refreshProperties() } }
                }
            }
        }
    }

    private func row(_ property: CameraProperty) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(PropertyFormat.title(for: property.name))
                Text(property.options.isEmpty ? property.name : "\(property.name) · \(property.options.count) options")
                    .font(.caption.monospaced()).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(PropertyFormat.display(property.name, property.value))
                .font(.callout).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.trailing)
            if !property.settable {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}
