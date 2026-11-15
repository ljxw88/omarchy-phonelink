#!/bin/bash

# Install phonelink into an Omarchy setup. Run it again to update.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
HYPR_DIR="$HOME/.config/hypr"
CONFIG_DIR="$HOME/.config/phonelink"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
PACKAGES=(scrcpy android-tools android-udev qrencode jq)

step() {
  printf '\e[32m→\e[0m %s\n' "$*"
}

if ! command -v hyprctl &>/dev/null || [[ ! -f $HYPR_DIR/hyprland.lua ]]; then
  echo "phonelink is made for Omarchy (Hyprland with a Lua config)." >&2
  exit 1
fi

missing=()
for pkg in "${PACKAGES[@]}"; do
  pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
done
if ((${#missing[@]})); then
  step "Installing ${missing[*]}"
  if command -v omarchy &>/dev/null; then
    omarchy pkg add "${missing[@]}"
  else
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
fi

step "Installing the phonelink command"
install -Dm755 bin/phonelink "$BIN_DIR/phonelink"
install -Dm644 applications/phonelink.desktop "$APPS_DIR/phonelink.desktop"
[[ -f $CONFIG_DIR/config ]] || install -Dm644 config.example "$CONFIG_DIR/config"
update-desktop-database "$APPS_DIR" &>/dev/null || true

step "Adding keybindings and window rules"
install -Dm644 hypr/phonelink.lua "$HYPR_DIR/phonelink.lua"
if ! grep -q 'require("hypr.phonelink")' "$HYPR_DIR/hyprland.lua"; then
  printf '\n-- Android phone windows (phonelink).\nrequire("hypr.phonelink")\n' >>"$HYPR_DIR/hyprland.lua"
fi

step "Adding the Phone menu"
if [[ ! -f $MENU_FILE ]]; then
  mkdir -p "$(dirname "$MENU_FILE")"
  printf '{\n}\n' >"$MENU_FILE"
fi
if ! grep -q '^ *"phone":' "$MENU_FILE"; then
  last=$(grep -n '^}' "$MENU_FILE" | tail -1 | cut -d: -f1 || true)
  if [[ -z $last ]]; then
    echo "Couldn't find where to add the Phone menu in $MENU_FILE." >&2
    echo "Add the entries from omarchy/menu.jsonc to it by hand." >&2
  else
    # The entry before ours needs a trailing comma.
    prev=$(head -n $((last - 1)) "$MENU_FILE" | grep -nvE '^\s*(//.*)?$' | tail -1 || true)
    if [[ -n $prev && ${prev#*:} != *, && ${prev#*:} != *\{ ]]; then
      sed -i "${prev%%:*}s/\$/,/" "$MENU_FILE"
    fi

    tmp=$(mktemp)
    {
      head -n $((last - 1)) "$MENU_FILE"
      echo
      cat omarchy/menu.jsonc
      tail -n +"$last" "$MENU_FILE"
    } >"$tmp"
    cat "$tmp" >"$MENU_FILE"
    rm -f "$tmp"
  fi
fi

hyprctl reload >/dev/null || true
command -v omarchy &>/dev/null && omarchy menu refresh >/dev/null 2>&1 || true

errors=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
if [[ -n $errors ]]; then
  echo "Hyprland reported config errors:" >&2
  echo "$errors" >&2
  exit 1
fi

cat <<'EOF'

Installed. Set up your phone once:
  1. Settings › About phone › Software information: tap Build number 7 times.
  2. Settings › Developer options: turn on Wireless debugging (or USB debugging
     and plug the phone in).
  3. Omarchy menu › Phone › Wi-Fi › Pair with QR code, and scan it from
     Wireless debugging › Pair device with QR code.

Then press Super + Alt + P to open a phone app, or Super + Alt + Shift + P to
mirror the whole screen.
EOF
