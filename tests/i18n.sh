#!/bin/bash

# Checks that every key the bar panel looks up with strings.t("…") or
# catalog.t("…") is in i18n/en.json, and that en.json has no unused keys.

set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/../shell/phonelink.panel" || exit 1

used=$(grep -ohE '\b(strings|catalog)\.t\("[^"]+"' ./*.qml | sed -E 's/.*\("//; s/"$//' | sort -u)
defined=$(jq -r 'keys[]' i18n/en.json | sort)
failed=false

missing=$(comm -23 <(echo "$used") <(echo "$defined"))
if [[ -n $missing ]]; then
  echo "Used in the QML but not in i18n/en.json:"
  echo "$missing" | sed 's/^/  /'
  failed=true
fi

unused=$(comm -13 <(echo "$used") <(echo "$defined"))
if [[ -n $unused ]]; then
  echo "In i18n/en.json but not used:"
  echo "$unused" | sed 's/^/  /'
  failed=true
fi

# A key that isn't a plain string can't be checked.
dynamic=$(grep -nE '\b(strings|catalog)\.t\([^"]' ./*.qml)
if [[ -n $dynamic ]]; then
  echo "Translated with a key that isn't a plain string:"
  echo "$dynamic" | sed 's/^/  /'
  failed=true
fi

if $failed; then
  exit 1
fi
echo "$(wc -l <<<"$used") translation keys, all in en.json and all used"
