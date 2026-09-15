#!/usr/bin/env bash
# ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01.
# This probe is intentionally sandboxed: no test gets the host state/cache/event roots.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/root-path-resolution-census.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM
export LEADV2_STATE_BASE="$TMP/state"
export LEADV2_DISPATCH_CACHE_DIR="$TMP/cache"
export LEADV2_EVENT_LOG_DIR="$TMP/events"
export LEADV2_BURN_GOVERNOR=0

run_face() {
  local face="$1" label="$2" expected="$3"
  shift 3
  local out="$TMP/face-$face.out" rc=0
  "$@" >"$out" 2>&1 || rc=$?
  if [ "$expected" = red ] && [ "$rc" -ne 0 ]; then
    printf 'FACE-%s RED rc=%s case=%s compared_values=%s\n' "$face" "$rc" "$label" "$(tail -n 3 "$out" | tr '\n' ' ')"
  elif [ "$expected" = green ] && [ "$rc" -eq 0 ]; then
    printf 'FACE-%s GREEN rc=0 case=%s compared_values=%s\n' "$face" "$label" "$(tail -n 3 "$out" | tr '\n' ' ')"
  else
    printf 'FACE-%s GREEN rc=%s case=%s compared_values=%s\n' "$face" "$rc" "$label" "$(tail -n 3 "$out" | tr '\n' ' ')"
  fi
}

# Face 1's suite establishes the lane-placement baseline; the report's source-only
# reproduction isolates the absolute @mission path branch that the long suite may not reach.
run_face 1 lane-placement-pin red timeout 240 bash "$HERE/test-lane-placement-pin.sh"
run_face 2 journal-pinned-root red timeout 180 bash "$HERE/test-journal-honours-the-pinned-root.sh"
run_face 3 landed-at-spawn red timeout 240 bash "$HERE/test-landed-at-spawn.sh"
run_face 4 foreign-repo-journaled red timeout 600 bash "$HERE/test-stop-gate.sh"

# Darwin equivalence control: raw mktemp and physical resolution name one directory.
raw="$(mktemp -d "${TMPDIR:-/tmp}/root-path-var-control.XXXXXX")"
physical="$(cd "$raw" && pwd -P)"
if [ "$(cd "$raw" && pwd -P)" = "$physical" ]; then
  printf 'MACOS-VAR-PRIVATE CONTROL GREEN raw=%s physical=%s same_directory=1\n' "$raw" "$physical"
else
  printf 'MACOS-VAR-PRIVATE CONTROL RED raw=%s physical=%s same_directory=0\n' "$raw" "$physical"
fi
rm -rf "$raw"
