import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Explains where the settings file lives, what is in it, and how a profile
/// from the Windows application is brought across. It is the only place those
/// rules are written down for the user, so it doubles as the file format's
/// documentation.
struct HelpView: View {
    @ObservedObject private var config = AppModel.shared.config
    @State private var report: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                whereItLives
                portable
                fields
                positions
                groups
                windows
                links
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(width: 620, height: 640)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings and their file").font(.title2).bold()
            Text("Everything the app remembers is plain JSON you can read, edit, copy between machines and keep in version control.")
                .foregroundStyle(.secondary)
        }
    }

    private var whereItLives: some View {
        section("Where it lives") {
            Text("The active profile is **\(config.currentProfile)**, kept in:")
            code(config.activeProfilePath)
            Text("Every profile is one file in the same folder, named after the profile. The file next to them, `state.json`, holds which profile is in use and the shortcuts that switch profiles.")
            HStack {
                Button("Reveal in Finder") { config.revealInFinder() }
                Button("Import a Windows profile…") { importWindowsProfile() }
            }
            .padding(.top, 4)
            if let report {
                Text(report).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var portable: some View {
        section("Carrying settings with the app") {
            Text("A file named `settings.json` placed **next to the app** wins over the one in Application Support. The app then treats that folder as its home: it reads that file at launch, writes changes back into it, and looks for further profiles in a `profiles` folder beside it.")
            code("…/EVE-APM Mac.app\n…/settings.json        ← used first when present\n…/profiles/mining.json")
            Text("Remove that file and the app goes back to Application Support. Nothing is copied or moved between the two, so you decide which one is in play.")
        }
    }

    private var fields: some View {
        section("What is in a profile") {
            Text("A file is read field by field. Anything absent falls back to its default, so a file with a single line is valid, and a file written by an older build keeps everything it does hold. A field this build cannot read — the wrong type, a hand-edit gone wrong — is left at its default and named in the log; the rest of the file is kept. A file that is not JSON at all is left untouched, copied beside itself as `<name>.broken.json`, and reported.")
            table([
                ("thumbnailWidth", "80–800", "Width in points; the height follows the client's aspect"),
                ("opacity", "0.2–1", "Thumbnail transparency"),
                ("frameRate", "1–30", "Capture rate per second"),
                ("alwaysOnTop / hideActiveThumbnail / lockPositions", "true / false", "Window behaviour"),
                ("showCharacterName / showSystemName", "true / false", "Overlays on the thumbnail"),
                ("borderWidth", "0–12", "Border thickness in points"),
                ("activeBorderColor / inactiveBorderColor / labelColor", "{red, green, blue, alpha}", "Components from 0 to 1"),
                ("characterBorderColors", "{\"Name\": colour}", "Border colour for one character"),
                ("autoMinimizeEnabled / autoMinimizeDelay", "true / false, 0.5–120", "Minimising inactive clients"),
                ("neverMinimize", "[\"Name\", …]", "Characters exempt from that"),
                ("positions", "{\"Name\": {\"x\": …, \"y\": …}}", "Thumbnail corners, see below"),
                ("hotkeys", "[{id, keyCode, modifiers, action}]", "Shortcuts of this profile; a character may have several"),
                ("hotkeysRequireEVEFocus", "true / false", "Shortcuts act only while EVE is in front"),
                ("wildcardHotkeys", "true / false", "A shortcut answers with further modifiers held too"),
                ("cycleGroups", "[{name, characters, includesNotLoggedIn, loops}]", "Named squads with shortcuts of their own"),
                ("characterThumbnailWidths", "{\"Name\": 80–800}", "A width of its own for one character"),
                ("snapDistance", "0–60", "How near an edge a dragged thumbnail snaps; 0 is off"),
                ("labelFontSize", "8–32", "Size of the overlay text"),
                ("characterNamePosition / systemNamePosition", "\"top\" / \"bottom\"", "Which edge each overlay sits on"),
                ("systemNameColor", "{red, green, blue, alpha}", "Colour of the system name"),
                ("overlayBackground / overlayBackgroundColor", "true / false, colour", "A plate behind the overlay text"),
                ("activeBorderStyle / inactiveBorderStyle", "\"solid\" / \"dashed\" / \"dotted\"", "How each border is drawn"),
                ("inactiveBorderWidth", "0–12", "Border thickness for inactive clients"),
                ("clientBundleIdentifiers", "[\"com.ccpgames.eveonline\"]", "What counts as an EVE client"),
                ("hideThumbnailsWhenEVEUnfocused / eveFocusDebounce", "true / false, 0–10", "Step aside while another application is in front"),
                ("hiddenCharacters", "[\"Name\", …]", "Characters with no thumbnail at all"),
                ("neverClose", "[\"Name\", …]", "Characters left running by Quit EVE Clients"),
                ("showNotLoggedInClients / notLoggedInBadge", "true / false", "Clients still on the login screen"),
                ("notLoggedInStack", "\"row\" / \"column\" / \"pile\"", "How those are gathered"),
                ("notLoggedInAnchor", "{\"x\": …, \"y\": …}", "Where that gathering starts"),
                ("alertColor / alertPosition", "colour, \"top\" / \"middle\" / \"bottom\"", "How a notice is drawn"),
                ("miningTimeout", "5–600", "Seconds of quiet before mining counts as stopped"),
                ("switchOnMouseDown / dragWithRightButton", "true / false", "What the mouse does on a thumbnail"),
                ("rememberClientWindows / clientWindowFrames", "true / false, {\"Name\": rect}", "The game window's own place per character"),
                ("monitorChatLogs / monitorGameLogs", "true / false", "Reading EVE's logs"),
                ("chatLogDirectory / gameLogDirectory", "path or \"\"", "Empty means where EVE writes them"),
                ("alertsEnabled / alertsOnActiveClient / alertDuration", "true / false, 1–60", "Notices on thumbnails"),
                ("mutedAlerts", "[\"fleetInvite\", …]", "Alert kinds to keep quiet")
            ])
        }
    }

    private var positions: some View {
        section("Thumbnail positions") {
            Text("A position is the bottom-left corner of the thumbnail, in the coordinate space macOS uses for windows: **x** grows to the right, **y** grows upwards from the bottom of the main display.")
            Text("The rules are strict on purpose:")
            bullet("A position is written the instant a thumbnail moves, and saved to disk as soon as you let go. An arrangement is never lost to a crash or a forced quit.")
            bullet("A remembered position is used exactly as written, as long as most of the thumbnail lands on a display attached right now. Sitting over the Dock or the menu bar is allowed, and so is hanging a little off an edge.")
            bullet("A position that lands off every display — a monitor that is gone, or a file from a machine with a larger screen — is dropped, the thumbnail is placed where it can be seen, and the new position is written back.")
            bullet("A dragged thumbnail lines up with its neighbours and the edges of the screen when it comes within the snapping distance, which the Thumbnails tab sets.")
            bullet("Plugging a display in or out re-checks every thumbnail by the same rule; the ones that still fit are left alone.")
        }
    }

    private var windows: some View {
        section("Coming from the Windows application") {
            Text("EVE-APM Preview for Windows does not store JSON: it writes Qt INI files, one per profile, in a `profiles` folder next to its executable. The settings both applications share are translated for you by **Import a Windows profile…** above; pick a `.ini` and it becomes a profile here.")
            Text("What comes across: thumbnail width and opacity, always-on-top, locked positions, hiding the active thumbnail, the highlight colour, auto-minimise with its delay and exempt characters, the name and system overlays with the name colour, log monitoring, combat alerts with their duration, the EVE-focus rule for shortcuts, per-character border colours, and thumbnail positions.")
            Text("Positions are flipped as they are read, because Windows measures down from the top of the screen and macOS up from the bottom; the parked position Windows gives minimised windows is discarded. Shortcuts are not carried over: the two systems name keys differently, so they are worth setting again.")
        }
    }

    private var groups: some View {
        section("Cycle groups") {
            Text("A group is a named list of characters in the order you want to walk them. Give it a pair of shortcuts and they step through that group alone, leaving every other client where it is. A group holds names, not clients, so a member that is logged out is simply skipped and the group survives.")
            bullet("**Wrap round at the ends** decides whether stepping past the last member returns to the first or stops there.")
            bullet("**Include clients not logged in** adds the clients still on the login screen to the walk.")
            bullet("Starting from a client outside the group enters it at the first member.")
        }
    }

    private var links: some View {
        section("Links") {
            code("""
                eveapm://character/<name>   switch to that character
                eveapm://profile/<name>     switch profile
                eveapm://hotkey/suspend     eveapm://hotkey/resume
                eveapm://thumbnail/hide     eveapm://thumbnail/show
                eveapm://config/open        open the settings window
                """)
        }
    }

    // MARK: - Pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(.init(text))
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func table(_ rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0).font(.system(.caption, design: .monospaced)).bold()
                        Text(row.1).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(row.2).font(.caption)
                }
            }
        }
    }

    private func importWindowsProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a profile written by EVE-APM Preview for Windows"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let name = url.deletingPathExtension().lastPathComponent
        let height = NSScreen.main?.frame.height ?? 1080
        let imported = WindowsProfile.settings(fromINI: text, screenHeight: height)
        config.adopt(imported, asProfile: name)
        report = "Imported \(imported.positions.count) position(s) into the profile “\(config.currentProfile)”."
    }
}
