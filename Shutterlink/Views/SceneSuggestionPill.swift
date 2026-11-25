import SwiftUI

/// The scene assistant's suggestion, floating over the bottom of live view: what it sees, why, and
/// one button. Nothing changes until that button is tapped; the cross keeps it away for a while.
struct SceneSuggestionPill: View {
    @Environment(CameraModel.self) private var camera
    let suggestion: SceneSuggestion
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(suggestion.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(suggestion.actionTitle, action: onApply)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(Theme.accent))
                .frame(minHeight: Theme.target)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .disabled(camera.presetRunning || camera.isShooting)
            Button {
                withAnimation(.snappy) { camera.dismissSceneSuggestion() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: Theme.target)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .surface(.clear, in: .rect(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 520)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title). \(suggestion.detail)")
        .accessibilityAction(named: suggestion.actionTitle, onApply)
    }
}
