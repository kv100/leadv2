#!/usr/bin/env bash
# test-lane-adopt-writeset-refusal.sh — SD-DISPATCH-WRITESET-TWO-ROW-FIX-01 (F4s).
#
# The composed failure (f4-composition.md): leadv2-session-runner.sh adopted its
# pid through lane_adopt_pid -> lane_register, and when the task's original row
# (registered by dispatch with writes_reason=prepass_pending, then the resolved
# declaration) was gone, the lane-state engine APPENDED a second same-task row
# with no writes/writes_reason/first_seen_at at all -- a live unknown-scope
# blocker the registry's pending window then refused every concurrent dispatch
# on. Every component was individually correct; the defect was the two row
# shapes. This suite proves the repair against the REAL lane-state engine and
# the REAL registry checker:
#   1. strict adoption (lane_adopt_pid) with no prior row refuses rc=4 and
#      leaves active.yaml untouched (no row shape B minted);
#   2. a dead prior row carrying writes is INHERITED: the new row carries the
#      same writes and first_seen_at (clock not laundered);
#   3. a dead prior row carrying only writes_reason is inherited the same way;
#   4. a dead prior row carrying NEITHER still refuses (nothing to inherit);
#   5. plain lane_register (dispatch's own :8956 path) keeps minting rows with
#      no writes -- the refusal is scoped to adoption, never a blanket reject;
#   6. NEGATIVE CONTROL (f9fe3e2b2caf): an orphan row (write-less, in-window,
#      DEAD pid) must NOT block a disjoint declared candidate (rc=0);
#   7. its complement: the same write-less row with a LIVE worker pid DOES
#      refuse rc=5 reason=pending_resolution -- proving 6 passes for the right
#      reason, not because the checker is blind;
#   8. a DECLARED incumbent blocks only on a REAL path intersection: overlap
#      refuses rc=5 with paths=, disjoint proceeds rc=0;
#   9. NEGATIVE CONTROL on the refusal itself: with the strict-refusal clause
#      mutated out of a copy of the lib, case 1's adoption mints a write-less
#      row (rc=0) -- the suite shows its own red.
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-adopt-writeset-refusal.sh
# run-all-triggers: leadv2-lane-state.sh leadv2-session-runner.sh leadv2-codex-session-runner.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${SCRIPTS_DIR}/lib/leadv2-lane-state.sh"
REGISTRY_SH="${SCRIPTS_DIR}/leadv2-active-registry.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-adopt-ws.XXXXXX")"
SLEEP_PIDS=()
kill_sleepers() { (( ${#SLEEP_PIDS[@]} )) && kill ${SLEEP_PIDS[@]} 2>/dev/null; }
trap 'kill_sleepers; rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; STATE_ROOT="$TMP/state"; REG_ROOT="$TMP/regroot"
mkdir -p "$REPO" "$STATE_ROOT"

new_sleeper() { sleep 300 </dev/null >/dev/null 2>&1 & echo $!; }

# run_adopt <lib-path> <task> -> rc in $?, engine stderr in $TMP/adopt.err
run_adopt() {
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
    bash -c 'source "$1"; lane_adopt_pid "$2" lead "$3" spawning "$$"' _ "$1" "$2" "$REPO" \
    >/dev/null 2>"$TMP/adopt.err"
}

# run_register_plain <task> -- dispatch's non-adoption register path (no strict flag)
run_register_plain() {
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
    bash -c 'source "$1"; lane_register "$2" lead "$3" spawning "$$"' _ "$LIB" "$1" "$REPO" \
    >/dev/null 2>"$TMP/reg.err"
}

# write_rows <yaml-path> <python-literal rows list>
write_rows() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml, os
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
rows = eval(sys.argv[2])
if isinstance(rows, dict): rows=[rows]
yaml.safe_dump({'meta': {}, 'sessions': rows}, open(sys.argv[1], 'w', encoding='utf-8'), default_flow_style=False, sort_keys=False)
PY
}

sessions_json() { # <yaml-path>
  python3 -c '
import sys, yaml, json
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(json.dumps(data.get("sessions") or []))' "$1"
}

row_of() { # <yaml-path> <task> -> one row as JSON (or null); prefers the non-dead row
  sessions_json "$1" | python3 -c '
import sys, json
rows = json.load(sys.stdin)
m = [r for r in rows if r.get("task_id") == sys.argv[1]]
pick = next((r for r in m if not r.get("dead_at")), m[0] if m else None)
print(json.dumps(pick))' "$2"
}
# bash-guard: allow

YAML="$STATE_ROOT/active.yaml"
NOW_STAMP="2026-09-11T00:00:00Z"

# ══ 1. no prior row at all -> strict adoption refuses, yaml untouched ══════
rm -f "$YAML" "$STATE_ROOT/active.yaml.lock"
run_adopt "$LIB" ADOPTEE-1; RC=$?
if [[ "$RC" -eq 4 ]] && grep -q 'refused: adoption found no reusable row' "$TMP/adopt.err" && [[ ! -f "$YAML" ]]; then
  pass "1: adoption with no prior row refuses rc=4, says why, and mints nothing"
else
  fail "1: rc=$RC yaml_exists=$([[ -f $YAML ]] && echo yes || echo no) err=$(head -c 200 "$TMP/adopt.err" 2>/dev/null)"
fi

# ══ 2. dead prior row WITH writes -> inherited, clock carried ══════════════
write_rows "$YAML" "[{'task_id':'ADOPTEE-2','session_id':'s','lead_session_id':'lead','worktree':'$REPO','phase':'build','pid':99999,'pid_start_time':'x','started_at':'2026-09-10T10:00:00Z','updated_at':'2026-09-10T10:00:00Z','dead_at':'2026-09-10T11:00:00Z','writes':'src/a.txt,src/b.txt','writes_reason':None,'first_seen_at':'2026-09-10T10:00:00Z'}]"
run_adopt "$LIB" ADOPTEE-2; RC=$?
ROW="$(row_of "$YAML" ADOPTEE-2)"
if [[ "$RC" -eq 0 ]] && printf '%s' "$ROW" | python3 -c '
import sys, json
r = json.load(sys.stdin)
sys.exit(0 if r and r.get("dead_at") is None and r.get("writes") == "src/a.txt,src/b.txt"
         and "writes_reason" not in r and r.get("first_seen_at") == "2026-09-10T10:00:00Z" else 1)' ; then
  pass "2: dead prior row's writes + first_seen_at carried into the adopted row (no clock laundering)"
else
  fail "2: rc=$RC row=$ROW"
fi

# ══ 3. dead prior row with ONLY a reason -> reason inherited ═══════════════
write_rows "$YAML" "[{'task_id':'ADOPTEE-3','session_id':'s','lead_session_id':'lead','worktree':'$REPO','phase':'build','pid':99998,'pid_start_time':'x','started_at':'2026-09-10T12:00:00Z','updated_at':'2026-09-10T12:00:00Z','dead_at':'2026-09-10T13:00:00Z','writes_reason':'prepass_pending','first_seen_at':'2026-09-10T12:00:00Z'}]"
run_adopt "$LIB" ADOPTEE-3; RC=$?
ROW="$(row_of "$YAML" ADOPTEE-3)"
if [[ "$RC" -eq 0 ]] && printf '%s' "$ROW" | python3 -c '
import sys, json
r = json.load(sys.stdin)
sys.exit(0 if r and r.get("writes_reason") == "prepass_pending"
         and r.get("first_seen_at") == "2026-09-10T12:00:00Z" and "writes" not in r else 1)' ; then
  pass "3: reason-only prior row: writes_reason + first_seen_at inherited"
else
  fail "3: rc=$RC row=$ROW"
fi

# ══ 4. dead prior row carrying NEITHER -> still refused ════════════════════
write_rows "$YAML" "[{'task_id':'ADOPTEE-4','session_id':'s','lead_session_id':'lead','worktree':'$REPO','phase':'build','pid':99997,'pid_start_time':'x','started_at':'2026-09-10T14:00:00Z','updated_at':'2026-09-10T14:00:00Z','dead_at':'2026-09-10T15:00:00Z'}]"
cp "$YAML" "$TMP/pre4.yaml"
run_adopt "$LIB" ADOPTEE-4; RC=$?
if [[ "$RC" -eq 4 ]] && cmp -s "$YAML" "$TMP/pre4.yaml"; then
  pass "4: prior row exists but carries no declaration -> rc=4, yaml byte-identical"
else
  fail "4: rc=$RC yaml_changed=$([[ -f $YAML ]] && ! cmp -s "$YAML" "$TMP/pre4.yaml" && echo yes || echo no)"
fi

# ══ 5. plain lane_register stays legacy (no blanket reject) ════════════════
write_rows "$YAML" "[]"
run_register_plain PLAIN-5; RC=$?
ROW="$(row_of "$YAML" PLAIN-5)"
if [[ "$RC" -eq 0 ]] && printf '%s' "$ROW" | python3 -c '
import sys, json
r = json.load(sys.stdin)
sys.exit(0 if r and "writes" not in r and "writes_reason" not in r else 1)' ; then
  pass "5: non-adoption lane_register still mints a write-less row (dispatch :8956 path unchanged)"
else
  fail "5: rc=$RC row=$ROW"
fi
# bash-guard: allow

# ── registry-side controls: REAL checker, scratch control plane ────────────
mkdir -p "$REG_ROOT"
( cd "$REG_ROOT" && git init -q && git config user.email t@e.com && git config user.name t \
  && : > seed && git add seed && git commit -qm seed ) >/dev/null 2>&1

# reg_case <shape> <incumbent-pid> <cand-writes> -> "rc=<n>" on stdout;
# incumbent rewritten fresh each call (shape 'declared' -> writes set, else None)
reg_case() {
  local shape="$1" ipid="$2" cw="$3"
  LEADV2_PROJECT_ROOT="$REG_ROOT" LEADV2_STATE_ROOT="$REG_ROOT" \
  LEADV2_BURN_GOVERNOR=0 LEADV2_WRITESET_PENDING_WINDOW_SEC=900 \
    bash -c '
    set -uo pipefail
    source "$1"; root="$2"; ipid="$3"; shape="$4"; cw="$5"
    Y="$(_leadv2_yaml_file)"
    python3 - "$Y" "$ipid" "$shape" "$root" <<PYEOF
import sys, yaml, os, datetime
path, ipid, shape, root = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
row = {"session_id": "s-inc", "task_id": "INC-" + shape, "worktree": root, "branch": "b",
       "started_at": now, "phase": "build", "class": "Standard", "pulse_log": "",
       "pid": ipid, "pid_birth": None, "proc_kind": None, "pid_role": "lead_durable",
       "parent_session_id": None, "daemon_mode": False, "last_pulse_at": now,
       "stale": False, "note": "", "group_key": None, "risk_tags": None,
       "writes": ("shared/x.txt" if shape == "declared" else None),
       "writes_reason": None, "first_seen_at": now,
       "protocol_version": 2, "backend": "headless", "phase_started_at": now,
       "updated_at": now, "log_path": "", "provider_receipts": []}
os.makedirs(os.path.dirname(path), exist_ok=True)
yaml.safe_dump({"meta": {}, "sessions": [row]}, open(path, "w", encoding="utf-8"), default_flow_style=False, sort_keys=False)
PYEOF
    leadv2_active_register "CAND" Standard "$root" "$root" false "" "" "$cw" "" >/dev/null 2>"$root/reg.err"
    echo "rc=$?"
    ' _ "$REGISTRY_SH" "$REG_ROOT" "$ipid" "$shape" "$cw"
}

# ══ 6. orphan row (write-less, in-window, DEAD pid) must NOT block ═════════
DEAD_PID="$(new_sleeper)"; kill "$DEAD_PID" 2>/dev/null; sleep 0.3
OUT6="$(reg_case orphan "$DEAD_PID" 'cand/b.txt' | tail -1)"
if [[ "$OUT6" == "rc=0" ]]; then
  pass "6: write-less orphan with a dead pid does NOT block a disjoint declared candidate"
else
  fail "6: out=$OUT6 err=$(head -c 200 "$REG_ROOT/reg.err" 2>/dev/null)"
fi

# ══ 7. complement: same shape, LIVE worker pid -> pending refusal rc=5 ═════
LIVE_PID="$(new_sleeper)"; SLEEP_PIDS+=("$LIVE_PID")
OUT7="$(reg_case livebare "$LIVE_PID" 'cand/b.txt' | tail -1)"
if [[ "$OUT7" == "rc=5" ]] && grep -q 'reason=pending_resolution' "$REG_ROOT/reg.err"; then
  pass "7: same write-less row with a LIVE worker still refuses rc=5 pending_resolution (6 passes for the right reason)"
else
  fail "7: out=$OUT7 err=$(head -c 200 "$REG_ROOT/reg.err" 2>/dev/null)"
fi

# ══ 8. declared incumbent blocks ONLY on a real path intersection ══════════
OUT8A="$(reg_case declared "$LIVE_PID" 'shared/x.txt/nested.md' | tail -1)"
if [[ "$OUT8A" == "rc=5" ]] && grep -q 'writeset conflict' "$REG_ROOT/reg.err" && grep -q 'paths=' "$REG_ROOT/reg.err"; then
  pass "8a: declared incumbent + overlapping candidate -> rc=5 with paths="
else
  fail "8a: out=$OUT8A err=$(head -c 200 "$REG_ROOT/reg.err" 2>/dev/null)"
fi
OUT8B="$(reg_case declared "$LIVE_PID" 'other/z.txt' | tail -1)"
if [[ "$OUT8B" == "rc=0" ]]; then
  pass "8b: declared incumbent + disjoint candidate -> rc=0 (no blanket block on declaration)"
else
  fail "8b: out=$OUT8B err=$(head -c 200 "$REG_ROOT/reg.err" 2>/dev/null)"
fi

# ══ 9. NEGATIVE CONTROL: refusal mutated out -> case 1 shape mints a row ═══
MUTDIR="$TMP/mutlib"; mkdir -p "$MUTDIR/lib"
cp "${SCRIPTS_DIR}/leadv2-state-path.sh" "$MUTDIR/"
# state-path.sh sources this sibling from its own dir (:121) -- without the
# copy, every path resolution in the mutant dies rc=1 before register runs.
cp "${SCRIPTS_DIR}/leadv2-portable-lock.sh" "$MUTDIR/"
cp "$LIB" "$MUTDIR/lib/leadv2-lane-state.sh"
python3 - "$MUTDIR/lib/leadv2-lane-state.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "      if os.environ.get('LEADV2_LANE_STATE_ADOPT_STRICT','') == '1' and prior_writes is None and prior_reason is None:"
new = "      if False and prior_writes is None and prior_reason is None:  # MUTANT: refusal disabled"
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
PY
rm -f "$YAML" "$STATE_ROOT/active.yaml.lock"
# register-only probe (no transition): the mutant must MINT the write-less
# row -- the refusal was the only thing standing between strict adoption and
# row shape B.
LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  bash -c 'source "$1"; LEADV2_LANE_STATE_ADOPT_STRICT=1 lane_register "$2" lead "$3" spawning "$$"' \
  _ "$MUTDIR/lib/leadv2-lane-state.sh" MUT-9 "$REPO" >/dev/null 2>"$TMP/adopt.err"; MRC=$?
MROW="$(row_of "$YAML" MUT-9 2>/dev/null || printf 'null')"
if [[ "$MRC" -eq 0 ]] && ! grep -q 'refused: adoption found no reusable row' "$TMP/adopt.err" \
   && printf '%s' "$MROW" | python3 -c 'import sys,json; r=json.load(sys.stdin); sys.exit(0 if r and "writes" not in r and "writes_reason" not in r else 1)'; then
  pass "9-RED: refusal mutated out -> strict register mints a write-less row rc=0 -- suite can see its own red"
else
  fail "9-RED: mutant still refused or wrong shape (rc=$MRC row=$MROW) -- negative control proves nothing"
fi

# ── final count line ────────────────────────────────────────────────────────
printf '[TEST] %s: %d passed, %d failed\n' "test-lane-adopt-writeset-refusal" "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '[TEST] failures:\n'; printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
# bash-guard: allow
