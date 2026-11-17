import SwiftUI

/// High Res Shot can't be switched on over Wi-Fi, so this walks through it and helps verify the result.
struct HighResView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.3x3.square")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.pulse, options: .repeating.speed(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("High Res Shot").font(.title3.weight(.semibold))
                            Text("8 sensor-shifted frames → 50 MP JPEG, 80 MP RAW")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    card {
                        Label("Turn it on at the camera", systemImage: "camera")
                            .font(.headline)
                        Text("The PEN-F doesn't accept this setting over Wi-Fi. On the camera, open MENU ▸ Shooting Menu 2 ▸ High Res Shot ▸ On (or press the button you've assigned to it). A 0 s delay is fine when you shoot from the phone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    card {
                        Label("Then", systemImage: "list.number").font(.headline)
                        step(1, "Tripod, and nothing moving in the scene: wind, water and people smear.")
                        step(2, "The camera limits High Res to slower ISOs and shorter exposures; check its screen.")
                        step(3, "Tap the shutter here. The camera takes about a second to capture, then a few more to merge. The app waits for it.")
                        step(4, "Open Card: High Res files show a 50 MP badge.")
                    }
                    card {
                        Label("For the night sky", systemImage: "moon.stars")
                            .font(.headline)
                        Text("Stars move between the 8 frames, so High Res suits landscapes and still subjects, not long star exposures. For astro, use the Astro preset and the interval timer to stack instead.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle("High Res Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

extension CameraImage {
    /// A normal PEN-F JPEG is ~8–12 MB and an ORF ~20–25 MB; High Res files are far bigger.
    var looksHighRes: Bool {
        switch fileExtension {
        case "JPG": size > 18_000_000
        case "ORF": size > 50_000_000
        default: false
        }
    }
}
