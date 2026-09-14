#!/usr/bin/env bash
# tests/test-mark-finished-releases-writeset.sh — PLUGIN-MARK-FINISHED-DOES-NOT-RELEASE-THE-ROW-01
# run-all-triggers: leadv2-active-registry.sh
#
# PROBLEM: leadv2_active_mark_finished used to stamp terminal_status and
# return rc=0 WITHOUT releasing the row's writeset/lane-cap claim -- a merged
# lane's row survived forever, so the next lane needing the same files was
# refused writeset_conflict against a lane that no longer existed.
#
# FIX (see leadv2-active-registry.sh's mark_finished op): the row is kept
# (terminal_status/terminal_evidence stay readable for
# leadv2-lane-heartbeat.sh's `status`, per PULSE-01), but is now stamped
# `stale: true` -- the SAME convention register/check_writes/check_limits
# already use to exclude a row from new admission and the lane cap. rc=0 is
# verified by re-reading active.yaml after the write, not just "the function
# ran".
#
# Tests:
#   1. bash -n syntax check
#   2. mark an EXISTING row finished -> rc=0, re-read shows stale=true +
#      terminal_status, AND a conflicting writeset check that was refused
#      BEFORE finish is admitted AFTER finish (the behavioural proof the bug
#      report asked for)
#   3. mark a row that does NOT exist -> non-zero (rc=4), file byte-identical
#   4. simulate a failed write (state dir made read-only, so mkstemp/rename
#      cannot land -- chmod on the FILE alone does not block rename(2) on
#      this filesystem, verified empirically) -> non-zero, file unchanged
#      and still valid YAML (never truncated/half-written)
#
# Portable: sandboxed via LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT env
# overrides, no git repo needed.
# Run: bash plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../leadv2-temp.sh"
REGISTRY_SH="$SCRIPT_DIR/../leadv2-active-registry.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

new_sandbox() {
  local d
  d="$(lv2_mktemp_dir "mark-finished-test")"
  mkdir -p "$d/proj" "$d/state"
  printf '%s' "$d"
}

# ── Test 1: syntax ───────────────────────────────────────────────────────────
if bash -n "$REGISTRY_SH"; then
  pass "1: bash -n leadv2-active-registry.sh"
else
  fail "1: bash -n leadv2-active-registry.sh"
fi

# ── Test 2: finish releases the writeset claim, row stays readable ─────────
test2() {
  local sb yaml before_conflict_rc finish_rc after_conflict_rc
  sb="$(new_sandbox)"
  yaml="$(
    LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
      source "'"$REGISTRY_SH"'"
      _leadv2_yaml_file
    '
  )"

  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register T1 Standard "$LEADV2_PROJECT_ROOT" branch false "" "" "src/a.txt" >/dev/null
  '

  before_conflict_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/a.txt"
  ' >/dev/null 2>&1 || before_conflict_rc=$?

  finish_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished T1 completed "{\"has_diff\":true}"
  ' >/dev/null 2>&1 || finish_rc=$?

  after_conflict_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/a.txt"
  ' >/dev/null 2>&1 || after_conflict_rc=$?

  local row_json
  row_json="$(python3 -c '
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1])) or {}
row = next((s for s in d.get("sessions") or [] if s.get("task_id") == "T1"), None)
print(json.dumps(row))
' "$yaml")"
  local stale term
  stale="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('stale'))" <<<"$row_json")"
  term="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('terminal_status'))" <<<"$row_json")"

  if [[ "$before_conflict_rc" -eq 5 && "$finish_rc" -eq 0 && "$after_conflict_rc" -eq 0 \
        && "$stale" == "True" && "$term" == "completed" ]]; then
    pass "2: finish rc=0, stale=True, terminal_status=completed, writeset conflict released (before=5 after=0)"
  else
    fail "2: before_conflict_rc=$before_conflict_rc finish_rc=$finish_rc after_conflict_rc=$after_conflict_rc stale=$stale term=$term row=$row_json"
  fi
}
test2

# ── Test 3: unregistered task_id -> non-zero, file byte-identical ──────────
test3() {
  local sb yaml rc
  sb="$(new_sandbox)"
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register T1 Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null
  '
  yaml="$(
    LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
      source "'"$REGISTRY_SH"'"
      _leadv2_yaml_file
    '
  )"
  cp "$yaml" "$yaml.before"

  rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished NOPE completed "{}"
  ' >/dev/null 2>&1 || rc=$?

  if [[ "$rc" -ne 0 ]] && cmp -s "$yaml" "$yaml.before"; then
    pass "3: unregistered task_id -> rc=$rc (non-zero), active.yaml byte-identical"
  else
    fail "3: rc=$rc, cmp=$(cmp -s "$yaml" "$yaml.before"; echo $?)"
  fi
}
test3

# ── Test 4: failed write (read-only state dir) -> non-zero, file intact ────
test4() {
  local sb yaml state_dir rc
  sb="$(new_sandbox)"
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_register T1 Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null
  '
  yaml="$(
    LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
      source "'"$REGISTRY_SH"'"
      _leadv2_yaml_file
    '
  )"
  cp "$yaml" "$yaml.before"
  state_dir="$(dirname "$yaml")"
  chmod 555 "$state_dir"

  rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished T1 completed "{}"
  ' >/dev/null 2>&1 || rc=$?

  chmod 755 "$state_dir"

  local still_valid=0
  python3 -c "import yaml; yaml.safe_load(open('$yaml'))" 2>/dev/null && still_valid=1

  if [[ "$rc" -ne 0 ]] && cmp -s "$yaml" "$yaml.before" && [[ "$still_valid" -eq 1 ]]; then
    pass "4: read-only state dir -> rc=$rc (non-zero), active.yaml unchanged and still valid YAML"
  else
    fail "4: rc=$rc, cmp=$(cmp -s "$yaml" "$yaml.before"; echo $?), still_valid=$still_valid"
  fi
}
test4

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
