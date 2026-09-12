#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-route-arbiter leadv2-cost-actuals
# test-arbiter-uses-observed-cost.sh — ARBITER-LEARNS-WHAT-WORK-COSTS-01
# (founder order 2026-09-12, row 4c06462a1a71).
#
# Proves the arbiter ROUTES FROM OBSERVED COST, not from the static matrix
# alone: the SAME task descriptor (kind=code size=standard) must land on
# DIFFERENT arms when the recorded cost_actual history differs —
#   no history            -> cheapest matrix arm (glm-flash 0.33), the exact
#                            pre-2026-09-12 behaviour, cost_actuals=no_history
#   glm-flash burns rounds -> same descriptor moves to glm (1.0): 0.33*4 > 1
#   the history names glm  -> glm-flash is SPARED (history damns only the arm
#                            it names) — a cheap arm with a clean record is
#                            not re-priced by another arm's failures
#   first-pass history     -> glm-flash stays (0.33*1): observed cheapness is
#                            kept, not assumed
# plus the boundaries: OBS_MIN_ROWS (2 rows are no basis), the kill switch
# (LEADV2_ARBITER_OBSERVED_COST=0 restores the matrix-alone line byte-for-byte
# in behaviour), journal-unavailable (unknown, never zero), the protected path
# (a protected:false arm stays EXCLUDED no matter how its price moves), the
# WRITER half (lib/leadv2-cost-actuals.sh derives rounds/arm from the same
# journal and refuses rows for never-spawned sigs), and a before/after pair
# against the pre-feature arbiter for the same history.
#
# Every case drives the REAL sourced function under bash -c (never an
# emulation), with only the ambient probes stubbed: quota, freepool gate,
# state file, failure ledger and the events journal (the same
# ROUTE_ARBITER_EVENTS_JOURNAL seam the failure-memory and forecast suites
# stub). Negative control lives in nc-arbiter-observed-cost.sh and reaches
# this suite through LEADV2_TEST_ARBITER_BIN.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# LEADV2_TEST_ARBITER_BIN: injection seam for negative controls (nc-*.sh).
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
LAST_ASSERT="(none yet)"
SUMMARY_PRINTED=0
_suite_abort_report() {
  local rc=$?
  [[ ${SUMMARY_PRINTED} -eq 1 ]] && return 0
  printf 'ABORT: suite exited rc=%s WITHOUT a summary after %s assertion(s); last completed: %s\n' \
    "${rc}" "$((PASS+FAIL))" "${LAST_ASSERT}" >&2
}
trap _suite_abort_report EXIT
pass(){ LAST_ASSERT="$1"; printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ LAST_ASSERT="$1"; printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
# Every run self-identifies WHICH arbiter bytes it sourced (W1 round-2 lesson:
# a green summary over the wrong tree is worse than red).
printf 'arbiter_under_test=%s sha256=%s\n' "$ARBITER" "$(shasum -a 256 "$ARBITER" 2>/dev/null | awk '{print substr($1,1,16)}')"

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

# Minimal two-arm matrix, production-faithful prices (glm-flash 0.33 vs glm 1,
# config/leadv2-routing.yaml capability_matrix): the ONLY economics under test
# is the observed-rounds multiplier, so the fixture isolates exactly that.
cat >"$TMP/routing.yaml" <<'EOF'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  observed_cost: {min_rows: 3}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  capability_matrix:
    - {arm: glm-flash, provider: glm, model: glm-5.3-flash, cost: 0.33, kinds: [code], sizes: [standard], protected: false, capability: 3}
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF

quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
Q="$(quota 13 20 45)"
: >"$TMP/ledger.jsonl"

# run <descriptor> <events-journal> [extra env as KEY=VAL...] -> full decision line
run(){
  local desc="$1" journal="$2"; shift 2
  rm -f "$TMP/state"
  env "$@" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$journal" \
    ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" \
    ROUTE_TEST_QUOTA="$Q" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$desc" 2>&1
}
# hist <journal> <arm> <class> <rounds...> — write one cost_actual row per
# DISTINCT task (the reader dedupes by task keeping max rounds; distinct tasks
# make the mean exact).
hist(){
  local journal="$1" arm="$2" cls="$3"; shift 3
  local i=0 r
  for r in "$@"; do
    i=$((i+1))
    printf '{"seq":%d,"ts":"2026-09-12T01:00:00Z","repo":"t","task":"hist%d","arm":"%s","kind":"cost_actual","detail":"class=%s kind=code rounds=%d wall_s=600 terminal=dead cause=review_fail"}\n' \
      "$i" "$i" "$arm" "$cls" "$r" >>"$journal"
  done
}
arm_of(){ printf '%s\n' "$1" | grep -m1 -oE '^arm=[^[:space:]]+' | cut -d= -f2; }
token_of(){ printf '%s\n' "$1" | grep -oE 'cost_actuals=[^ ]*' | head -1; }

DESC='{"kind":"code","size":"standard","task":"aabbccdd"}'

# (1) No history: cheapest matrix arm, exactly today's behaviour, named.
: >"$TMP/ev-empty.jsonl"
out="$(run "$DESC" "$TMP/ev-empty.jsonl")"
if [[ "$(arm_of "$out")" == "glm-flash" && "$(token_of "$out")" == "cost_actuals=no_history" ]]; then
  pass "(1) no history -> matrix-cheapest arm=glm-flash, cost_actuals=no_history"
else
  fail "(1) no history: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (2) THE acceptance case: same task, glm-flash history of 4-round burns
# (n=4 >= min_rows) -> 0.33*4=1.32 > glm's 1.0 -> the arm MOVES to glm.
: >"$TMP/ev-burn.jsonl"; hist "$TMP/ev-burn.jsonl" glm-flash standard 4 4 4 4
out="$(run "$DESC" "$TMP/ev-burn.jsonl")"
if [[ "$(arm_of "$out")" == "glm" && "$(token_of "$out")" == "cost_actuals=standard/glm-flash:n=4,avg_rounds=4.00" ]]; then
  pass "(2) same task + glm-flash 4-round history -> arm=glm, priced token on the line"
else
  fail "(2) burn history: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (3) History naming GLM spares glm-flash: 1.0*4=4.0 vs clean 0.33 -> the
# cheap arm keeps the work. History damns only the arm it names.
: >"$TMP/ev-glm.jsonl"; hist "$TMP/ev-glm.jsonl" glm standard 4 4 4 4
out="$(run "$DESC" "$TMP/ev-glm.jsonl")"
if [[ "$(arm_of "$out")" == "glm-flash" && "$(token_of "$out")" == "cost_actuals=standard/glm:n=4,avg_rounds=4.00" ]]; then
  pass "(3) history names glm -> glm-flash spared (arm=glm-flash), glm priced"
else
  fail "(3) glm-named history: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (4) First-pass history keeps the cheap arm cheap: mean(1,1,1,2)=1.25 ->
# 0.33*1.25=0.41 < 1.0. Observed cheapness is kept, not assumed.
: >"$TMP/ev-first.jsonl"; hist "$TMP/ev-first.jsonl" glm-flash standard 1 1 1 2
out="$(run "$DESC" "$TMP/ev-first.jsonl")"
if [[ "$(arm_of "$out")" == "glm-flash" && "$(token_of "$out")" == "cost_actuals=standard/glm-flash:n=4,avg_rounds=1.25" ]]; then
  pass "(4) first-pass history (avg 1.25) -> glm-flash stays, priced at the observed mean"
else
  fail "(4) first-pass history: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (5) OBS_MIN_ROWS: two 4-round rows are no basis (FORECAST_MIN_ROWS rule) —
# the arm must NOT move, and the line must say matrix_only (rows exist, no
# candidate had enough).
: >"$TMP/ev-thin.jsonl"; hist "$TMP/ev-thin.jsonl" glm-flash standard 4 4
out="$(run "$DESC" "$TMP/ev-thin.jsonl")"
if [[ "$(arm_of "$out")" == "glm-flash" && "$(token_of "$out")" == "cost_actuals=matrix_only" ]]; then
  pass "(5) 2 rows < min_rows=3 -> no re-pricing (arm=glm-flash), cost_actuals=matrix_only"
else
  fail "(5) thin history: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (6) Kill switch: damning history + LEADV2_ARBITER_OBSERVED_COST=0 -> the
# matrix-alone routing AND no cost_actuals token at all.
out="$(run "$DESC" "$TMP/ev-burn.jsonl" LEADV2_ARBITER_OBSERVED_COST=0)"
if [[ "$(arm_of "$out")" == "glm-flash" && -z "$(token_of "$out")" ]]; then
  pass "(6) kill switch -> matrix-alone routing (arm=glm-flash), token absent"
else
  fail "(6) kill switch: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (7) Journal unavailable is unknown, never zero: no re-pricing, but the line
# says it could not look.
out="$(run "$DESC" "$TMP/ev-missing.jsonl")"
if [[ "$(arm_of "$out")" == "glm-flash" && "$(token_of "$out")" == "cost_actuals=unavailable" ]]; then
  pass "(7) unreadable journal -> arm=glm-flash, cost_actuals=unavailable"
else
  fail "(7) unavailable journal: got arm=$(arm_of "$out") $(token_of "$out") out=[$out]"
fi

# (8) Protection is upstream of price: same damning glm-flash history, but the
# descriptor is protected (safety-ish lane) — glm-flash is protected:false and
# must stay EXCLUDED exactly as before, winner glm, refusal stage named.
PDESC='{"kind":"code","size":"standard","protected":true,"task":"aabbccdd"}'
out="$(run "$PDESC" "$TMP/ev-burn.jsonl")"
if [[ "$(arm_of "$out")" == "glm" && "$(printf '%s\n' "$out" | grep -q 'arm_excluded=.*glm-flash' && printf yes)" == "yes" ]]; then
  pass "(8) protected descriptor: glm-flash stays excluded under its own damning history"
else
  fail "(8) protected path: got arm=$(arm_of "$out") out=[$out]"
fi

# (9) WRITER half: lib/leadv2-cost-actuals.sh derives rounds/arm/wall from the
# same journal (last spawn's arm, spawn count, first-spawn wall) and emits one
# cost_actual row through the emitter; a sig with NO spawns gets NO row.
mkdir -p "$TMP/evdir"
cat >"$TMP/evdir/wrepo.jsonl" <<'EOF'
{"seq":1,"ts":"2026-09-12T01:00:00Z","repo":"wrepo","task":"cafe0001","arm":"glm-flash","kind":"worker_spawned"}
{"seq":2,"ts":"2026-09-12T01:10:00Z","repo":"wrepo","task":"deadbeef","arm":"glm","kind":"worker_spawned"}
{"seq":3,"ts":"2026-09-12T01:20:00Z","repo":"wrepo","task":"cafe0001","arm":"glm","kind":"worker_spawned"}
EOF
cat >"$TMP/fake-emitter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LEADV2_NC_EMIT_CAPTURE"
exit 0
EOF
chmod +x "$TMP/fake-emitter.sh"
: >"$TMP/emit.log"
wout="$(LEADV2_NC_EMIT_CAPTURE="$TMP/emit.log" LEADV2_EVENT_LOG_DIR="$TMP/evdir" \
  LEADV2_COST_ACTUAL_EVENT_BIN="$TMP/fake-emitter.sh" \
  bash -c 'source "$0"; leadv2_cost_actual_record wrepo cafe0001 dead review_fail standard code glm-5.3' \
  "${SCRIPTS_DIR}/lib/leadv2-cost-actuals.sh")"
emit_row="$(cat "$TMP/emit.log")"
# 2 spawns for cafe0001, last on arm glm -> rounds=2, arm=glm; wall is
# first-spawn->now (>=0, monotone sanity only); stdout lands the decision line.
if printf '%s' "$emit_row" | grep -q -- '--kind cost_actual --task cafe0001 --arm glm' \
   && printf '%s' "$emit_row" | grep -q 'rounds=2' \
   && printf '%s' "$emit_row" | grep -q 'class=standard' \
   && printf '%s' "$wout" | grep -q 'cost_actual_recorded task=cafe0001 arm=glm' \
   && printf '%s' "$wout" | grep -q 'wall_s='; then
  pass "(9) writer: 2 spawns -> rounds=2, arm=last spawn (glm), class stamped, decision line printed"
else
  fail "(9) writer: emit=[$emit_row] stdout=[$wout]"
fi
: >"$TMP/emit.log"
wout="$(LEADV2_NC_EMIT_CAPTURE="$TMP/emit.log" LEADV2_EVENT_LOG_DIR="$TMP/evdir" \
  LEADV2_COST_ACTUAL_EVENT_BIN="$TMP/fake-emitter.sh" \
  bash -c 'source "$0"; leadv2_cost_actual_record wrepo nosuchsig refused writeset_conflict standard code glm-5.3' \
  "${SCRIPTS_DIR}/lib/leadv2-cost-actuals.sh")"
if [[ -z "$(cat "$TMP/emit.log")" && -z "$wout" ]]; then
  pass "(10) writer: never-spawned sig -> no row, no line (nothing burned on an arm)"
else
  fail "(10) writer on unspawned sig: emit=[$(cat "$TMP/emit.log")] stdout=[$wout]"
fi

# (11) Real production matrix, before/after in one artifact: the SAME
# descriptor against the REAL config matrix. Production TODAY picks glm for
# standard/code via capability_fit (glm-flash is fit-demoted there, a floor
# older than this row), so the observable production move is GLM's OWN burn
# history re-pricing it 1.0*4=4.0 above codex's 3.0: glm -> codex, reason
# flipping capability_fit -> cheapest_capable, glm named in the priced token.
# This is the founder-readable route-line pair.
if [[ -r "$ROUTING" && "$ARBITER" == "${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh" ]]; then
  : >"$TMP/ev-prod.jsonl"
  prod_before="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/ev-prod.jsonl" \
    ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" ROUTE_TEST_QUOTA="$Q" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$DESC" 2>&1)"
  hist "$TMP/ev-prod.jsonl" glm standard 4 4 4 4
  prod_after="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/ev-prod.jsonl" \
    ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" ROUTE_TEST_QUOTA="$Q" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$DESC" 2>&1)"
  printf 'PROD-BEFORE: %s\n' "$(printf '%s\n' "$prod_before" | grep -m1 '^arm=')"
  printf 'PROD-AFTER:  %s\n' "$(printf '%s\n' "$prod_after" | grep -m1 '^arm=')"
  if [[ "$(arm_of "$prod_before")" == "glm" && "$(arm_of "$prod_after")" == "codex" \
     && "$(token_of "$prod_after")" == "cost_actuals=standard/glm:n=4,avg_rounds=4.00" ]]; then
    pass "(11) production matrix: same descriptor glm -> codex once glm's burn history exists"
  else
    fail "(11) production matrix: before=$(arm_of "$prod_before") after=$(arm_of "$prod_after") tok=$(token_of "$prod_after")"
  fi
else
  printf 'PROD-PAIR: skipped (mutant arbiter under test or routing unreadable)\n'
fi

# (12) Old-arbiter control: the PRE-FEATURE arbiter, given the SAME burn
# history, must still pick glm-flash — the estimate-blind behaviour this row
# exists to end. If it moves too, the suite is proving nothing about this diff.
# Anchored on the commit that ADDED lib/leadv2-cost-actuals.sh (its parent's
# arbiter is the last blind one), never on HEAD: HEAD carried the feature from
# the moment this row's diff landed, and a HEAD-anchored control rotted into a
# permanent red the day it was committed (case-12 red on a green feature,
# measured 2026-09-12). The add-commit anchor cannot rot by landing.
if command -v git >/dev/null 2>&1 \
   && git -C "${SCRIPTS_DIR}/../../.." rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _feat_rev="$(git -C "${SCRIPTS_DIR}/../../.." log -1 --format=%H --diff-filter=A \
    -- plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh 2>/dev/null)"
  git -C "${SCRIPTS_DIR}/../../.." show "${_feat_rev}^:plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh" >"$TMP/arbiter-head.sh" 2>/dev/null
  if [[ -s "$TMP/arbiter-head.sh" ]]; then
    old_out="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" \
      LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
      LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/ev-burn.jsonl" \
      ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" ROUTE_TEST_QUOTA="$Q" \
      bash -c 'source "$0"; route_arbiter worker "$1"' "$TMP/arbiter-head.sh" "$DESC" 2>&1)"
    printf 'PRE-FEATURE-ARBITER-ON-BURN-HISTORY: %s (rev=%s^)\n' "$(arm_of "$old_out")" "${_feat_rev:0:12}"
    if [[ "$(arm_of "$old_out")" == "glm-flash" ]]; then
      pass "(12) pre-feature arbiter on the same history still picks glm-flash (blind) — the delta is this diff"
    else
      fail "(12) pre-feature arbiter moved too (arm=$(arm_of "$old_out")) — history is leaking through something older"
    fi
  else
    printf 'PRE-FEATURE-ARBITER: skipped (git show produced nothing)\n'
  fi
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
