#!/usr/bin/env bash
# Tests for bin/omarchy-tray against a throwaway shell.json.

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cli="$here/../bin/omarchy-tray"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export TRAY_CONFIG="$work/shell.json"
export TRAY_ID="io.github.tomfaulkner.tray"

cat >"$TRAY_CONFIG" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }],
      "center": [{ "id": "io.github.tyrichards.omaski" }],
      "right": [{ "id": "omarchy.audio" }]
    }
  },
  "plugins": []
}
JSON

failed=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failed=$((failed + 1))
  fi
}

jq_get() { jq -r "$1" "$TRAY_CONFIG"; }

tray_items() {
  jq -r --arg tray "$TRAY_ID" '
    [.bar.layout | to_entries[] | .value[]? | select(.id == $tray)
     | (.items // [])[] | .id] | join(",")
  ' "$TRAY_CONFIG"
}

bar_ids() {
  jq -r '[.bar.layout | to_entries[] | .value[]? | .id] | join(",")' "$TRAY_CONFIG"
}

plugins_ids() {
  jq -r '[.plugins[]? | .id] | join(",")' "$TRAY_CONFIG"
}

"$cli" add io.github.tyrichards.omaski --move >/dev/null
check "add --move: tile lands in the tray" "io.github.tyrichards.omaski" "$(tray_items)"
check "add --move: plugin leaves the bar" "omarchy.menu,omarchy.audio,io.github.tomfaulkner.tray" "$(bar_ids)"
check "add --move: plugin stays enabled via plugins[]" "io.github.tyrichards.omaski" "$(plugins_ids)"

"$cli" add io.github.tyrichards.omaski --move >/dev/null
check "add is idempotent" "io.github.tyrichards.omaski" "$(tray_items)"

"$cli" add hegjon.unifi >/dev/null
check "add without --move keeps the bar entry" "omarchy.menu,omarchy.audio,io.github.tomfaulkner.tray" "$(bar_ids)"
check "add without --move appends" "io.github.tyrichards.omaski,hegjon.unifi" "$(tray_items)"
check "add without --move does not touch plugins[]" "io.github.tyrichards.omaski" "$(plugins_ids)"

"$cli" remove io.github.tyrichards.omaski >/dev/null
check "remove drops the tile" "hegjon.unifi" "$(tray_items)"
check "remove also disables a moved plugin" "" "$(plugins_ids)"

"$cli" remove hegjon.unifi >/dev/null
check "remove empties the tray" "" "$(tray_items)"

backups=$(ls "$work"/shell.json.bak.* 2>/dev/null | wc -l | tr -d ' ')
check "every write is backed up" "5" "$backups"

TRAY_ID="missing.tray" "$cli" add hegjon.unifi 2>/dev/null
check "a second tray entry is refused" "1" "$?"
check "refused add does not write" "5" "$(ls "$work"/shell.json.bak.* 2>/dev/null | wc -l | tr -d ' ')"

exit $((failed == 0 ? 0 : 1))
