#!/bin/bash

# Runs every check CI runs. Needs shellcheck, jq and lua (luac).
# SHELLCHECK=/path/to/shellcheck picks another ShellCheck.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

failed=0
check() {
  local name=$1
  shift
  if "$@"; then
    printf '\e[32m✓\e[0m %s\n' "$name"
  else
    printf '\e[31m✗\e[0m %s\n' "$name"
    failed=1
  fi
}

scripts=(bin/phonelink install.sh uninstall.sh tests/*.sh)

bash_syntax() {
  local f
  for f in "${scripts[@]}"; do bash -n "$f" || return 1; done
}

lua_syntax() {
  local luac
  luac=$(command -v luac luac5.4 | head -1)
  [[ -n $luac ]] || { echo "luac not found (install lua)"; return 1; }
  "$luac" -p hypr/phonelink.lua
}

# Omarchy drops whole-line // comments and trailing commas, then parses the
# menu file as JSON (MenuModel.js). The entries go inside its braces.
menu_entries() {
  { echo '{'; cat omarchy/menu.jsonc; echo '}'; } |
    sed -E '/^\s*\/\//d' | sed -zE 's/,(\s*[]}])/\1/g' | jq -e 'has("phone")' >/dev/null
}

check "ShellCheck" "${SHELLCHECK:-shellcheck}" -S warning "${scripts[@]}"
check "Bash syntax" bash_syntax
check "Plugin JSON" jq empty shell/phonelink.panel/manifest.json shell/phonelink.panel/i18n/*.json
check "Lua syntax" lua_syntax
check "Menu entries" menu_entries
check "Translations" tests/i18n.sh
check "Installer edits" tests/edits.sh

exit "$failed"
