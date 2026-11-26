import SwiftUI

struct LiveViewPane: View {
    @Environment(CameraModel.self) private var camera
    var showGrid = false
    var showHistogram = false
    @Binding var showLoupe: Bool
    /// Space taken by HUD drawn over the top of the image (landscape), so overlays sit below it.
    var hudTopInset: CGFloat = 0
    /// The focus readout and zoom are shown under the picture instead (portrait, 213).
    var loupeControlsBelow = false
    @State private var flash = 0.0
    // Loupe: magnify the whole viewfinder like a camera's focus assist.
    @AppStorage("loupe.zoom") private var loupeZoom = 4.0
    @State private var loupeCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var panStart: CGPoint?
    @State private var pinchStart: Double?
    /// Where the motion box was when a drag on it began.
    @State private var motionDragStart: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let content = camera.frameSpace
            let imageRect = Self.fitRect(content, in: bounds)

            ZStack(alignment: .topLeading) {
                Color(white: 0.05)

                if showLoupe {
                    magnified(in: imageRect)
                } else {
                    LiveImage()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)
                }

                if showGrid && !showLoupe {
                    CompositionGrid()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)
                        .transition(.opacity)
                }

                if !showLoupe { afOverlay(in: imageRect) }

                if !showLoupe, camera.motion.armed || camera.motion.editing {
                    motionBox(in: imageRect)
                }

                if showHistogram, !showLoupe, !camera.histogram.isEmpty {
                    HistogramView(values: camera.histogram)
                        .frame(width: 100, height: 36)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .surface(.clear, in: .rect(cornerRadius: 12, style: .continuous))
                        .padding(10)
                        .frame(width: bounds.width, height: bounds.height, alignment: .topTrailing)
                        .padding(.top, hudTopInset + (camera.focusPoint != nil ? 40 : 0))
                        .allowsHitTesting(false)
                        .transition(.blurReplace)
                }

                if showLoupe {
                    loupeHUD(bounds: bounds)
                        .transition(.opacity)
                }

                Color.white.opacity(flash).allowsHitTesting(false)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusOverlay(stalled: camera.isLiveViewStalled(at: context.date))
                        .frame(width: bounds.width, height: bounds.height)
                }

                if camera.focusPoint != nil, !showLoupe {
                    Button { Task { await camera.clearFocus() } } label: {
                        Label("AF", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.surface)
                    .padding(10)
                    .padding(.top, hudTopInset)
                    .frame(width: bounds.width, alignment: .trailing)
                    .accessibilityLabel("Clear focus point")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard imageRect.width > 0, imageRect.height > 0 else { return }
                if showLoupe {
                    // In the loupe, a tap re-centres the magnified area on that spot.
                    let p = sourcePoint(location, in: imageRect)
                    withAnimation(.snappy) { loupeCenter = clamped(p) }
                    return
                }
                let normalized = CGPoint(x: (location.x - imageRect.minX) / imageRect.width,
                                         y: (location.y - imageRect.minY) / imageRect.height)
                guard (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return }
                Task { await camera.tapFocus(normalized: normalized) }
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard showLoupe, imageRect.width > 0 else { return }
                        let start = panStart ?? loupeCenter
                        if panStart == nil { panStart = start }
                        let big = CGSize(width: imageRect.width * loupeZoom, height: imageRect.height * loupeZoom)
                        loupeCenter = clamped(CGPoint(x: start.x - value.translation.width / big.width,
                                                      y: start.y - value.translation.height / big.height))
                    }
                    .onEnded { _ in panStart = nil },
                including: showLoupe ? .all : .subviews
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        guard showLoupe else { return }
                        let start = pinchStart ?? loupeZoom
                        if pinchStart == nil { pinchStart = start }
                        loupeZoom = min(10, max(2, start * value.magnification))
                    }
                    .onEnded { _ in pinchStart = nil },
                including: showLoupe ? .all : .subviews
            )
        }
        .clipped()
        .animation(.smooth, value: showGrid)
        .animation(.smooth, value: showHistogram)
        .animation(.smooth(duration: 0.35), value: showLoupe)
        .onChange(of: showLoupe) { _, on in
            if on { loupeCenter = clamped(camera.focusPoint ?? CGPoint(x: 0.5, y: 0.5)) }
            updateMeter()
        }
        .onChange(of: loupeCenter) { updateMeter() }
        .onChange(of: loupeZoom) { updateMeter() }
        .onAppear { updateMeter() }
        .onChange(of: camera.shotCounter) {
            flash = 0.85
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
        }
    }

    // MARK: - Loupe

    /// The motion trigger's box: dashed while it's being placed, solid amber while armed. Drag to move.
    private func motionBox(in imageRect: CGRect) -> some View {
        let region = camera.motion.region
        let armed = camera.motion.armed
        let color: Color = armed ? Theme.accent : .white
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return shape
            .fill(color.opacity(armed ? 0.08 : 0.05))
            .overlay(shape.stroke(color, style: StrokeStyle(lineWidth: 2, dash: armed ? [] : [6, 4])))
            .overlay(alignment: .topLeading) {
                CapsLabel(armed ? "Motion · \(camera.motion.shots)" : "Motion box", color: color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: .capsule)
                    .padding(5)
            }
            .frame(width: region.width * imageRect.width, height: region.height * imageRect.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = motionDragStart ?? region.origin
                        if motionDragStart == nil { motionDragStart = start }
                        var moved = region
                        moved.origin.x = min(max(start.x + value.translation.width / imageRect.width, 0), 1 - region.width)
                        moved.origin.y = min(max(start.y + value.translation.height / imageRect.height, 0), 1 - region.height)
                        camera.motion.region = moved
                    }
                    .onEnded { _ in motionDragStart = nil }
            )
            .offset(x: imageRect.minX + region.minX * imageRect.width, y: imageRect.minY + region.minY * imageRect.height)
            .accessibilityLabel(armed ? "Motion trigger armed, \(camera.motion.shots) shots" : "Motion trigger box")
    }

    private func magnified(in imageRect: CGRect) -> some View {
        let big = CGSize(width: imageRect.width * loupeZoom, height: imageRect.height * loupeZoom)
        let x = imageRect.width / 2 - loupeCenter.x * big.width
        let y = imageRect.height / 2 - loupeCenter.y * big.height
        return LiveImage(smooth: true)
            .frame(width: big.width, height: big.height)
            .offset(x: x, y: y)
            .frame(width: imageRect.width, height: imageRect.height, alignment: .topLeading)
            .clipped()
            .offset(x: imageRect.minX, y: imageRect.minY)
    }

    private func loupeHUD(bounds: CGSize) -> some View {
        ZStack {
            // Crosshair at the centre of the magnified area.
            ZStack {
                Rectangle().frame(width: 1, height: 18)
                Rectangle().frame(width: 18, height: 1)
            }
            .foregroundStyle(Theme.accent.opacity(0.9))
            .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    // 213: "Loupe ×" on the left, the minimap on the right.
                    Button { showLoupe = false } label: {
                        HStack(spacing: 4) {
                            Text("Loupe")
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .frame(minHeight: Theme.target, alignment: .top)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close loupe")
                    Spacer()
                    MiniMap(center: loupeCenter, zoom: loupeZoom)
                }
                Spacer()
                if !loupeControlsBelow { HStack(alignment: .bottom) {
                    FocusMeter(score: camera.focusScore, peak: camera.focusPeak, floor: camera.focusFloor)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([2.0, 4.0, 8.0], id: \.self) { z in
                            Button("\(Int(z))×") { withAnimation(.snappy) { loupeZoom = z } }
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(abs(loupeZoom - z) < 0.5 ? Theme.accent : .white)
                                .frame(width: Theme.target, height: Theme.target)
                                .contentShape(.rect)
                        }
                    }
                    .padding(.horizontal, 4)
                    .surface(.regular, in: .capsule)
                } }
            }
            .padding(10)
            .padding(.top, hudTopInset)
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    /// Keep the magnified area inside the frame.
    private func clamped(_ p: CGPoint) -> CGPoint {
        let half = 0.5 / max(loupeZoom, 1)
        return CGPoint(x: min(max(p.x, half), 1 - half), y: min(max(p.y, half), 1 - half))
    }

    /// A point on screen while magnified → normalised point in the full frame.
    private func sourcePoint(_ location: CGPoint, in imageRect: CGRect) -> CGPoint {
        let dx = (location.x - imageRect.midX) / (imageRect.width * loupeZoom)
        let dy = (location.y - imageRect.midY) / (imageRect.height * loupeZoom)
        return CGPoint(x: loupeCenter.x + dx, y: loupeCenter.y + dy)
    }

    private func updateMeter() {
        guard showLoupe else {
            camera.setFocusMeterRegion(nil)
            return
        }
        // Measure the middle half of what's magnified, where the crosshair is.
        let w = 0.5 / loupeZoom, h = 0.5 / loupeZoom
        camera.setFocusMeterRegion(CGRect(x: loupeCenter.x - w / 2, y: loupeCenter.y - h / 2, width: w, height: h))
    }

    @ViewBuilder
    private func afOverlay(in imageRect: CGRect) -> some View {
        let lv = camera.frameSpace
        let sx = imageRect.width / lv.width
        let sy = imageRect.height / lv.height
        let info = camera.liveInfo

        if info.afState > 0, info.afRect.width > 0 {
            let r = info.afRect
            RoundedRectangle(cornerRadius: 3)
                .stroke(info.afState == 1 ? Color.green : Color.red, lineWidth: 2)
                .frame(width: r.width * sx, height: r.height * sy)
                .position(x: imageRect.minX + r.midX * sx, y: imageRect.minY + r.midY * sy)
                .allowsHitTesting(false)
        } else if let n = camera.focusPoint {
            let p = CGPoint(x: n.x * lv.width, y: n.y * lv.height)
            FocusBrackets()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 56, height: 56)
                .keyframeAnimator(initialValue: 1.6, trigger: n) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(0.9, duration: 0.22, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.2, spring: .bouncy)
                }
                .position(x: imageRect.minX + p.x * sx, y: imageRect.minY + p.y * sy)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func statusOverlay(stalled: Bool) -> some View {
        if camera.frameSize == .zero || stalled || camera.isSwitchingMode || camera.mode != .rec {
            VStack(spacing: 12) {
                if stalled {
                    Image(systemName: "video.slash").font(.title)
                    Text("No live view frames are arriving.")
                        .font(.headline)
                    Text("The camera sends live view to UDP port \(camera.udpPort). Check that Local Network access is on for Shutterlink in \(Platform.settings) ▸ Privacy & Security, then restart live view.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Restart live view") { Task { await camera.restartLiveView() } }
                        .buttonStyle(.accent)
                } else if camera.isSwitchingMode || camera.liveViewRunning || camera.mode != .rec {
                    ProgressView()
                    Text(camera.mode == .rec ? "Starting live view…" : "Switching to shooting mode…")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "video").font(.title)
                    Text("Live view is off").font(.subheadline).foregroundStyle(.secondary)
                    Button("Start live view") { Task { await camera.restartLiveView() } }
                        .buttonStyle(.accent)
                }
            }
            .padding(24)
            .surface(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(camera.frameSize == .zero ? Color.clear : Color.black.opacity(0.45))
            .transition(.opacity)
        }
    }

    static func fitRect(_ content: CGSize, in bounds: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// Four corner brackets, like a camera's AF target.
struct FocusBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let l = min(rect.width, rect.height) * 0.28
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x + dx * l, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * l))
        }
        return p
    }
}

/// The only view that reads the per-frame image, so a new frame redraws just this.
private struct LiveImage: View {
    @Environment(CameraModel.self) private var camera
    var smooth = false

    var body: some View {
        if let frame = camera.liveFrame {
            Image(uiImage: frame)
                .resizable()
                .interpolation(smooth ? .high : .medium)
                .overlay {
                    if camera.focusPeaking, let peaks = camera.peakingOverlay {
                        Image(uiImage: peaks)
                            .resizable()
                            .interpolation(.medium)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// Where the magnified area sits in the whole frame.
private struct MiniMap: View {
    @Environment(CameraModel.self) private var camera
    let center: CGPoint
    let zoom: Double

    var body: some View {
        let size = CGSize(width: 84, height: 63)
        ZStack(alignment: .topLeading) {
            Color.black
            if let frame = camera.ambientFrame {
                Image(uiImage: frame).resizable()
            }
            Rectangle()
                .stroke(Theme.accent, lineWidth: 1.5)
                .frame(width: size.width / zoom, height: size.height / zoom)
                .offset(x: (center.x - 0.5 / zoom) * size.width, y: (center.y - 0.5 / zoom) * size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .padding(3)
        .surface(.regular, in: .rect(cornerRadius: 11, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The loupe's controls under the picture (213): zoom chips, then FOCUS over a big reading in Barlow
/// ("SHARPEST" in green at the peak) and its bar.
struct LoupeReadout: View {
    @Environment(CameraModel.self) private var camera
    @AppStorage("loupe.zoom") private var loupeZoom = 4.0

    var body: some View {
        let reading = FocusReading(score: camera.focusScore, peak: camera.focusPeak, floor: camera.focusFloor)
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach([2.0, 4.0, 8.0], id: \.self) { z in
                    let on = abs(loupeZoom - z) < 0.5
                    Button { withAnimation(.snappy) { loupeZoom = z } } label: {
                        Text("\(Int(z))×")
                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.background : Theme.text)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(on ? Theme.text : Color.black.opacity(0.25)))
                            .overlay(Circle().stroke(on ? Color.clear : Theme.text.opacity(0.35), lineWidth: 1))
                            .frame(width: Theme.target, height: Theme.target)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Int(z)) times")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            VStack(spacing: 4) {
                Text("FOCUS").font(.system(size: 12, weight: .medium)).tracking(1.7).foregroundStyle(Theme.accent)
                Text(reading.atPeak ? "SHARPEST" : reading.swept ? "keep turning" : "turn the ring slowly")
                    .font(.num(reading.atPeak ? 54 : 40))
                    .foregroundStyle(reading.atPeak ? Theme.green : Theme.text)
                    .contentTransition(.interpolate)
                    .lineLimit(1).minimumScaleFactor(0.6)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.stroke)
                        Capsule().fill(reading.atPeak ? Theme.green : Theme.accent)
                            .frame(width: geo.size.width * reading.fraction)
                            .animation(.smooth(duration: 0.15), value: reading.fraction)
                    }
                }
                .frame(width: 210, height: 6)
                .padding(.top, 4)
            }
            .accessibilityElement()
            .accessibilityLabel("Focus meter")
            .accessibilityValue(reading.atPeak ? "Sharpest" : "\(Int(reading.fraction * 100)) percent of best")
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.success, trigger: reading.atPeak) { _, new in new }
    }
}

/// How sharp the loupe's view is against the best and worst seen since it moved.
struct FocusReading {
    let fraction: Double
    let swept: Bool
    let atPeak: Bool

    init(score: Double?, peak: Double, floor: Double) {
        // Only call a peak once the focus has actually been swept: the best reading must stand
        // clearly above the worst, and there must be detail (stars, edges) to measure.
        let range = peak - (floor.isFinite ? floor : peak)
        swept = range > max(3, peak * 0.2)
        fraction = (score != nil && swept) ? min(1, max(0, ((score ?? 0) - (peak - range)) / range)) : 0.15
        atPeak = swept && fraction > 0.95
    }
}

/// Sharpness bar for manual focus: turn the ring until it peaks (green = at the best seen).
private struct FocusMeter: View {
    let score: Double?
    let peak: Double
    let floor: Double

    var body: some View {
        // Only call a peak once the focus has actually been swept: the best reading must stand
        // clearly above the worst, and there must be detail (stars, edges) to measure.
        let range = peak - (floor.isFinite ? floor : peak)
        let swept = range > max(3, peak * 0.2)
        let fraction = (score != nil && swept) ? min(1, max(0, ((score ?? 0) - (peak - range)) / range)) : 0.15
        let atPeak = swept && fraction > 0.95
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("FOCUS").font(.system(size: 9, weight: .bold)).tracking(1)
                Text(atPeak ? "SHARPEST" : swept ? "keep turning" : "turn the ring slowly")
                    .font(.system(size: 9, weight: atPeak ? .bold : .regular))
                    .foregroundStyle(atPeak ? Color.green : .secondary)
                    .contentTransition(.interpolate)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(atPeak ? Color.green : Theme.accent)
                    .frame(width: 130 * fraction)
                    .animation(.smooth(duration: 0.15), value: fraction)
            }
            .frame(width: 130, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .surface(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.success, trigger: atPeak) { _, new in new }
        .accessibilityElement()
        .accessibilityLabel("Focus meter")
        .accessibilityValue(atPeak ? "Sharpest" : "\(Int(fraction * 100)) percent of best")
    }
}
