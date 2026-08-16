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

An ad-hoc signed build gets a new signature on every rebuild, and macOS ties the
grants to that signature — so after `make` you may have to re-approve. Signing
with a stable identity avoids it: `make IDENTITY="Developer ID Application: …"`.

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

**Links**
- `eveapm://character/<name>` — switch to that character
- `eveapm://hotkey/suspend`, `eveapm://hotkey/resume`
- `eveapm://thumbnail/hide`, `eveapm://thumbnail/show`
- `eveapm://config/open`

## What is not here yet

Chat and game log monitoring (system names on thumbnails, combat alerts) and
configuration profiles are in the Windows original and not in this one yet. EVE
writes the same logs on macOS, under `~/Documents/EVE/logs`, so the parsing work
carries over.

## Notes for multiboxing on macOS

Run the clients in windowed mode. A client in native full screen owns its own
Space, and macOS switches Spaces with an animation on every activation, which is
slower and more disorienting than the window raise you get in windowed mode.

## Licence

MIT, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

EVE Online and the EVE logo are the registered trademarks of CCP hf. All rights
are reserved worldwide. This application is not affiliated with or endorsed by
CCP hf.
