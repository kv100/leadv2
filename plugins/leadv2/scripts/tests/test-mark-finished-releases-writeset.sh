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
#   2. mark TWO live duplicate rows finished -> rc=0, re-read shows both
#      stale=true + terminal_status, AND neither duplicate blocks its former
#      write set or lane-cap admission afterward
#   3. mark a row that does NOT exist -> non-zero (rc=4), file byte-identical
#   4. force os.replace failure -> non-zero and active.yaml byte-identical
#   5. force yaml.dump failure while staging the temp -> non-zero and
#      active.yaml byte-identical.  The production implementation has no
#      direct-write fallback, so neither failure can touch the live file.
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

# ── Test 2: finish releases every duplicate claim, rows stay readable ──────
test2() {
  local sb yaml before_a_rc before_b_rc finish_rc after_a_rc after_b_rc
  sb="$(new_sandbox)"
  yaml="$(
    LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
      source "'"$REGISTRY_SH"'"
      _leadv2_yaml_file
    '
  )"

  mkdir -p "$(dirname "$yaml")"
  cat > "$yaml" <<'YAML'
meta:
  schema_version: 2
  hard_limit: 2
  standard_max: 2
sessions:
  - task_id: T1
    class: Standard
    worktree: /fixture/one
    writes: src/a.txt
    stale: false
  - task_id: T1
    class: Standard
    worktree: /fixture/two
    writes: src/b.txt
    stale: false
YAML

  before_a_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/a.txt"
  ' >/dev/null 2>&1 || before_a_rc=$?

  before_b_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/b.txt"
  ' >/dev/null 2>&1 || before_b_rc=$?

  finish_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished T1 completed "{\"has_diff\":true}"
  ' >/dev/null 2>&1 || finish_rc=$?

  after_a_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/a.txt"
  ' >/dev/null 2>&1 || after_a_rc=$?

  after_b_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_check_writes_conflict T2 "src/b.txt"
  ' >/dev/null 2>&1 || after_b_rc=$?

  local rows_json
  rows_json="$(python3 -c '
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1])) or {}
rows = [s for s in d.get("sessions") or [] if s.get("task_id") == "T1"]
print(json.dumps(rows))
' "$yaml")"
  local released
  released="$(python3 -c 'import json,sys; rows=json.load(sys.stdin); print(len(rows) == 2 and all(r.get("stale") is True and r.get("terminal_status") == "completed" for r in rows))' <<<"$rows_json")"

  if [[ "$before_a_rc" -eq 5 && "$before_b_rc" -eq 5 && "$finish_rc" -eq 0 \
        && "$after_a_rc" -eq 0 && "$after_b_rc" -eq 0 && "$released" == "True" ]]; then
    pass "2: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)"
  else
    fail "2: before_a/b=$before_a_rc/$before_b_rc finish_rc=$finish_rc after_a/b=$after_a_rc/$after_b_rc released=$released rows=$rows_json"
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

# ── Test 4/5: staging failures never touch active.yaml ─────────────────────
test4() {
  local sb yaml hook_dir rc_replace rc_dump
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
  hook_dir="$sb/hooks"
  mkdir -p "$hook_dir"
  cat > "$hook_dir/sitecustomize.py" <<'PY'
import os
if os.environ.get("LV2_TEST_FORCE_REPLACE"):
    def fail_replace(*_args, **_kwargs):
        raise OSError("forced os.replace failure")
    os.replace = fail_replace
if os.environ.get("LV2_TEST_FORCE_DUMP"):
    import yaml
    def fail_dump(*_args, **_kwargs):
        raise OSError("forced yaml.dump failure")
    yaml.dump = fail_dump
PY

  rc_replace=0
  PYTHONPATH="$hook_dir" LV2_TEST_FORCE_REPLACE=1 LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished T1 completed "{}"
  ' >/dev/null 2>&1 || rc_replace=$?

  local replace_intact=0 dump_intact=0
  cmp -s "$yaml" "$yaml.before" && replace_intact=1

  rc_dump=0
  PYTHONPATH="$hook_dir" LV2_TEST_FORCE_DUMP=1 LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished T1 completed "{}"
  ' >/dev/null 2>&1 || rc_dump=$?
  cmp -s "$yaml" "$yaml.before" && dump_intact=1

  if [[ "$rc_replace" -ne 0 && "$replace_intact" -eq 1 && "$rc_dump" -ne 0 && "$dump_intact" -eq 1 ]]; then
    pass "4: forced os.replace rc=$rc_replace and forced yaml.dump rc=$rc_dump leave active.yaml byte-identical"
  else
    fail "4: replace_rc=$rc_replace replace_intact=$replace_intact dump_rc=$rc_dump dump_intact=$dump_intact"
  fi
}
test4

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
