#!/usr/bin/env bash
# tests/test-single-writer-lane-state.sh — D1-SINGLE-WRITER-FOR-LANE-STATE
#
# Proof suite for the single-writer lane-state design:
#   T1  full lifecycle through the owner (leadv2_active_register ->
#       update_phase x3 -> mark_finished): ONE row, correct terminal state
#   T2  single textual body: leadv2_active_register defined exactly once in
#       the tree; helpers' legacy active.md duplicates are fail-loud rc=4
#       stubs; fanout/launcher reach the relocated body via alias only
#   T3  negative control A: a genuinely unowned row STILL becomes
#       recovered_unowned via lane_reconcile (de-duplication did not kill
#       the recovery mechanism)
#   T4  negative control B: a second writer attempting a transition it does
#       NOT own (update_phase / mark_finished on a recovery-owned row) is
#       REFUSED rc=8 with the row intact — not a silent win
#   T5  adoption re-opens: lane_register with a live worker pid clears
#       `recovered` and update_phase succeeds again
#   T6  reaper: a recovered row dead longer than
#       LEADV2_RECOVERED_UNOWNED_RETENTION_SEC is REMOVED by reconcile
#       (expiry alone accumulated 24 forever-rows, measured 2026-09-06)
#   T7  release contract: leadv2_active_release_verified removes our/stale
#       rows (rc=0) and refuses a foreign live row (rc=2, intact)
#   T8  sourcing the registry does not enable errexit in the caller
#   T9  the pump's pid-less reservation routes through the owner:
#       leadv2_active_reserve_lane + leadv2_active_set_lane_pid
#
# Mutation control (applied via scripts/leadv2-mutation-control.sh, INSIDE
# the changed function bodies — see mutation-control/ artifacts):
#   M1  leadv2-active-registry.sh update_phase op: `target["phase"] = new_phase`
#       neutered -> T1 goes RED (the phase write never lands)
#   M2  leadv2-active-registry.sh update_phase op: the `if target.get("recovered")`
#       refusal disabled -> T4 goes RED (the ownership refusal this lane
#       exists to build)
#
# Fully sandboxed: LEADV2_STATE_ROOT + LEADV2_PROJECT_ROOT point at mktemp
# dirs; the live ~/.claude/leadv2-state tree is never read or written.
# run-all-triggers: leadv2-active-registry leadv2-lane-state leadv2-dispatch-code leadv2-backlog-pump

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="$SCRIPTS_DIR/lib/leadv2-lane-state.sh"
REG="$SCRIPTS_DIR/leadv2-active-registry.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $*"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/d1sw.XXXXXX")"
REPO="$TMP/repo"; STATE_ROOT="$TMP/state"
mkdir -p "$REPO/.claude/worktrees/D1-LANE" "$STATE_ROOT"
LANE_WT="$REPO/.claude/worktrees/D1-LANE"
RREPO="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$REPO")"
RLANE="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$LANE_WT")"

new_sleeper() { sleep 300 </dev/null >/dev/null 2>&1 & echo $!; }
birth_of() { tr -s ' ' ' ' <<< "$(ps -o lstart= -p "$1" 2>/dev/null)"; }
SLEEP_PIDS=()

write_yaml() { # rows as a python literal list
  python3 - "$STATE_ROOT/active.yaml" "$1" <<'PY'
import sys, yaml, os
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
rows = eval(sys.argv[2])
if isinstance(rows, dict): rows=[rows]
yaml.safe_dump({'meta': {}, 'sessions': rows}, open(sys.argv[1], 'w', encoding='utf-8'), default_flow_style=False, sort_keys=False)
PY
}

sessions() {
  python3 -c '
import sys, yaml, json
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(json.dumps(data.get("sessions") or []))' "$STATE_ROOT/active.yaml" 2>/dev/null
}

run_reconcile() {
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$LIB'; lane_reconcile" >/dev/null 2>"$TMP/rec.err"
}

# in-sandbox registry caller: runs "$@" with the registry sourced
regsh() {
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
    bash -c "source '$REG'; $*" 2>"$TMP/reg.err"
}

# ── T1: full lifecycle through the owner ─────────────────────────────────
t1() {
  : > "$STATE_ROOT/active.yaml"
  regsh '
    leadv2_active_register "D1-T1" "Standard" "$LEADV2_PROJECT_ROOT" "test-branch" "false" >/dev/null
    leadv2_active_update_phase "D1-T1" build  >/dev/null
    leadv2_active_update_phase "D1-T1" review >/dev/null
    leadv2_active_update_phase "D1-T1" finished >/dev/null
    leadv2_active_mark_finished "D1-T1" "verified" "{\"proof\": \"t1\"}" >/dev/null
  '
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
t1 = [r for r in rows if r.get("task_id") == "D1-T1"]
ok = (len(rows) == 1 and len(t1) == 1
      and t1[0].get("phase") == "finished"
      and t1[0].get("terminal_status") == "verified")
sys.exit(0 if ok else 1)'
}

if t1; then pass "T1: register -> build -> review -> finished -> mark_finished via the owner; exactly ONE row, terminal state correct"; else fail "T1: lifecycle via owner wrong ($(sessions))"; fi

# ── T2: single textual body (static census) ─────────────────────────────
# exactly two definitions of the name exist: the real body (registry) and
# helpers' fail-loud rc=4 stub — a THIRD body anywhere is a regression
t2_defs="$(grep -c '^leadv2_active_register()' "$REG")"
t2_stubs="$(grep -c 'registry not loaded — refusing to write legacy active.md' "$SCRIPTS_DIR/leadv2-helpers.sh")"
t2_total="$(grep -h '^leadv2_active_register()' "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/lib/*.sh 2>/dev/null | wc -l | tr -d ' ')"
t2_stub_body="$(sed -n '/^leadv2_active_register()/,/^}/p' "$SCRIPTS_DIR/leadv2-helpers.sh" | grep -c 'return 4')"
t2_fnbody="$(grep -c '^leadv2_fanout_register_session()' "$REG")"
t2_alias_reg="$(grep -c '^_fanout_register_session() { leadv2_fanout_register_session' "$REG")"
t2_alias_dup="$(grep -c '^_fanout_register_session()' "$SCRIPTS_DIR/leadv2-fanout.sh" "$SCRIPTS_DIR/leadv2-fanout-lane-launcher.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
if [[ "$t2_defs" == 1 && "$t2_total" == 2 && "$t2_stub_body" -ge 1 && "$t2_stubs" -ge 3 && "$t2_fnbody" == 1 && "$t2_alias_reg" == 1 && "$t2_alias_dup" == 0 ]]; then
  pass "T2: one real body (registry) + one fail-loud helpers stub; fanout body relocated, aliased only in the registry"
else
  fail "T2: defs=$t2_defs total=$t2_total stub_body=$t2_stub_body stubs=$t2_stubs fnbody=$t2_fnbody alias_reg=$t2_alias_reg alias_dup=$t2_alias_dup"
fi

# ── T3: genuinely unowned row still becomes recovered_unowned ───────────
t3() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"; : > "$STATE_ROOT/active.yaml"
  local pid by
  pid="$(new_sleeper)"; SLEEP_PIDS+=("$pid"); by="$(birth_of "$pid")"
  printf 'worktree %s\n' "$RLANE" > "$TMP/wt.txt"
  printf ' 30133 %s /bin/zsh -c source snapshot.sh grep -r foo %s\n' "$by" "$RLANE" > "$TMP/ps.txt"
  printf '30133\t%s\n' "$TMP" >> "$TMP/cwd.txt"
  run_reconcile
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
lanes = [r for r in rows if str(r.get("worktree","")) == "'"$RLANE"'"]
ok = (len(lanes) == 1 and lanes[0].get("phase") == "recovered_unowned"
      and "pid" not in lanes[0] and lanes[0].get("recovered") is True
      and lanes[0].get("session_id") == "recovered")
sys.exit(0 if ok else 1)'
}
if t3; then pass "T3: genuinely unowned lane -> recovered_unowned row via lane_reconcile (recovery mechanism intact)"; else fail "T3: unowned row did not become recovered_unowned ($(sessions))"; fi

# ── T4: second writer refused on a recovery-owned row ────────────────────
t4_rc_up=99; t4_rc_mf=99; t4_out=""
t4_out="$(
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  bash -c "source '$REG'
    leadv2_active_update_phase D1-LANE build >/dev/null; echo UP_RC=\$?
    leadv2_active_mark_finished D1-LANE verified >/dev/null; echo MF_RC=\$?
  " 2>"$TMP/t4.err" || true
)"
t4_rc_up="$(printf '%s\n' "$t4_out" | sed -n 's/^UP_RC=//p')"
t4_rc_mf="$(printf '%s\n' "$t4_out" | sed -n 's/^MF_RC=//p')"
sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
lanes = [r for r in rows if r.get("task_id") == "D1-LANE"]
ok = len(lanes) == 1 and lanes[0].get("recovered") and not lanes[0].get("dead_at") and lanes[0].get("phase") == "recovered_unowned"
sys.exit(0 if ok else 1)'
t4_row=$?
if [[ "$t4_rc_up" == 8 && "$t4_rc_mf" == 8 && "$t4_row" == 0 && "$(grep -c 'recovery-owned' "$TMP/t4.err")" -ge 2 ]]; then
  pass "T4: update_phase rc=8 and mark_finished rc=8 on the recovery-owned row; row intact, refusal is loud"
else
  fail "T4: up=$t4_rc_up mf=$t4_rc_mf row_ok=$t4_row err=$(cat "$TMP/t4.err")"
fi

# ── T5: adoption clears recovered and re-opens transitions ───────────────
t5_adopt_rc=99
t5_adopt_rc="$(LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
  bash -c "source '$LIB'; lane_register D1-LANE adopted-lead '$RLANE' build \$\$ >/dev/null 2>&1; echo \$?" || echo 99)"
t5_phase_rc="$(regsh 'leadv2_active_update_phase D1-LANE review >/dev/null 2>&1; echo $?' | tail -1)"
sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
lanes = [r for r in rows if r.get("task_id") == "D1-LANE"]
sys.exit(0 if len(lanes) == 1 and not lanes[0].get("recovered") and lanes[0].get("phase") == "review" else 1)'
t5_ok=$?
if [[ "$t5_adopt_rc" == 0 && "$t5_phase_rc" == 0 && "$t5_ok" == 0 ]]; then
  pass "T5: live adoption cleared 'recovered'; update_phase succeeded again (rc=0, phase=review)"
else
  fail "T5: adopt=$t5_adopt_rc phase=$t5_phase_rc row_ok=$t5_ok"
fi

# ── T6: the reaper removes long-dead recovered rows ─────────────────────
t6() {
  : > "$TMP/birth.txt"; : > "$TMP/cwd.txt"
  write_yaml "[{'task_id':'D1-OLD-R','session_id':'recovered','lead_session_id':'recovered','worktree':'$RREPO/.claude/worktrees/D1-OLD-R','phase':'recovered_unowned','started_at':'2020-01-01T00:00:00Z','updated_at':'2020-01-01T00:00:00Z','dead_at':'2020-01-02T00:00:00Z','recovered':True,'lane_events':[]}]"
  printf 'worktree %s/.claude/worktrees/D1-OTHER\n' "$RREPO" > "$TMP/wt.txt"
  : > "$TMP/ps.txt"
  run_reconcile
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
sys.exit(0 if not any(r.get("task_id") == "D1-OLD-R" for r in rows) else 1)'
}
if t6 && grep -q 'recovered_rows_reaped=D1-OLD-R' "$TMP/rec.err"; then
  pass "T6: recovered row past RETENTION (dead_at 2020) REMOVED by reconcile, reaped row named in stderr"
else
  fail "T6: row not reaped ($(sessions); err=$(cat "$TMP/rec.err"))"
fi

# ── T7: release_verified contract ────────────────────────────────────────
t7() {
  : > "$STATE_ROOT/active.yaml"
  local dead_pid live_pid dead_birth out rc_a rc_b
  dead_pid="$(new_sleeper)"; SLEEP_PIDS+=("$dead_pid")
  dead_birth="$(birth_of "$dead_pid")"
  kill "$dead_pid" 2>/dev/null; wait "$dead_pid" 2>/dev/null
  live_pid="$(new_sleeper)"; SLEEP_PIDS+=("$live_pid")
  write_yaml "[
    {'task_id':'D1-R7A','session_id':'sess-A','lead_session_id':'sess-A','worktree':'$RREPO','phase':'build','pid':$dead_pid,'pid_start_time':'$dead_birth','started_at':'2026-09-06T00:00:00Z','updated_at':'2026-09-06T00:00:00Z','dead_at':None,'recovered':False,'lane_events':[]},
    {'task_id':'D1-R7B','session_id':'sess-B','lead_session_id':'sess-B','worktree':'$RREPO','phase':'build','pid':$live_pid,'pid_start_time':'$(birth_of "$live_pid")','started_at':'2026-09-06T00:00:00Z','updated_at':'2026-09-06T00:00:00Z','dead_at':None,'recovered':False,'lane_events':[]}]"
  out="$(
    LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
    bash -c "source '$REG'
      leadv2_active_release_verified D1-R7A sess-A $dead_pid >/dev/null 2>&1; echo A_RC=\$?
      leadv2_active_release_verified D1-R7B WRONG-SESS $live_pid >/dev/null 2>&1; echo B_RC=\$?
    " || true)"
  rc_a="$(printf '%s\n' "$out" | sed -n 's/^A_RC=//p')"
  rc_b="$(printf '%s\n' "$out" | sed -n 's/^B_RC=//p')"
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
ok = (not any(r.get("task_id") == "D1-R7A" for r in rows)
      and sum(1 for r in rows if r.get("task_id") == "D1-R7B" and not r.get("dead_at")) == 1)
sys.exit(0 if ok and sys.argv[1] == "0" and sys.argv[2] != "0" else 1)' "$rc_a" "$rc_b"
}
if t7; then pass "T7: our dead row released rc=0; foreign LIVE row refused (rc!=0) and left intact"; else fail "T7: release contract broken ($(sessions))"; fi

# ── T8: sourcing the registry must not enable errexit in the caller ──────
t8_out="$(LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  bash -c "source '$REG'; [[ -o errexit ]] && echo ERREXIT_LEAKED || echo ERREXIT_CLEAN" 2>/dev/null || true)"
if [[ "$t8_out" == *ERREXIT_CLEAN* ]]; then
  pass "T8: sourcing leadv2-active-registry.sh leaves caller errexit OFF (the old silent-kill leak is fixed)"
else
  fail "T8: errexit state after sourcing: $t8_out"
fi

# ── T9: pid-less reservation routes through the owner (pump path) ────────
t9() {
  : > "$STATE_ROOT/active.yaml"
  regsh '
    leadv2_active_reserve_lane "D1-PUMP" "suite reserves before write set is known" >/dev/null 2>&1 || exit 10
    leadv2_active_set_lane_pid "D1-PUMP" "424242" || true
  '
  sessions | python3 -c '
import sys, json
rows = json.load(sys.stdin)
r = [x for x in rows if x.get("task_id") == "D1-PUMP"]
sys.exit(0 if len(r) == 1 and r[0].get("pid") == 424242 and str(r[0].get("session_id","")).startswith("p-") else 1)'
}
if t9; then pass "T9: reserve_lane registers pid-less row (p- session) then set_lane_pid stamps the worker pid"; else fail "T9: reserve/set path wrong ($(sessions); $(cat "$TMP/reg.err"))"; fi

for p in "${SLEEP_PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done
rm -rf "$TMP"

log ""
log "single-writer lane-state: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
