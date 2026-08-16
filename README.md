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
- `eveapm://config/open`

## Where things are kept

Profiles live in `~/Library/Application Support/EVE-APM-Mac/profiles/<name>.json`
and the chosen profile in `state.json` beside them. Logs are read from
`~/Documents/EVE/logs`, which macOS may ask you to allow the first time.

The one thing the Windows original does that this does not is track a mining
cycle by its ticks; the events that end a cycle are reported.

## Notes for multiboxing on macOS

Run the clients in windowed mode. A client in native full screen owns its own
Space, and macOS switches Spaces with an animation on every activation, which is
slower and more disorienting than the window raise you get in windowed mode.

## Licence

MIT, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

EVE Online and the EVE logo are the registered trademarks of CCP hf. All rights
are reserved worldwide. This application is not affiliated with or endorsed by
CCP hf.
