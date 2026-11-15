# Reference

## Contents

- [Requirements](#requirements)
- [What the installer changes](#what-the-installer-changes)
- [The bar icon](#the-bar-icon)
- [The network map](#the-network-map)
- [Inside a phone window](#inside-a-phone-window)
- [Sound](#sound)
- [Which phone](#which-phone)
- [Commands](#commands)
- [Settings](#settings)
- [The direct Wi-Fi link](#the-direct-wi-fi-link)
- [Away from home (Tailscale)](#away-from-home-tailscale)
- [Staying smooth and connected](#staying-smooth-and-connected)
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
your copy stays and the new one is saved beside it as `phonelink.lua.new`. If
the installer has no record of the version it last put there, it replaces the
file and keeps the old one as `phonelink.lua.bak.<time>`.

If **Super + Alt + P**, **Super + Alt + Shift + P** or **Super + Alt + V** is
already taken when you first install, the installer says so. To keep your
bindings, set `phonelink_bindings = false` in `~/.config/hypr/hyprland.lua`,
above the line that loads phonelink.

`uninstall.sh` undoes all of this except the packages and your settings, and
deletes the `phonelink-direct` network connection. An edited `phonelink.lua`
is kept as `phonelink.lua.edited`.

## The bar icon

Dimmed: no phone. Accent color: a phone window is open.

- **Click** opens the panel. At the top: the phone, how it's connected, and
  buttons for the network map, the direct link, the Phone menu and
  disconnecting (or Connect and Pair when no phone is connected). Below: tiles
  for Mirror, your recent and pinned apps, and All apps. An open window's tile
  is filled and marked with a dot; the speaker in a tile's corner shows where
  its sound plays and switches it. The 󰅙 in an app's other corner takes it off
  the panel (a pinned app stays in the launcher); opening it again brings it
  back.

  Arrow keys or h/j/k/l move, Enter opens, M mirrors, S switches the sound,
  X removes an app, N opens the network map, Esc closes.
- **Right click** mirrors the phone.
- **Middle click** opens the full app list.

Move it by dragging it along the bar, or with
`omarchy bar move phonelink.panel --section <section>`.

## The network map

The map button at the top of the bar panel (or `phonelink network --panel`,
or **N** in the panel) shows every way this computer has to the phone, as a lane between the
two, with the address at each end:

| Lane | This computer's address | The phone's address |
|---|---|---|
| USB | None; the cable carries it | None; adb uses the phone's serial number |
| Direct Wi-Fi | Handed out by the phone, which runs the link | Always 192.168.49.1 on a link the phone runs |
| Wi-Fi | Handed out by your router (DHCP) | Handed out by your router. phonelink finds it in the phone's mDNS announcement |
| Tailscale | Assigned by Tailscale | Assigned by Tailscale. phonelink notes it while the phone is nearby |

The port after the phone's address is its Wireless debugging port. It's the
same on every network the phone is on, and changes each time Wireless
debugging is turned on.

The lane in use is drawn in your theme's accent color, with traffic flowing
from the phone to this computer, and shows its round trip, data rate and any
backlog. A solid line is connected but idle; a dashed one could connect. The
Wi-Fi lane shows your router in the middle, and the Tailscale lane whether
traffic goes direct or through a relay. Point at a lane, or move to it with
the arrow keys, to read where its addresses came from. Chips below show what's
streaming and the phone's mobile data address (from its carrier, and not
reachable from here).

`phonelink network` prints the same map in a terminal, and
`phonelink network --json` gives it as data.

## Inside a phone window

| | |
|---|---|
| Back | **Super + B** or right-click |
| Home | **Super + H** or middle-click |
| Notification panel | **Super + N** |
| Rotate | **Super + R** |
| Sound on this computer or the phone | **Super + Alt + V** |
| Float the window | **Super + T** |

Copy and paste work both ways. Drag a file onto a window to send it to the
phone, or drag an APK to install it.

Each phone app runs on its own virtual display that resizes with its tile, so
it lays itself out like a desktop app and leaves the phone's own screen free.
Apps can't turn that display: an app that only works in landscape or portrait
is fitted into the window's shape, with bars if it has to, the way Android
tablets do it.
The mirror keeps the phone's shape inside its tile.

## Sound

Switch a phone window's sound between **this computer** (the default) and
**the phone** with **Super + Alt + V** in the window, or with the speaker
button on its row in the bar panel. The sound moves right away.

Android mixes every app's sound into one output, so phone windows share one
sound: switching one moves it for all open phone windows. Each app and the
mirror remembers its setting, and opening a window set to this computer brings
the sound here. Opening one set to the phone leaves the sound where it is.
When the last phone window closes, the sound goes back to the phone.

In the bar panel, an open window's speaker button shows where the sound plays
now. For an app that isn't open, it shows where its sound will play when it
opens.

While the sound plays here, the phone's speaker is silent. It goes to this
computer's current output, as set in Omarchy's audio panel.

## Which phone

phonelink remembers the phones it has used, by serial number, in
`~/.local/state/phonelink/phones`, and leaves other Android devices alone. It
never uses emulators or virtual machines. It learns a phone when you pair it
with `phonelink pair`, connect to it with `phonelink connect`, use it over USB,
or set it as `SERIAL` in the config, and uses the first phone it finds while it
knows none. A USB device it doesn't know is used only when none of yours
answers. Over Tailscale it only uses your own Android devices. A window that
loses its connection only reconnects to the same phone.

## Commands

```
phonelink              Open the Phone menu
phonelink apps         Pick a phone app and open it in its own window
phonelink open <pkg>   Open one phone app in its own window
phonelink mirror       Mirror and control the whole phone screen
phonelink pin          Choose which phone apps appear in the app launcher
phonelink hide <pkg>   Take an app off the bar panel (opening it brings it back)
phonelink pair         Pair over Wi-Fi with a QR code
phonelink connect      Connect to a paired phone, nearby or over Tailscale
phonelink connect <port>  Reach the phone over Tailscale at this Wireless debugging port
phonelink connect <address:port>  Connect to the phone at this address
phonelink sound [pc|phone|toggle] [mirror|<pkg>]
                       Play a window's sound on this computer or the phone
phonelink direct       Link straight to the phone with Wi-Fi Direct
phonelink direct off   Drop the direct link
phonelink direct toggle  Turn the direct link on or off
phonelink wifi         Switch a USB-connected phone to Wi-Fi (unencrypted port 5555)
phonelink wifi off     Close port 5555 again
phonelink stop         Close phone windows and drop all connections (also: disconnect)
phonelink refresh      Re-read the app list from the phone
phonelink status       Show connected phones and open windows
phonelink status --json  What the bar shows, as data
phonelink doctor       Check for common causes of lag and dropouts
phonelink network      Show every way to the phone, with addresses and where they came from
phonelink network --panel  Open the network map in the bar
```

`phonelink stop` also disconnects other phones and TVs that adb reaches over
Wi-Fi, closes port 5555 if `phonelink wifi` opened it,
and stops adb unless a USB device or an emulator is connected.
`phonelink status` and `phonelink doctor` start adb again, which reconnects
the phone.

## Settings

`~/.config/phonelink/config` is a bash file:

| Setting | Default | |
|---|---|---|
| `DIRECT` | `auto` | `off` always goes through the router |
| `APP_ICONS` | `play` | `off` skips looking up app icons on Google Play |
| `APP_DPI` | `200` | Size of the UI in app windows; higher is bigger |
| `SOUND` | `pc` | Where a window's sound plays until you switch it: `pc` or `phone` |
| `KEYBOARD` | `uhid` | `uhid` gives the phone a real keyboard, so its own keyboard app handles languages such as Chinese |
| `SERIAL` | | Always use this phone. Windows then stay on the connection they start on |
| `TAILSCALE` | `auto` | `off` never reaches the phone over Tailscale |
| `TAILSCALE_HOST` | | The phone's Tailscale name, if phonelink can't work it out |
| `REMOTE_ARGS` | | Extra scrcpy options over Tailscale |
| `ADAPT` | `auto` | `off` uses scrcpy's own defaults instead of fitting the quality to the connection |
| `RECONNECT_SECS` | `120` | How long a window that lost its connection keeps trying; `0` closes it |
| `MIRROR_ARGS` | `(--max-size=1600)` | scrcpy options for the mirror |
| `APP_ARGS` | `(--no-vd-system-decorations --keep-active)` | scrcpy options for app windows |
| `COMMON_ARGS` | | Extra scrcpy options for both |

Setting `MIRROR_ARGS` or `APP_ARGS` replaces its default, so keep the default
options you still want. Your options come after the automatic quality ones, so
they win. With a `--video-bit-rate` of your own, phonelink no longer lowers the
quality when the link falls behind; it still reconnects after drops. The
mirror's `--max-size` is the largest it gets: quality steps 4 and 5 make it
smaller still.

To float the mirror instead of tiling it, uncomment the last line of
`~/.config/hypr/phonelink.lua`.

## The direct Wi-Fi link

Over Wi-Fi, video normally travels phone → router → computer. When the phone is
only on Wi-Fi, phonelink links the two directly with Wi-Fi Direct, the
connection Samsung's Smart View uses. Both stay on your home network.

The first window you open in a session sets it up, which takes about 15
seconds. phonelink wakes the phone and waits up to 30 seconds for you to
unlock it. To open the phone's Wi-Fi Direct page fresh, it closes the phone's
Settings app, so anything you had open there is lost. phonelink taps Connect
on the invitation for you. If that tap doesn't happen, tap Connect yourself.

If setting up the link fails, phonelink uses your router. While the link is
down, each window you open tries again, but not within 10 minutes of a failed
try. The link is saved as a NetworkManager connection named
`phonelink-direct`, which stays until you uninstall phonelink.

## Away from home (Tailscale)

When the phone isn't nearby, phonelink reaches it over Tailscale. Nearby
connections always come first, so at home nothing changes.

**What it needs:**

- Tailscale running on the computer and the phone, on the same tailnet.
- The phone on Wi-Fi with Wireless debugging on. Android turns Wireless
  debugging off on mobile data. Any Wi-Fi network works, not just yours.

**How phonelink finds the phone:** whenever the phone connects nearby,
phonelink notes its Tailscale address and Wireless debugging port. If it has
never seen the phone, it uses your only Android device on the tailnet, or
`TAILSCALE_HOST` from the config. Other people's devices on the tailnet, and
devices shared with you, are never used.

**When the port changes:** Wireless debugging picks a new port each time it's
turned on, including after the phone changes Wi-Fi network. Then phonelink asks
for the port shown under **Wireless debugging › IP address & port**. You can
also give it directly with `phonelink connect <port>`.

**On mobile data:** before you leave, plug the phone in and run `phonelink wifi`.
The phone then listens on port 5555 until it restarts, on any network,
including mobile data. phonelink tries that port over Tailscale. A computer the
phone hasn't allowed before has to be approved on the phone's screen.
Unlike Wireless debugging, this port isn't encrypted, so avoid it on shared
networks. `phonelink wifi off` or `phonelink stop` closes it. If the port is
already open, `phonelink wifi` leaves it as it is.

**Speed:** video starts lighter over Tailscale, and the direct Wi-Fi link is
off, since the phone isn't nearby. How smooth it is depends on the
upload speed where the phone is. If Tailscale can't make a direct connection
and relays traffic through its servers, phonelink warns you, and the bar shows
"Tailscale · relayed". Expect lag then.

## Staying smooth and connected

scrcpy sends video over TCP at a fixed bit rate and never drops frames. When
the connection can't carry that rate, the picture doesn't get worse; it gets
later, and the delay keeps growing. scrcpy also can't change its settings or
its connection while it runs. So phonelink runs each window as a session that
watches the connection from outside and restarts scrcpy when something has to
change. A restart takes a second or two.

**Quality levels**

| Step | Bit rate | Frame rate | Used for |
|---|---|---|---|
| 1 | 16 Mbit/s | 60 | USB |
| 2 | 8 Mbit/s | 60 | The direct link or a good Wi-Fi network |
| 3 | 5 Mbit/s | 60 | A slower Wi-Fi uplink, or several windows at once |
| 4 | 3 Mbit/s | 30 | Tailscale |
| 5 | 1.5 Mbit/s | 24 | Relayed Tailscale, or links that keep falling behind |

From step 3 down, phones with a hardware H.265 encoder use it, which keeps the
picture sharper at the same bit rate. The mirror also gets smaller at steps 4
and 5.

**Choosing the start:** USB always starts at step 1. Otherwise a window starts
at step 2 nearby or step 4 over Tailscale, and a step lower for each of these:
the phone's Wi-Fi uplink is under 25 Mbit/s (two steps under 12 Mbit/s, so
step 4 on your Wi-Fi), another phone window is open (so step 5 over
Tailscale), and Tailscale relays the traffic. The direct link ignores the
uplink. If a lower step was needed on this network before, it starts there.
Only some phones report their uplink (Samsung's do, as "Calculated Tx"); on
others, phonelink skips it.

**Falling behind:** phonelink reads the connection's round-trip time from the
kernel every 2 seconds. When it stays well above its best (50 ms over it
nearby, 150 ms over Tailscale) for about 10 seconds, the window restarts one
step lower, at most once every 30 seconds. The step is remembered for that
network. After 10 minutes without trouble, the next window there starts a step
higher again.

**Dropouts:** the phone sends a frame at least every 100 ms, even of a still
screen. When no data arrives for 5 seconds twice in a row, or the window closes
because the phone went away, phonelink finds the phone again by whatever way
works: USB, the direct link, your Wi-Fi, or Tailscale. It keeps trying for
`RECONNECT_SECS` (2 minutes by default). The window comes back on the workspace
it was on, without switching your view. App windows reopen the app, which most
apps resume where they were. The same happens after this computer wakes from
sleep.

**Better paths:** every 20 seconds nearby, and every 6 over Tailscale,
phonelink checks for a faster way to the phone. Plugging the phone in moves the
windows to USB, and coming home moves them from Tailscale to your Wi-Fi. With
`SERIAL` set, windows stay on the connection they start on.

**The direct link:** when it ends up on a different Wi-Fi channel than your
network, the Wi-Fi card has to switch between the two, which slows both. Then
phonelink uses the router instead.

**Sound:** the phone's sound has its own connection, which reconnects and
moves to a better path the same way the windows do, checking every 10 seconds.
Over Wi-Fi and Tailscale it buffers a little more audio, so short hiccups
don't crackle.

**What phonelink can't fix:** Android's low-latency Wi-Fi mode needs a rooted
phone. A connection that's simply too slow stays slow; `phonelink doctor`
points out the usual causes, such as Wi-Fi power saving, 2.4 GHz, a weak signal,
or the phone and computer on different access points.

What each window decided, and why, is logged in
`~/.local/state/phonelink/logs/sessions.log`.

## Troubleshooting

- **Laggy, or keeps reconnecting.** Run `phonelink doctor`, or
  **Omarchy menu › Phone › Check connection**. It checks both Wi-Fi
  connections, the phone's uplink on phones that report it, the direct link
  and Tailscale, and says what to change.

- **No phone found.** Check that Wireless debugging is on. Android turns it off
  when the phone restarts or changes Wi-Fi network. A quick-settings tile helps:
  **Developer options › Quick settings developer tiles › Wireless debugging**.
- **The direct link won't connect.** Keep the phone unlocked and nearby while
  it's set up.
- **Can't reach the phone away from home.** Check that the Tailscale app on the
  phone is connected, the phone is on Wi-Fi, and Wireless debugging is on. Then
  run `phonelink connect <port>` with the port the phone shows.
- **A black window.** Some apps, such as banking apps and Netflix, block screen
  capture.
- **A landscape video looks small next to another window.** Side by side, each
  window is taller than it is wide, so the video is fitted in with bars. Press
  **Super + J** to stack the windows instead, which makes both wide, or give the
  video the whole workspace.
- **No sound on this computer.** Check the window's sound button in the bar
  panel. Sound needs Android 11 or newer. If it still fails, the error is in
  `~/.local/state/phonelink/logs/phonelink-sound.log`.
- **Another phone, an emulator or a virtual machine.** phonelink only uses the
  phones it knows. See [Which phone](#which-phone).
- **Disconnect and Android Studio.** Disconnecting normally stops adb, because
  that's the only way to stop it reconnecting the phone while Wireless
  debugging is on. If an emulator or a USB device is connected, adb stays up for
  them, and the phone may reconnect.

Each window's scrcpy log is in `~/.local/state/phonelink/logs/`, beside
`sessions.log`.

## Privacy

phonelink has no servers of its own; video, sound and input go between your
computer and phone. Worth knowing:

- Over Tailscale, traffic may pass through Tailscale's relay servers when the
  two can't connect directly. It stays encrypted.
- `phonelink wifi` opens port 5555 on the phone, which isn't encrypted, so
  others on the same network can read the traffic. Wireless debugging is
  encrypted.
- App icons: the first time you open or pin a phone app, phonelink looks it up
  on Google Play and downloads its icon from Google's image server, which tells
  Google the app's package name. Pinning an app whose icon wasn't found looks
  it up again. Set `APP_ICONS="off"` to use a generic icon and make no such
  requests.
