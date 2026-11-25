import SwiftUI

/// High Res Shot can't be switched on over Wi-Fi, so this walks through it and helps verify the
/// result: in a sheet on a phone, in the inspector on a large canvas.
struct HighResPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BigNumber(value: "50 MP", caption: "8 sensor-shifted frames → 50 MP JPEG, 80 MP RAW", size: 120)
            card(spacing: 10) {
                Label("Turn it on at the camera", systemImage: "camera")
                    .font(.headline)
                Text("Olympus cameras don't accept this setting over Wi-Fi. On the camera, open MENU ▸ Shooting Menu 2 ▸ High Res Shot ▸ On (or press the button you've assigned to it). A 0 s delay is fine when you shoot from the phone.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            card(spacing: 10) {
                Label("Then", systemImage: "list.number").font(.headline)
                step(1, "Tripod, and nothing moving in the scene: wind, water and people smear.")
                step(2, "The camera limits High Res to slower ISOs and shorter exposures; check its screen.")
                step(3, "Tap the shutter here. The camera takes about a second to capture, then a few more to merge. The app waits for it.")
                step(4, "Open Card: High Res files show a 50 MP badge.")
            }
            card(spacing: 10) {
                Label("For the night sky", systemImage: "moon.stars")
                    .font(.headline)
                Text("Stars move between the 8 frames, so High Res suits landscapes and still subjects, not long star exposures. For astro, use the Astro preset and the interval timer to stack instead.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
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
            Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
        }
    }
}

extension CameraImage {
    /// A normal PEN-F JPEG is ~8–12 MB and an ORF ~20–25 MB; High Res files are far bigger.
    var looksHighRes: Bool {
        guard urls == nil else { return false }   // LUMIX files (no Olympus High Res mode)
        return switch fileExtension {
        case "JPG": size > 18_000_000
        case "ORF": size > 50_000_000
        default: false
        }
    }
}
