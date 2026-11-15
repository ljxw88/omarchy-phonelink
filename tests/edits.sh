#!/bin/bash

# Checks the edits install.sh and uninstall.sh make to Omarchy's menu file
# and to ~/.config/hypr, on throwaway copies. Needs bash, GNU sed and jq.

set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

check() {
  local what=$1
  shift
  if "$@"; then
    echo "ok    $what"
  else
    echo "FAIL  $what"
    failures=$((failures + 1))
  fi
}

# The menu's ids as Omarchy reads them (MenuModel.js), sorted on one line,
# or "unreadable".
ids() {
  sed -E '/^\s*\/\//d' "$1" | sed -zE 's/,(\s*[]}])/\1/g' | jq -rse '
    if length == 1 and (.[0] | type) == "object" then
      .[0] | if (.items | type) == "object" then .items else . end | keys | join(" ")
    else error end' 2>/dev/null || echo unreadable
}

PHONE_IDS=$(sed -nE 's/^\s*"([^"]+)":.*/\1/p' omarchy/menu.jsonc | sort | tr '\n' ' ')
PHONE_IDS=${PHONE_IDS% }

# Expected ids: the given ones plus the Phone menu's, sorted like ids().
with_phone() {
  printf '%s\n' "$@" $PHONE_IDS | sort | tr '\n' ' ' | sed 's/ $//'
}

install_menu_into() {
  (source ./install.sh && install_menu "$1" omarchy/menu.jsonc) >"$tmp/out" 2>&1
}

uninstall_menu_from() {
  (source ./uninstall.sh; HYPR_FILE=/nonexistent MENU_FILE=$1 remove_config_lines) >"$tmp/out" 2>&1
}

fixture() {
  cat >"$tmp/$1.jsonc"
  printf '%s' "$tmp/$1.jsonc"
}

same() {
  [[ $1 == "$2" ]] || {
    echo "      got:  $1"
    echo "      want: $2"
    return 1
  }
}

# ------------------------------------------------------------ install

f="$tmp/new/omarchy-menu.jsonc"
install_menu_into "$f"
check "a new menu file gets the Phone menu" same "$(ids "$f")" "$(with_phone)"
cp "$f" "$tmp/once"
install_menu_into "$f"
check "installing twice changes nothing" cmp -s "$f" "$tmp/once"

f=$(fixture spaces-after-comma <<<$'{\n  "a": {"label": "A"},   \n}')
install_menu_into "$f"
check "spaces after a comma don't add a second one" same "$(ids "$f")" "$(with_phone a)"

f=$(fixture spaces-no-comma <<<$'{\n  "a": {"label": "A"}  \t\n}')
install_menu_into "$f"
check "spaces after an entry without a comma" same "$(ids "$f")" "$(with_phone a)"

f=$(fixture spaces-after-brace <<<$'{   \n}')
install_menu_into "$f"
check "spaces after the opening brace" same "$(ids "$f")" "$(with_phone)"

f=$(fixture comment-last <<<$'{\n  "a": {"label": "A"}\n  // mine\n}')
install_menu_into "$f"
check "a comment between the last entry and the brace" same "$(ids "$f")" "$(with_phone a)"

f=$(fixture comments-only <<<$'// my menu, empty for now')
install_menu_into "$f"
check "a file of only comments" same "$(ids "$f")" "$(with_phone)"

f=$(fixture items <<<$'{\n  "items": {\n    "a": {"label": "A"}\n  }\n}')
install_menu_into "$f"
check "entries kept in \"items\" get the Phone menu there" same "$(ids "$f")" "$(with_phone a)"
check "  and not at the top" same "$(sed -E '/^\s*\/\//d' "$f" | sed -zE 's/,(\s*[]}])/\1/g' | jq -r 'keys | join(" ")')" "items"

f=$(fixture items-then-more <<<$'{\n  "items": {\n    "a": {"label": "A"}\n  },\n  "other": true\n}')
install_menu_into "$f"
check "\"items\" followed by other keys" same "$(ids "$f")" "$(with_phone a)"

f=$(fixture update <<<$'{\n  "a": {},\n  // >>> phonelink >>> old\n  "phone": {"label": "Old"},\n  // <<< phonelink <<<\n  "b": {}\n}')
install_menu_into "$f"
check "an update replaces the old block and keeps what follows" same "$(ids "$f")" "$(with_phone a b)"
check "  with one block" same "$(grep -c '>>> phonelink >>>' "$f")" 1
check "  and the new labels" same "$(grep -c '"Old"' "$f")" 0

f=$(fixture legacy <<<$'{\n  "a": {},\n  // Android phone (phonelink, built on scrcpy).\n  "phone": {"label": "Old"},\n  "phone.apps": {"label": "Old"},\n  "b": {}\n}')
install_menu_into "$f"
check "the first release's unmarked entries are replaced" same "$(ids "$f")" "$(with_phone a b)"
check "  with the new labels" same "$(grep -c '"Old"' "$f")" 0

block=$(sed 's/^/  /' omarchy/menu.jsonc)
f=$(fixture double-comma <<<$'{\n  "a": {},  ,\n\n'"$block"$'\n}')
check "(a menu with \",  ,\" is unreadable)" same "$(ids "$f")" unreadable
install_menu_into "$f"
check "an install repairs \",  ,\" left by older installers" same "$(ids "$f")" "$(with_phone a)"

f=$(fixture no-end-marker <<<$'{\n  // >>> phonelink >>> old\n  "phone": {},\n  "b": {}\n}')
cp "$f" "$tmp/before"
install_menu_into "$f"
check "a block without its end marker is left alone" cmp -s "$f" "$tmp/before"
check "  and the user is told" grep -q 'missing its' "$tmp/out"

f=$(fixture unreadable <<<$'{\n  "a": {}\n  "b": {}\n}')
cp "$f" "$tmp/before"
install_menu_into "$f"
check "a file Omarchy can't read is left alone" cmp -s "$f" "$tmp/before"
check "  and the user is told" grep -q "can't read" "$tmp/out"

f=$(fixture one-line <<<'{"a": {}}')
cp "$f" "$tmp/before"
install_menu_into "$f"
check "a one-line file is left alone" cmp -s "$f" "$tmp/before"
check "  and the user is told" grep -q 'by hand' "$tmp/out"

mkdir -p "$tmp/dotfiles"
printf '{\n  "a": {}\n}\n' >"$tmp/dotfiles/menu.jsonc"
ln -s "$tmp/dotfiles/menu.jsonc" "$tmp/linked.jsonc"
install_menu_into "$tmp/linked.jsonc"
check "a symlinked menu file stays a symlink" test -L "$tmp/linked.jsonc"
check "  and its target gets the Phone menu" same "$(ids "$tmp/dotfiles/menu.jsonc")" "$(with_phone a)"

# ------------------------------------------------------------ uninstall

uninstall_menu_from "$tmp/linked.jsonc"
check "uninstall keeps a symlinked menu file a symlink" test -L "$tmp/linked.jsonc"
check "  and takes the Phone menu out of its target" same "$(ids "$tmp/dotfiles/menu.jsonc")" a

f="$tmp/items.jsonc"
uninstall_menu_from "$f"
check "uninstall takes the Phone menu out of \"items\"" same "$(ids "$f")" a

f=$(fixture no-end-marker <<<$'{\n  // >>> phonelink >>> old\n  "phone": {},\n  "b": {}\n}')
cp "$f" "$tmp/before"
uninstall_menu_from "$f"
check "uninstall leaves a block without its end marker alone" cmp -s "$f" "$tmp/before"

f=$(fixture no-start-marker <<<$'{\n  "a": {},\n  // <<< phonelink <<<\n  "b": {}\n}')
cp "$f" "$tmp/before"
uninstall_menu_from "$f"
check "uninstall leaves an end marker without its start alone" cmp -s "$f" "$tmp/before"

mkdir -p "$tmp/hypr" "$tmp/state/phonelink"
cat >"$tmp/dotfiles/hyprland.lua" <<'EOF'
require("hypr.bindings")

-- Android phone windows (phonelink).
require("hypr.phonelink")
require "hypr.phonelink"
  require('hypr.phonelink');
EOF
ln -s "$tmp/dotfiles/hyprland.lua" "$tmp/hypr/hyprland.lua"
(source ./uninstall.sh; HYPR_FILE="$tmp/hypr/hyprland.lua" MENU_FILE=/nonexistent remove_config_lines) >"$tmp/out" 2>&1
check "uninstall takes every require of phonelink out of hyprland.lua" same "$(grep -c phonelink "$tmp/dotfiles/hyprland.lua")" 0
check "  and keeps the rest" grep -qx 'require("hypr.bindings")' "$tmp/dotfiles/hyprland.lua"
check "  and keeps hyprland.lua a symlink" test -L "$tmp/hypr/hyprland.lua"

printf 'require("hypr.phonelink") -- phone\n' >"$tmp/hypr/other.lua"
(source ./uninstall.sh; HYPR_FILE="$tmp/hypr/other.lua" MENU_FILE=/nonexistent remove_config_lines) >"$tmp/out" 2>&1
check "uninstall says when a line it can't take out still loads phonelink" grep -q 'still loads' "$tmp/out"

remove_hypr() {
  (source ./uninstall.sh; HYPR_DIR="$tmp/hypr" STATE_DIR="$tmp/state/phonelink" remove_hypr_file) >"$tmp/out" 2>&1
}

printf -- '-- old\n' >"$tmp/hypr/phonelink.lua.bak.123"
printf -- '-- new\n' >"$tmp/hypr/phonelink.lua.new"
printf -- '-- installed\n' >"$tmp/hypr/phonelink.lua"
sha256sum <"$tmp/hypr/phonelink.lua" | cut -d' ' -f1 >"$tmp/state/phonelink/hypr-phonelink.lua.sha256"
remove_hypr
check "uninstall removes an unedited phonelink.lua" test ! -e "$tmp/hypr/phonelink.lua"
check "  and the installer's copies" test -z "$(find "$tmp/hypr" -name 'phonelink*')"

printf -- '-- edited\n' >"$tmp/hypr/phonelink.lua"
remove_hypr
check "uninstall keeps an edited phonelink.lua aside" grep -qx -- '-- edited' "$tmp/hypr/phonelink.lua.edited"
check "  and says so" grep -q 'edited' "$tmp/out"

# ------------------------------------------------------------ install.sh's view of hyprland.lua

loads() {
  (source ./install.sh && grep -qE "$REQUIRE_RE" <<<"$1")
}
check "install sees phonelink loaded as it writes it" loads 'require("hypr.phonelink")'
check "  or written another way" loads "require 'hypr.phonelink'"
check "  or commented out, and doesn't add it back" loads '-- require("hypr.phonelink")'
check "  but not other modules" bash -c "! (source ./install.sh && grep -qE \"\$REQUIRE_RE\" <<<'require(\"hypr.bindings\")')"

echo
if ((failures)); then
  echo "$failures failed"
  exit 1
fi
echo "All passed"
