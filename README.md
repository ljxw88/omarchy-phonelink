# omarchy-phonelink

Use your Android phone from [Omarchy](https://omarchy.org): open phone apps in
their own tiled windows, or mirror and control the whole phone screen, with
your mouse and keyboard. It works over USB or Wi-Fi and needs no app on the phone.

It's a thin Omarchy layer over [scrcpy](https://github.com/Genymobile/scrcpy),
which does the video and input.

## Features

- **Phone apps as windows.** Each app runs on its own virtual display that
  resizes with its tile, so it lays itself out like a desktop app. The phone's
  own screen stays free, and you can open several apps at once.
- **Screen mirroring** with two-way control, sound, clipboard sync in both
  directions, and drag-and-drop to send files or install APKs.
- **Direct Wi-Fi link.** Over Wi-Fi, video normally travels phone → router →
  laptop. phonelink links the two straight to each other with Wi-Fi Direct, the
  connection Smart View uses, while both stay on your home network. It sets
  this up by itself and taps the phone's Connect prompt for you.
- **Fits into Omarchy.** A Phone menu, keybindings, tiling window rules,
  launcher entries with real app icons, theme colors and Omarchy notifications.
- **Wi-Fi pairing with a QR code**, so you never need a cable.

## Requirements

- Omarchy (Hyprland with Omarchy's Lua config).
- An Android phone. Android 11 or newer is needed for Wi-Fi pairing.
- For the direct Wi-Fi link: NetworkManager with wpa_supplicant (iwd can't do
  Wi-Fi Direct), and a Wi-Fi card that supports Wi-Fi Direct alongside a normal
  connection. Without these, phonelink goes through your router instead.

Tested with a Samsung Galaxy Z Fold (Android 17) and a laptop with a MediaTek
MT7922 Wi-Fi card.

## Install

```bash
git clone https://github.com/ljxw88/omarchy-phonelink
cd omarchy-phonelink
./install.sh
```

The installer adds any missing packages (`scrcpy`, `android-tools`,
`android-udev`, `qrencode`, `jq`), then:

- puts the `phonelink` command in `~/.local/bin`
- adds `~/.config/hypr/phonelink.lua` (keybindings and window rules) and loads
  it from `~/.config/hypr/hyprland.lua`
- adds a Phone section to `~/.config/omarchy/extensions/omarchy-menu.jsonc`
- adds a "Phone" entry to the app launcher
- creates `~/.config/phonelink/config` for your settings

Run it again after pulling to update.

## Set up your phone

1. **Settings › About phone › Software information**: tap **Build number**
   seven times to turn on Developer options.
2. **Settings › Developer options**: turn on **Wireless debugging**. (Or turn on
   **USB debugging** and plug the phone in.)
3. On the computer, open **Omarchy menu › Phone › Wi-Fi › Pair with QR code**.
   On the phone, open **Wireless debugging › Pair device with QR code** and scan it.

After that the phone connects by itself whenever Wireless debugging is on. To
switch it on quickly, add the tile under **Developer options › Quick settings
developer tiles › Wireless debugging**.

On Samsung phones, turn off **Settings › Security and privacy › Auto Blocker**
if USB debugging is greyed out or mouse input is blocked.

## Use

| | |
|---|---|
| Open a phone app | **Super + Alt + P** |
| Mirror the whole phone | **Super + Alt + Shift + P** |
| Everything else | **Omarchy menu › Phone** |

Inside a phone window:

| | |
|---|---|
| Back | **Super + B** or right-click |
| Home | **Super + H** or middle-click |
| Notification panel | **Super + N** |
| Rotate | **Super + R** |
| Float the mirror | **Super + T** |

Phone apps tile like any other window. The mirror tiles too, keeping the
phone's shape inside its tile.

The command line covers the same ground:

```
phonelink apps         Pick a phone app and open it in its own window
phonelink open <pkg>   Open one phone app in its own window
phonelink mirror       Mirror and control the whole phone screen
phonelink pin          Choose which phone apps appear in the app launcher
phonelink pair         Pair over Wi-Fi with a QR code
phonelink direct       Link straight to the phone with Wi-Fi Direct
phonelink direct off   Drop the direct link
phonelink stop         Close phone windows and drop all connections
phonelink status       Show connected phones
```

## Settings

`~/.config/phonelink/config` is a bash file. The main settings:

| Setting | Default | |
|---|---|---|
| `DIRECT` | `auto` | Set to `off` to always go through the router |
| `APP_DPI` | `200` | Size of the UI in app windows; higher is bigger |
| `KEYBOARD` | `uhid` | `uhid` gives the phone a real keyboard, so its own keyboard app handles languages such as Chinese |
| `MIRROR_ARGS` | `(--max-size=1600)` | Extra scrcpy options for the mirror |
| `APP_ARGS` | | Extra scrcpy options for app windows |
| `COMMON_ARGS` | `(--video-bit-rate=10M)` | Extra scrcpy options for both |

To float the mirror instead of tiling it, uncomment the last line of
`~/.config/hypr/phonelink.lua`.

## Troubleshooting

- **No phone found.** Check that Wireless debugging is on. Android turns it off
  when the phone restarts or changes Wi-Fi network.
- **Laggy over Wi-Fi.** Check that the direct link is up (`phonelink status`).
  If it can't be set up, lower `--max-size` or the bit rate in the config. USB
  is the fastest option.
- **The direct link won't connect.** Keep the phone unlocked while it's being
  set up. It briefly opens the phone's Wi-Fi Direct page, then returns.
- **A black window.** Some apps, such as banking apps and Netflix, block screen
  capture.
- **Sound plays only in one window.** That's deliberate: only the first phone
  window forwards sound, so it doesn't play twice.

Each window's scrcpy log is in `~/.local/state/phonelink/logs/`.

## Uninstall

```bash
./uninstall.sh
```

This leaves scrcpy, adb and `~/.config/phonelink` in place.

## License

MIT. scrcpy is licensed separately under Apache 2.0.
