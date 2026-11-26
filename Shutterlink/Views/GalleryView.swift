import SwiftUI
import UniformTypeIdentifiers

/// Browses the SD card. The camera has to be in playback mode for this, so live view
/// stops while it's open and restarts on Done.
struct GalleryView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @Namespace private var zoom
    @State private var starredOnly = false
    /// Workspace only: the photo in the preview pane.
    @State private var selectedID: CameraImage.ID?
    /// Mac: the open panel that picks where the starred RAWs go.
    @State private var pickRawFolder = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]
    /// Larger thumbnails where there's a large canvas to fill.
    private static let workspaceColumns = [GridItem(.adaptive(minimum: 120), spacing: 3)]

    private var visibleImages: [CameraImage] {
        starredOnly ? camera.images.filter { camera.isStarred($0) } : camera.images
    }

    private var starredCount: Int { camera.images.filter { camera.isStarred($0) }.count }
    private var importing: Bool { camera.rawImport != nil && camera.rawImport?.message == nil }

    var body: some View {
        GeometryReader { geo in
            let workspace = Workspace.isWorkspace(geo)
            let landscape = geo.size.width > geo.size.height
            NavigationStack {
                Group {
                    if workspace, !camera.images.isEmpty {
                        split(landscape: landscape, size: geo.size)
                    } else {
                        browser(workspace: false)
                            // A flat black bar, as designed, not system glass.
                            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                    }
                }
                .navigationTitle(camera.images.isEmpty ? "On the card" : "On the card · \(camera.images.count)")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: CameraImage.self) { image in
                    PhotoPager(images: visibleImages, start: image)
                        .navigationTransition(.zoom(sourceID: image.id, in: zoom))
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                            Task { await camera.closeGallery() }
                        }
                    }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reload") { Task { await camera.openGallery() } }
                            .foregroundStyle(Theme.secondary)
                            .disabled(camera.galleryLoading)
                    }.sharedBackgroundVisibility(.hidden)
                }
                .tint(Theme.text)
                .animation(.smooth, value: camera.rawImport)
                .task { await camera.openGallery() }
            }
        }
    }

    /// The card's folders and thumbnails, or why there's nothing to show.
    @ViewBuilder private func browser(workspace: Bool) -> some View {
        if camera.galleryLoading && camera.images.isEmpty {
            ProgressView("Reading the card…")
        } else if let error = camera.galleryError, camera.images.isEmpty {
            ContentUnavailableView("Couldn't read the card", systemImage: "sdcard",
                                   description: Text(error))
        } else if camera.images.isEmpty && camera.cardFolders.isEmpty {
            ContentUnavailableView("No photos", systemImage: "photo.on.rectangle",
                                   description: Text("Nothing on the card yet."))
        } else if starredOnly && starredCount == 0 {
            ContentUnavailableView("No starred photos", systemImage: "star",
                                   description: Text("\(Platform.isMac ? "Right-click" : "Tap and hold") a photo to star it, or use the star when viewing it."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    ForEach(camera.cardFolders.filter { folder in
                        !starredOnly || visibleImages.contains { $0.directory == folder.path }
                    }) { folder in
                        Section {
                            folderContent(folder, selects: workspace)
                        } header: {
                            FolderHeader(folder: folder)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Workspace (large canvases)

    /// The photo shown in the preview pane: the one you picked, else the first JPEG listed (cameras
    /// don't serve a preview for every RAW), else the first photo.
    private var previewed: CameraImage? {
        visibleImages.first { $0.id == selectedID }
            ?? visibleImages.first { $0.fileExtension == "JPG" }
            ?? visibleImages.first
    }

    /// Browser and preview together: side by side on a wide canvas, preview over the browser on a
    /// tall one. Tapping a thumbnail shows it in the preview; the preview opens full screen.
    @ViewBuilder private func split(landscape: Bool, size: CGSize) -> some View {
        let grid = browser(workspace: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaBar(edge: .bottom) { bottomBar }
        if landscape {
            HStack(spacing: 0) {
                grid.frame(width: min(560, max(330, (size.width * 0.38).rounded())))
                Hairline(axis: .vertical).ignoresSafeArea(edges: .bottom)
                previewPane
            }
        } else {
            VStack(spacing: 0) {
                previewPane.frame(height: (size.height * 0.5).rounded())
                Hairline()
                grid
            }
        }
    }

    @ViewBuilder private var previewPane: some View {
        if let image = previewed {
            PhotoPage(image: image)
                .id(image.id)
                .overlay(alignment: .topTrailing) {
                    NavigationLink(value: image) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.surfaceCircle)
                    .padding(12)
                    .accessibilityLabel("Full screen")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No photo selected", systemImage: "photo",
                                   description: Text("Pick a photo to see it here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Filter, and "download the RAWs of the photos I starred".
    private var bottomBar: some View {
        VStack(spacing: 8) {
            RawImportBar()
            if !camera.images.isEmpty {
                HStack(spacing: 8) {
                    ForEach([false, true], id: \.self) { starred in
                        Button(starred ? (starredCount > 0 ? "Starred · \(starredCount)" : "Starred") : "All") {
                            withAnimation(.snappy) { starredOnly = starred }
                        }
                        .buttonStyle(ChipStyle(selected: starredOnly == starred))
                        .accessibilityAddTraits(starredOnly == starred ? .isSelected : [])
                    }
                    .sensoryFeedback(.selection, trigger: starredOnly)
                    Spacer(minLength: 0)
                    Button {
                        // On a Mac the RAWs go to a folder you pick (for Lightroom, Capture One…);
                        // on iPhone and iPad, to Photos.
                        if Platform.isMac { pickRawFolder = true } else { camera.downloadStarredRAWs() }
                    } label: {
                        Label(Platform.isMac ? "RAWs…" : "RAWs", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.accent)
                    .fixedSize()
                    .disabled(starredCount == 0 || importing)
                    .accessibilityLabel(Platform.isMac ? "Save the RAW files of starred photos to a folder"
                                                       : "Download the RAW files of starred photos")
                    .help("Save the RAW files of starred photos to a folder")
                    .fileImporter(isPresented: $pickRawFolder, allowedContentTypes: [.folder]) { result in
                        if case .success(let folder) = result { camera.downloadStarredRAWs(to: folder) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
        }
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    /// `selects`: a tap shows the photo in the preview pane (the workspace split) instead of opening it.
    @ViewBuilder private func folderContent(_ folder: CardFolder, selects: Bool) -> some View {
        let items = visibleImages.filter { $0.directory == folder.path }
        if items.isEmpty, !starredOnly {
            Label(folder.isForeign
                  ? "The camera lists this folder (made by another camera) as empty, so nothing in it can be fetched over Wi-Fi. If it holds photos, \(Platform.isMac ? "put the card in your Mac's SD card slot or a card reader and import it with Photos or Finder" : "put the card in a USB-C SD reader on your iPhone and use Photos ▸ Import")."
                  : "No photos in this folder.",
                  systemImage: folder.isForeign ? "camera.badge.ellipsis" : "photo")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 10)
        } else if !items.isEmpty {
            let perRow = selects ? 4 : 3
            let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
            LazyVStack(spacing: 8) {
              ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                FilmStrip {
                  ForEach(row) { image in
                    Group {
                        if selects {
                            // In the split, a tap shows the photo in the preview pane.
                            let selected = previewed?.id == image.id
                            Button {
                                selectedID = image.id
                            } label: {
                                ThumbnailCell(image: image)
                                    .matchedTransitionSource(id: image.id, in: zoom)
                                    .overlay {
                                        if selected {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Theme.accent, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        } else {
                            NavigationLink(value: image) {
                                ThumbnailCell(image: image)
                                    .matchedTransitionSource(id: image.id, in: zoom)
                            }
                        }
                    }
                    .contextMenu {
                        let starred = camera.isStarred(image)
                        Button(starred ? "Remove star" : "Star", systemImage: starred ? "star.slash" : "star") {
                            camera.toggleStar(image)
                        }
                        if !starred, camera.rawCompanion(of: image) != nil, image.fileExtension == "JPG" {
                            Text("Has a RAW file")
                        }
                    }
                  }
                  if row.count < perRow {
                      ForEach(0..<(perRow - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                  }
                }
              }
            }
        }
    }
}

private struct FolderHeader: View {
    let folder: CardFolder

    var body: some View {
        HStack(spacing: 10) {
            Text(folder.name).font(.num(20)).tracking(0.8)
            Text("\(folder.count)")
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Theme.stroke, in: .capsule)
            if folder.isForeign {
                Text("other camera").font(.caption).foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.background.opacity(0.92))
    }
}

/// A row of frames on a strip of film: sprocket holes above and below.
private struct FilmStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 4) {
            holes
            HStack(alignment: .top, spacing: 8) { content }
            holes
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color(hex: 0x161513))
    }

    private var holes: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: 0, width: 9, height: size.height), cornerRadius: 2),
                         with: .color(Theme.background))
                x += 18
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A hand-drawn red circle round a starred frame.
private struct Scribble: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        path.move(to: p(0.09, 0.51))
        path.addCurve(to: p(0.62, 0.06), control1: p(0.07, 0.15), control2: p(0.38, 0.03))
        path.addCurve(to: p(0.93, 0.62), control1: p(0.9, 0.1), control2: p(0.98, 0.36))
        path.addCurve(to: p(0.31, 0.92), control1: p(0.88, 0.9), control2: p(0.53, 1.0))
        path.addCurve(to: p(0.10, 0.44), control1: p(0.12, 0.86), control2: p(0.05, 0.7))
        return path
    }
}

private struct ThumbnailCell: View {
    @Environment(CameraModel.self) private var camera
    let image: CameraImage
    @State private var thumbnail: UIImage?
    @State private var noThumbnail = false

    private var frameNumber: String {
        let index = (camera.images.firstIndex { $0.id == image.id } ?? 0) + 1
        return "\(index)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            picture
            Text(frameNumber)
                .font(.num(13, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color(hex: 0xE8B04A))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picture: some View {
        Color(hex: 0x1F1F1D)
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill().transition(.opacity)
                } else if noThumbnail {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").font(.title3)
                        Text(image.name).font(.system(size: 9).monospaced()).lineLimit(1)
                    }
                    .foregroundStyle(Theme.secondary)
                    .padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .animation(.smooth, value: thumbnail != nil)
            .clipShape(.rect(cornerRadius: 2, style: .continuous))
            .overlay {
                if camera.isStarred(image) {
                    Scribble().stroke(Color(hex: 0xFF4B3A), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(-3)
                        .transition(.opacity)
                        .accessibilityLabel("Starred")
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if image.fileExtension != "JPG" { badge(image.fileExtension) }
                    if image.looksHighRes { badge("50 MP", tint: Theme.accent) }
                }
                .padding(4)
            }
            .animation(.bouncy, value: camera.isStarred(image))
            .task(id: image.path) {
                thumbnail = await camera.thumbnail(for: image)
                noThumbnail = thumbnail == nil
            }
    }

    private func badge(_ text: String, tint: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Swipe between photos; each one zooms with a pinch or a double tap.
private struct PhotoPager: View {
    /// The photos as they were when the pager opened, so unstarring one while the Starred filter
    /// is on doesn't pull it out from under you.
    @State private var images: [CameraImage]
    @State private var selection: CameraImage.ID

    init(images: [CameraImage], start: CameraImage) {
        _images = State(initialValue: images)
        _selection = State(initialValue: start.id)
    }

    private var current: CameraImage? { images.first { $0.id == selection } }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(images) { image in
                PhotoPage(image: image).tag(image.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(current?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotoPage: View {
    @Environment(CameraModel.self) private var camera
    let image: CameraImage
    @State private var preview: UIImage?
    @State private var loadError: String?
    @State private var saving = false
    @State private var saveMessage: String?
    /// Mac: the original, downloaded and waiting for the save panel.
    @State private var exportFile: OriginalFile?
    @State private var exporting = false

    var body: some View {
        ZStack {
            Color.black
            if let preview {
                ZoomableImage(image: preview)
            } else if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(Theme.secondary).padding()
            } else {
                ProgressView()
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(image.name).font(.num(24))
                        Text(image.size == 0 && image.urls == nil
                             ? "From another camera"
                             : "\(image.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: Int64(image.size), countStyle: .file))\(image.looksHighRes ? " · High Res" : "")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button {
                        camera.toggleStar(image)
                    } label: {
                        Image(systemName: camera.isStarred(image) ? "star.fill" : "star")
                            .foregroundStyle(camera.isStarred(image) ? Theme.accent : .white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.surfaceCircle)
                    .sensoryFeedback(.selection, trigger: camera.isStarred(image))
                    .accessibilityLabel(camera.isStarred(image) ? "Remove star" : "Star")
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.accent)
                    .tint(Theme.accent)
                    .allowsHitTesting(!saving)
                    #if targetEnvironment(macCatalyst)
                    // The original as it came off the card, to a folder you pick.
                    Button {
                        Task { await saveAs() }
                    } label: {
                        Label("Save As…", systemImage: "folder")
                    }
                    .buttonStyle(.surface)
                    .allowsHitTesting(!saving)
                    .fileExporter(isPresented: $exporting, document: exportFile, contentType: .data,
                                  defaultFilename: image.name) { result in
                        switch result {
                        case .success(let url): saveMessage = "Saved \(url.lastPathComponent) to \(url.deletingLastPathComponent().lastPathComponent)."
                        case .failure(let error): saveMessage = error.localizedDescription
                        }
                        exportFile = nil
                    }
                    #endif
                }
                if let saveMessage {
                    Text(saveMessage).font(.footnote).foregroundStyle(Theme.secondary).transition(.blurReplace)
                }
            }
            .padding(14)
            .surface(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .animation(.smooth, value: saveMessage)
        }
        .task {
            do { preview = try await camera.preview(for: image) } catch { loadError = error.localizedDescription }
        }
    }

    #if targetEnvironment(macCatalyst)
    private func saveAs() async {
        saving = true
        saveMessage = nil
        defer { saving = false }
        do {
            exportFile = OriginalFile(data: try await camera.downloadOriginal(image))
            exporting = true
        } catch {
            saveMessage = error.localizedDescription
        }
    }
    #endif

    private func save() async {
        saving = true
        saveMessage = nil
        defer { saving = false }
        do {
            let tagged = try await camera.saveOriginalToPhotos(image)
            saveMessage = tagged ? "Saved the full-size original to Photos, with its location."
                : "Saved the full-size original to Photos."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

/// Pinch to zoom (up to 8×), drag to pan, double-tap to toggle 1× / 3×.
private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(8, max(1, lastScale * value.magnification)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation(.smooth) { reset() } }
                    }
            )
            // Panning only while zoomed in. At 1× the drag must not claim the touch, or the pager
            // never sees the swipe to the previous or next photo.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.bouncy(duration: 0.35)) {
                    if scale > 1 { reset() } else { scale = 3; lastScale = 3 }
                }
            }
            .accessibilityLabel("Photo")
            .accessibilityHint("Pinch or double-tap to zoom. Swipe for the next photo")
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// A photo or video as it came off the card, for the Mac's save panel.
struct OriginalFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
