# Reference

## Contents

- [Requirements](#requirements)
- [What the installer changes](#what-the-installer-changes)
- [The bar icon](#the-bar-icon)
- [Inside a phone window](#inside-a-phone-window)
- [Commands](#commands)
- [Settings](#settings)
- [The direct Wi-Fi link](#the-direct-wi-fi-link)
- [Away from home (Tailscale)](#away-from-home-tailscale)
- [Troubleshooting](#troubleshooting)
- [Privacy](#privacy)

## Requirements

- Omarchy (Hyprland with Omarchy's Lua config).
- An Android phone. Wi-Fi pairing needs Android 11 or newer.
- For the direct Wi-Fi link: NetworkManager with wpa_supplicant (iwd can't do
  Wi-Fi Direct), and a Wi-Fi card that supports Wi-Fi Direct alongside a normal
  connection. Without these, phonelink goes through your router instead.
- For use away from home: [Tailscale](https://tailscale.com) on the computer
  and the phone, on the same tailnet.

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
phonelink connect      Connect to a paired phone, nearby or over Tailscale
phonelink connect <port>  Reach the phone over Tailscale at this Wireless debugging port
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
| `TAILSCALE` | `auto` | `off` never reaches the phone over Tailscale |
| `TAILSCALE_HOST` | | The phone's Tailscale name, if phonelink can't work it out |
| `REMOTE_ARGS` | `(--video-bit-rate=4M --max-fps=30)` | Extra scrcpy options over Tailscale |
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

## Away from home (Tailscale)

When the phone isn't nearby, phonelink reaches it over Tailscale. Nearby
connections always come first, so at home nothing changes.

**What it needs:**

- Tailscale running on the computer and the phone, on the same tailnet.
- The phone on Wi-Fi with Wireless debugging on. Android turns Wireless
  debugging off on mobile data. Any Wi-Fi network works, not just yours.

**How phonelink finds the phone:** whenever the phone connects nearby,
phonelink notes its Tailscale address and Wireless debugging port. If it has
never seen the phone, it uses the tailnet's only Android device, or
`TAILSCALE_HOST` from the config.

**When the port changes:** Wireless debugging picks a new port each time it's
turned on, including after the phone changes Wi-Fi network. Then phonelink asks
for the port shown under **Wireless debugging › IP address & port**. You can
also give it directly with `phonelink connect <port>`.

**On mobile data:** before you leave, plug the phone in and run `phonelink wifi`.
The phone then listens on port 5555 until it restarts, on any network,
including mobile data. phonelink tries that port over Tailscale. A computer the
phone hasn't allowed before has to be approved on the phone's screen.

**Speed:** video is lighter over Tailscale (`REMOTE_ARGS`), and the direct Wi-Fi
link is off, since the phone isn't nearby. How smooth it is depends on the
upload speed where the phone is. If Tailscale can't make a direct connection
and relays traffic through its servers, phonelink warns you, and the bar shows
"Tailscale · relayed". Expect lag then.

## Troubleshooting

- **No phone found.** Check that Wireless debugging is on. Android turns it off
  when the phone restarts or changes Wi-Fi network. A quick-settings tile helps:
  **Developer options › Quick settings developer tiles › Wireless debugging**.
- **Laggy over Wi-Fi.** Check that the direct link is up (`phonelink status`).
  If it can't be set up, lower `--max-size` or the bit rate in the config. USB
  is the fastest option.
- **The direct link won't connect.** Keep the phone unlocked and nearby while
  it's set up.
- **Can't reach the phone away from home.** Check that the Tailscale app on the
  phone is connected, the phone is on Wi-Fi, and Wireless debugging is on. Then
  run `phonelink connect <port>` with the port the phone shows.
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
