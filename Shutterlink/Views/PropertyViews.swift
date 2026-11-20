import SwiftUI

/// Horizontal row of glass chips for the main exposure settings. Tapping one opens its dial.
struct PropertyStrip: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    let onMore: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(PropertyFormat.featured, id: \.name) { item in
                        if let property = camera.properties[item.name] {
                            PropertyChip(title: item.title,
                                         value: PropertyFormat.display(property.name, property.value),
                                         enabled: property.settable && !property.options.isEmpty,
                                         selected: active == item.name) {
                                withAnimation(.snappy) { active = active == item.name ? nil : item.name }
                            }
                        }
                    }
                    PropertyChip(title: "All", value: "\(camera.properties.count) ›", enabled: true, selected: false, action: onMore)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
        .overlay {
            if camera.properties.isEmpty && camera.mode == .rec && !camera.isSwitchingMode {
                Text("No settings read yet. Use ··· ▸ Reload settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PropertyChip: View {
    let title: String
    let value: String
    let enabled: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                    if !enabled {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                    }
                }
                .foregroundStyle(enabled ? Theme.accent : .secondary)
                Text(value)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(enabled ? .white : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: 72, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .surface(selected ? .regular.tint(Theme.accent.opacity(0.45)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 16, style: .continuous))
        .disabled(!enabled)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A camera-style dial: swipe through a property's values; the one under the marker is applied
/// iPhone Camera–style exposure ruler: fine ticks for every step, taller labelled ticks on full
/// stops, a fixed centre marker, the live value above, and a haptic tick for every step crossed
/// (a firmer one on full stops). The value is sent to the camera when scrolling stops.
struct ValueDial: View {
    let property: CameraProperty
    var showsTitle = true
    let onCommit: (String) -> Void

    @State private var centered: String?
    @State private var committed: String

    init(property: CameraProperty, showsTitle: Bool = true, onCommit: @escaping (String) -> Void) {
        self.property = property
        self.showsTitle = showsTitle
        self.onCommit = onCommit
        _centered = State(initialValue: property.value)
        _committed = State(initialValue: property.value)
    }

    private var usesIcons: Bool { property.name == "wbvalue" }
    private var spacing: CGFloat { usesIcons ? 46 : (property.name == "shutspeedvalue" ? 13 : 11) }
    private var current: String { centered ?? committed }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if showsTitle {
                    Text(PropertyFormat.title(for: property.name).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                Text(PropertyFormat.display(property.name, current))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: current)
            }
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(property.options, id: \.self) { option in
                                tick(option)
                                    .frame(width: spacing)
                                    .contentShape(.rect)
                                    .id(option)
                                    .onTapGesture { select(option, proxy: proxy) }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, max(0, (geo.size.width - spacing) / 2), for: .scrollContent)
                    // Snap to each tick; .never lets a fling run through many steps.
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                    .scrollPosition(id: $centered, anchor: .center)
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle, let centered { commit(centered) }
                    }
                    .task {
                        // Start centred on the current value (the initial scroll position isn't reliable).
                        try? await Task.sleep(for: .milliseconds(20))
                        proxy.scrollTo(committed, anchor: .center)
                    }
                    .onChange(of: property.value) { _, newValue in
                        // The camera may adjust or reject a value (or a preset changed it): follow it.
                        committed = newValue
                        if centered != newValue {
                            withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
                            centered = newValue
                        }
                    }
                    .overlay(alignment: .top) {
                        // Centre marker.
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: 2, height: usesIcons ? 20 : 22)
                            .offset(y: -3)
                            .allowsHitTesting(false)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                               .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(PropertyFormat.title(for: property.name))
                    .accessibilityValue(PropertyFormat.display(property.name, current))
                    .accessibilityAdjustableAction { direction in
                        guard let index = property.options.firstIndex(of: current) else { return }
                        let next = direction == .increment ? index + 1 : index - 1
                        guard property.options.indices.contains(next) else { return }
                        select(property.options[next], proxy: proxy)
                    }
                }
            }
            .frame(height: usesIcons ? 40 : 30)
        }
        .padding(.vertical, 4)
        // A light click per step and a solid thunk on full stops, like a detented dial.
        .sensoryFeedback(trigger: centered) { _, new in
            guard let new else { return nil }
            return Self.isMajor(property.name, new) ? .impact(weight: .heavy, intensity: 1.0) : .selection
        }
    }

    @ViewBuilder private func tick(_ option: String) -> some View {
        let major = Self.isMajor(property.name, option)
        let selected = option == current
        VStack(spacing: 4) {
            Capsule()
                .fill(selected ? Theme.accent : Color.white.opacity(major ? 0.85 : 0.4))
                .frame(width: major ? 1.5 : 1, height: usesIcons ? 12 : (major ? 14 : 8))
            if usesIcons {
                Image(systemName: SettingSpec.optionIcon(property.name, option) ?? "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Color.white.opacity(0.7))
            } else if major {
                Text(Self.shortLabel(property.name, option))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Theme.accent : Color.white.opacity(0.6))
                    .fixedSize()
            }
        }
        .frame(height: usesIcons ? 40 : 30, alignment: .top)
    }

    private func select(_ option: String, proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo(option, anchor: .center) }
        centered = option
        commit(option)
    }

    private func commit(_ value: String) {
        guard value != committed else { return }
        committed = value
        onCommit(value)
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
                        Text(label).foregroundStyle(.white)
                        Spacer()
                        if !label.contains(option) {
                            Text(option).font(.caption.monospaced()).foregroundStyle(.secondary)
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
                let sorted = camera.properties.values.sorted { $0.name < $1.name }
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
                    Text("Read with get_camprop.cgi?com=desc&propname=desclist. Locked rows are read-only in the current mode.")
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
                Text(property.name).font(.body.monospaced())
                if !property.options.isEmpty {
                    Text("\(property.options.count) options").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(property.value).font(.callout.monospaced()).foregroundStyle(.secondary)
            if !property.settable {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
