import SwiftUI

/// Browses the SD card. The camera has to be in playback mode for this, so live view
/// stops while it's open and restarts on Done.
struct GalleryView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @Namespace private var zoom
    @State private var starredOnly = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    private var visibleImages: [CameraImage] {
        starredOnly ? camera.images.filter { camera.isStarred($0) } : camera.images
    }

    private var starredCount: Int { camera.images.filter { camera.isStarred($0) }.count }
    private var importing: Bool { camera.rawImport != nil && camera.rawImport?.message == nil }

    var body: some View {
        NavigationStack {
            Group {
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
                                           description: Text("Tap and hold a photo to star it, or use the star when viewing it."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                            ForEach(camera.cardFolders.filter { folder in
                                !starredOnly || visibleImages.contains { $0.directory == folder.path }
                            }) { folder in
                                Section {
                                    folderContent(folder)
                                } header: {
                                    FolderHeader(folder: folder)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
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
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                        Task { await camera.closeGallery() }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await camera.openGallery() } }
                        .disabled(camera.galleryLoading)
                }
            }
            .safeAreaBar(edge: .bottom) { bottomBar }
            .animation(.smooth, value: camera.rawImport)
            .task { await camera.openGallery() }
        }
    }

    /// Filter, and "download the RAWs of the photos I starred".
    private var bottomBar: some View {
        VStack(spacing: 8) {
            RawImportBar()
            if !camera.images.isEmpty {
                HStack(spacing: 10) {
                    Picker("Show", selection: $starredOnly) {
                        Text("All").tag(false)
                        Text(starredCount > 0 ? "Starred · \(starredCount)" : "Starred").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 230)
                    Spacer(minLength: 0)
                    Button {
                        camera.downloadStarredRAWs()
                    } label: {
                        Label("RAWs", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.accent)
                    .tint(Theme.accent)
                    .disabled(starredCount == 0 || importing)
                    .accessibilityLabel("Download the RAW files of starred photos")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder private func folderContent(_ folder: CardFolder) -> some View {
        let items = visibleImages.filter { $0.directory == folder.path }
        if items.isEmpty && starredOnly {
            EmptyView()
        } else if items.isEmpty {
            Label(folder.isForeign
                  ? "The camera lists this folder (made by another camera) as empty, so nothing in it can be fetched over Wi-Fi. If it holds photos, put the card in a USB-C SD reader on your iPhone and use Photos ▸ Import."
                  : "No photos in this folder.",
                  systemImage: folder.isForeign ? "camera.badge.ellipsis" : "photo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 10)
        } else {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { image in
                    NavigationLink(value: image) {
                        ThumbnailCell(image: image)
                            .matchedTransitionSource(id: image.id, in: zoom)
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
            }
            .padding(.horizontal, 3)
        }
    }
}

private struct FolderHeader: View {
    let folder: CardFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            Text(folder.name).font(.subheadline.monospaced().weight(.semibold))
            Text("\(folder.count)")
                .font(.caption.monospacedDigit().weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .surface(.regular, in: .capsule)
            if folder.isForeign {
                Text("other camera").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6))
    }
}

private struct ThumbnailCell: View {
    @Environment(CameraModel.self) private var camera
    let image: CameraImage
    @State private var thumbnail: UIImage?
    @State private var noThumbnail = false

    var body: some View {
        Color(white: 0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill().transition(.opacity)
                } else if noThumbnail {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").font(.title3)
                        Text(image.name).font(.system(size: 9).monospaced()).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .animation(.smooth, value: thumbnail != nil)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if image.fileExtension != "JPG" { badge(image.fileExtension) }
                    if image.looksHighRes { badge("50 MP", tint: Theme.accent) }
                }
                .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                if camera.isStarred(image) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(4)
                        .background(Color.black.opacity(0.55), in: .circle)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Starred")
                }
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

    var body: some View {
        ZStack {
            Color.black
            if let preview {
                ZoomableImage(image: preview)
            } else if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.secondary).padding()
            } else {
                ProgressView()
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(image.name).font(.headline.monospaced())
                        Text(image.size == 0 && image.urls == nil
                             ? "From another camera"
                             : "\(image.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: Int64(image.size), countStyle: .file))\(image.looksHighRes ? " · High Res" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                }
                if let saveMessage {
                    Text(saveMessage).font(.footnote).foregroundStyle(.secondary).transition(.blurReplace)
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
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(.bouncy(duration: 0.35)) {
                    if scale > 1 { reset() } else { scale = 3; lastScale = 3 }
                }
            }
            .accessibilityLabel("Photo")
            .accessibilityHint("Pinch or double-tap to zoom")
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}
