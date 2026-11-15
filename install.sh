#!/bin/bash

# Install phonelink into an Omarchy setup. Run it again to update.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
HYPR_DIR="$HOME/.config/hypr"
CONFIG_DIR="$HOME/.config/phonelink"
STATE_DIR="$HOME/.local/state/phonelink"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/phonelink.panel"
PACKAGES=(scrcpy android-tools android-udev qrencode jq)

step() {
  printf '\e[32m→\e[0m %s\n' "$*"
}

note() {
  printf '\e[33m!\e[0m %s\n' "$*"
}

if ((EUID == 0)); then
  echo "Run install.sh as yourself, not as root. It asks for your password when it needs it." >&2
  exit 1
fi

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
first_install=true
grep -q 'require("hypr.phonelink")' "$HYPR_DIR/hyprland.lua" && first_install=false

if $first_install; then
  taken=$(omarchy menu keybindings --print 2>/dev/null | grep -E '^SUPER (SHIFT )?ALT \+ (P|V)\s' || true)
  if [[ -n $taken ]]; then
    note "These keys are already bound, and phonelink binds them too:"
    echo "$taken" | sed 's/^/    /'
    note "To keep yours, set phonelink_bindings = false in ~/.config/hypr/hyprland.lua above require(\"hypr.phonelink\")."
  fi
fi

# phonelink.lua is replaced on update unless you've edited it. The checksum
# of what was last installed tells the two apart.
hypr_file="$HYPR_DIR/phonelink.lua"
sum_file="$STATE_DIR/hypr-phonelink.lua.sha256"
new_sum=$(sha256sum <hypr/phonelink.lua | cut -d' ' -f1)
mkdir -p "$STATE_DIR"
if [[ ! -f $hypr_file ]] || cmp -s hypr/phonelink.lua "$hypr_file"; then
  install -Dm644 hypr/phonelink.lua "$hypr_file"
  echo "$new_sum" >"$sum_file"
else
  current_sum=$(sha256sum <"$hypr_file" | cut -d' ' -f1)
  if [[ -s $sum_file && $current_sum == "$(<"$sum_file")" ]]; then
    install -Dm644 hypr/phonelink.lua "$hypr_file"
    echo "$new_sum" >"$sum_file"
  elif [[ ! -s $sum_file ]]; then
    # Installed before phonelink kept track, so keep a copy to be safe.
    backup="$hypr_file.bak.$(date +%s)"
    cp "$hypr_file" "$backup"
    install -Dm644 hypr/phonelink.lua "$hypr_file"
    echo "$new_sum" >"$sum_file"
    note "Updated ~/.config/hypr/phonelink.lua; the previous one is in ${backup/#$HOME/\~}."
  else
    install -Dm644 hypr/phonelink.lua "$hypr_file.new"
    note "You've edited ~/.config/hypr/phonelink.lua, so it was kept. The new version is phonelink.lua.new beside it."
  fi
fi

if $first_install; then
  printf '\n-- Android phone windows (phonelink).\nrequire("hypr.phonelink")\n' >>"$HYPR_DIR/hyprland.lua"
fi

step "Adding the Phone menu"
if [[ ! -f $MENU_FILE ]]; then
  mkdir -p "$(dirname "$MENU_FILE")"
  printf '{\n}\n' >"$MENU_FILE"
fi

# Take out the phonelink block, between its markers, and the unmarked entries
# the first release wrote, then put the current block in.
sed -i -E \
  -e '/^ *\/\/ >>> phonelink >>>/,/^ *\/\/ <<< phonelink <<</d' \
  -e '/^ *\/\/ Android phone \(phonelink, built on scrcpy\)\.$/d' \
  -e '/^ *"phone(\.(apps|mirror|sound|pin|refresh|stop|wireless(\.(direct|connect|pair|usb|disconnect))?))?":/d' \
  "$MENU_FILE"

last=$(grep -n '^}' "$MENU_FILE" | tail -1 | cut -d: -f1 || true)
if [[ -z $last ]]; then
  note "Couldn't find where to add the Phone menu in $MENU_FILE."
  note "Add the entries from omarchy/menu.jsonc to it by hand."
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
  } | cat -s >"$tmp"
  cat "$tmp" >"$MENU_FILE"
  rm -f "$tmp"
fi

hyprctl reload >/dev/null || true
command -v omarchy &>/dev/null && omarchy menu refresh >/dev/null 2>&1 || true

step "Adding the Phone icon to the bar"
updating=false
[[ -d $PLUGIN_DIR ]] && updating=true
mkdir -p "$PLUGIN_DIR"
cp -r shell/phonelink.panel/. "$PLUGIN_DIR/"
if command -v omarchy-shell &>/dev/null; then
  if $updating; then
    # Hot reload can miss changes to a running widget; a restart can't.
    omarchy restart shell >/dev/null 2>&1 || true
  else
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
      sleep 1
      omarchy plugin enable phonelink.panel --before omarchy.bluetooth >/dev/null 2>&1 && break
      omarchy plugin enable phonelink.panel --section right >/dev/null 2>&1 && break
    done
  fi
fi

errors=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
if [[ -n $errors ]]; then
  echo "Hyprland reported config errors:" >&2
  echo "$errors" >&2
  exit 1
fi

if $first_install; then
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
else
  echo
  echo "Updated."
fi
