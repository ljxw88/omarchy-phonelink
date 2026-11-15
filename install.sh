#!/bin/bash

# Install phonelink into an Omarchy setup. Run it again to update.

# Omarchy reads Hyprland modules, menus and plugins from ~/.config whatever
# XDG_CONFIG_HOME says. phonelink's own files follow the XDG variables.
BIN_DIR="$HOME/.local/bin"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
HYPR_DIR="$HOME/.config/hypr"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/phonelink"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/phonelink"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/phonelink.panel"
PACKAGES=(scrcpy android-tools android-udev qrencode jq iw)

# A line in hyprland.lua that loads phonelink, even commented out.
REQUIRE_RE="require\s*\(?\s*[\"']hypr.phonelink[\"']"

step() {
  printf '\e[32m→\e[0m %s\n' "$*"
}

note() {
  printf '\e[33m!\e[0m %s\n' "$*"
}

# Prints the menu's entries the way Omarchy reads them (see MenuModel.js):
# whole-line // comments and trailing commas dropped, then parsed as JSON.
# Fails when Omarchy couldn't read the file.
menu_items() {
  sed -E '/^\s*\/\//d' "$1" | sed -zE 's/,(\s*[]}])/\1/g' | jq -se '
    if length == 1 and (.[0] | type) == "object" then
      .[0] | if (.items | type) == "object" then .items else . end
    else error end' 2>/dev/null
}

# True unless a phonelink block in the menu is missing one of its markers.
menu_markers_ok() {
  awk '
    /^[[:space:]]*\/\/ >>> phonelink >>>/ { if (open) bad = 1; open = 1 }
    /^[[:space:]]*\/\/ <<< phonelink <<</ { if (!open) bad = 1; open = 0 }
    END { exit bad || open }' "$1"
}

# Takes out the phonelink block, between its markers, and the unmarked
# entries the first release wrote. sed edits through a symlinked file.
remove_menu_entries() {
  sed -i --follow-symlinks -E \
    -e '/^\s*\/\/ >>> phonelink >>>/,/^\s*\/\/ <<< phonelink <<</d' \
    -e '/^\s*\/\/ Android phone \(phonelink, built on scrcpy\)\.$/d' \
    -e '/^\s*"phone(\.(apps|mirror|sound|pin|refresh|stop|doctor|network|wireless(\.(direct|connect|pair|usb|disconnect))?))?":/d' \
    "$1"
}

# Prints the number of the line whose brace closes the menu's entries: the
# "items" object when the file has one, or else the outer object. Prints
# nothing unless that brace starts its line.
menu_end_line() {
  awk '
    /^[[:space:]]*\/\// { next }
    {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (instr) {
          if (esc) esc = 0
          else if (c == "\\") esc = 1
          else if (c == "\"") instr = 0
          else if (depth == 1) word = word c
          continue
        }
        if (c == "\"") {
          instr = 1
          if (depth == 1) word = ""
        } else if (c == "{" || c == "[") {
          if (depth == 1 && c == "{" && word == "items") initems = 1
          depth++
        } else if (c == "}" || c == "]") {
          depth--
          start = substr($0, 1, i - 1) ~ /^[[:space:]]*$/
          if (depth == 1 && initems) { items = start ? NR : -1; initems = 0 }
          if (depth == 0 && !outer) outer = start ? NR : -1
        }
      }
    }
    END {
      line = items ? items : outer
      if (line > 0) print line
    }' "$1"
}

# Puts the block of menu entries in $2 before the line that closes the
# menu's entries, giving the entry before it the comma it needs.
add_menu_entries() {
  local file=$1 block=$2 end indent prev tmp
  end=$(menu_end_line "$file")
  [[ -n $end ]] || return 1
  indent=$(sed -n "${end}s/[^[:space:]].*//p" "$file")
  prev=$(head -n $((end - 1)) "$file" | grep -nvE '^\s*(//.*)?$' | tail -1 | cut -d: -f1)
  tmp=$(mktemp)
  {
    # Older installers could leave "},  ," here; it gets one comma again.
    head -n $((end - 1)) "$file" | awk -v n="${prev:-0}" '
      NR == n { sub(/[[:space:]]+$/, ""); sub(/,[[:space:]]*,$/, ","); if ($0 !~ /[,{]$/) $0 = $0 "," }
      { print }'
    echo
    sed "s/^/$indent/" "$block"
    tail -n +"$end" "$file"
  } | cat -s >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Adds the Phone menu to Omarchy's menu file, in place of any older one. If
# Omarchy couldn't read the result, the file is put back as it was.
install_menu() {
  local file=$1 block=$2 backup ok=false
  mkdir -p "$(dirname "$file")"
  grep -qvE '^\s*(//.*)?$' "$file" 2>/dev/null || printf '{\n}\n' >>"$file"

  if ! menu_markers_ok "$file"; then
    note "The phonelink part of ${file/#$HOME/\~} is missing its >>> or <<< line, so it was left as it is."
    note "Fix that by hand, then run install.sh again."
    return 1
  fi

  backup=$(mktemp)
  cat "$file" >"$backup"
  remove_menu_entries "$file" && add_menu_entries "$file" "$block" &&
    menu_items "$file" | jq -e 'has("phone")' >/dev/null && ok=true
  if ! $ok; then
    cat "$backup" >"$file"
    if menu_items "$file" >/dev/null; then
      note "Couldn't add the Phone menu to ${file/#$HOME/\~}. Add the entries from omarchy/menu.jsonc to it by hand."
    else
      note "Omarchy can't read ${file/#$HOME/\~}, so the Phone menu wasn't added. Fix it, then run install.sh again."
    fi
  fi
  rm -f "$backup"
  $ok
}

config_errors() {
  hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true
}

bar_icon_enabled() {
  omarchy plugin list --json 2>/dev/null |
    jq -e '.[] | select(.id == "phonelink.panel") | .enabled' >/dev/null
}

enable_bar_icon() {
  local _
  command -v omarchy-shell &>/dev/null || return 1
  for _ in 1 2 3 4 5; do
    sleep 1
    bar_icon_enabled && return 0
    omarchy plugin enable phonelink.panel --before omarchy.bluetooth >/dev/null 2>&1 && return 0
    omarchy plugin enable phonelink.panel --section right >/dev/null 2>&1 && return 0
  done
  return 1
}

# The tests source this file for the functions above.
[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if ((EUID == 0)); then
  echo "Run install.sh as yourself, not as root. It asks for your password when it needs it." >&2
  exit 1
fi

if ! command -v omarchy &>/dev/null || ! command -v hyprctl &>/dev/null || [[ ! -f $HYPR_DIR/hyprland.lua ]]; then
  echo "phonelink is made for Omarchy (Hyprland with a Lua config)." >&2
  exit 1
fi

missing=()
for pkg in "${PACKAGES[@]}"; do
  pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
done
if ((${#missing[@]})); then
  step "Installing ${missing[*]}"
  omarchy pkg add "${missing[@]}"
fi

errors_before=$(config_errors)

step "Installing the phonelink command"
install -Dm755 bin/phonelink "$BIN_DIR/phonelink"
install -Dm644 applications/phonelink.desktop "$APPS_DIR/phonelink.desktop"
[[ -f $CONFIG_DIR/config ]] || install -Dm644 config.example "$CONFIG_DIR/config"
update-desktop-database "$APPS_DIR" &>/dev/null || true

step "Adding keybindings and window rules"
first_install=true
grep -qE "$REQUIRE_RE" "$HYPR_DIR/hyprland.lua" && first_install=false

if $first_install; then
  taken=$(omarchy menu keybindings --print 2>/dev/null | grep -E '^SUPER (SHIFT )?ALT \+ (P|V)\s' || true)
  if [[ -n $taken ]]; then
    note "These keys are already bound, and phonelink binds them too:"
    echo "$taken" | sed 's/^/    /'
    note "To keep yours, set phonelink_bindings = false in ~/.config/hypr/hyprland.lua above require(\"hypr.phonelink\")."
  fi
fi

# phonelink.lua is replaced on update unless you've edited it. The checksum
# of what was last installed tells the two apart. cp writes through a
# symlinked file.
hypr_file="$HYPR_DIR/phonelink.lua"
sum_file="$STATE_DIR/hypr-phonelink.lua.sha256"
new_sum=$(sha256sum <hypr/phonelink.lua | cut -d' ' -f1)
mkdir -p "$STATE_DIR"
if [[ ! -f $hypr_file ]] || cmp -s hypr/phonelink.lua "$hypr_file"; then
  cp hypr/phonelink.lua "$hypr_file"
  echo "$new_sum" >"$sum_file"
else
  current_sum=$(sha256sum <"$hypr_file" | cut -d' ' -f1)
  if [[ -s $sum_file && $current_sum == "$(<"$sum_file")" ]]; then
    cp hypr/phonelink.lua "$hypr_file"
    echo "$new_sum" >"$sum_file"
  elif [[ ! -s $sum_file ]]; then
    # Installed before phonelink kept track, so keep a copy to be safe.
    backup="$hypr_file.bak.$(date +%s)"
    cp "$hypr_file" "$backup"
    cp hypr/phonelink.lua "$hypr_file"
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
install_menu "$MENU_FILE" omarchy/menu.jsonc || true

hyprctl reload >/dev/null || true
omarchy menu refresh >/dev/null 2>&1 || true

step "Adding the Phone icon to the bar"
updating=false
[[ -d $PLUGIN_DIR ]] && updating=true
mkdir -p "$PLUGIN_DIR"
cp -r shell/phonelink.panel/. "$PLUGIN_DIR/"
# Marks a bar icon that couldn't be added, so the next run tries again.
# Otherwise a missing icon is one the user took off, and stays off.
pending="$STATE_DIR/bar-icon-pending"
$updating || touch "$pending"
if command -v omarchy-shell &>/dev/null; then
  if $updating; then
    # Hot reload can miss changes to a running widget; a restart can't.
    omarchy restart shell >/dev/null 2>&1 || true
  else
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
fi
if [[ -f $pending ]]; then
  if enable_bar_icon; then
    rm -f "$pending"
  else
    note "Couldn't add the phone icon to the bar. Add it with: omarchy plugin enable phonelink.panel"
  fi
fi

errors=$(config_errors)
if [[ -n $errors && $errors != "$errors_before" ]]; then
  if $first_install; then
    # Leave Hyprland as it was rather than with a line that breaks it.
    sed -i --follow-symlinks -E \
      -e '/^-- Android phone windows \(phonelink\)\.$/d' \
      -e "/^\s*$REQUIRE_RE\s*\)?\s*;?\s*$/d" "$HYPR_DIR/hyprland.lua"
    hyprctl reload >/dev/null || true
    echo "Hyprland reported config errors, so phonelink was taken out of hyprland.lua again:" >&2
  else
    echo "Hyprland reported config errors:" >&2
  fi
  echo "$errors" >&2
  exit 1
fi

if $first_install; then
  cat <<'EOF'

Installed. On the phone, once:
  1. About phone › Software information › tap Build number 7 times
  2. Developer options › Wireless debugging: on
  3. Omarchy menu › Phone › Connection › Pair, and scan the code

Then click the phone icon in the bar.
EOF
else
  echo
  echo "Updated."
fi
