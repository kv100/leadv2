#!/usr/bin/env bash
# tests/test-status-surface-cwd.sh — SWIFTBAR-LIVE-01 cwd-independence regression.
#
# Reproduces the exact real-world failure this task fixes: SwiftBar launches
# leadv2-status-surface.10s.sh with cwd=/ and a near-empty environment (no
# PROJECT_ROOT, PATH stripped to the OS basics). Before this fix that crashed
# leadv2-state-path.sh (`mkdir -p //docs/leadv2`) and rendered nothing usable.
#
# Run: bash plugins/leadv2/scripts/tests/test-status-surface-cwd.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="${SCRIPT_DIR}/leadv2-status-surface.10s.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

_run_from() {
  # $1 = cwd to launch from
  ( cd "$1" 2>/dev/null && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/local/bin \
      bash "$BAR" 2>&1 )
}

OUT_ROOT="$(_run_from /)"
RC_ROOT=$?

if [ "$RC_ROOT" -eq 0 ]; then
  pass "exit 0 from cwd=/"
else
  fail "exit 0 from cwd=/ (got rc=$RC_ROOT)"
fi

if [ -n "$OUT_ROOT" ]; then
  pass "non-empty output from cwd=/"
else
  fail "non-empty output from cwd=/ (got empty)"
fi

# lanes section must carry at least one data row -- not '(none)', not a
# '⚠'-prefixed line standing in for a blank screen.
_lanes_data_rows="$(printf '%s\n' "$OUT_ROOT" | awk '
  /^lanes \(/ { insec=1; next }
  insec && /^---/ { exit }
  insec && $0 !~ /^  (none)/ && NF { print }
')"
if printf '%s\n' "$_lanes_data_rows" | grep -q .; then
  pass "lanes section has >=1 data row"
else
  fail "lanes section has >=1 data row (got: $(printf '%s' "$OUT_ROOT" | head -8 | tr '\n' '|'))"
fi

if printf '%s\n' "$OUT_ROOT" | grep -Eq 'unreadable|не измеряется|не прочитан|stale [0-9]'; then
  fail "no forbidden failure-glyph strings present (found one)"
else
  pass "no forbidden failure-glyph strings present"
fi

_title="$(printf '%s\n' "$OUT_ROOT" | sed -n '1p')"
case "$_title" in
  '⚠️'*) fail "title line does not start with ⚠️ (got: $_title)" ;;
  *)     pass "title line does not start with ⚠️" ;;
esac

# cwd-invariance: the SAME run from $HOME, /tmp, and / must yield the SAME
# lane rows (the whole point of this fix -- the renderer no longer derives
# anything from cwd on the production/no-STATE_DIR-override path).
_lanes_rows_of() {
  # AGE is a live-ticking column (0s -> 1s -> ...) between the three
  # sequential real invocations below, so it is blanked before comparing --
  # cwd-invariance is about which rows/identities render, not the wall-clock
  # instant each invocation happened to sample.
  printf '%s\n' "$1" | awk '
    /^lanes \(/ { insec=1; next }
    insec && /^---/ { exit }
    insec && $0 !~ /^  (none)/ && NF { print }
  ' | sed -E 's/[[:space:]]+[0-9]+[smh][[:space:]]+/ <AGE> /'
}
OUT_HOME="$(_run_from "$HOME")"
OUT_TMP="$(_run_from /tmp)"
ROWS_ROOT="$(_lanes_rows_of "$OUT_ROOT")"
ROWS_HOME="$(_lanes_rows_of "$OUT_HOME")"
ROWS_TMP="$(_lanes_rows_of "$OUT_TMP")"
if [ "$ROWS_ROOT" = "$ROWS_HOME" ] && [ "$ROWS_ROOT" = "$ROWS_TMP" ]; then
  pass "cwd-invariance: same lane rows from /, \$HOME, and /tmp"
else
  fail "cwd-invariance: lane rows differ by cwd (root vs home vs tmp)"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
