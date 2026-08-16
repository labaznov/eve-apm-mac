import SwiftUI

/// The whole configuration surface. Every control writes straight into the
/// settings store, which the running thumbnails observe.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var config = AppModel.shared.config
    @ObservedObject private var registry = AppModel.shared.registry

    var body: some View {
        VStack(spacing: 0) {
            PermissionsBanner()
            TabView {
                ThumbnailSettings(settings: $config.settings)
                    .tabItem { Label("Thumbnails", systemImage: "rectangle.on.rectangle") }
                BehaviourSettings(settings: $config.settings, characters: characters)
                    .tabItem { Label("Behaviour", systemImage: "gearshape") }
                HotkeySettings(settings: $config.settings, characters: characters)
                    .tabItem { Label("Hotkeys", systemImage: "keyboard") }
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
    let characters: [String]

    var body: some View {
        VStack(alignment: .leading) {
            Table(of: Binding<Hotkey>.self) {
                TableColumn("Action") { binding in
                    Text(Self.describe(binding.wrappedValue.action))
                }
                TableColumn("Shortcut") { binding in
                    HotkeyRecorder(keyCode: binding.keyCode, modifiers: binding.modifiers)
                        .frame(height: 24)
                }
            } rows: {
                ForEach($settings.hotkeys) { binding in
                    TableRow(binding)
                }
            }
            .frame(minHeight: 260)

            HStack {
                Menu("Add") {
                    Button("Cycle forward") { add(.cycleForward) }
                    Button("Cycle backward") { add(.cycleBackward) }
                    Button("Toggle thumbnails") { add(.toggleThumbnails) }
                    Button("Suspend or resume hotkeys") { add(.toggleHotkeys) }
                    if !characters.isEmpty {
                        Divider()
                        ForEach(characters, id: \.self) { character in
                            Button(character) { add(.activate(character: character)) }
                        }
                    }
                }
                .frame(width: 120)

                Button("Remove last") {
                    if !settings.hotkeys.isEmpty { settings.hotkeys.removeLast() }
                }
                .disabled(settings.hotkeys.isEmpty)

                Spacer()
            }
        }
        .padding(8)
    }

    private func add(_ action: HotkeyAction) {
        settings.hotkeys.append(Hotkey(keyCode: 0, modifiers: 0, action: action))
    }

    private static func describe(_ action: HotkeyAction) -> String {
        switch action {
        case .activate(let character): "Switch to \(character)"
        case .cycleForward: "Cycle forward"
        case .cycleBackward: "Cycle backward"
        case .toggleThumbnails: "Toggle thumbnails"
        case .toggleHotkeys: "Suspend or resume hotkeys"
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
