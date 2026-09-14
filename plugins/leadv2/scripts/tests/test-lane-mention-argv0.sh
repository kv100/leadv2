#!/usr/bin/env bash
# tests/test-lane-mention-argv0.sh — LANE-MENTION-ARGV0-01 regression suite.
#
# f853b0e3 narrowed the self-race guard for pid-bearing rows, but the
# recovery sweep in lib/leadv2-lane-state.sh could still mint a PID-LESS
# `recovered_unowned` row for the dispatcher's OWN command line: the mention
# test judged argv[0] only, and `bash /…/leadv2-dispatch-code.sh …` has
# argv[0] == 'bash', never the script -- so the `non_workers` exclusion never
# applied. leadv2-lane-liveness.sh then gave that pid-less row `starting:`
# grace and re-stamped started_at every pass, refusing every re-dispatch
# forever (measured live twice on V5-M1-L0, sig ea519b21).
#
# Directions covered:
#   D-1a  hook-run sweep: a non-ancestor process running the dispatcher
#         script (any interpreter wrapper) does NOT mint a mention/row.
#         Run against the UNFIXED lib (ed30627c) first -- RED -- then the
#         fixed lib -- GREEN. Both shown verbatim.
#   D-1b  self-run sweep: the SAME line, but the pid IS an ancestor of the
#         reconcile itself (ancestry check must run before the mention
#         test, not just before adoption). RED before, GREEN after.
#   D-1c  interpreter-wrapper variants (nohup, bash -x) -- still no row.
#   D-2   a real worker-marker program still mints a row (adoption/mention
#         unaffected for genuine workers); the existing tool-shell mention
#         case (HEAD case 2) still mints a pid-less visibility row.
#   D-2b  liveness change: a pid-less `recovered` row gets NO `starting:`
#         grace (falls straight to the dead determination); a normal
#         pid-less REGISTERED (non-recovered) row keeps its grace,
#         unaffected -- negative control.
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-mention-argv0.sh
# run-all-triggers: leadv2-lane-state.sh leadv2-lane-liveness.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${SCRIPTS_DIR}/lib/leadv2-lane-state.sh"
LIVENESS="${SCRIPTS_DIR}/leadv2-lane-liveness.sh"
STATE_PATH="${SCRIPTS_DIR}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-mention-argv0.XXXXXX")"
SLEEP_PIDS=()
kill_sleepers() { (( ${#SLEEP_PIDS[@]} )) && kill "${SLEEP_PIDS[@]}" 2>/dev/null; }
trap 'kill_sleepers; rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
STATE_ROOT="$TMP/state"
mkdir -p "$REPO/.claude/worktrees" "$STATE_ROOT"
LANE_WT="$REPO/.claude/worktrees/LIVE-LANES-Y"
mkdir -p "$LANE_WT"

realp() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
RREPO="$(realp "$REPO")"; RLANE="$(realp "$LANE_WT")"
birth_of() { tr -s ' ' ' ' <<< "$(ps -o lstart= -p "$1" 2>/dev/null)"; }
new_sleeper() { sleep 300 </dev/null >/dev/null 2>&1 & echo $!; }

# --- unfixed (base ed30627c) copy of the lib, same sibling deps as the
# MUTDIR pattern in test-leadv2-lane-state.sh case 5 --------------------
BASEDIR="$TMP/base"
mkdir -p "$BASEDIR/lib"
cp "${SCRIPTS_DIR}/leadv2-state-path.sh" "$BASEDIR/"
cp "${SCRIPTS_DIR}/leadv2-portable-lock.sh" "$BASEDIR/"
if ! git -C "$SCRIPTS_DIR" show ed30627c:plugins/leadv2/scripts/lib/leadv2-lane-state.sh > "$BASEDIR/lib/leadv2-lane-state.sh" 2>"$TMP/base.err"; then
  printf '[TEST-SETUP] FATAL: could not materialize base ed30627c lib copy\n%s\n' "$(cat "$TMP/base.err")" >&2
  exit 90
fi

sessions() {
  python3 -c '
import sys, yaml, json
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(json.dumps(data.get("sessions") or []))' "$STATE_ROOT/active.yaml"
}

run_reconcile_against() { # <lib-path>
  local lib="$1"
  : > "$STATE_ROOT/active.yaml"
  printf 'sessions: []\n' > "$STATE_ROOT/active.yaml"
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$lib'; lane_reconcile" >/dev/null 2>"$TMP/rec.err"
}

rows_for_lane() {
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
print(sum(1 for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"))'
}

# ============================================================================
# D-1a: hook-run sweep -- pid NOT an ancestor, argv is
#   bash <abs>/leadv2-dispatch-code.sh --worktree <RLANE> --task X
# ============================================================================
d1a_fixture() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30601 Wed Sep  3 09:00:00 2026 bash %s/leadv2-dispatch-code.sh --worktree %s --task X\n' \
    "$SCRIPTS_DIR" "$RLANE" > "$TMP/ps.txt"
}

d1a_fixture
run_reconcile_against "$BASEDIR/lib/leadv2-lane-state.sh"
RED_N="$(rows_for_lane)"
if [[ "$RED_N" != "0" ]]; then
  pass "D-1a-RED: unfixed lib mints $RED_N row(s) for the dispatcher's own command line (bash argv[0]) — reproduces the live defect"
else
  fail "D-1a-RED: unfixed lib stayed green ($RED_N rows) — negative control proves nothing, base copy may be wrong"
fi

d1a_fixture
run_reconcile_against "$LIB"
GREEN_N="$(rows_for_lane)"
if [[ "$GREEN_N" == "0" ]]; then
  pass "D-1a-GREEN: fixed lib mints 0 rows for the same dispatcher command line"
else
  fail "D-1a-GREEN: fixed lib still minted $GREEN_N row(s)"
fi

# ============================================================================
# D-1b: self-run sweep -- SAME shape, but the pid IS this test shell's own
# pid ($$), a real ancestor of the reconcile's python3 process.
# ============================================================================
d1b_fixture() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  local by; by="$(birth_of "$$")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' %s %s bash %s/leadv2-dispatch-code.sh --worktree %s --task X\n' \
    "$$" "$by" "$SCRIPTS_DIR" "$RLANE" > "$TMP/ps.txt"
}

d1b_fixture
run_reconcile_against "$BASEDIR/lib/leadv2-lane-state.sh"
RED_N="$(rows_for_lane)"
if [[ "$RED_N" != "0" ]]; then
  pass "D-1b-RED: unfixed lib mints $RED_N row(s) for its own ancestor's dispatcher line (ancestry checked after the mention test)"
else
  fail "D-1b-RED: unfixed lib stayed green ($RED_N rows) — negative control proves nothing"
fi

d1b_fixture
run_reconcile_against "$LIB"
GREEN_N="$(rows_for_lane)"
if [[ "$GREEN_N" == "0" ]]; then
  pass "D-1b-GREEN: fixed lib mints 0 rows once ancestry is checked before the mention test"
else
  fail "D-1b-GREEN: fixed lib still minted $GREEN_N row(s)"
fi

# ============================================================================
# D-1c: interpreter-wrapper variants -- nohup, and bash -x -- still no row
# on the fixed lib (program-set basis is interpreter-agnostic).
# ============================================================================
d1c_case() { # <label> <command-prefix>
  local label="$1" cmd="$2"
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30602 Wed Sep  3 09:00:00 2026 %s %s/leadv2-dispatch-code.sh --worktree %s --task X\n' \
    "$cmd" "$SCRIPTS_DIR" "$RLANE" > "$TMP/ps.txt"
  run_reconcile_against "$LIB"
  local n; n="$(rows_for_lane)"
  if [[ "$n" == "0" ]]; then
    pass "D-1c: '$label' wrapper mints 0 rows"
  else
    fail "D-1c: '$label' wrapper minted $n row(s)"
  fi
}
d1c_case "nohup bash" "nohup bash"
d1c_case "bash -x" "bash -x"

# ============================================================================
# D-2: a real worker-marker program still mints a row (adoption path
# unaffected); the tool-shell mention case (HEAD case 2) still mints a
# pid-less visibility row (argv[0]-basis for tool names is unchanged).
# ============================================================================
d2_worker_adopted() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  local by pid
  pid="$(new_sleeper)"; SLEEP_PIDS+=("$pid"); by="$(birth_of "$pid")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' %s %s claude -p developer arm --worktree %s\n' "$pid" "$by" "$RLANE" > "$TMP/ps.txt"
  printf '%s\t%s\n' "$pid" "$by" >> "$TMP/birth.txt"
  printf '%s\t%s\n' "$pid" "$RLANE" >> "$TMP/cwd.txt"
  run_reconcile_against "$LIB"
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
rec = [r for r in rows if r.get("phase") == "recovered" and r.get("recovered")]
ok = len(rec) == 1 and str(rec[0].get("pid")) == "'"$pid"'"
sys.exit(0 if ok else 1)'
}
if d2_worker_adopted; then
  pass "D-2: genuine worker-marker process still adopted with its pid (argv0 fix does not touch worker_markers)"
else
  fail "D-2: genuine worker-marker process was NOT adopted — adoption path regressed"
fi

d2_tool_shell_mentions() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30603 Wed Sep  3 09:00:00 2026 /bin/zsh -c source snapshot.sh grep -r foo %s\n' "$RLANE" > "$TMP/ps.txt"
  run_reconcile_against "$LIB"
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
lanes = [r for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"]
ok = len(lanes) == 1 and lanes[0].get("phase") == "recovered_unowned" and "pid" not in lanes[0]
sys.exit(0 if ok else 1)'
}
if d2_tool_shell_mentions; then
  pass "D-2: tool-shell bystander (HEAD case 2) still mints a pid-less recovered_unowned row — tool argv0 basis untouched"
else
  fail "D-2: tool-shell bystander no longer mints a visibility row — case 2 regressed"
fi

# ============================================================================
# D-2b: liveness change -- a pid-less `recovered` row gets no starting grace;
# a normal pid-less REGISTERED (non-recovered) row keeps it (negative
# control, unaffected by this change).
# ============================================================================
active="$(LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$REPO" bash "$STATE_PATH" active.yaml)"
mkdir -p "$(dirname "$active")"

now_iso() { python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))'; }

cat > "$active" <<YAML
sessions:
  - task_id: PIDLESS-RECOVERED
    session_id: recovered
    lead_session_id: recovered
    phase: recovered_unowned
    started_at: "$(now_iso)"
    updated_at: "$(now_iso)"
    dead_at: null
    recovered: true
    lane_events: []
YAML
verdict_recovered="$(LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" bash "$LIVENESS" --project-root "$REPO" --lane PIDLESS-RECOVERED --json)"
if grep -q '"verdict": *"starting:' <<<"$verdict_recovered"; then
  fail "D-2b: pid-less recovered row still gets starting: grace (change 2 not effective)"
else
  pass "D-2b: pid-less recovered row gets NO starting: grace"
fi

cat > "$active" <<YAML
sessions:
  - task_id: PIDLESS-REGISTERED
    session_id: lead
    lead_session_id: lead
    phase: build
    started_at: "$(now_iso)"
    updated_at: "$(now_iso)"
    dead_at: null
    recovered: false
    lane_events: []
YAML
verdict_registered="$(LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" bash "$LIVENESS" --project-root "$REPO" --lane PIDLESS-REGISTERED --json)"
if grep -q '"verdict": *"starting:' <<<"$verdict_registered"; then
  pass "D-2b-control: a normal pid-less REGISTERED (non-recovered) row keeps its starting: grace"
else
  fail "D-2b-control: normal registered row lost its starting: grace — collateral regression\n$verdict_registered"
fi

# --- final count line ------------------------------------------------------
printf '[TEST] %s: %d passed, %d failed\n' "test-lane-mention-argv0" "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '[TEST] failures:\n'; printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
