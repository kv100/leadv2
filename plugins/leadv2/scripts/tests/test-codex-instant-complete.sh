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
# Output is now two lines (path, window-candidate-count — nit 2-A); take
# line 1 for the path assertion.
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
c4_scan="$(CODEX_HOME="$c4_home" bash "$harness_script" _codex_newest_rollout_since "$since_epoch" "" 2>/dev/null)"
found="$(printf '%s\n' "$c4_scan" | sed -n '1p')"
c4_count="$(printf '%s\n' "$c4_scan" | sed -n '2p')"
if [ "$found" = "$c4_new" ] && [ "$c4_count" = "1" ]; then
  echo "[CODEX-INSTANT-COMPLETE]   picked c4_new, ignored c4_old (mtime < since), count=1 ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected path=$c4_new count=1, got path='$found' count='$c4_count'" >&2
  fail=$((fail + 1))
fi

# Case 4b (nit 2-A): two candidates in the same window (a sibling dispatch's
# rollout) — the cwd-matched one must be preferred, and the total window
# count must be reported as 2 so the caller journals an ambiguity warning.
c4b_home="$(mktemp -d)"
cleanup_items+=("$c4b_home")
c4b_dir="$c4b_home/sessions/2026/08/20"
mkdir -p "$c4b_dir"
c4b_mine="$c4b_dir/rollout-mine.jsonl"
c4b_sibling="$c4b_dir/rollout-sibling.jsonl"
write_rollout "$c4b_mine" \
  '{"type":"session_meta","payload":{"cwd":"/work/mine"}}' \
  '{"type":"event_msg","payload":{"type":"task_started"}}'
write_rollout "$c4b_sibling" \
  '{"type":"session_meta","payload":{"cwd":"/work/sibling"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null,"duration_ms":900}}'
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+10, int(sys.argv[2])+10))" "$c4b_mine" "$since_epoch"
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+50, int(sys.argv[2])+50))" "$c4b_sibling" "$since_epoch"

echo "[CODEX-INSTANT-COMPLETE] case 4b: cwd match preferred over a newer sibling rollout, ambiguity count=2"
c4b_scan="$(CODEX_HOME="$c4b_home" bash "$harness_script" _codex_newest_rollout_since "$since_epoch" "/work/mine" 2>/dev/null)"
c4b_found="$(printf '%s\n' "$c4b_scan" | sed -n '1p')"
c4b_count="$(printf '%s\n' "$c4b_scan" | sed -n '2p')"
if [ "$c4b_found" = "$c4b_mine" ] && [ "$c4b_count" = "2" ]; then
  echo "[CODEX-INSTANT-COMPLETE]   picked cwd-matched rollout despite sibling being newer, count=2 ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected path=$c4b_mine count=2, got path='$c4b_found' count='$c4b_count'" >&2
  fail=$((fail + 1))
fi

# Case 4c (round-1 HIGH regression): a concurrent sibling's rollout is the
# newest in the window and shows a DEAD shape, but THIS dispatch's own
# rollout is absent/has no session_meta.cwd yet -- zero exact-cwd matches.
# Must NOT fall back to "newest of anyone": no candidate should be picked,
# so the caller can make no terminal decision from this scan.
c4c_home="$(mktemp -d)"
cleanup_items+=("$c4c_home")
c4c_dir="$c4c_home/sessions/2026/08/20"
mkdir -p "$c4c_dir"
c4c_mine="$c4c_dir/rollout-mine.jsonl"
c4c_sibling="$c4c_dir/rollout-sibling.jsonl"
write_rollout "$c4c_mine" \
  '{"type":"event_msg","payload":{"type":"task_started"}}'
write_rollout "$c4c_sibling" \
  '{"type":"session_meta","payload":{"cwd":"/work/sibling"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null,"duration_ms":900}}'
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+10, int(sys.argv[2])+10))" "$c4c_mine" "$since_epoch"
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+50, int(sys.argv[2])+50))" "$c4c_sibling" "$since_epoch"

echo "[CODEX-INSTANT-COMPLETE] case 4c: sibling is newest+dead-shaped but own cwd absent -- no candidate picked"
c4c_scan="$(CODEX_HOME="$c4c_home" bash "$harness_script" _codex_newest_rollout_since "$since_epoch" "/work/mine" 2>/dev/null)"
c4c_found="$(printf '%s\n' "$c4c_scan" | sed -n '1p')"
c4c_count="$(printf '%s\n' "$c4c_scan" | sed -n '2p')"
if [ -z "$c4c_found" ] && [ "$c4c_count" = "2" ]; then
  echo "[CODEX-INSTANT-COMPLETE]   correctly returned no candidate (not the sibling), count=2 ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected empty path count=2, got path='$c4c_found' count='$c4c_count'" >&2
  fail=$((fail + 1))
fi

echo "[CODEX-INSTANT-COMPLETE] case 4d: end-to-end deadline-check must not terminal-decide off the sibling's dead shape"
c4d_start=$(date +%s)
rc=0
CODEX_HOME="$c4c_home" LEADV2_CODEX_INSTANT_COMPLETE_SECS=2 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1 \
  DISPATCH_SELF_BIN=/bin/true \
  bash "$harness_script" _codex_instant_complete_deadline_check "testsig8" "$since_epoch" "/work/mine" \
  >/dev/null 2>&1 || rc=$?
c4d_elapsed=$(( $(date +%s) - c4d_start ))
if [ "$rc" -eq 0 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   correctly proceeded (rc=0) in ${c4d_elapsed}s, sibling's dead shape ignored ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=0 (no terminal decision), got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 5: end-to-end deadline-check declares the dead shape within the window
# and returns 7 (the caller's spill signal). Same isolated CODEX_HOME as
# case 4 — c4_new already carries the dead shape. Real DISPATCH_SELF_BIN
# (nit 2-C) so requirement (c) — the provider strike is actually recorded —
# is asserted from the real lockout file, not just the rc=7 spill.
c5_lockout_dir="$(mktemp -d)"
cleanup_items+=("$c5_lockout_dir")
echo "[CODEX-INSTANT-COMPLETE] case 5: deadline-check returns 7 on the dead shape AND records the strike"
rc=0
CODEX_HOME="$c4_home" LEADV2_CODEX_INSTANT_COMPLETE_SECS=5 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1 \
  DISPATCH_SELF_BIN="$DISPATCH" LEADV2_QUOTA_LOCKOUT_DIR="$c5_lockout_dir" \
  bash "$harness_script" _codex_instant_complete_deadline_check "testsig8" "$since_epoch" >/dev/null 2>&1 || rc=$?
c5_lockfile="$c5_lockout_dir/quota-lockout-codex.json"
if [ "$rc" -eq 7 ] && [ -f "$c5_lockfile" ] && grep -q "arm_dead_instant_complete" "$c5_lockfile"; then
  echo "[CODEX-INSTANT-COMPLETE]   deadline-check returned 7 (spill) AND wrote $c5_lockfile ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=7 + lockfile with reason, got rc=$rc lockfile_exists=$([ -f "$c5_lockfile" ] && echo yes || echo no)" >&2
  fail=$((fail + 1))
fi

# Case 6 (nit 2-B): a non-terminal event newer than spawn (job alive, no
# task_complete yet) must return 0 promptly — NOT wait out the full window.
c6_home="$(mktemp -d)"
cleanup_items+=("$c6_home")
c6_dir="$c6_home/sessions/2026/08/20"
mkdir -p "$c6_dir"
c6_alive="$c6_dir/rollout-alive.jsonl"
write_rollout "$c6_alive" '{"type":"event_msg","payload":{"type":"task_started"}}'
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+10, int(sys.argv[2])+10))" "$c6_alive" "$since_epoch"

echo "[CODEX-INSTANT-COMPLETE] case 6: non-terminal activity since spawn returns 0 early, not at the 30s window"
c6_start=$(date +%s)
rc=0
CODEX_HOME="$c6_home" LEADV2_CODEX_INSTANT_COMPLETE_SECS=30 LEADV2_ARM_EARLY_VERDICT_POLL_S=0.1 \
  DISPATCH_SELF_BIN=/bin/true \
  bash "$harness_script" _codex_instant_complete_deadline_check "testsig8" "$since_epoch" >/dev/null 2>&1 || rc=$?
c6_elapsed=$(( $(date +%s) - c6_start ))
if [ "$rc" -eq 0 ] && [ "$c6_elapsed" -lt 15 ]; then
  echo "[CODEX-INSTANT-COMPLETE]   returned 0 in ${c6_elapsed}s, well under the 30s window ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-INSTANT-COMPLETE]   FAIL: expected rc=0 in <15s, got rc=$rc elapsed=${c6_elapsed}s" >&2
  fail=$((fail + 1))
fi

echo "[CODEX-INSTANT-COMPLETE] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
