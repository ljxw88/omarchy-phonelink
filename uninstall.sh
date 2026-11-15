#!/bin/bash

# Remove phonelink. scrcpy, adb and your settings in ~/.config/phonelink stay.

set -uo pipefail

HYPR_FILE="$HOME/.config/hypr/hyprland.lua"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

disconnect() {
  [[ -x $HOME/.local/bin/phonelink ]] && "$HOME/.local/bin/phonelink" stop &>/dev/null
  nmcli connection delete phonelink-direct &>/dev/null
}

remove_files() {
  rm -f "$HOME/.local/bin/phonelink" \
    "$HOME/.config/hypr/phonelink.lua" \
    "$HOME/.local/share/applications/phonelink.desktop" \
    "$HOME"/.local/share/applications/phonelink.*.desktop \
    "$HOME"/.local/share/icons/hicolor/256x256/apps/phonelink.*.png
  rm -rf "$HOME/.local/state/phonelink"
}

remove_config_lines() {
  [[ -f $HYPR_FILE ]] &&
    sed -i '/^-- Android phone windows (phonelink)\.$/d; /^require("hypr\.phonelink")$/d' "$HYPR_FILE"
  [[ -f $MENU_FILE ]] &&
    sed -i '/^ *\/\/ Android phone (phonelink, built on scrcpy)\.$/d; /^ *"phone[".]/d' "$MENU_FILE"
}

main() {
  disconnect
  remove_files
  remove_config_lines
  hyprctl reload >/dev/null 2>&1
  command -v omarchy &>/dev/null && omarchy menu refresh >/dev/null 2>&1
  update-desktop-database "$HOME/.local/share/applications" &>/dev/null
  echo "phonelink removed. Your settings are still in ~/.config/phonelink."
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && main "$@"
