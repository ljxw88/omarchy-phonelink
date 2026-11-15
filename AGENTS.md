# Instructions for AI agents

How to install, update and remove omarchy-phonelink for a user. Follow the
steps in order and report what happened in plain words.

## Install

1. Check that this is Omarchy:

   ```bash
   command -v omarchy hyprctl && test -f ~/.config/hypr/hyprland.lua
   ```

   If that fails, stop. Tell the user phonelink needs Omarchy.

2. Get the code, or update it if it's already there:

   ```bash
   dir=~/.local/share/omarchy-phonelink
   if [ -d "$dir/.git" ]; then git -C "$dir" pull; else git clone https://github.com/ljxw88/omarchy-phonelink "$dir"; fi
   ```

3. Install the packages. `install.sh` asks for a sudo password when any are
   missing. If you can't answer a password prompt in your terminal, install
   them first with a graphical prompt:

   ```bash
   pacman -Q scrcpy android-tools android-udev qrencode jq >/dev/null 2>&1 ||
     pkexec pacman -S --needed --noconfirm scrcpy android-tools android-udev qrencode jq
   ```

4. Run the installer as the user, not as root. Running it again is safe.

   ```bash
   ~/.local/share/omarchy-phonelink/install.sh
   ```

   On an update it restarts the Omarchy bar, which flickers for a second.

5. Check the result:

   ```bash
   hyprctl configerrors          # should print nothing
   phonelink --help              # should list the commands
   ```

6. Pass on any line the installer printed with `!`. These say that
   Super + Alt + P was already taken, or that the user's edited
   `~/.config/hypr/phonelink.lua` was kept.

## Help the user set up their phone

These steps happen on the phone, so guide the user one step at a time:

1. **Settings › About phone › Software information**: tap **Build number** 7 times.
2. **Settings › Developer options**: turn on **Wireless debugging**.
3. Run `phonelink pair`. It opens a terminal with a QR code. On the phone, open
   **Wireless debugging › Pair device with QR code** and scan it.
4. Confirm with `phonelink status`. It should list the phone.

On Samsung phones, if debugging is greyed out or mouse input is blocked, the user
should turn off **Settings › Security and privacy › Auto Blocker**.

Then tell them: **Super + Alt + P** opens a phone app, **Super + Alt + Shift + P**
mirrors the phone, and the phone icon in the bar has everything else.

If the user wants to use the phone away from home, check that `tailscale status`
lists the phone. Remote use then works by itself once the phone has connected
nearby. See [docs/reference.md](docs/reference.md#away-from-home-tailscale).

## Update

```bash
git -C ~/.local/share/omarchy-phonelink pull && ~/.local/share/omarchy-phonelink/install.sh
```

## Uninstall

Only when the user asks:

```bash
~/.local/share/omarchy-phonelink/uninstall.sh
```

This keeps scrcpy, adb and the user's settings in `~/.config/phonelink`.

## Rules

- Don't edit anything in `/usr/share/omarchy`.
- Don't run `phonelink stop` or `phonelink direct off` while the user has phone
  windows open, unless they ask. Both close the connection those windows use.
- To see which path the phone uses and where each address came from, run
  `phonelink network`.
- For lag or dropouts, run `phonelink doctor` first, then read
  `~/.local/state/phonelink/logs/sessions.log`, which records each window's
  quality changes and reconnections. More in
  [docs/reference.md](docs/reference.md#troubleshooting).
