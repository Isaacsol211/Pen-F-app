import SwiftUI

/// Browses the SD card. The camera has to be in playback mode for this, so live view
/// stops while it's open and restarts on Done.
struct GalleryView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @Namespace private var zoom

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

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
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                            ForEach(camera.cardFolders) { folder in
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
                PhotoPager(images: camera.images, start: image)
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
            .task { await camera.openGallery() }
        }
    }

    @ViewBuilder private func folderContent(_ folder: CardFolder) -> some View {
        let items = camera.images.filter { $0.directory == folder.path }
        if items.isEmpty {
            Label(folder.isForeign
                  ? "The PEN-F lists this folder (made by another camera) as empty, so nothing in it can be fetched over Wi-Fi. If it holds photos, put the card in a USB-C SD reader on your iPhone and use Photos ▸ Import."
                  : "No photos in this folder.",
                  systemImage: folder.isForeign ? "camera.badge.ellipsis" : "photo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 10)
        } else {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { image in
                    NavigationLink(value: image) {
                        ThumbnailCell(image: image)
                            .matchedTransitionSource(id: image.id, in: zoom)
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
                .glassEffect(.regular, in: .capsule)
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
    let images: [CameraImage]
    @State private var selection: CameraImage.ID

    init(images: [CameraImage], start: CameraImage) {
        self.images = images
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
                        Text(image.size == 0
                             ? "From another camera"
                             : "\(image.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: Int64(image.size), countStyle: .file))\(image.looksHighRes ? " · High Res" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .allowsHitTesting(!saving)
                }
                if let saveMessage {
                    Text(saveMessage).font(.footnote).foregroundStyle(.secondary).transition(.blurReplace)
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
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
            try await camera.saveOriginalToPhotos(image)
            saveMessage = "Saved the full-size original to Photos."
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
