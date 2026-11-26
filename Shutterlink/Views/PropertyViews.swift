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
                   isAnchor: { property.name == "expcomp" && Double($0) == 0 },
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

/// One setting's options as a wheel: the chosen value very large between two accent rules, the neighbours
/// shrinking and fading away above and below. Drag to turn it; tap a value to set it.
struct PropertyOptionsList: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    let property: CameraProperty

    @State private var position: Double?
    @State private var dragStart: Double?
    @State private var highlighted: String?

    private var current: CameraProperty { camera.properties[property.name] ?? property }
    private var options: [String] { current.options }
    private var centreIndex: Int {
        if let position { return Int(position.rounded()) }
        return options.firstIndex(of: highlighted ?? current.value) ?? 0
    }
    private var centre: Double { position ?? Double(centreIndex) }

    // Size and vertical offset by distance from the centre (in values), interpolated between whole steps.
    private static let sizes: [CGFloat] = [150, 38, 26, 20, 14]
    private static let offsets: [CGFloat] = [0, 128, 176, 212, 240]
    private func lerp(_ table: [CGFloat], _ d: Double) -> CGFloat {
        let a = min(abs(d), Double(table.count - 1))
        let i = Int(a), f = CGFloat(a - Double(i))
        return table[i] + (table[min(i + 1, table.count - 1)] - table[i]) * f
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let mid = geo.size.height / 2
                ZStack {
                    // The two accent rules round the chosen value.
                    VStack(spacing: 0) {
                        Rectangle().fill(Theme.accent).frame(height: 1)
                        Spacer()
                        Rectangle().fill(Theme.accent).frame(height: 1)
                    }
                    .frame(height: 168)
                    .position(x: geo.size.width / 2, y: mid)
                    ForEach(options.indices, id: \.self) { i in
                        let d = Double(i) - centre
                        if abs(d) < 4.5 {
                            let isCentre = abs(d) < 0.5
                            Button {
                                guard current.settable else { return }
                                Task { await camera.setProperty(property.name, to: options[i]) }
                                dismiss()
                            } label: {
                                Text(PropertyFormat.display(property.name, options[i]))
                                    .font(.num(lerp(Self.sizes, d), weight: isCentre ? .semibold : .medium))
                                    .foregroundStyle(isCentre ? Theme.text : Color(hex: 0xA9A8A2))
                                    .opacity(max(0.15, 1 - abs(d) * 0.22))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                    .frame(maxWidth: geo.size.width - 90)
                                    .frame(height: max(30, lerp(Self.sizes, d) * 1.05))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .position(x: geo.size.width / 2, y: mid + (d < 0 ? -1 : 1) * lerp(Self.offsets, d))
                            .accessibilityLabel(PropertyFormat.display(property.name, options[i]))
                            .accessibilityAddTraits(options[i] == current.value ? .isSelected : [])
                        }
                    }
                    // The pointer, left of the chosen value.
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 14))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Theme.accent)
                        .position(x: 28, y: mid)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { drag in
                            if dragStart == nil { dragStart = Double(centreIndex) }
                            let moved = -Double(drag.translation.height / 46)
                            position = min(Double(options.count - 1), max(0, (dragStart ?? 0) + moved))
                        }
                        .onEnded { _ in
                            dragStart = nil
                            highlighted = options.indices.contains(centreIndex) ? options[centreIndex] : nil
                            withAnimation(.snappy(duration: 0.2)) { position = nil }
                        }
                )
                .sensoryFeedback(.selection, trigger: centreIndex)
                .animation(.snappy(duration: 0.15), value: centreIndex)
            }
            let value = options.indices.contains(centreIndex) ? options[centreIndex] : current.value
            HStack {
                Text("\(options.count) options")
                Spacer()
                Text("camera code \(value)")
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Text(current.settable ? "Drag to turn, tap a value to set it." : "This setting is locked in the current mode.")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
                .padding(.bottom, 16)
        }
        .background { AmbientBackground() }
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
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Everything the camera lets the app read or change over Wi-Fi. Locked rows can't be changed in the current mode.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .listRowBackgroundClear(ambient: true)
            .navigationTitle("Camera settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reload") { Task { await camera.refreshProperties() } }
                }.sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Theme.text)
    }

    private func row(_ property: CameraProperty) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(PropertyFormat.title(for: property.name)).font(.system(size: 16, weight: .medium))
                Text(property.options.isEmpty ? property.name : "\(property.name) · \(property.options.count) options")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(PropertyFormat.display(property.name, property.value))
                .font(.num(22, weight: .medium))
                .foregroundStyle(property.settable ? Theme.text : Theme.secondary)
                .multilineTextAlignment(.trailing)
            if !property.settable {
                Image(systemName: "lock").font(.caption).foregroundStyle(Theme.tertiary)
            }
        }
        .listRowBackground(Color.clear)
    }
}
