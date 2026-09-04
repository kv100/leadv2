#!/usr/bin/env bash
# tests/test-leadv2-lane-state.sh — RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01
# regression suite for the orphan-recovery block inside
# lib/leadv2-lane-state.sh `_lv2_lane_state_mutate reconcile`.
#
# Covers, using ONLY the shipped test seams (never real orchestration):
#   1. a lane worktree whose task already has a LIVE owner row carrying the
#      REPO ROOT in worktree: (the exact live case) -> NO recovered row.
#   2. a lane worktree with no owner row and a ps table whose only match is a
#      bystander shell that merely MENTIONS the path -> NOT adopted; an
#      unowned visibility row (no pid) is registered instead, and it
#      survives a second reconcile within its TTL.
#   3. a genuine orphan with a real owning process (cwd proven) -> IS
#      recovered with that pid.
#   4. the writes-less bound: an unowned recovered row past
#      LEADV2_RECOVERED_UNOWNED_TTL_SEC is expired (dead_at set), so it can
#      no longer fall into the registry's pending window and refuse a lane.
#   5. NEGATIVE CONTROL: with the task_id known-matching clause reverted
#      inside the function body (mutant copy of the lib), case 1 goes RED;
#      restored, it goes GREEN. Both runs verbatim in the log.
#
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-lane-state.sh
# run-all-triggers: leadv2-lane-state.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${SCRIPTS_DIR}/lib/leadv2-lane-state.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; sed -n '1,5p' "$TMP/rec.err" 2>/dev/null | sed 's/^/       rec.err: /'; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-state-recov.XXXXXX")"
kill_sleepers() { (( ${#SLEEP_PIDS[@]} )) && kill ${SLEEP_PIDS[@]} 2>/dev/null; }
trap 'kill_sleepers; rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
STATE_ROOT="$TMP/state"
mkdir -p "$REPO/.claude/worktrees" "$STATE_ROOT"

LANE_WT="$REPO/.claude/worktrees/LIVE-LANES-X"
mkdir -p "$LANE_WT"

# --- fixture helpers -------------------------------------------------------

new_sleeper() { # prints pid of a real live process (needed by os.kill(0))
  sleep 300 </dev/null >/dev/null 2>&1 & echo $!
}

birth_of() { tr -s ' ' ' ' <<< "$(ps -o lstart= -p "$1" 2>/dev/null)"; }
realp() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
RREPO="$(realp "$REPO")"; RLANE="$(realp "$LANE_WT")"

write_yaml() { # rows already assembled as a python literal list
  python3 - "$STATE_ROOT/active.yaml" "$1" <<'PY'
import sys, yaml, os
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
rows = eval(sys.argv[2])
if isinstance(rows, dict): rows=[rows]
yaml.safe_dump({'meta': {}, 'sessions': rows}, open(sys.argv[1], 'w', encoding='utf-8'), default_flow_style=False, sort_keys=False)
PY
}

owner_row() { # <task> <worktree> <pid>
  printf "{'task_id':'%s','session_id':'lead','lead_session_id':'lead','worktree':'%s','phase':'build','pid':%s,'pid_start_time':'%s','started_at':'2026-09-04T09:00:00Z','updated_at':'2026-09-04T09:00:00Z','dead_at':None,'recovered':False,'lane_events':[]}" \
    "$1" "$2" "$3" "$(birth_of "$3")"
}

run_reconcile() { # [lib-path]
  local lib="${1:-$LIB}"
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$lib'; lane_reconcile" >/dev/null 2>"$TMP/rec.err"
}

sessions() { # dump sessions as compact JSON
  python3 -c '
import sys, yaml, json
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(json.dumps(data.get("sessions") or []))' "$STATE_ROOT/active.yaml"
}

count_rows() { # <json-expr over sessions>
  sessions | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))'
}

# --- Case 1: live lead-owner row at REPO ROOT -> no recovery ---------------
case1() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  local by pid
  pid="$(new_sleeper)"; by="$(birth_of "$pid")"
  # bystander: a tool shell whose argv merely mentions the lane path
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30132 %s /bin/zsh -c source ~/.claude/shell-snapshots/snapshot.sh cd %s\n' "$by" "$RLANE" > "$TMP/ps.txt"
  printf '%s\t%s\n' "$pid" "$by" >> "$TMP/birth.txt"
  printf '30132\t%s\n' "$RREPO" >> "$TMP/cwd.txt"   # bystander cwd is the repo root, NOT the lane
  write_yaml "$(owner_row LIVE-LANES-X "$RREPO" "$pid")"
  run_reconcile
  n="$(sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
print(sum(1 for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"))')"
  [[ "$n" == "0" ]]
}

if case1; then pass "case1: live lead-owner row at repo root -> no recovered row for the lane"; else fail "case1: a row was recovered for a lane already owned by a live lead row"; fi

# --- Case 2: no owner row + bystander-only ps -> unowned row, no pid -------
SLEEP_PIDS=()
case2() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"; : > "$STATE_ROOT/active.yaml"
  local by pid
  pid="$(new_sleeper)"; SLEEP_PIDS+=("$pid"); by="$(birth_of "$pid")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30133 %s /bin/zsh -c source snapshot.sh grep -r foo %s\n' "$by" "$RLANE" > "$TMP/ps.txt"
  printf '%s\t%s\n' "$pid" "$by" >> "$TMP/birth.txt"
  printf '30133\t%s\n' "$TMP" >> "$TMP/cwd.txt"     # cwd is elsewhere
  run_reconcile
  python3 - "$RLANE" "$STATE_ROOT/active.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}
rows = data.get("sessions") or []
lanes = [r for r in rows if str(r.get("worktree","")) == sys.argv[1]]
ok = (len(lanes) == 1 and lanes[0].get("phase") == "recovered_unowned"
      and "pid" not in lanes[0] and lanes[0].get("recovered") is True
      and not any(r.get("phase") == "recovered" and r.get("pid") == 30133 for r in rows))
sys.exit(0 if ok else 1)
PY
}

if case2; then pass "case2: bystander not adopted; unowned pid-less recovered_unowned row registered"; else fail "case2: bystander was adopted or row shape wrong"; fi

# --- Case 2b: unowned row survives a second reconcile within TTL -----------
if run_reconcile && sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
lanes = [r for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"]
sys.exit(0 if len(lanes) == 1 and not lanes[0].get("dead_at") else 1)'; then
  pass "case2b: unowned row not killed for being pidless on the next pass"
else
  fail "case2b: unowned row was dead-marked (would re-adopt a fresh bystander next pass)"
fi

# --- Case 3: genuine orphan with real owning process -> recovered ----------
case3() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"; : > "$STATE_ROOT/active.yaml"
  local by pid
  pid="$(new_sleeper)"; SLEEP_PIDS+=("$pid"); by="$(birth_of "$pid")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' %s %s claude -p developer arm --worktree %s\n' "$pid" "$by" "$RLANE" > "$TMP/ps.txt"
  printf '%s\t%s\n' "$pid" "$by" >> "$TMP/birth.txt"
  printf '%s\t%s\n' "$pid" "$RLANE" >> "$TMP/cwd.txt"   # cwd IS the lane
  run_reconcile
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
rec = [r for r in rows if r.get("phase") == "recovered" and r.get("recovered")]
ok = len(rec) == 1 and rec[0].get("task_id") == "LIVE-LANES-X" and str(rec[0].get("pid")) == "'"$pid"'"
sys.exit(0 if ok else 1)'
}

if case3; then pass "case3: genuine orphan with proven owner recovered with the right pid"; else fail "case3: genuine orphan NOT recovered (mechanism broken)"; fi

# --- Case 4: the writes-less bound — expired unowned row is released -------
case4() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  write_yaml "[{'task_id':'OLD-LANE','session_id':'recovered','lead_session_id':'recovered','worktree':'$RREPO/.claude/worktrees/OLD-LANE','phase':'recovered_unowned','started_at':'2020-01-01T00:00:00Z','updated_at':'2020-01-01T00:00:00Z','dead_at':None,'recovered':True,'lane_events':[]}]"
  printf 'worktree %s/.claude/worktrees/OTHER-LANE\n' "$RREPO" > "$TMP/wt.txt"
  : > "$TMP/ps.txt"
  run_reconcile
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
old = [r for r in rows if r.get("task_id") == "OLD-LANE"]
sys.exit(0 if len(old) == 1 and old[0].get("dead_at") else 1)'
}

if case4; then pass "case4: unowned recovered row past LEADV2_RECOVERED_UNOWNED_TTL_SEC (900s, mirrors the registry pending window) is expired -> no longer pending -> cannot refuse a lane"; else fail "case4: expired unowned row still live (unbounded block)"; fi

# --- Case 5: NEGATIVE CONTROL on the known-matching clause -----------------
MUTDIR="$TMP/mutlib"
mkdir -p "$MUTDIR/lib"
cp "${SCRIPTS_DIR}/leadv2-state-path.sh" "$MUTDIR/"
cp "$LIB" "$MUTDIR/lib/leadv2-lane-state.sh"
python3 - "$MUTDIR/lib/leadv2-lane-state.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "      if real in known or task in live_tasks: continue"
new = "      if real in known: continue  # MUTANT: task_id known-matching reverted"
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
PY

case1_mutant_run() {
  # same fixture as case1, but against the MUTANT lib
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  local by pid
  pid="$(new_sleeper)"; SLEEP_PIDS+=("$pid"); by="$(birth_of "$pid")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30132 %s /bin/zsh -c source snapshot.sh cd %s\n' "$by" "$RLANE" > "$TMP/ps.txt"
  printf '%s\t%s\n' "$pid" "$by" >> "$TMP/birth.txt"
  printf '30132\t%s\n' "$RREPO" >> "$TMP/cwd.txt"
  write_yaml "$(owner_row LIVE-LANES-X "$RREPO" "$pid")"
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$MUTDIR/lib/leadv2-lane-state.sh'; lane_reconcile" >/dev/null 2>&1
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
print(sum(1 for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"))'
}

RED_N="$(case1_mutant_run)"
if [[ "$RED_N" != "0" ]]; then
  pass "case5-RED: mutant (known-matching reverted) recovered $RED_N spurious row(s) — suite shows its own red: $RED_N != 0"
else
  fail "case5-RED: mutant still green — negative control proves nothing"
fi

case1; GREEN_N=$n
if [[ "$GREEN_N" == "0" ]]; then
  pass "case5-GREEN: restored lib, case1 clean again (0 spurious rows)"
else
  fail "case5-GREEN: case1 stayed red after restore ($GREEN_N rows)"
fi

# --- final count line ------------------------------------------------------
printf '[TEST] %s: %d passed, %d failed\n' "test-leadv2-lane-state" "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '[TEST] failures:\n'; printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
