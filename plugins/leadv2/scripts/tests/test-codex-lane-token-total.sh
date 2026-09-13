#!/usr/bin/env bash
# run-all-triggers: leadv2-cost-actuals.sh leadv2-cost-actuals leadv2-dispatch-code.sh leadv2-dispatch-code
# tests/test-codex-lane-token-total.sh — CODEX-LANES-PRODUCE-NO-TOKEN-READING-01
#
# Guards the codex half of the observed-cost loop: costs.yaml is a
# claude-subsession.sh artifact only, so a codex-armed lane never got a token
# reading (measured live 2026-09-14: 0/8 pure-codex dispatch dirs on
# leadv2+persona-engine ever produced one). This suite fixtures the join
# leadv2_lane_token_total now performs instead — arm-registered's
# `arm=codex handle=<jobId>` row -> the job's own threadId -> its rollout
# file's cumulative token_usage_record — without touching any real
# ~/.codex/sessions data, and separately guards leadv2_lane_token_reason's
# named-reason split (no_seam_for_arm / costs_yaml_absent / turn_events_empty
# / parse_failed) so `tokens=-` is never silent about which case it is.
#
# Exit 0 = pass.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COST_LIB="${LEADV2_COST_ACTUALS_SH:-${SCRIPTS_ROOT}/lib/leadv2-cost-actuals.sh}"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "codex-tok")"
trap 'rm -rf "$TMP"' EXIT

if bash -n "$COST_LIB"; then pass "0 bash -n lib/leadv2-cost-actuals.sh"; else fail "0 bash -n lib/leadv2-cost-actuals.sh"; fi

# Fixture scaffolding shared by every case below.
ROOT="$TMP/lane-root"
HANDOFF="$ROOT/docs/handoff/dispatch-TESTSIG2"
STATE_ROOT="$TMP/codex-state"
CODEX_HOME="$TMP/codex-home"
mkdir -p "$HANDOFF" "$STATE_ROOT/wsA/jobs" "$CODEX_HOME/sessions/2026/09/14"

write_rollout() { # <path> <thread_id> <last_input> <last_output>
  local p="$1" tid="$2" inp="$3" outp="$4"
  cat > "$p" <<JSONL
{"type":"session_meta","payload":{"cwd":"/tmp/x"}}
{"type":"token_usage_record","payload":{"thread_id":"${tid}","usage":{"input_tokens":100,"output_tokens":10},"thread_token_usage":{"input_tokens":100,"output_tokens":10}}}
{"type":"token_usage_record","payload":{"thread_id":"${tid}","usage":{"input_tokens":$((inp-100)),"output_tokens":$((outp-10))},"thread_token_usage":{"input_tokens":${inp},"output_tokens":${outp}}}}
JSONL
}

# ---------------------------------------------------------------------------
# 1. happy path — one codex spawn, exact job->thread->rollout join, correct sum
# ---------------------------------------------------------------------------
TID1="11111111-1111-1111-1111-111111111111"
printf 'arm=codex handle=task-fake111-aaaaaa epoch=1789300000 LEAD_SESSION=x\n' > "$HANDOFF/arm-registered"
cat > "$STATE_ROOT/wsA/jobs/task-fake111-aaaaaa.json" <<JSON
{"id":"task-fake111-aaaaaa","status":"completed","threadId":"${TID1}","workspaceRoot":"/tmp/x"}
JSON
write_rollout "$CODEX_HOME/sessions/2026/09/14/rollout-2026-09-14T00-00-00-${TID1}.jsonl" "${TID1}" 900 90

TOK1="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" LEADV2_COST_FLUSH_SH=/bin/true \
  bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG2'")"
if [[ "$TOK1" == "990" ]]; then pass "1 codex rollout join sums input+output = 990"; else fail "1 codex rollout tokens='$TOK1' (want 990)"; fi

REASON1="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" \
  bash -c "source '$COST_LIB'; leadv2_lane_token_reason '$ROOT' 'TESTSIG2'")"
log "1b reason on a resolved total (informational, not asserted): $REASON1"

# ---------------------------------------------------------------------------
# 2. two codex spawns (re-dispatch) — sums across distinct threads
# ---------------------------------------------------------------------------
TID2="22222222-2222-2222-2222-222222222222"
printf 'arm=codex handle=task-fake222-bbbbbb epoch=1789300100 LEAD_SESSION=x\n' >> "$HANDOFF/arm-registered"
cat > "$STATE_ROOT/wsA/jobs/task-fake222-bbbbbb.json" <<JSON
{"id":"task-fake222-bbbbbb","status":"completed","threadId":"${TID2}","workspaceRoot":"/tmp/x"}
JSON
write_rollout "$CODEX_HOME/sessions/2026/09/14/rollout-2026-09-14T00-10-00-${TID2}.jsonl" "${TID2}" 300 30

TOK2="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" LEADV2_COST_FLUSH_SH=/bin/true \
  bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG2'")"
if [[ "$TOK2" == "1320" ]]; then pass "2 two codex spawns sum across threads = 1320 (990+330)"; else fail "2 tokens='$TOK2' (want 1320)"; fi

# ---------------------------------------------------------------------------
# 3. ambiguous rollout match (>1 file with the same thread suffix) -> never guess
# ---------------------------------------------------------------------------
ROOT3="$TMP/lane-root3"
HANDOFF3="$ROOT3/docs/handoff/dispatch-TESTSIG3"
mkdir -p "$HANDOFF3"
TID3="33333333-3333-3333-3333-333333333333"
printf 'arm=codex handle=task-fake333-cccccc epoch=1789300200 LEAD_SESSION=x\n' > "$HANDOFF3/arm-registered"
cat > "$STATE_ROOT/wsA/jobs/task-fake333-cccccc.json" <<JSON
{"id":"task-fake333-cccccc","status":"completed","threadId":"${TID3}","workspaceRoot":"/tmp/x"}
JSON
mkdir -p "$CODEX_HOME/sessions/2026/09/13"
write_rollout "$CODEX_HOME/sessions/2026/09/14/rollout-2026-09-14T01-00-00-${TID3}.jsonl" "${TID3}" 500 50
write_rollout "$CODEX_HOME/sessions/2026/09/13/rollout-2026-09-13T23-00-00-${TID3}.jsonl" "${TID3}" 500 50
TOK3="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" LEADV2_COST_FLUSH_SH=/bin/true \
  bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT3' 'TESTSIG3'")"
if [[ "$TOK3" == "-" ]]; then pass "3 ambiguous >1 rollout match -> '-' (never guesses a sibling's file)"; else fail "3 ambiguous tokens='$TOK3' (want -)"; fi

# ---------------------------------------------------------------------------
# 4. job json missing (rotated/never written) -> '-'
# ---------------------------------------------------------------------------
ROOT4="$TMP/lane-root4"
HANDOFF4="$ROOT4/docs/handoff/dispatch-TESTSIG4"
mkdir -p "$HANDOFF4"
printf 'arm=codex handle=task-ghost000-dddddd epoch=1789300300 LEAD_SESSION=x\n' > "$HANDOFF4/arm-registered"
TOK4="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" LEADV2_COST_FLUSH_SH=/bin/true \
  bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT4' 'TESTSIG4'")"
if [[ "$TOK4" == "-" ]]; then pass "4 no job json for handle -> '-'"; else fail "4 tokens='$TOK4' (want -)"; fi

# ---------------------------------------------------------------------------
# 5. leadv2_lane_token_reason — the four named reasons
# ---------------------------------------------------------------------------
ROOT5="$TMP/lane-root5"
mkdir -p "$ROOT5/docs/handoff/dispatch-NOSEAM"
R_NOSEAM="$(bash -c "source '$COST_LIB'; leadv2_lane_token_reason '$ROOT5' 'NOSEAM'")"
if [[ "$R_NOSEAM" == "no_seam_for_arm" ]]; then pass "5a no artifacts at all -> no_seam_for_arm"; else fail "5a reason='$R_NOSEAM'"; fi

R_COSTSABSENT="$(CODEX_GUARD_STATE_ROOT="$STATE_ROOT" CODEX_HOME="$CODEX_HOME" \
  bash -c "source '$COST_LIB'; leadv2_lane_token_reason '$ROOT4' 'TESTSIG4'")"
if [[ "$R_COSTSABSENT" == "costs_yaml_absent" ]]; then pass "5b codex handle but unresolved rollout -> costs_yaml_absent"; else fail "5b reason='$R_COSTSABSENT'"; fi

ROOT6="$TMP/lane-root6"
HANDOFF6="$ROOT6/docs/handoff/dispatch-TESTSIG6"
mkdir -p "$HANDOFF6"
printf '2026-09-14T00:00:00Z\tattempt-1\t44444444-4444-4444-4444-444444444444\n' > "$HANDOFF6/sessions.map"
R_TURNEMPTY="$(LEADV2_BURN_DB="$TMP/no-such.db" bash -c "source '$COST_LIB'; leadv2_lane_token_reason '$ROOT6' 'TESTSIG6'")"
if [[ "$R_TURNEMPTY" == "turn_events_empty" ]]; then pass "5c only sessions.map, no burn db -> turn_events_empty"; else fail "5c reason='$R_TURNEMPTY'"; fi

ROOT7="$TMP/lane-root7"
HANDOFF7="$ROOT7/docs/handoff/dispatch-TESTSIG7"
mkdir -p "$HANDOFF7"
printf 'not: a, token, line\n' > "$HANDOFF7/costs.yaml"
R_PARSEFAIL="$(LEADV2_COST_FLUSH_SH=/bin/true bash -c "source '$COST_LIB'; leadv2_lane_token_reason '$ROOT7' 'TESTSIG7'")"
if [[ "$R_PARSEFAIL" == "parse_failed" ]]; then pass "5d costs.yaml exists but unparseable -> parse_failed"; else fail "5d reason='$R_PARSEFAIL'"; fi

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
