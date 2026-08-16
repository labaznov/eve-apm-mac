# EVE-APM Mac

Live thumbnail previews of every running EVE Online client on macOS, with
click-to-switch and global hotkeys. A native rewrite of the Windows-only
[EVE-APM Preview](https://github.com/mrmjstc/eve-apm-preview) — same idea, macOS
frameworks throughout.

It does not broadcast input, does not read or write anything inside the game and
does not automate play. It shows windows and raises them.

## Requirements

- macOS 14 or newer
- The native EVE Online client for macOS
- Xcode command line tools (to build)

## Build and run

```sh
make        # builds build/EVE-APM Mac.app
make run    # builds and launches it
make test   # unit tests
```

The app lives in the menu bar; it has no Dock icon.

## Permissions

macOS gates both halves of what the app does, and it asks for them on first
launch:

| Grant | Why | Without it |
|---|---|---|
| **Screen Recording** | ScreenCaptureKit mirrors each client window | No thumbnails at all |
| **Accessibility** | Raising and minimising other apps' windows | Switching is less reliable, auto-minimise does nothing |

Both live in System Settings → Privacy & Security. The Settings window shows a
banner with a shortcut to the right pane while either is missing.

macOS ties both grants to the signature of the app that asked for them, and an
ad-hoc signature changes on every build — so every rebuild would lose them. Run
this once to create a local self-signed identity, after which `make` picks it up
automatically and the grants stick:

```sh
./scripts/dev-identity.sh
```

The first build after that asks for the login keychain password, because
`codesign` has to reach the new private key. Answer with **Always Allow** and it
stops asking; plain *Allow* only covers that one build.

## Features

**Windows**
- Live thumbnail per client, updated continuously even when the client is behind
  other windows
- Click a thumbnail to switch to that client
- Thumbnails float above other windows and never steal focus
- Drag to arrange; positions are remembered per character and can be locked
- Optional auto-minimise of inactive clients, with a delay and a never-minimise
  list
- Border highlight on the active client, custom border colour per character
- Optional hiding of the active client's own thumbnail
- Adjustable width, opacity and frame rate

**Hotkeys**
- Global shortcuts to switch to a named character, cycle forward or backward,
  toggle the thumbnails, or suspend the hotkeys themselves
- Restricted to EVE by default: while another application is in front the
  shortcuts are unregistered, so even a bare arrow key reaches that application
  untouched

**Logs**
- The solar system each character sits in, shown on its thumbnail, read from the
  Local channel log and from jumps in the game log
- Alerts on the thumbnail of a client you are not looking at: fleet invites,
  follow-in-warp and regroup orders, conversation requests, decloaks, finished
  compression runs, broken mining crystals, mining stopped by a depleted
  asteroid or a full hold
- Each alert kind can be silenced on its own, and the log folders can be pointed
  elsewhere

**Profiles**
- Any number of named profiles, each with its own sizes, positions, colours,
  behaviour and shortcuts
- Switch by shortcut, by menu or by link; the profile-switching shortcuts are
  shared by every profile so they keep working after a switch

**Links**
- `eveapm://character/<name>` — switch to that character
- `eveapm://profile/<name>` — switch profile
- `eveapm://hotkey/suspend`, `eveapm://hotkey/resume`
- `eveapm://thumbnail/hide`, `eveapm://thumbnail/show`
- `eveapm://config/open`, `eveapm://help/open`

## Settings and their file

**Help** in the menu documents the settings file in full: every field, its
range, and the rules below. It also imports a Windows profile and reveals the
active file in Finder.

Profiles are plain JSON in
`~/Library/Application Support/EVE-APM-Mac/profiles/<name>.json`, with the
chosen profile and the profile-switching shortcuts in `state.json` beside them.
Anything absent from a file falls back to its default, and values outside their
range are pulled back into it when read.

**Carrying settings with the app.** A `settings.json` placed *next to the app*
wins over the one in Application Support. The app then works out of that folder:
it reads that file at launch, writes changes back into it, and looks for further
profiles in a `profiles` folder beside it. Remove the file and it goes back to
Application Support; nothing is copied or moved between the two.

**Thumbnail positions** are the bottom-left corner of the thumbnail, in the
coordinate space macOS uses for windows.

- A position is written the instant a thumbnail moves and saved to disk as soon
  as you let go, so an arrangement is never lost to a crash or a forced quit.
- A remembered position is used exactly as written, as long as the thumbnail
  fits entirely on one of the displays attached right now.
- A position that lands off every display is dropped, the thumbnail is placed
  where it can be seen, and the new position is written back.
- Plugging a display in or out re-checks every thumbnail by the same rule.

**Coming from Windows.** EVE-APM Preview for Windows does not store JSON: it
writes Qt INI files, one per profile, next to its executable. *Import a Windows
profile…* in Help translates one into a profile here — sizes, opacity, colours,
auto-minimise, overlays, log and alert settings, per-character border colours
and thumbnail positions, with the positions flipped from Windows' top-left
origin to the bottom-left one macOS uses. Shortcuts are not carried over; the
two systems name keys differently.

Logs are read from `~/Documents/EVE/logs`, which macOS may ask you to allow the
first time.

The one thing the Windows original does that this does not is track a mining
cycle by its ticks; the events that end a cycle are reported.

## When thumbnails go blank

macOS can leave its screen capture service wedged — streams start, no frames
ever arrive, and every capturing application on the machine is affected. **Restart
Screen Capture…** in the menu asks for an administrator password and restarts
the service; macOS brings it back by itself. The menu item says *(no frames)*
when the app can tell this has happened.

## Notes for multiboxing on macOS

Run the clients in windowed mode. A client in native full screen owns its own
Space, and macOS switches Spaces with an animation on every activation, which is
slower and more disorienting than the window raise you get in windowed mode.

## Releases

```sh
./scripts/release.sh 0.2.1 [notes.md]
```

It stamps the version into `Info.plist`, runs the tests, builds the universal
app, tags the commit and uploads the archive. A published version is never
rewritten: every build that reaches anyone gets a number of its own, so a report
of "it happens on 0.2.1" means one exact binary.

## Licence

MIT, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

EVE Online and the EVE logo are the registered trademarks of CCP hf. All rights
are reserved worldwide. This application is not affiliated with or endorsed by
CCP hf.
