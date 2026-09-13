#!/usr/bin/env bash
# changed-scope triggers, self-registered:
# run-all-triggers: leadv2-route-arbiter leadv2-arbiter-replay leadv2-cost-estimate leadv2-cost-actuals leadv2-dispatch-code leadv2-dispatch-product-close
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
ARBITER="${SCRIPTS}/lib/leadv2-route-arbiter.sh"
REPLAY="${SCRIPTS}/leadv2-arbiter-replay.py"
ESTIMATE="${SCRIPTS}/leadv2-cost-estimate.sh"
COST_LIB="${SCRIPTS}/lib/leadv2-cost-actuals.sh"
TMP="$(mktemp -d /private/tmp/arbiter-record-inputs.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/routing.yaml" <<'YAML'
router_v2:
  quota_ceilings: {glm: {work_pct: 90, review_pct: 90}, codex: {work_pct: 90, review_pct: 90}, claude: {work_pct: 90, review_pct: 90}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  capability_fit: {enabled: true}
  capability_matrix:
    - {arm: cheap, provider: glm, model: cheap, cost: 1, capability: 2, protected: true, sizes: [standard], kinds: [code]}
    - {arm: capable, provider: codex, model: capable, cost: 5, capability: 4, protected: true, sizes: [standard], kinds: [code]}
YAML
cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":10,"seven_day_pct":10}]}}'
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
: >"$TMP/events.jsonl"; : >"$TMP/ledger.jsonl"; : >"$TMP/decisions.jsonl"

out="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/decisions.jsonl" ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl" ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 bash "$ARBITER" worker '{"kind":"code","size":"standard","task":"record-fixture","complexity":"standard","duration_class":"long","complexity_source":"judge"}')"
if [[ "$out" == arm=capable\ * && "$out" == *'complexity=standard'* && "$out" == *'fit_bucket='* ]]; then
  pass 'arbiter success line carries the replay inputs'
else
  fail "unexpected arbiter decision: $out"
fi

if python3 - "$TMP/decisions.jsonl" <<'PY'
import json, sys
r=json.loads(open(sys.argv[1]).readline())
required=('record_schema_version','complexity','duration_class','req_eff','util_glm','reset_glm','fit_bucket','reset_urgency','cost_src','candidate_set','arm_excluded')
assert r.get('record_schema_version') == 2, r
assert all(k in r for k in required), sorted(r)
assert {c['arm'] for c in r['candidate_set']} == {'cheap','capable'}, r['candidate_set']
assert r['arm_excluded'].get('cheap') == 'price_ratio', r['arm_excluded']
PY
then
  pass 'schema-v2 record contains winner inputs, both candidates, and exclusion reasons'
else
  fail 'decision record omitted a replay input or candidate'
fi

replay_out="$(python3 "$REPLAY" "$TMP/decisions.jsonl" --complexity simple)"
if [[ "$replay_out" == *'original=capable replay=cheap'* && "$replay_out" == *'SUMMARY replayable=1 movement=1 old_schema_refused=0 malformed=0'* ]]; then
  pass 'complexity replay moves the recorded decision from capable to cheap'
else
  fail "replay did not produce its expected movement: $replay_out"
fi
printf '%s\n' '{"arm":"cheap"}' >"$TMP/old.jsonl"
set +e
old_out="$(python3 "$REPLAY" "$TMP/old.jsonl" --complexity simple 2>&1)"; old_rc=$?
set -e
if [[ $old_rc -eq 2 && "$old_out" == *'replayable=0 movement=0 old_schema_refused=1'* ]]; then
  pass 'replay refuses output-only schema-v1 rows'
else
  fail "old schema was accepted: rc=$old_rc out=$old_out"
fi

mkdir -p "$TMP/project/docs/handoff/founder-task"
if PROJECT_ROOT="$TMP/project" bash "$ESTIMATE" --task-id founder-task --main-model sonnet --dispatch-sig8 abc12345 >/dev/null 2>&1 \
  && grep -q '^  dispatch_sig8: abc12345$' "$TMP/project/docs/handoff/founder-task/cost-estimate.yaml"; then
  pass 'estimate records the dispatch signature used by its terminal actual'
else
  fail 'estimate did not record dispatch_sig8'
fi
mkdir -p "$TMP/event-dir"
printf '%s\n' '{"kind":"worker_spawned","task":"abc12345","arm":"cheap","ts":"2026-09-13T00:00:00Z"}' >"$TMP/event-dir/repo.jsonl"
cat >"$TMP/event.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$EVENT_CAPTURE"
EOF
chmod +x "$TMP/event.sh"
actual_out="$(LEADV2_EVENT_LOG_DIR="$TMP/event-dir" LEADV2_COST_ACTUAL_EVENT_BIN="$TMP/event.sh" EVENT_CAPTURE="$TMP/event-capture" bash -c 'source "$0"; leadv2_cost_actual_record repo abc12345 landed done standard code cheap 123 founder-task' "$COST_LIB")"
if [[ "$actual_out" == *'estimate_task_id=founder-task'* ]] && grep -q 'estimate_task_id=founder-task' "$TMP/event-capture"; then
  pass 'cost_actual carries the reciprocal estimate_task_id join key'
else
  fail "cost_actual join key absent: $actual_out"
fi

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
