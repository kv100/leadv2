#!/usr/bin/env bash
# ENV-PIN-SILENTLY-BEATS-THE-ARBITER-01 (founder 2026-09-11: "always decide,
# never hard-pin"): think_model() consults the arbiter FIRST and a non-empty
# verdict is FINAL. LEADV2_THINK_MODEL is only the fail-open candidate; the
# last resort is journalled as such. Every row carries chosen_by=<arbiter|
# env_fallback|last_resort> and the token env_pin is never emitted again.
# Hermeticity: fixture routing matrix + cap yaml in this suite's tmpdir, a
# stubbed quota reader (LEADV2_ROUTE_ARBITER_QUOTA_LIVE), hermetic HOME, and
# a redirected census sink — no live quota, no live config, no real-state
# writes. LEADV2_TEST_ROUTER exists ONLY so nc-think-model-arbiter-wins.sh
# can point this suite at a mutated scratch copy; the default is the real
# router (do NOT stub the router here — it is the thing under test).
# run-all-triggers: leadv2-router.sh leadv2-think-model.sh model-capability.yaml leadv2-routing.yaml leadv2-route-arbiter.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTER="${LEADV2_TEST_ROUTER:-$SCRIPTS_DIR/leadv2-router.sh}"
REAL_HOME="$HOME"
# case 7 compares the real census sink's stat before/after — capture it BEFORE
# the first router call mints any row.
_sink_stat(){ { stat -f '%m %z' "$1" 2>/dev/null || stat -c '%Y %s' "$1" 2>/dev/null; } || echo absent; }
REAL_SINK="$REAL_HOME/.claude/leadv2-state/leadv2/think-model-decisions.log"
REAL_SINK_BEFORE="$(_sink_stat "$REAL_SINK")"
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/test-think-model-arbiter-wins.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
LAST_ASSERT="(none yet -- died before the first assertion)"
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

# Hermetic HOME + every shared-state seam redirected: census sink, arbiter
# ledger/decisions/events/state. Nothing under the real ~/.claude may be
# touched (asserted by case 7).
mkdir -p "$TMP/home"
export HOME="$TMP/home"
export LEADV2_THINK_DECISIONS_FILE="$TMP/think-decisions.log"
export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh"
export LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh"
export LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-think"
export LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/decisions.jsonl"
export LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl"
export LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl"

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-1}"
EOF
cat >"$TMP/dead.sh" <<'EOF'
#!/usr/bin/env bash
echo "probe exploded" >&2
exit 9
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh" "$TMP/dead.sh"

# Fixture routing matrix: codex (cost 3) vs fable (cost 8), both covering
# plan/review/audit at standard+heavy — the choice is forced by quota, so the
# arbiter's cheapest_capable answer is codex under healthy windows and the
# suite cannot flip on a live-config edit.
ROUTING_YAML="$TMP/routing.yaml"
cat >"$ROUTING_YAML" <<'EOF'
router_v2:
  quota_ceilings:
    codex:  { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  capability_matrix:
    - { arm: codex, provider: codex, model: gpt-fixture, tier: volume, cost: 3, kinds: [plan, review, audit], sizes: [standard, heavy], tags: [review], review: true, protected: true, capability: 4 }
    - { arm: fable, provider: claude, model: fable, tier: high, cost: 8, kinds: [plan, review, audit], sizes: [standard, heavy], tags: [architecture], review: true, protected: true, capability: 4 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - { kinds: [plan, audit, review], effort: high }
    - { default: true, effort: medium }
EOF
MISSING_ROUTING="$TMP/no-such-routing.yaml"   # deliberately never created

CAP_YAML="$TMP/cap.yaml"
cat >"$CAP_YAML" <<'EOF'
codex:
  model_id: gpt-fixture
fable:
  model_id: claude-fable-fixture
think_stakes:
  default_class: heavy
  classes:
    heavy:     { size: heavy, complexity: complex, tier_floor: none }
    strategic: { size: heavy, complexity: complex, tier_floor: none }
EOF
# Kill-switch fixture: codex marked unavailable, fable free.
CAP_NO_CODEX="$TMP/cap-no-codex.yaml"
cat >"$CAP_NO_CODEX" <<'EOF'
codex:
  unavailable: true
fable:
  model_id: claude-fable-fixture
think_stakes:
  default_class: heavy
  classes:
    heavy:     { size: heavy, complexity: complex, tier_floor: none }
    strategic: { size: heavy, complexity: complex, tier_floor: none }
EOF

# Same quota-shape helper as test-think-through-arbiter.sh: <glm%> <codex%>
# <claude%>. Codex 20 / claude 20 sits far under every fixture ceiling.
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
HEALTHY="$(quota 10 20 20)"

# run_think <pin:'-'> <routing> <cap-yaml> <live-reader> [think-model args...]
# Never inherits ambient think env (a lane shell exports LEADV2_THINK_MODEL
# from dispatch-code; every case sets it explicitly or unsets it).
run_think(){
  local pin="$1" rtg="$2" cap="$3" live="$4"; shift 4
  local cmd=(env -u LEADV2_THINK_MODEL -u LEADV2_THINK_ROLE -u LEADV2_THINK_CLASS \
             -u LEADV2_THINK_TASK_ID -u LEADV2_TASK_ID \
             LEADV2_ROUTE_ARBITER_ROUTING_YAML="$rtg" \
             LEADV2_MODEL_CAPABILITY_YAML="$cap" \
             LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$live" \
             ROUTE_TEST_QUOTA="$HEALTHY" ROUTE_TEST_FREE_RC=1)
  [[ "$pin" != "-" ]] && cmd+=(LEADV2_THINK_MODEL="$pin")
  "${cmd[@]}" bash "$ROUTER" think-model "$@" 2>"$TMP/stderr.log"
}
last_row(){ tail -1 "$LEADV2_THINK_DECISIONS_FILE" 2>/dev/null || true; }

# ── case 1: healthy quota, env unset -> arbiter's arm, arbiter's reason ─────
out="$(run_think - "$ROUTING_YAML" "$CAP_YAML" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" == "codex" ]] && grep -q 'reason=arbiter_cheapest_capable' <<<"$row" \
   && grep -q 'chosen_by=arbiter' <<<"$row"; then
  pass "case1: arbiter decides (codex, reason=arbiter_cheapest_capable, chosen_by=arbiter)"
else
  fail "case1: expected codex/arbiter_cheapest_capable/chosen_by=arbiter, got '$out' row='$row'"
fi

# ── case 2 (THE ROW): healthy quota, env=fable -> arbiter STILL wins ────────
out="$(run_think fable "$ROUTING_YAML" "$CAP_YAML" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" == "codex" && "$row" == *"chosen_by=arbiter"* ]]; then
  pass "case2: env is not a pin — LEADV2_THINK_MODEL=fable still returns the arbiter's codex"
else
  fail "case2: env pin outranked the arbiter: out='$out' row='$row'"
fi
envpin_count="$(grep -c 'env_pin' "$LEADV2_THINK_DECISIONS_FILE" 2>/dev/null || true)"
if [[ "${envpin_count:-0}" -eq 0 ]]; then
  pass "case2: census rows contain zero env_pin tokens"
else
  fail "case2: env_pin still emitted (${envpin_count} rows)"
fi

# ── case 3: arbiter has no verdict (routing yaml missing) + env=fable ───────
out="$(run_think fable "$MISSING_ROUTING" "$CAP_YAML" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" == "fable" ]] && grep -q 'reason=fail_open_env_candidate_think_config_unreadable' <<<"$row" \
   && grep -q 'chosen_by=env_fallback' <<<"$row"; then
  pass "case3: no verdict -> env candidate fable, journalled env_fallback with the arbiter's why"
else
  fail "case3: expected fable/fail_open_env_candidate_think_config_unreadable/env_fallback, got '$out' row='$row'"
fi

# ── case 3b: dead quota reader (S5) + env=fable -> fail-open env candidate ──
out="$(run_think fable "$ROUTING_YAML" "$CAP_YAML" "$TMP/dead.sh" --role judge)"
row="$(last_row)"
if [[ "$out" == "fable" && "$row" == *" reason=fail_open_env_candidate_arbiter_fail_open_rc="* ]]; then
  pass "case3b: dead quota probe fails open to env candidate with arbiter_fail_open_rc reason"
else
  fail "case3b: expected fable/fail_open_env_candidate_arbiter_fail_open_rc=*, got '$out' row='$row'"
fi

# ── case 4: no verdict, env unset -> last resort, journalled as such ────────
out="$(run_think - "$MISSING_ROUTING" "$CAP_YAML" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" == "fable" && "$row" == *" reason=fail_open_last_resort_"* && "$row" == *" chosen_by=last_resort"* ]]; then
  pass "case4: no verdict, no env -> last-resort fable, journalled last_resort"
else
  fail "case4: expected fable/fail_open_last_resort_*/chosen_by=last_resort, got '$out' row='$row'"
fi

# ── case 5a: kill switch beats the arbiter (codex unavailable, still cheapest)
out="$(run_think codex "$ROUTING_YAML" "$CAP_NO_CODEX" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" != "codex" && "$out" == "fable" && "$row" == *" chosen_by=arbiter"* ]]; then
  pass "case5a: kill-switched codex excluded even though arbiter+env both favour it (fable, chosen_by=arbiter)"
else
  fail "case5a: kill switch not binding: out='$out' row='$row'"
fi

# ── case 5b: kill switch beats the env fallback too ─────────────────────────
out="$(run_think codex "$MISSING_ROUTING" "$CAP_NO_CODEX" "$TMP/live.sh" --role judge)"
row="$(last_row)"
if [[ "$out" != "codex" && "$out" == "fable" && "$row" == *" chosen_by=env_fallback"* ]]; then
  pass "case5b: env candidate codex is kill-switch-checked on the fallback rung (fable, chosen_by=env_fallback)"
else
  fail "case5b: dead env candidate resurrected: out='$out' row='$row'"
fi

# ── case 6: every role takes the same path, none carries its own literal ────
role_fail=0
for role in default judge diagnose plan architect learn; do
  o="$(run_think fable "$ROUTING_YAML" "$CAP_YAML" "$TMP/live.sh" --role "$role")"
  r="$(last_row)"
  if [[ "$o" != "codex" || "$r" != *" chosen_by=arbiter"* ]]; then
    fail "case6: role '$role' env half: expected codex/chosen_by=arbiter, got '$o' row='$r'"
    role_fail=1
  fi
  o="$(run_think - "$MISSING_ROUTING" "$CAP_YAML" "$TMP/live.sh" --role "$role")"
  r="$(last_row)"
  if [[ "$o" != "fable" || "$r" != *" chosen_by=last_resort"* ]]; then
    fail "case6: role '$role' fail-open half: expected fable/chosen_by=last_resort, got '$o' row='$r'"
    role_fail=1
  fi
done
if [[ "$role_fail" -eq 0 ]]; then
  pass "case6: all six roles arbiter-decided under quota and last_resort on fail-open — no role literal"
fi

# ── case 7: hygiene — the real census sink was never touched ────────────────
if [[ ! -e "$HOME/.claude/leadv2-state/leadv2/think-model-decisions.log" ]] \
   && [[ ! -d "$HOME/.claude/leadv2-state" ]] \
   && [[ "$(_sink_stat "$REAL_SINK")" == "$REAL_SINK_BEFORE" ]]; then
  pass "case7: no census row outside the suite tmpdir (hermetic home clean, real sink untouched)"
else
  fail "case7: census write leaked: hermetic-home sink exists or real sink changed ($(_sink_stat "$REAL_SINK"))"
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: %s pass, %s fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
