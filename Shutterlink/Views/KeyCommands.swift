import SwiftUI

// The menu bar on a Mac and keyboard shortcuts on an iPad with a keyboard. Everything here does
// what a tap on the camera screen does; nothing is reachable only from a menu.

/// What the camera screen offers the menus. RemoteView publishes it while it's on screen; with no
/// camera connected it's nil and the menus are greyed out.
struct RemoteActions {
    var openCard: () -> Void
    var cardAvailable: Bool
    var allSettings: () -> Void
    var log: () -> Void
    var disconnect: () -> Void
    /// The exposure value whose dial is open, if any.
    var activeSetting: String?
    var toggleDial: (String) -> Void
    /// The same tools as the inspector's tiles, with the same actions.
    var tools: [ToolItem]
}

extension FocusedValues {
    @Entry var remoteActions: RemoteActions?
}

extension CameraModel {
    /// Whether the shutter can be pressed now (the shutter button greys out otherwise).
    var canShoot: Bool {
        phase == .connected && mode == .rec && !isSwitchingMode && !bracket.running
    }

    /// One press of the shutter, as a tap on the shutter button (or VoiceOver, or a key) does it:
    /// starts or stops a movie or an open-ended exposure, else focuses and takes one picture.
    func pressShutterOnce() async {
        if isMovieMode {
            await toggleMovie()
        } else if isOpenEndedShutter {
            await toggleOpenExposure()
        } else {
            await shutterPressed()
            await shutterReleased()
        }
    }

    /// Moves the value of `name` one step along its dial (+1 = rightwards on the ruler).
    func stepProperty(_ name: String, by delta: Int) {
        guard let next = stepped(name, by: delta) else { return }
        Task { await setProperty(name, to: next) }
    }

    func stepped(_ name: String, by delta: Int) -> String? {
        guard let raw = properties[name] else { return nil }
        let property = dialOptions(for: raw)
        guard property.settable, let index = property.options.firstIndex(of: property.value),
              property.options.indices.contains(index + delta) else { return nil }
        return property.options[index + delta]
    }
}

struct CameraCommands: Commands {
    @FocusedValue(\.remoteActions) private var remote

    private var camera: CameraModel { CameraModel.shared }

    /// The exposure values with their own dial, in the order of the inspector's grid.
    private static let dials: [(name: String, title: String, key: KeyEquivalent)] = [
        ("focalvalue", "Aperture", "1"),
        ("shutspeedvalue", "Shutter Speed", "2"),
        ("isospeedvalue", "ISO", "3"),
        ("expcomp", "Exposure Compensation", "4"),
        ("wbvalue", "White Balance", "5"),
        ("drivemode", "Drive Mode", "6"),
    ]

    /// Shortcuts for the switches people flip most while shooting.
    private static let toolKeys: [String: KeyboardShortcut] = [
        "loupe": KeyboardShortcut("l"),
        "grid": KeyboardShortcut("'"),
        "peaking": KeyboardShortcut("p", modifiers: [.command, .shift]),
        "night": KeyboardShortcut("n", modifiers: [.command, .shift]),
    ]

    private var shutterTitle: String {
        if camera.isMovieMode { return camera.isRecordingMovie ? "Stop Recording" : "Start Recording" }
        if camera.isOpenEndedShutter { return camera.isShooting ? "End Exposure" : "Start Exposure" }
        return "Take Picture"
    }

    var body: some Commands {
        CommandMenu("Camera") {
            Button(shutterTitle) { Task { await camera.pressShutterOnce() } }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(remote == nil || !camera.canShoot)
            Button("Restart Live View") { Task { await camera.restartLiveView() } }
                .keyboardShortcut("r")
                .disabled(remote == nil || camera.isBusyExposing)
            Button("Browse Card…") { remote?.openCard() }
                .keyboardShortcut("o")
                .disabled(!(remote?.cardAvailable ?? false))
            Divider()
            Button("All Camera Settings…") { remote?.allSettings() }
                .keyboardShortcut("i")
                .disabled(remote == nil || camera.isBusyExposing)
            Button("Request Log") { remote?.log() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(remote == nil)
            Divider()
            Button("Disconnect…") { remote?.disconnect() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(remote == nil || camera.isBusyExposing)
        }
        CommandMenu("Exposure") {
            ForEach(Self.dials, id: \.name) { dial in
                Toggle(dial.title, isOn: Binding(get: { remote?.activeSetting == dial.name },
                                                 set: { _ in remote?.toggleDial(dial.name) }))
                    .keyboardShortcut(dial.key)
                    .disabled(remote == nil || camera.properties[dial.name] == nil || camera.isBusyExposing)
            }
            Divider()
            Button("Next Value") { step(1) }
                .keyboardShortcut(.rightArrow)
                .disabled(stepTarget(1) == nil)
            Button("Previous Value") { step(-1) }
                .keyboardShortcut(.leftArrow)
                .disabled(stepTarget(-1) == nil)
        }
        CommandMenu("Tools") {
            if let tools = remote?.tools {
                ForEach(tools) { tool in
                    if tool.opens {
                        Button(tool.title + "…", systemImage: tool.icon, action: tool.action)
                            .keyboardShortcut(Self.toolKeys[tool.id])
                    } else {
                        Toggle(isOn: Binding(get: { tool.on }, set: { _ in tool.action() })) {
                            Label(tool.title, systemImage: tool.icon)
                        }
                        .keyboardShortcut(Self.toolKeys[tool.id])
                    }
                }
            } else {
                Text("Connect to a camera first").disabled(true)
            }
        }
    }

    /// The value a step of the open dial would set, or nil (no dial open, camera's choice, end).
    private func stepTarget(_ delta: Int) -> String? {
        guard let name = remote?.activeSetting, !camera.isBusyExposing else { return nil }
        return camera.stepped(name, by: delta)
    }

    private func step(_ delta: Int) {
        guard let name = remote?.activeSetting else { return }
        camera.stepProperty(name, by: delta)
    }
}
