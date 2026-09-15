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
#   2. copied live stale/dead/spawning fixture -> the actual dispatch-time
#      overlap reader sees a claim before finish and none after it
#   3. mark TWO live duplicate rows finished -> rc=0, re-read shows both
#      stale=true + terminal_status, AND neither duplicate blocks its former
#      write set or lane-cap admission afterward
#   4. mark a row that does NOT exist -> non-zero (rc=4), file byte-identical
#   5. force os.replace failure -> non-zero and active.yaml byte-identical
#   6. force yaml.dump failure while staging the temp -> non-zero and
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
OVERLAP_SH="$SCRIPT_DIR/../leadv2-writes-overlap.sh"

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

# ── Test 2: copied live stale/dead/spawning row loses its material claim ───
test2() {
  local sb yaml liveness_stub before finish_rc after released
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
sessions:
  - session_id: s-20260915T030041Z-1-62617
    task_id: dispatch-2c6e1405
    phase: spawning
    stale: true
    writes: plugins/leadv2/scripts/leadv2-orphan-reaper.sh,plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence...
    dead_at: '2026-09-15T08:25:42Z'
    updated_at: '2026-09-15T08:27:14Z'
    lane_events:
    - {at: '2026-09-15T08:25:42Z', event: reconciled_dead}
YAML
  liveness_stub="$sb/alive-liveness.sh"
  cat > "$liveness_stub" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"lanes":[{"lane":"dispatch-2c6e1405","verdict":"alive:fixture"}]}'
SH
  chmod +x "$liveness_stub"

  # The overlap checker is the dispatch-time consumer that does not infer a
  # claim release merely from `stale`; it sees the copied row as a live
  # incumbent, exactly exposing the stale-only mark_finished branch.
  before="$(LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" \
    LEADV2_WRITES_OVERLAP_LIVENESS_BIN="$liveness_stub" \
    bash "$OVERLAP_SH" --task-id CANDIDATE --writes "plugins/leadv2/scripts/leadv2-orphan-reaper.sh" --project-root "$sb/proj")"

  finish_rc=0
  LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
    source "'"$REGISTRY_SH"'"
    leadv2_active_mark_finished dispatch-2c6e1405 landed "{\"evidence\":\"merged d08d4f17\"}"
  ' >/dev/null 2>&1 || finish_rc=$?

  after="$(LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" \
    LEADV2_WRITES_OVERLAP_LIVENESS_BIN="$liveness_stub" \
    bash "$OVERLAP_SH" --task-id CANDIDATE --writes "plugins/leadv2/scripts/leadv2-orphan-reaper.sh" --project-root "$sb/proj")"
  released="$(python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
rows = [r for r in doc.get("sessions") or [] if r.get("task_id") == "dispatch-2c6e1405"]
print(len(rows) == 1 and rows[0].get("stale") is True and rows[0].get("terminal_status") == "landed" and all(not rows[0].get(k) for k in ("writes", "write_set")))
' "$yaml")"
  if [[ "$before" == *'other=dispatch-2c6e1405'* && "$finish_rc" -eq 0 && -z "$after" && "$released" == "True" ]]; then
    pass "2: copied live stale/dead/spawning dispatch row loses material writes claim (overlap before=hit after=clear)"
  else
    fail "2: before=[${before}] finish_rc=$finish_rc after=[${after}] released=$released"
  fi
}
test2

# ── Test 3: finish releases every duplicate claim, rows stay readable ──────
test3() {
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
    pass "3: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)"
  else
    fail "3: before_a/b=$before_a_rc/$before_b_rc finish_rc=$finish_rc after_a/b=$after_a_rc/$after_b_rc released=$released rows=$rows_json"
  fi
}
test3

# ── Test 4: unregistered task_id -> non-zero, file byte-identical ──────────
test4() {
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
    pass "4: unregistered task_id -> rc=$rc (non-zero), active.yaml byte-identical"
  else
    fail "4: rc=$rc, cmp=$(cmp -s "$yaml" "$yaml.before"; echo $?)"
  fi
}
test4

# ── Test 5/6: staging failures never touch active.yaml ─────────────────────
test5() {
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
    real_dump = yaml.dump
    dump_calls = 0
    fail_on = int(os.environ["LV2_TEST_FORCE_DUMP"])
    def fail_dump(*args, **kwargs):
        global dump_calls
        dump_calls += 1
        if dump_calls == fail_on:
            raise OSError("forced yaml.dump failure")
        return real_dump(*args, **kwargs)
    yaml.dump = fail_dump
PY

  rc_replace=0
  # Current code does one staging dump, then replace.  The mutation control
  # restores a direct "w" fallback that reaches dump call 2 only after that
  # open has truncated active.yaml; this forces that second dump to fail.
  PYTHONPATH="$hook_dir" LV2_TEST_FORCE_REPLACE=1 LV2_TEST_FORCE_DUMP=2 LEADV2_PROJECT_ROOT="$sb/proj" LEADV2_STATE_ROOT="$sb/state" bash -c '
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
    pass "5: forced os.replace rc=$rc_replace and forced yaml.dump rc=$rc_dump leave active.yaml byte-identical"
  else
    fail "5: replace_rc=$rc_replace replace_intact=$replace_intact dump_rc=$rc_dump dump_intact=$dump_intact"
  fi
}
test5

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
