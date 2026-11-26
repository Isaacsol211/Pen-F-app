import SwiftUI

/// High Res Shot can't be switched on over Wi-Fi, so this walks through it and helps verify the
/// result: in a sheet on a phone, in the inspector on a large canvas.
struct HighResPanel: View {
    @Environment(\.dismiss) private var dismiss

    // 312: the big number, caps sections, numbered steps between hairlines, Done at the bottom.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BigNumber(value: "50 MP", caption: "8 sensor-shifted frames → 50 MP JPEG, 80 MP RAW", size: 120)
                .padding(.bottom, 8)
            SectionLabel("Turn it on at the camera")
            NoteRow("Olympus cameras don't accept this setting over Wi-Fi. On the camera, open MENU ▸ Shooting Menu 2 ▸ High Res Shot ▸ On (or press the button you've assigned to it). A 0 s delay is fine when you shoot from the phone.")
            SectionLabel("Then")
            step(1, "Tripod, and nothing moving in the scene: wind, water and people smear.")
            step(2, "The camera limits High Res to slower ISOs and shorter exposures; check its screen.")
            step(3, "Tap the shutter here. The camera takes about a second to capture, then a few more to merge. The app waits for it.")
            step(4, "Open Card: High Res files show a 50 MP badge.")
            SectionLabel("For the night sky")
            NoteRow("Stars move between the 8 frames, so High Res suits landscapes and still subjects, not long star exposures. For astro, use the Astro preset and the interval timer to stack instead.")
            Spacer(minLength: 20)
            Button("Done") { dismiss() }
                .buttonStyle(.outline)
                .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.num(18))
                .foregroundStyle(n == 1 ? Theme.onAccent : Theme.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(n == 1 ? Theme.accent : Color.clear))
                .overlay(Circle().strokeBorder(n == 1 ? Color.clear : Theme.tertiary, lineWidth: 1.5))
            Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
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
