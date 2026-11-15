#!/bin/bash

# Remove phonelink. scrcpy, adb and your settings in ~/.config/phonelink stay.

set -uo pipefail

# Omarchy reads Hyprland modules, menus and plugins from ~/.config whatever
# XDG_CONFIG_HOME says. phonelink's own files follow the XDG variables.
HYPR_DIR="$HOME/.config/hypr"
HYPR_FILE="$HYPR_DIR/hyprland.lua"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/phonelink.panel"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/phonelink"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/phonelink"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
SOURCE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# A line in hyprland.lua that loads phonelink, as install.sh writes it or
# written another way.
REQUIRE_LINE="^\s*require\s*\(?\s*[\"']hypr.phonelink[\"']\s*\)?\s*;?\s*$"

note() {
  printf '\e[33m!\e[0m %s\n' "$*"
}

# The same checks and edits of Omarchy's menu file as in install.sh.
menu_items() {
  sed -E '/^\s*\/\//d' "$1" | sed -zE 's/,(\s*[]}])/\1/g' | jq -se '
    if length == 1 and (.[0] | type) == "object" then
      .[0] | if (.items | type) == "object" then .items else . end
    else error end' 2>/dev/null
}

menu_markers_ok() {
  awk '
    /^[[:space:]]*\/\/ >>> phonelink >>>/ { if (open) bad = 1; open = 1 }
    /^[[:space:]]*\/\/ <<< phonelink <<</ { if (!open) bad = 1; open = 0 }
    END { exit bad || open }' "$1"
}

remove_menu_entries() {
  sed -i --follow-symlinks -E \
    -e '/^\s*\/\/ >>> phonelink >>>/,/^\s*\/\/ <<< phonelink <<</d' \
    -e '/^\s*\/\/ Android phone \(phonelink, built on scrcpy\)\.$/d' \
    -e '/^\s*"phone(\.(apps|mirror|sound|pin|refresh|stop|doctor|network|wireless(\.(direct|connect|pair|usb|disconnect))?))?":/d' \
    "$1"
}

disconnect() {
  [[ -x $HOME/.local/bin/phonelink ]] && "$HOME/.local/bin/phonelink" stop &>/dev/null
  nmcli connection delete phonelink-direct &>/dev/null
}

# Removes ~/.config/hypr/phonelink.lua and the copies the installer made,
# but keeps it aside if you've edited it since it was installed.
remove_hypr_file() {
  local file="$HYPR_DIR/phonelink.lua" sum backup
  if [[ -f $file ]]; then
    sum=$(sha256sum <"$file" | cut -d' ' -f1)
    if [[ $sum != "$(cat "$STATE_DIR/hypr-phonelink.lua.sha256" 2>/dev/null)" ]] &&
      ! cmp -s "$file" "$SOURCE_DIR/hypr/phonelink.lua"; then
      backup="$file.edited"
      [[ -e $backup ]] && backup+=".$(date +%s)"
      mv "$file" "$backup"
      note "You'd edited ~/.config/hypr/phonelink.lua, so it's kept as ${backup/#$HOME/\~}."
    fi
  fi
  rm -f "$file" "$file.new" "$file".bak.*
}

remove_files() {
  remove_hypr_file
  rm -f "$HOME/.local/bin/phonelink" \
    "$DATA_DIR/applications/phonelink.desktop" \
    "$DATA_DIR"/applications/phonelink.*.desktop \
    "$DATA_DIR"/icons/hicolor/256x256/apps/phonelink.*.png
  rm -rf "$STATE_DIR"
}

remove_config_lines() {
  local backup
  if [[ -f $HYPR_FILE ]]; then
    sed -i --follow-symlinks -E \
      -e '/^-- Android phone windows \(phonelink\)\.$/d' \
      -e "/$REQUIRE_LINE/d" "$HYPR_FILE"
    if grep -nE 'hypr.phonelink' "$HYPR_FILE" | grep -qvE '^[0-9]+:\s*--'; then
      note "${HYPR_FILE/#$HOME/\~} still loads hypr.phonelink. Take that line out, or Hyprland reports an error."
    fi
  fi

  [[ -f $MENU_FILE ]] || return 0
  if ! menu_markers_ok "$MENU_FILE"; then
    note "The phonelink part of ~/.config/omarchy/extensions/omarchy-menu.jsonc is missing its >>> or <<< line, so it was left in. Take it out by hand."
    return 0
  fi
  backup=$(mktemp)
  cat "$MENU_FILE" >"$backup"
  remove_menu_entries "$MENU_FILE"
  if menu_items "$backup" >/dev/null && ! menu_items "$MENU_FILE" >/dev/null; then
    cat "$backup" >"$MENU_FILE"
    note "Couldn't take the Phone menu out of ~/.config/omarchy/extensions/omarchy-menu.jsonc. Take it out by hand."
  fi
  rm -f "$backup"
}

main() {
  disconnect
  command -v omarchy &>/dev/null && omarchy plugin disable phonelink.panel >/dev/null 2>&1
  rm -rf "$PLUGIN_DIR"
  remove_files
  remove_config_lines
  hyprctl reload >/dev/null 2>&1
  command -v omarchy &>/dev/null && omarchy menu refresh >/dev/null 2>&1
  update-desktop-database "$DATA_DIR/applications" &>/dev/null
  echo "phonelink removed. Your settings are still in ${CONFIG_DIR/#$HOME/\~}."
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && main "$@"
