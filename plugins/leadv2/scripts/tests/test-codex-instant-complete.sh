#!/usr/bin/env bash
# test-codex-instant-complete.sh — SD-CODEX-SILENT-INSTANT-COMPLETE-01
# Extracts (does not source-and-run the whole dispatcher, which has heavy
# top-level side effects) the three pure helper functions
# _codex_newest_rollout_since / _codex_rollout_dead_shape /
# _codex_instant_complete_deadline_check from leadv2-dispatch-code.sh and
# unit-tests them against fixture rollout files.

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
DISPATCH="$TEST_DIR/../leadv2-dispatch-code.sh"

pass=0
fail=0
cleanup_items=()
cleanup() {
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

harness="$(mktemp -d)"
cleanup_items+=("$harness")
harness_script="$harness/harness.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set +e'
  sed -n '/^_codex_newest_rollout_since()/,/^}$/p' "$DISPATCH"
  sed -n '/^_codex_rollout_dead_shape()/,/^}$/p' "$DISPATCH"
  sed -n '/^_codex_instant_complete_deadline_check()/,/^}$/p' "$DISPATCH"
  echo '"$@"'
} > "$harness_script"
chmod +x "$harness_script"

check_extracted() {
  local fn="$1"
  if ! grep -q "^${fn}()" "$harness_script"; then
    echo "[CODEX-INSTANT-COMPLETE] FAIL: ${fn} not found in ${DISPATCH} (extraction broke, or fn renamed)" >&2
    fail=$((fail + 1))
    return 1
  fi
  return 0
}
check_extracted "_codex_newest_rollout_since" || true
check_extracted "_codex_rollout_dead_shape" || true
check_extracted "_codex_instant_complete_deadline_check" || true

# --- fixture CODEX_HOME with a rollout tree --------------------------------
codex_home="$(mktemp -d)"
cleanup_items+=("$codex_home")
sessions_dir="$codex_home/sessions/2026/08/20"
mkdir -p "$sessions_dir"

write_rollout() {  # <path> <event-jsonl-lines...>
  local path="$1"; shift
  printf '%s\n' "$@" > "$path"
}

# Case 1: the exact live dead shape (task_started then task_complete with
# last_agent_message null, duration_ms=946 — the probed incident record).
dead_rollout="$sessions_dir/rollout-2026-08-20T05-22-53-dead.jsonl"
write_rollout "$dead_rollout" \
  '{"timestamp":"2026-08-20T02:22:57.000Z","type":"event_msg","payload":{"type":"task_started"}}' \
  '{"timestamp":"2026-08-20T02:22:58.199Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"01a01cfa-8ccd-7101-bdd7-b1c4cec4af81","last_agent_message":null,"completed_at":1787192578,"duration_ms":946}}'

echo "[CODEX-INSTANT-COMPLETE] case 1: dead shape (task_complete + last_agent_message=null)"
rc=0
CODEX_HOME="$codex_home" bash "$harness_script" _codex_rollout_dead_shape "$dead_rollout" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   detected dead shape (rc=0) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=0, got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 2: healthy terminal completion (real message) must NOT be flagged dead.
healthy_rollout="$sessions_dir/rollout-2026-08-20T05-30-00-healthy.jsonl"
write_rollout "$healthy_rollout" \
  '{"timestamp":"2026-08-20T02:30:00.000Z","type":"event_msg","payload":{"type":"task_started"}}' \
  '{"timestamp":"2026-08-20T02:30:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"x","last_agent_message":"Done, diff applied.","completed_at":1787192700,"duration_ms":5000}}'

echo "[CODEX-INSTANT-COMPLETE] case 2: healthy terminal completion (real last_agent_message)"
rc=0
CODEX_HOME="$codex_home" bash "$harness_script" _codex_rollout_dead_shape "$healthy_rollout" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   correctly NOT flagged dead (rc=2) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=2, got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 3: still-running job (no task_complete yet) must report rc=1 (unknown,
# not dead) so the deadline loop keeps polling instead of spilling early.
running_rollout="$sessions_dir/rollout-2026-08-20T05-31-00-running.jsonl"
write_rollout "$running_rollout" \
  '{"timestamp":"2026-08-20T02:31:00.000Z","type":"event_msg","payload":{"type":"task_started"}}'

echo "[CODEX-INSTANT-COMPLETE] case 3: still-running job (no task_complete yet)"
rc=0
CODEX_HOME="$codex_home" bash "$harness_script" _codex_rollout_dead_shape "$running_rollout" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   correctly reported unknown/still-running (rc=1) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=1, got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 4: _codex_newest_rollout_since must pick the newest file at/after the
# since-epoch and ignore an older, pre-existing rollout from an unrelated run.
# Isolated CODEX_HOME with explicit, python-set mtimes (touch -t is
# ambiguous about local-vs-UTC and about "now" relative to fixture dates —
# os.utime with explicit epoch seconds is deterministic on any host/date).
c4_home="$(mktemp -d)"
cleanup_items+=("$c4_home")
c4_dir="$c4_home/sessions/2026/08/20"
mkdir -p "$c4_dir"
c4_old="$c4_dir/rollout-old.jsonl"
c4_new="$c4_dir/rollout-new.jsonl"
write_rollout "$c4_old" '{"type":"event_msg","payload":{"type":"task_started"}}'
write_rollout "$c4_new" \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null,"duration_ms":900}}'
since_epoch=1787192500
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])-1000, int(sys.argv[2])-1000))" "$c4_old" "$since_epoch"
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+50, int(sys.argv[2])+50))" "$c4_new" "$since_epoch"

echo "[CODEX-INSTANT-COMPLETE] case 4: newest-rollout-since picks the right file, ignores older-than-since"
found="$(CODEX_HOME="$c4_home" bash "$harness_script" _codex_newest_rollout_since "$since_epoch" 2>/dev/null)"
if [ "$found" = "$c4_new" ]; then
  echo "[CODEX-INSTANT-COMPLETE]   picked c4_new, ignored c4_old (mtime < since) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected $c4_new, got '$found'" >&2
  fail=$((fail + 1))
fi

# Case 5: end-to-end deadline-check declares the dead shape within the window
# and returns 7 (the caller's spill signal). Same isolated CODEX_HOME as
# case 4 — c4_new already carries the dead shape.
echo "[CODEX-INSTANT-COMPLETE] case 5: deadline-check returns 7 on the dead shape"
rc=0
CODEX_HOME="$c4_home" LEADV2_CODEX_INSTANT_COMPLETE_SECS=5 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1 \
  DISPATCH_SELF_BIN=/bin/true \
  bash "$harness_script" _codex_instant_complete_deadline_check "testsig8" "$since_epoch" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 7 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   deadline-check returned 7 (spill) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=7, got rc=$rc" >&2
  fail=$((fail + 1))
fi

echo "[CODEX-INSTANT-COMPLETE] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
