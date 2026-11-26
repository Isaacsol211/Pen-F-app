import SwiftUI

// The workspace layouts: what the app does with a large canvas (every iPad, full screen or in a
// big Stage Manager / Split View window). They are picked from the space a view is given, never
// from the device, so a window that is resized moves between them and the phone layouts live.

enum Workspace {
    /// The short side, safe areas included, from which a screen gets the workspace layouts. The
    /// smallest iPad (mini, 744 pt) is above it; an iPhone Duo's unfolded screen (669 pt) and every
    /// iPhone are below it and keep the phone layouts.
    static let workspaceSide: CGFloat = 700

    static func isWorkspace(_ geo: GeometryProxy) -> Bool {
        let insets = geo.safeAreaInsets
        let width = geo.size.width + insets.leading + insets.trailing
        let height = geo.size.height + insets.top + insets.bottom
        return min(width, height) >= workspaceSide
    }
}

/// A 1 pt rule between the regions of a workspace layout.
struct Hairline: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .accessibilityHidden(true)
    }
}

// MARK: - Exposure

/// The exposure values as a grid of big readouts, always in view in the inspector. Tap one for its
/// dial, which opens right under the grid. Shows what the camera is actually using, like the strip.
struct ExposureGrid: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 23

    private var items: [String] {
        var names = ["focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode", "quality"]
        if camera.isMovieMode { names.append("exposemovie") }
        return names.filter { camera.properties[$0] != nil }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items, id: \.self) { name in
                cell(name)
            }
        }
        .animation(.snappy, value: active)
        .animation(.smooth, value: items)
        .disabled(camera.isBusyExposing)
        .sensoryFeedback(.selection, trigger: active)
    }

    private func cell(_ name: String) -> some View {
        let property = camera.properties[name].map(camera.dialOptions(for:))
        let locked = !(property?.settable ?? false)
        let selected = active == name
        let auto = Self.isAuto(name, locked: locked, mode: camera.properties["takemode"]?.value)
        let value = Self.value(name, property, camera: camera)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            active = selected ? nil : name
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // AUTO replaces the label when the camera is choosing this value itself.
                CapsLabel(auto ? "Auto" : Self.label(name),
                          color: selected ? Theme.onAccent.opacity(0.75) : (auto ? Theme.accent.opacity(0.85) : Theme.secondary))
                Group {
                    if name == "drivemode" {
                        HStack(spacing: 6) {
                            Image(systemName: SettingSpec.optionIcon(name, property?.value ?? "") ?? "square")
                            readout(camera.stripValue(name, property), scale: 0.72)
                        }
                        .font(.system(size: valueSize * 0.85, weight: .semibold))
                        .frame(height: valueSize * 1.2)
                    } else if name == "wbvalue" {
                        // A named white balance in full where the cell is wide enough for it.
                        ViewThatFits(in: .horizontal) {
                            readout(value, scale: 1)
                            readout(value, scale: 0.72)
                            readout(camera.stripValue(name, property), scale: 0.72)
                        }
                        .frame(height: valueSize * 1.2)
                    } else {
                        readout(value, scale: 1)
                            .contentTransition(.numericText())
                            .frame(height: valueSize * 1.2)
                    }
                }
                .foregroundStyle(selected ? Theme.onAccent : (auto ? Theme.secondary : Theme.text))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(shape.fill(selected ? Theme.accent : Color.clear))
            .overlay(shape.stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(value)\(auto ? ", automatic" : "")")
        .accessibilityHint("Shows the options")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func readout(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.num(valueSize * scale * 1.15))
            .lineLimit(1)
    }

    /// The strip's value, except that there's room here to name the white balance in full.
    static func value(_ name: String, _ property: CameraProperty?, camera: CameraModel) -> String {
        if name == "wbvalue", let raw = property?.value, raw != "0", let full = PropertyFormat.whiteBalance[raw] {
            return full
        }
        return camera.stripValue(name, property)
    }

    /// The camera picks this value itself (shutter in A, aperture in S…), so the cell says AUTO. Not
    /// for drive or quality, and not for EV in M, where it simply has no effect.
    static func isAuto(_ name: String, locked: Bool, mode: String?) -> Bool {
        guard locked, !["drivemode", "quality"].contains(name) else { return false }
        return !(name == "expcomp" && mode?.uppercased() == "M")
    }

    static func label(_ name: String) -> String {
        switch name {
        case "focalvalue": "F-stop"
        case "shutspeedvalue": "Shutter"
        case "isospeedvalue": "ISO"
        case "expcomp": "EV"
        case "wbvalue": "WB"
        case "drivemode": "Drive"
        case "quality": "Quality"
        case "exposemovie": "Video"
        default: name
        }
    }
}

// MARK: - Histogram

/// The live histogram at a size you can judge exposure from, in the inspector instead of a
/// thumbnail over the picture.
struct HistogramCard: View {
    @Environment(CameraModel.self) private var camera
    var height: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Histogram", color: Theme.tertiary)
            HistogramView(values: camera.histogram)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(12)
        .surface(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Tools

/// The tools as tiles that stay in view, in one grid: the ones that open their own panel first
/// (the arrow on a tile says so), then the switches.
struct ToolTiles: View {
    let tools: [ToolItem]
    /// A fixed number of tiles per row (the inspector, whose width is known); else as many 108 pt
    /// tiles as the column fits.
    var columns: Int?

    var body: some View {
        let grid = columns.map { Array(repeating: GridItem(.flexible(), spacing: 8), count: $0) }
            ?? [GridItem(.adaptive(minimum: 108), spacing: 8)]
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Tools", color: Theme.tertiary)
                .padding(.leading, 2)
                .padding(.top, 4)
            LazyVGrid(columns: grid, spacing: 8) {
                ForEach(tools.filter(\.opens) + tools.filter { !$0.opens }) { ToolTextTile(item: $0) }
            }
        }
    }
}

/// A tool in the inspector (design 502): its name on a small tile, white when it is on; a lock for a
/// locked Pro tool, ↗ for one that opens a panel.
struct ToolTextTile: View {
    let item: ToolItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: item.action) {
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(item.on ? Theme.background : Theme.text)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: Theme.target)
                .background(shape.fill(item.on ? Theme.text : Color.clear))
                .overlay(shape.stroke(item.on ? Color.clear : Theme.outline, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if item.locked {
                        Image(systemName: "lock").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.accent).padding(4)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.on)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.opens ? "" : (item.on ? "On" : "Off"))
        .accessibilityHint(item.locked ? "Part of Shutterlink Pro" : (item.opens ? "Opens \(item.title)" : ""))
    }
}

// MARK: - Side panels

/// The tools that are sheets on a phone and panels in the workspace inspector.
enum SidePanel: String, Identifiable {
    case interval, bracket, highRes, presets, nd, motion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval: "Interval timer"
        case .bracket: "Bracketing"
        case .highRes: "High Res Shot"
        case .presets: "Presets"
        case .nd: "ND filter"
        case .motion: "Motion trigger"
        }
    }

    var icon: String {
        switch self {
        case .interval: "timer"
        case .bracket: "square.stack.3d.down.right"
        case .highRes: "square.grid.3x3.square"
        case .presets: "wand.and.stars"
        case .nd: "camera.filters"
        case .motion: "figure.walk.motion"
        }
    }
}

/// A tool's panel. In the inspector: a title bar with a close button over its content, with the live
/// view and the shutter in view beside it. With no `onClose`, the phone's sheet: the same content in
/// a scroll view with a Done button.
struct SidePanelView: View {
    let panel: SidePanel
    var onClose: (() -> Void)?
    var openAstro: () -> Void = {}
    var openFocusStack: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let onClose {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(panel.title).font(.num(26))
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.text)
                            .frame(width: Theme.target, height: Theme.target)
                    }
                    .accessibilityLabel("Close \(panel.title)")
                }
                content
            }
        } else {
            // A design screen (3xx): the title on the left, Done on the right, then the content.
            VStack(spacing: 0) {
                ScreenHeader(panel.title) { HeaderButton("Done") { dismiss() } }
                    .padding(.top, 6)
                ScrollView {
                    content.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            // Presets sit on the blurred live view, as designed; the other screens on black.
            .background { if panel == .presets { AmbientBackground() } else { Theme.background.ignoresSafeArea() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch panel {
        case .interval: IntervalPanel()
        case .bracket: BracketPanel()
        case .highRes: HighResPanel()
        case .presets: PresetsPanel(openAstro: openAstro, openFocusStack: openFocusStack)
        case .nd: NDPanel()
        case .motion: MotionPanel()
        }
    }
}

/// Sheet sizing that only changes on a large canvas: a page-sized sheet there, the system's
/// automatic size (what the phone layouts have always had) everywhere else.
struct WorkspaceSheetSizing: PresentationSizing {
    var page: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        page ? PagePresentationSizing.page.proposedSize(for: root, context: context)
             : AutomaticPresentationSizing.automatic.proposedSize(for: root, context: context)
    }
}
