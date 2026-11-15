# Reference

## Contents

- [Requirements](#requirements)
- [What the installer changes](#what-the-installer-changes)
- [The bar icon](#the-bar-icon)
- [Inside a phone window](#inside-a-phone-window)
- [Commands](#commands)
- [Settings](#settings)
- [The direct Wi-Fi link](#the-direct-wi-fi-link)
- [Troubleshooting](#troubleshooting)
- [Privacy](#privacy)

## Requirements

- Omarchy (Hyprland with Omarchy's Lua config).
- An Android phone. Wi-Fi pairing needs Android 11 or newer.
- For the direct Wi-Fi link: NetworkManager with wpa_supplicant (iwd can't do
  Wi-Fi Direct), and a Wi-Fi card that supports Wi-Fi Direct alongside a normal
  connection. Without these, phonelink goes through your router instead.

Tested with a Samsung Galaxy Z Fold (Android 17) and a laptop with a MediaTek
MT7922 Wi-Fi card.

## What the installer changes

It installs any missing packages (`scrcpy`, `android-tools`, `android-udev`,
`qrencode`, `jq`), then:

- puts the `phonelink` command in `~/.local/bin`
- adds `~/.config/hypr/phonelink.lua` (keybindings and window rules) and loads
  it from `~/.config/hypr/hyprland.lua`
- adds a Phone section to `~/.config/omarchy/extensions/omarchy-menu.jsonc`
- adds a phone icon to the bar (the `phonelink.panel` shell plugin)
- adds a "Phone" entry to the app launcher
- creates `~/.config/phonelink/config` for your settings

Updates replace `~/.config/hypr/phonelink.lua` unless you've edited it. Then
your copy stays and the new one is saved beside it as `phonelink.lua.new`.

If **Super + Alt + P** is already taken, the installer says so. To keep your
binding, set `phonelink_bindings = false` in `~/.config/hypr/hyprland.lua`,
above the line that loads phonelink.

## The bar icon

The icon is dimmed when no phone is connected. It turns your theme's accent
color while a phone window is open.

- **Left click** opens a panel with:
  - the phone's name and how it's connected;
  - Mirror, and your recent and pinned apps;
  - the Direct Wi-Fi link switch;
  - Disconnect, or Connect and Pair when no phone is connected.

  In the panel, arrow keys or j/k move, Enter opens and Esc closes.
- **Right click** mirrors the phone.
- **Middle click** opens the full app list.

Move it by dragging it along the bar, or with
`omarchy bar move phonelink.panel --section <section>`.

## Inside a phone window

| | |
|---|---|
| Back | **Super + B** or right-click |
| Home | **Super + H** or middle-click |
| Notification panel | **Super + N** |
| Rotate | **Super + R** |
| Float the window | **Super + T** |

Copy and paste work both ways. Drag a file onto a window to send it to the
phone, or drag an APK to install it.

Each phone app runs on its own virtual display that resizes with its tile, so
it lays itself out like a desktop app and leaves the phone's own screen free.
The mirror keeps the phone's shape inside its tile.

## Commands

```
phonelink apps         Pick a phone app and open it in its own window
phonelink open <pkg>   Open one phone app in its own window
phonelink mirror       Mirror and control the whole phone screen
phonelink pin          Choose which phone apps appear in the app launcher
phonelink pair         Pair over Wi-Fi with a QR code
phonelink connect      Connect to a paired phone
phonelink direct       Link straight to the phone with Wi-Fi Direct
phonelink direct off   Drop the direct link
phonelink wifi         Switch a USB-connected phone to Wi-Fi
phonelink stop         Close phone windows and drop all connections
phonelink refresh      Re-read the app list from the phone
phonelink status       Show connected phones
```

## Settings

`~/.config/phonelink/config` is a bash file:

| Setting | Default | |
|---|---|---|
| `DIRECT` | `auto` | `off` always goes through the router |
| `APP_ICONS` | `play` | `off` skips looking up app icons on Google Play |
| `APP_DPI` | `200` | Size of the UI in app windows; higher is bigger |
| `KEYBOARD` | `uhid` | `uhid` gives the phone a real keyboard, so its own keyboard app handles languages such as Chinese |
| `SERIAL` | | Use this phone when several are connected |
| `MIRROR_ARGS` | `(--max-size=1600)` | Extra scrcpy options for the mirror |
| `APP_ARGS` | | Extra scrcpy options for app windows |
| `COMMON_ARGS` | `(--video-bit-rate=10M)` | Extra scrcpy options for both |

To float the mirror instead of tiling it, uncomment the last line of
`~/.config/hypr/phonelink.lua`.

## The direct Wi-Fi link

Over Wi-Fi, video normally travels phone → router → computer. When the phone is
only on Wi-Fi, phonelink links the two directly with Wi-Fi Direct, the
connection Samsung's Smart View uses. Both stay on your home network.

The first window you open in a session sets it up, which takes about 15
seconds. The phone needs to be unlocked. It briefly shows its Wi-Fi Direct page,
and phonelink taps Connect on the invitation for you. If that tap doesn't
happen, tap Connect yourself.

## Troubleshooting

- **No phone found.** Check that Wireless debugging is on. Android turns it off
  when the phone restarts or changes Wi-Fi network. A quick-settings tile helps:
  **Developer options › Quick settings developer tiles › Wireless debugging**.
- **Laggy over Wi-Fi.** Check that the direct link is up (`phonelink status`).
  If it can't be set up, lower `--max-size` or the bit rate in the config. USB
  is the fastest option.
- **The direct link won't connect.** Keep the phone unlocked and nearby while
  it's set up.
- **A black window.** Some apps, such as banking apps and Netflix, block screen
  capture.
- **Sound plays in only one window.** That's deliberate: only the first phone
  window forwards sound, so it doesn't play twice.
- **Android emulators.** phonelink ignores them. To use one anyway, set
  `SERIAL` to its name, such as `emulator-5554`.
- **Disconnect and Android Studio.** Disconnecting normally stops adb, because
  that's the only way to stop it reconnecting the phone while Wireless
  debugging is on. If an emulator or a USB device is connected, adb stays up for
  them, and the phone may reconnect.

Each window's log is in `~/.local/state/phonelink/logs/`.

## Privacy

Everything between your computer and phone stays on your network. The one
exception is app icons: the first time you open or pin a phone app, phonelink
fetches its icon from the app's Google Play page, which tells Google the app's
package name. Set `APP_ICONS="off"` to use a generic icon instead.
