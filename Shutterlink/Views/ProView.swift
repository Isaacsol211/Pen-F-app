import SwiftUI

/// Opens the Pro screen; `feature` is the locked tool that asked for it.
struct ProPrompt: Identifiable {
    let id = UUID()
    let feature: String?
}

/// What Pro adds, the trial, the purchase and Restore. Opened from a locked tool (`feature` names it)
/// or the ⋯ menu.
struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pro = ShutterlinkPro.shared
    /// The locked tool that opened this, e.g. "Astro".
    var feature: String?

    private static let features: [(icon: String, title: String, detail: String)] = [
        ("wand.and.stars", "One-tap setups",
         "Astro, Moon, Fireworks, Landscape, Action, Macro and Star trails set the whole exposure in one tap. Undo, and save your own"),
        ("timer", "Time-lapse", "Interval timer with day-to-night ramping"),
        ("square.stack.3d.down.right", "Bracketing and focus stacking", "Exposure brackets, and focus stacks on LUMIX, Nikon and Canon"),
        ("camera.filters", "Exposure tools", "ND filter calculator, expose to the right and the motion trigger"),
        ("square.grid.3x3.square", "High Res Shot helper", "On Olympus and OM System bodies that have it"),
        ("applewatch", "Apple Watch remote", "Live view, shutter and exposure on your wrist"),
        ("sparkle.magnifyingglass", "Scene suggestions that set things up", "Night sky to Astro, movement to 1/500 s, in one tap"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.features, id: \.title) { item in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline).foregroundStyle(.white)
                                    Text(item.detail).font(.subheadline).foregroundStyle(Theme.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                Image(systemName: item.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 30)
                            }
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                    Text("Free stays free: connecting to every brand, live view, all exposure settings, the shutter, video, Bulb and Live Composite, the card browser, saving, auto-save, geotagging and Wi-Fi joining.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .background(Theme.background)
            .navigationTitle("Shutterlink Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.background)
        .tint(Theme.accent)
        .task {
            if pro.products.isEmpty { await pro.loadProducts() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let feature, !pro.isUnlocked {
                Text("\(feature) is part of Shutterlink Pro")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(pro.isUnlocked ? "Pro is unlocked" : "The tools that do the work for you")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(pro.isUnlocked ? pro.statusText : "One purchase for iPhone, iPad and Mac. Yours to keep, no subscription.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if let message = pro.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.blurReplace)
            }
            if pro.purchased || pro.earlyUser || pro.testerUnlock {
                Button("Done") { dismiss() }
                    .buttonStyle(.accent)
            } else {
                if !pro.trialUsed {
                    Button {
                        Task {
                            await pro.startTrial()
                            if pro.isUnlocked { dismiss() }
                        }
                    } label: {
                        Text("Try free for \(ShutterlinkPro.trialDays) days").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.accent)
                    .disabled(pro.busy || pro.products[ShutterlinkPro.trialID] == nil)
                }
                let buy = Button {
                    Task {
                        await pro.buy()
                        if pro.purchased { dismiss() }
                    }
                } label: {
                    Text(pro.priceText.map { "Buy Pro · \($0)" } ?? "Buy Pro").frame(maxWidth: .infinity)
                }
                .disabled(pro.busy || pro.products[ShutterlinkPro.proID] == nil)
                // The trial is the main button until it's used; then buying is.
                if pro.trialUsed {
                    buy.buttonStyle(.accent)
                } else {
                    buy.buttonStyle(.surface)
                }
                HStack {
                    Button("Restore purchase") { Task { await pro.restore() } }
                        .font(.footnote.weight(.semibold))
                        .disabled(pro.busy)
                    Spacer()
                    if pro.busy { ProgressView() }
                }
                if pro.products.isEmpty {
                    Text("Prices load from the App Store.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !pro.trialUsed {
                    Text("The trial is free and doesn't renew or charge you. After \(ShutterlinkPro.trialDays) days the Pro tools lock until you buy.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .animation(.smooth, value: pro.message)
    }
}
