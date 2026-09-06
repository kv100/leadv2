#!/usr/bin/env bash
# tests/test-lane-pulse-watch-orphan-maxs.sh — SET-U-ABORTS-THE-FAILURE-PATH-01
# run-all-triggers: leadv2-lane-pulse-watch
#
# leadv2-lane-pulse-watch.sh's orphan-cleanup path (line ~449) referenced
# `$ORPHAN_MAXs` -- read by bash as the variable literally named
# `ORPHAN_MAXs` (no brace to separate `$ORPHAN_MAX` from the trailing "s"),
# which the script never assigns. Under `set -uo pipefail` (this file's own
# header), a watcher detecting its own orphan condition aborted with
# "unbound variable" instead of exiting 0 cleanly. Found via ShellCheck
# SC2154 during the SET-U-ABORTS-THE-FAILURE-PATH-01 triage, confirmed real
# (not a false positive) by isolated repro, 2026-09-06.
#
# This tests the exact failing expression directly rather than the full
# watcher (which needs a live registry/journal/SIG environment) -- the
# defect is a single string-interpolation typo, and the narrow claim
# ("does referencing this exact construct abort under set -u") is what
# needs proving, not the whole watcher's orphan-detection logic (already
# covered elsewhere).
set -uo pipefail
SCRIPT="/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '[TEST] FAIL: %s -- %s\n' "$1" "${2:-}"; }

echo "=== T1: current file (fixed) -- the orphan-pulse line no longer references an unset var ==="
if grep -qF '"row_frozen>${ORPHAN_MAX}s"' "$SCRIPT"; then
  pass "T1a: source uses the braced form \${ORPHAN_MAX}s"
else
  fail "T1a: source uses the braced form \${ORPHAN_MAX}s" "not found in $SCRIPT"
fi
out="$(bash -c 'set -uo pipefail; ORPHAN_MAX=1800; printf "%s\n" "row_frozen>${ORPHAN_MAX}s"' 2>&1)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == "row_frozen>1800s" ]]; then
  pass "T1b: the fixed expression evaluates cleanly under set -u (rc=0, out='$out')"
else
  fail "T1b: the fixed expression evaluates cleanly under set -u" "rc=$rc out='$out'"
fi

echo "=== T2 (negative control): the exact pre-fix construct aborts under set -u ==="
out="$(bash -c 'set -uo pipefail; ORPHAN_MAX=1800; printf "%s\n" "row_frozen>$ORPHAN_MAXs"' 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "unbound variable" <<<"$out"; then
  pass "T2: the pre-fix construct aborts with 'unbound variable' (rc=$rc) -- suite discriminates"
else
  fail "T2: the pre-fix construct aborts with 'unbound variable'" "rc=$rc out='$out'"
fi

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
