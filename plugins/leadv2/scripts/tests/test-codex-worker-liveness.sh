#!/usr/bin/env bash
# test-codex-worker-liveness.sh — CODEX-ARM-WORKTREE-SCOPE-01
# Extracts (does not source-and-run the whole dispatcher) the pure helper
# functions _codex_rollout_turn_aborted / _codex_worker_liveness_deadline_check
# (plus their _codex_newest_rollout_since dependency) from
# leadv2-dispatch-code.sh and unit-tests them against a stubbed codex bin.

set -euo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

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
  sed -n '/^_codex_rollout_turn_aborted()/,/^}$/p' "$DISPATCH"
  sed -n '/^_codex_worker_liveness_deadline_check()/,/^}$/p' "$DISPATCH"
  echo '"$@"'
} > "$harness_script"
chmod +x "$harness_script"

check_extracted() {
  local fn="$1"
  if ! grep -q "^${fn}()" "$harness_script"; then
    echo "[CODEX-WORKER-LIVENESS] FAIL: ${fn} not found in ${DISPATCH} (extraction broke, or fn renamed)" >&2
    fail=$((fail + 1))
    return 1
  fi
  return 0
}
check_extracted "_codex_newest_rollout_since" || true
check_extracted "_codex_rollout_turn_aborted" || true
check_extracted "_codex_worker_liveness_deadline_check" || true

write_rollout() {  # <path> <event-jsonl-lines...>
  local path="$1"; shift
  printf '%s\n' "$@" > "$path"
}

# --- stub codex bins --------------------------------------------------------
alive_bin="$harness/codex-alive.sh"
cat > "$alive_bin" <<'SH'
#!/usr/bin/env bash
[ "$1" = "status" ] && exit 0
exit 0
SH
chmod +x "$alive_bin"

vanished_bin="$harness/codex-vanished.sh"
cat > "$vanished_bin" <<'SH'
#!/usr/bin/env bash
[ "$1" = "status" ] && { echo "No job found for $2" >&2; exit 1; }
exit 0
SH
chmod +x "$vanished_bin"

# round-1 HIGH fix: a transient/unrelated status failure (companion hiccup,
# malformed response) must NOT be treated as proof the job row is gone --
# only a positively-parsed "No job found" message may declare dead.
transient_bin="$harness/codex-transient.sh"
cat > "$transient_bin" <<'SH'
#!/usr/bin/env bash
[ "$1" = "status" ] && { echo "companion IPC error: connection reset" >&2; exit 1; }
exit 0
SH
chmod +x "$transient_bin"

lockout_dir="$(mktemp -d)"
cleanup_items+=("$lockout_dir")

# Case 1 (RED before the fix): job store has lost the row (status rc!=1) --
# must be declared dead (rc=7) and the strike must actually land, same
# evidence bar 2-C established for the sibling instant-complete check.
codex_home1="$(mktemp -d)"
cleanup_items+=("$codex_home1")
since_epoch=1787192500
echo "[CODEX-WORKER-LIVENESS] case 1: job store lost the row -> arm_dead_worker_liveness + strike recorded"
rc=0
CODEX_HOME="$codex_home1" CODEX_BIN="$vanished_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir" \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
lockfile="$lockout_dir/quota-lockout-codex.json"
if [ "$rc" -eq 7 ] && [ -f "$lockfile" ] && grep -q "arm_dead_worker_liveness" "$lockfile"; then
  echo "[CODEX-WORKER-LIVENESS]   returned 7 (spill) AND wrote $lockfile ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=7 + lockfile with reason, got rc=$rc lockfile_exists=$([ -f "$lockfile" ] && echo yes || echo no)" >&2
  fail=$((fail + 1))
fi

# Case 2: job store still has the row, no rollout at all yet -- must proceed
# (rc=0), not be misjudged dead just because there is nothing to scan.
codex_home2="$(mktemp -d)"
cleanup_items+=("$codex_home2")
lockout_dir2="$(mktemp -d)"
cleanup_items+=("$lockout_dir2")
echo "[CODEX-WORKER-LIVENESS] case 2: job store row present, no rollout yet -> proceed (rc=0)"
rc=0
CODEX_HOME="$codex_home2" CODEX_BIN="$alive_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir2" \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "[CODEX-WORKER-LIVENESS]   correctly proceeded (rc=0) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=0, got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 3: job store row present, rollout shows a turn_aborted event -- must
# be declared dead (rc=7) even though the job store itself still has a row.
codex_home3="$(mktemp -d)"
cleanup_items+=("$codex_home3")
sessions_dir3="$codex_home3/sessions/2026/08/20"
mkdir -p "$sessions_dir3"
aborted_rollout="$sessions_dir3/rollout-2026-08-20T05-40-00-aborted.jsonl"
write_rollout "$aborted_rollout" \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}'
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+10, int(sys.argv[2])+10))" "$aborted_rollout" "$since_epoch"
lockout_dir3="$(mktemp -d)"
cleanup_items+=("$lockout_dir3")
echo "[CODEX-WORKER-LIVENESS] case 3: turn_aborted event in rollout -> arm_dead_worker_liveness + strike recorded"
rc=0
CODEX_HOME="$codex_home3" CODEX_BIN="$alive_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir3" \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
lockfile3="$lockout_dir3/quota-lockout-codex.json"
if [ "$rc" -eq 7 ] && [ -f "$lockfile3" ] && grep -q "arm_dead_worker_liveness" "$lockfile3"; then
  echo "[CODEX-WORKER-LIVENESS]   returned 7 (spill) AND wrote $lockfile3 ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=7 + lockfile with reason, got rc=$rc lockfile_exists=$([ -f "$lockfile3" ] && echo yes || echo no)" >&2
  fail=$((fail + 1))
fi

# Case 4: job store row present, rollout has a HEALTHY terminal completion
# (real last_agent_message, no turn_aborted) -- must proceed (rc=0).
codex_home4="$(mktemp -d)"
cleanup_items+=("$codex_home4")
sessions_dir4="$codex_home4/sessions/2026/08/20"
mkdir -p "$sessions_dir4"
healthy_rollout4="$sessions_dir4/rollout-2026-08-20T05-45-00-healthy.jsonl"
write_rollout "$healthy_rollout4" \
  '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Done.","duration_ms":50000}}'
python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2])+10, int(sys.argv[2])+10))" "$healthy_rollout4" "$since_epoch"
echo "[CODEX-WORKER-LIVENESS] case 4: healthy terminal completion, no turn_aborted -> proceed (rc=0)"
rc=0
CODEX_HOME="$codex_home4" CODEX_BIN="$alive_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$(mktemp -d)" \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "[CODEX-WORKER-LIVENESS]   correctly proceeded (rc=0) ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=0, got rc=$rc" >&2
  fail=$((fail + 1))
fi

# Case 5: no-poll-loop guarantee -- a HEALTHY spawn must not be taxed with
# extra latency (single-shot check, not the 60s LEADV2_CODEX_WORKER_LIVENESS_SECS
# window). Reuses case-2's alive fixture; must return well under 5s.
echo "[CODEX-WORKER-LIVENESS] case 5: single-shot check does not block for the 60s window on a healthy spawn"
c5_start=$(date +%s)
rc=0
CODEX_HOME="$codex_home2" CODEX_BIN="$alive_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$(mktemp -d)" LEADV2_CODEX_WORKER_LIVENESS_SECS=60 \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
c5_elapsed=$(( $(date +%s) - c5_start ))
if [ "$rc" -eq 0 ] && [ "$c5_elapsed" -lt 5 ]; then
  echo "[CODEX-WORKER-LIVENESS]   returned 0 in ${c5_elapsed}s, no blocking poll ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=0 in <5s, got rc=$rc elapsed=${c5_elapsed}s" >&2
  fail=$((fail + 1))
fi

# Case 6 (round-1 HIGH regression): status exits nonzero with a transient,
# non-"No job found" error -- must proceed (rc=0), no strike, no spill; the
# confirmed reservation must stay untouched.
codex_home6="$(mktemp -d)"
cleanup_items+=("$codex_home6")
lockout_dir6="$(mktemp -d)"
cleanup_items+=("$lockout_dir6")
echo "[CODEX-WORKER-LIVENESS] case 6: transient status error (not 'No job found') -> proceed, no strike/spill"
rc=0
CODEX_HOME="$codex_home6" CODEX_BIN="$transient_bin" DISPATCH_SELF_BIN="$DISPATCH" \
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir6" \
  bash "$harness_script" _codex_worker_liveness_deadline_check "job-abc123" "testsig8" "$since_epoch" "" \
  >/dev/null 2>&1 || rc=$?
lockfile6="$lockout_dir6/quota-lockout-codex.json"
if [ "$rc" -eq 0 ] && [ ! -f "$lockfile6" ]; then
  echo "[CODEX-WORKER-LIVENESS]   correctly proceeded (rc=0), no strike recorded ✓"
  pass=$((pass + 1))
else
  echo "[CODEX-WORKER-LIVENESS]   FAIL: expected rc=0 + no lockfile, got rc=$rc lockfile_exists=$([ -f "$lockfile6" ] && echo yes || echo no)" >&2
  fail=$((fail + 1))
fi

echo "[CODEX-WORKER-LIVENESS] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
