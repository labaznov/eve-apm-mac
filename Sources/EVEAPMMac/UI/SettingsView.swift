import SwiftUI

/// The whole configuration surface. Every control writes straight into the
/// settings store, which the running thumbnails observe.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var config = AppModel.shared.config
    @ObservedObject private var registry = AppModel.shared.registry
    @ObservedObject private var logs = AppModel.shared.logs

    var body: some View {
        VStack(spacing: 0) {
            PermissionsBanner()
            TabView {
                ThumbnailSettings(settings: $config.settings)
                    .tabItem { Label("Thumbnails", systemImage: "rectangle.on.rectangle") }
                BehaviourSettings(settings: $config.settings, characters: characters)
                    .tabItem { Label("Behaviour", systemImage: "gearshape") }
                HotkeySettings(settings: $config.settings,
                               globalHotkeys: $config.globalHotkeys,
                               characters: characters,
                               profiles: config.profiles)
                    .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                LogSettings(settings: $config.settings, systems: logs.systems)
                    .tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }
                ProfileSettings(config: config)
                    .tabItem { Label("Profiles", systemImage: "person.2") }
                ClientList(clients: registry.clients, frontmost: registry.frontmostPID)
                    .tabItem { Label("Clients", systemImage: "list.bullet") }
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }

    private var characters: [String] {
        registry.clients.compactMap(\.character).sorted()
    }
}

private struct PermissionsBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.hasScreenRecording || !model.hasAccessibility {
            VStack(alignment: .leading, spacing: 6) {
                if !model.hasScreenRecording {
                    row("Screen Recording is required to show live thumbnails",
                        action: Permissions.openScreenRecordingSettings)
                }
                if !model.hasAccessibility {
                    row("Accessibility is required to raise and minimise clients",
                        action: Permissions.openAccessibilitySettings)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.18))
        }
    }

    private func row(_ text: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            Button("Open Settings", action: action)
        }
    }
}

private struct ThumbnailSettings: View {
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section {
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $settings.thumbnailWidth,
                               in: Settings.thumbnailWidthRange, step: 10)
                        Text("\(Int(settings.thumbnailWidth)) pt").monospacedDigit().frame(width: 60)
                    }
                }
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $settings.opacity, in: Settings.opacityRange, step: 0.05)
                        Text(settings.opacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 60)
                    }
                }
                LabeledContent("Frame rate") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.frameRate) },
                            set: { settings.frameRate = Int($0) }
                        ), in: 1...30, step: 1)
                        Text("\(settings.frameRate) fps").monospacedDigit().frame(width: 60)
                    }
                }
            }

            Section {
                Toggle("Always on top", isOn: $settings.alwaysOnTop)
                Toggle("Hide the active client's thumbnail", isOn: $settings.hideActiveThumbnail)
                Toggle("Lock positions", isOn: $settings.lockPositions)
                Toggle("Show character names", isOn: $settings.showCharacterName)
            }

            Section("Border") {
                LabeledContent("Width") {
                    Stepper(value: $settings.borderWidth, in: 0...12, step: 1) {
                        Text("\(Int(settings.borderWidth)) pt").monospacedDigit()
                    }
                }
                ColorPicker("Active client", selection: colorBinding(\.activeBorderColor))
                ColorPicker("Inactive client", selection: colorBinding(\.inactiveBorderColor))
                ColorPicker("Character name", selection: colorBinding(\.labelColor))
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<Settings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(settings[keyPath: keyPath].nsColor) },
            set: { settings[keyPath: keyPath] = RGBAColor(NSColor($0)) }
        )
    }
}

private struct BehaviourSettings: View {
    @Binding var settings: Settings
    let characters: [String]

    var body: some View {
        Form {
            Section("Auto-minimise") {
                Toggle("Minimise inactive clients", isOn: $settings.autoMinimizeEnabled)
                LabeledContent("Delay") {
                    HStack {
                        Slider(value: $settings.autoMinimizeDelay, in: 0.5...60, step: 0.5)
                        Text("\(settings.autoMinimizeDelay, specifier: "%.1f") s")
                            .monospacedDigit().frame(width: 60)
                    }
                }
                .disabled(!settings.autoMinimizeEnabled)
            }

            Section("Never minimise") {
                if characters.isEmpty {
                    Text("No clients detected").foregroundStyle(.secondary)
                }
                ForEach(characters, id: \.self) { character in
                    Toggle(character, isOn: Binding(
                        get: { settings.neverMinimize.contains(character) },
                        set: { keep in
                            if keep {
                                if !settings.neverMinimize.contains(character) {
                                    settings.neverMinimize.append(character)
                                }
                            } else {
                                settings.neverMinimize.removeAll { $0 == character }
                            }
                        }
                    ))
                }
            }

            Section("Clients") {
                Text("Bundle identifiers treated as EVE clients")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Bundle identifiers", text: Binding(
                    get: { settings.clientBundleIdentifiers.joined(separator: ", ") },
                    set: {
                        settings.clientBundleIdentifiers = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                ), axis: .vertical)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeySettings: View {
    @Binding var settings: Settings
    @Binding var globalHotkeys: [Hotkey]
    let characters: [String]
    let profiles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts of this profile")
                .font(.headline)
            list($settings.hotkeys)

            Text("Shortcuts shared by every profile")
                .font(.headline)
            list($globalHotkeys)

            HStack {
                Menu("Add") {
                    Button("Cycle forward") { add(.cycleForward) }
                    Button("Cycle backward") { add(.cycleBackward) }
                    Button("Toggle thumbnails") { add(.toggleThumbnails) }
                    Button("Suspend or resume hotkeys") { add(.toggleHotkeys) }
                    Divider()
                    Button("Next profile") { add(.cycleProfileForward) }
                    Button("Previous profile") { add(.cycleProfileBackward) }
                    ForEach(profiles, id: \.self) { profile in
                        Button("Switch to \(profile)") { add(.switchProfile(name: profile)) }
                    }
                    if !characters.isEmpty {
                        Divider()
                        ForEach(characters, id: \.self) { character in
                            Button(character) { add(.activate(character: character)) }
                        }
                    }
                }
                .frame(width: 120)

                Button("Remove last") { removeLast() }
                    .disabled(settings.hotkeys.isEmpty && globalHotkeys.isEmpty)

                Spacer()
            }
        }
        .padding(8)
    }

    private func list(_ hotkeys: Binding<[Hotkey]>) -> some View {
        Table(of: Binding<Hotkey>.self) {
            TableColumn("Action") { binding in
                Text(Self.describe(binding.wrappedValue.action))
            }
            TableColumn("Shortcut") { binding in
                HotkeyRecorder(keyCode: binding.keyCode, modifiers: binding.modifiers)
                    .frame(height: 24)
            }
        } rows: {
            ForEach(hotkeys) { binding in
                TableRow(binding)
            }
        }
        .frame(minHeight: 120)
    }

    private func add(_ action: HotkeyAction) {
        let hotkey = Hotkey(keyCode: 0, modifiers: 0, action: action)
        if action.isGlobal {
            globalHotkeys.append(hotkey)
        } else {
            settings.hotkeys.append(hotkey)
        }
    }

    private func removeLast() {
        if !settings.hotkeys.isEmpty {
            settings.hotkeys.removeLast()
        } else if !globalHotkeys.isEmpty {
            globalHotkeys.removeLast()
        }
    }

    private static func describe(_ action: HotkeyAction) -> String {
        switch action {
        case .activate(let character): "Switch to \(character)"
        case .cycleForward: "Cycle forward"
        case .cycleBackward: "Cycle backward"
        case .toggleThumbnails: "Toggle thumbnails"
        case .toggleHotkeys: "Suspend or resume hotkeys"
        case .switchProfile(let name): "Switch to profile \(name)"
        case .cycleProfileForward: "Next profile"
        case .cycleProfileBackward: "Previous profile"
        }
    }
}

private struct ClientList: View {
    let clients: [EVEClient]
    let frontmost: pid_t?

    var body: some View {
        VStack(alignment: .leading) {
            if clients.isEmpty {
                Text("No EVE clients detected. Launch a client and it appears here.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            Table(clients) {
                TableColumn("Character") { client in
                    Text(client.character ?? "Not logged in")
                        .fontWeight(client.pid == frontmost ? .bold : .regular)
                }
                TableColumn("Window") { client in
                    Text("\(Int(client.frame.width))×\(Int(client.frame.height))").monospacedDigit()
                }
                TableColumn("PID") { client in
                    Text("\(client.pid)").monospacedDigit()
                }
            }
        }
        .padding(8)
    }
}

private struct LogSettings: View {
    @Binding var settings: Settings
    let systems: [String: String]

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Read chat logs for system changes", isOn: $settings.monitorChatLogs)
                Toggle("Read game logs for jumps and notices", isOn: $settings.monitorGameLogs)
                Toggle("Show the system name on thumbnails", isOn: $settings.showSystemName)
            }

            Section("Alerts") {
                Toggle("Show alerts on thumbnails", isOn: $settings.alertsEnabled)
                Toggle("Also on the client in use", isOn: $settings.alertsOnActiveClient)
                    .disabled(!settings.alertsEnabled)
                LabeledContent("Shown for") {
                    HStack {
                        Slider(value: $settings.alertDuration, in: 1...30, step: 1)
                        Text("\(Int(settings.alertDuration)) s").monospacedDigit().frame(width: 50)
                    }
                }
                .disabled(!settings.alertsEnabled)

                ForEach(AlertKind.allCases, id: \.rawValue) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { !settings.mutedAlerts.contains(kind.rawValue) },
                        set: { show in
                            if show {
                                settings.mutedAlerts.removeAll { $0 == kind.rawValue }
                            } else if !settings.mutedAlerts.contains(kind.rawValue) {
                                settings.mutedAlerts.append(kind.rawValue)
                            }
                        }
                    ))
                    .disabled(!settings.alertsEnabled)
                }
            }

            Section("Folders") {
                TextField("Chat logs", text: $settings.chatLogDirectory,
                          prompt: Text(Settings.defaultLogDirectory(.chat).path))
                TextField("Game logs", text: $settings.gameLogDirectory,
                          prompt: Text(Settings.defaultLogDirectory(.game).path))
            }

            Section("Seen") {
                if systems.isEmpty {
                    Text("No character located yet").foregroundStyle(.secondary)
                }
                ForEach(systems.sorted(by: { $0.key < $1.key }), id: \.key) { character, system in
                    LabeledContent(character) { Text(system).monospaced() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileSettings: View {
    @ObservedObject var config: ConfigStore
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A profile holds a whole set of settings: sizes, positions, colours and its own shortcuts. Switch between them with a shortcut or an eveapm://profile/<name> link.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(config.profiles, id: \.self, selection: Binding(
                get: { config.currentProfile },
                set: { name in config.switchTo(name ?? config.currentProfile) }
            )) { name in
                HStack {
                    Text(name)
                    if name == config.currentProfile {
                        Text("in use").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(name)
            }
            .frame(minHeight: 200)

            HStack {
                TextField("New profile", text: $newName)
                    .frame(width: 160)
                Button("Add") {
                    config.createProfile(named: newName)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Add empty") {
                    config.createProfile(named: newName, copyingCurrent: false)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button("Delete", role: .destructive) {
                    config.deleteProfile(config.currentProfile)
                }
                .disabled(config.profiles.count < 2)
            }
        }
        .padding(8)
    }
}
