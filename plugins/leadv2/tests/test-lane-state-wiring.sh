#!/usr/bin/env bash
# T8b integration coverage: the three lane-state consumer wiring points that
# tests/test-lane-state.sh (module-level unit tests) does not exercise --
# dispatch admission's cap-refusal exit code, session-runner's EXIT-trap
# deregister, and the sweeper's reconcile call marking a kill-9 lane dead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIB="${ROOT}/plugins/leadv2/scripts/lib/leadv2-lane-state.sh"
DISPATCH_SH="${ROOT}/plugins/leadv2/scripts/leadv2-dispatch-code.sh"
RUNNER_SH="${ROOT}/plugins/leadv2/scripts/leadv2-session-runner.sh"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/lv2-lane-wiring.XXXXXX")"
ALL_PIDS=()
cleanup() { local p; for p in "${ALL_PIDS[@]:-}"; do [[ -n "$p" ]] && kill -9 "$p" 2>/dev/null || true; done; rm -rf "$FIX"; }
trap cleanup EXIT
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

git -C "$FIX" init -q
git -C "$FIX" config user.email test@example.invalid
git -C "$FIX" config user.name test
touch "$FIX/.keep"; git -C "$FIX" add .keep; git -C "$FIX" commit -qm init
mkdir -p "$FIX/docs/leadv2" "$FIX/.claude/worktrees"
printf 'sessions: []\n' > "$FIX/docs/leadv2/active.yaml"
export LEADV2_PROJECT_ROOT="$FIX" LEADV2_STATE_ROOT="$FIX/docs/leadv2"
export LEADV2_LANE_STATE_TEST_BIRTH_FILE="$FIX/births.tsv"
birth() { printf '%s\t%s\n' "$1" "$2" >> "$LEADV2_LANE_STATE_TEST_BIRTH_FILE"; }
source "$LIB"

# ── (a) cap-refusal exits 3 through dispatch-code.sh's ACTUAL admission
# snippet (extracted verbatim from the real file, not reimplemented, so a
# future edit to that block is caught here instead of silently drifting) ──
_snippet="$(grep -A 12 'The lane-state module is the cap authority' "$DISPATCH_SH")"
[[ -n "$_snippet" ]] || fail 'admission snippet not found in leadv2-dispatch-code.sh -- has it moved?'
ADMIT_SH="$FIX/admit.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' "source \"$LIB\""
  printf '%s\n' 'emit() { :; }'  # dispatch-code.sh's journal writer -- a no-op stub is fine here.
  printf '%s\n' '_run_admission() {'
  printf '%s\n' '  local reg_id="$1" sig8="$2"'
  printf '%s\n' "  $_snippet"
  printf '%s\n' '}'
  printf '%s\n' '_run_admission "$1" "$2"'
} > "$ADMIT_SH"

sleep 60 & P1=$!; ALL_PIDS+=("$P1")
birth "$P1" 'Mon Jan  1 00:00:00 2024'
lane_register cap-a cap-lead "$FIX/.claude/worktrees/cap-a" build "$P1"
sleep 60 & P2=$!; ALL_PIDS+=("$P2")
birth "$P2" 'Tue Jan  2 00:00:00 2024'
lane_register cap-b cap-lead "$FIX/.claude/worktrees/cap-b" build "$P2"

sleep 60 & P3=$!; ALL_PIDS+=("$P3")
birth "$P3" 'Wed Jan  3 00:00:00 2024'
_admit_rc=0
DISPATCH_SLOT_PID="$P3" WORK_ROOT="$FIX/.claude/worktrees/cap-c" LEADV2_LEAD_SESSION_ID=cap-lead \
  bash "$ADMIT_SH" cap-c sig-cap-c || _admit_rc=$?
[[ "$_admit_rc" -eq 3 ]] || fail "dispatch admission snippet did not exit 3 for a full cap (rc=$_admit_rc)"
pass 'dispatch admission snippet exits 3 when the lead-session lane cap is full'

# ── (b) leadv2-session-runner.sh's EXIT trap deregisters the lane it adopted ──
RUN_TASK="runner-exit-trap"
RUN_TASK_DIR="$FIX/docs/handoff/$RUN_TASK"
mkdir -p "$RUN_TASK_DIR"
touch "$RUN_TASK_DIR/phase8-passed.flag"  # pre-satisfied sentinel -> runner exits 0 before ever launching claude -p
LEADV2_PROJECT_ROOT="$FIX" LEADV2_TASK_ID="$RUN_TASK" LEADV2_LEAD_SESSION_ID="runner-lead" \
  timeout 20 bash "$RUNNER_SH" >/dev/null 2>&1 || true
python3 - "$FIX/docs/leadv2/active.yaml" "$RUN_TASK" <<'PY' || exit 1
import sys, yaml
path, task = sys.argv[1:]
rows = yaml.safe_load(open(path)).get('sessions') or []
row = next((r for r in rows if r.get('task_id') == task), None)
assert row is not None, f"session-runner never registered a lane row for {task}"
assert row.get('dead_at'), f"session-runner exited without its EXIT trap deregistering {task}: {row}"
PY
pass 'leadv2-session-runner.sh EXIT trap deregisters its adopted lane on exit'

# ── (c) sweeper reconcile (the exact idiom dispatch-code.sh runs before
# every admission) marks a kill-9'd lane dead ──
sleep 60 & P4=$!; ALL_PIDS+=("$P4")
birth "$P4" 'Thu Jan  4 00:00:00 2024'
lane_register sweep-a sweep-lead "$FIX/.claude/worktrees/sweep-a" build "$P4"
kill -9 "$P4"; wait "$P4" 2>/dev/null || true
declare -F lane_reconcile >/dev/null 2>&1 && lane_reconcile >/dev/null 2>&1 || true
python3 - "$FIX/docs/leadv2/active.yaml" <<'PY' || exit 1
import sys, yaml
row = next(r for r in yaml.safe_load(open(sys.argv[1]))['sessions'] if r['task_id'] == 'sweep-a')
assert row['dead_at'] and row['lane_events'][-1]['event'] == 'reconciled_dead'
PY
pass 'sweeper reconcile call marks a kill-9 lane dead'
