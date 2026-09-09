#!/usr/bin/env bash
# W1-THINK-THROUGH-ARBITER-01: the thinking path goes through the route
# arbiter. Acceptance shape (brief, 2026-09-09):
#   1. a think role on a Light task and on a Heavy task get DIFFERENT arms,
#      and both think_model_resolved lines reach the journal;
#   2. without a LEADV2_THINK_MODEL pin the decision is the arbiter's, not
#      the constant fable;
#   3. (mutation, run by the lead via leadv2-mutation-control.sh) restoring
#      candidate="${LEADV2_THINK_MODEL:-fable}" inside think_model() reddens
#      the named cases below — light-mid-tier, quota-steered-light,
#      quota-steered-heavy and killswitch-floor-drop all read the arbiter's
#      answer, a hardcode answers fable to every one of them.
# run-all-triggers: leadv2-router.sh leadv2-think-model.sh model-capability.yaml leadv2-routing.yaml leadv2-route-arbiter.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTER="${SCRIPTS_DIR}/leadv2-router.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
JOURNAL="${SCRIPTS_DIR}/leadv2-journal.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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

# Hermetic HOME: the census sink, the arbiter ledger and the events journal
# all default under $HOME — none of them may touch the live tree from a suite.
mkdir -p "$TMP/home"
export HOME="$TMP/home"
export LEADV2_THINK_DECISIONS_FILE="$TMP/think-decisions.log"
export LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING"
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
chmod +x "$TMP/live.sh" "$TMP/free.sh"

# Same quota-shape helper as test-route-arbiter.sh: <glm%> <codex%> <claude%>.
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
# think <quota-json> [extra router args...] -> stdout = the resolved model
think(){
  local q="$1"; shift
  env -u LEADV2_THINK_MODEL -u LEADV2_THINK_ROLE -u LEADV2_THINK_CLASS \
      ROUTE_TEST_QUOTA="$q" ROUTE_TEST_FREE_RC="${ROUTE_TEST_FREE_RC:-1}" \
      bash "$ROUTER" think-model "$@" 2>"$TMP/stderr.log"
}
sink_lines(){ grep -h 'think_model_resolved' "$TMP/think-decisions.log" 2>/dev/null || true; }

HEALTHY="$(quota 10 20 20)"

# ── (1) Light vs Heavy: different arms, both journalled ──────────────────────
LIGHT_ARM="$(think "$HEALTHY" --class Light --role judge)"
HEAVY_ARM="$(think "$HEALTHY" --class Heavy --role judge)"
if [[ "$LIGHT_ARM" != "$HEAVY_ARM" && -n "$LIGHT_ARM" && -n "$HEAVY_ARM" ]]; then
  pass "light($LIGHT_ARM) != heavy($HEAVY_ARM) — stakes split the thinking hand"
else
  fail "light-vs-heavy gave identical/empty arms: light='$LIGHT_ARM' heavy='$HEAVY_ARM'"
fi
if sink_lines | grep -q "role=judge class=Light arm=${LIGHT_ARM} " \
   && sink_lines | grep -q "role=judge class=Heavy arm=${HEAVY_ARM} "; then
  pass "both think_model_resolved lines in the census sink (role, class, arm, model, reason)"
else
  fail "journal lines missing/incomplete: $(sink_lines | tail -2 | tr '\n' '|')"
fi

# ── (2) No pin: the ARBITER decides, not the constant fable ─────────────────
# (2a) Light must land on the mid claude tier the stakes data names —
#      sonnet (cost 5), NOT glm: the 2026-09-09 equivalence sample measured
#      glm vs fable at 6/10 strict verdict agreement, so the founder's
#      conditional ("prove match before defaulting to the cheap hand") keeps
#      the cheap hand out of the light DEFAULT pool. The pre-arbiter hardcode
#      answered fable to every call; this case reddens under it.
if [[ "$LIGHT_ARM" == "sonnet" ]]; then
  pass "light stakes pick the mid claude tier (sonnet; cheap hand excluded by equiv-sample)"
else
  fail "light auction expected sonnet, got '$LIGHT_ARM'"
fi
# (2b) Arbiter liveness via quota steering: the same Light call with claude
#      at 99% (every pooled arm over the ceiling) widens THROUGH the arbiter
#      to the cheapest capable arm outside the pool — glm. A hardcode answers
#      fable here, so this reddens under the mutation too.
STEERED="$(ROUTE_TEST_FREE_RC=1 think "$(quota 10 20 99)" --class Light --role judge)"
if [[ "$STEERED" == "glm" ]]; then
  pass "quota-steered light (claude 99%) widens through the arbiter: got '$STEERED'"
else
  fail "quota widening invisible: got '$STEERED' with claude at 99%"
fi
# (2d) Same degradation on the heavy stakes: floor arms capped -> the widened
#      pool is still an ARBITER decision (glm), not the constant fable.
STEERED_H="$(ROUTE_TEST_FREE_RC=1 think "$(quota 10 20 99)" --class Heavy --role judge)"
if [[ "$STEERED_H" == "glm" ]]; then
  pass "quota-steered heavy (claude 99%) widens through the arbiter: got '$STEERED_H'"
else
  fail "heavy quota widening invisible: got '$STEERED_H' with claude at 99%"
fi
# (2c) The arbiter's own decision record exists for the think call.
if grep -q '"subtype": *"think:judge"' "$TMP/decisions.jsonl" 2>/dev/null; then
  pass "arbiter decision row journalled with think subtype"
else
  fail "no think:judge row in arbiter decisions file"
fi

# ── (3) R6 compat: pin honored, kill switch still beats everything ──────────
PINNED="$(env LEADV2_THINK_MODEL=opus bash "$ROUTER" think-model 2>/dev/null)"
if [[ "$PINNED" == "opus" ]]; then
  pass "LEADV2_THINK_MODEL pin honored (opus)"
else
  fail "pin broken: got '$PINNED'"
fi
# fable kill-switched: the heavy pool must drop it and the arbiter must
# answer opus (kill switch filters the pool BEFORE the call).
cat >"$TMP/cap-no-fable.yaml" <<'EOF'
fable:
  unavailable: true
opus:
  role: think_fallback
think_stakes:
  default_class: heavy
  classes:
    light:     { size: standard, complexity: trivial }
    standard:  { size: standard, complexity: standard }
    heavy:     { size: heavy,    complexity: complex, tier_floor: high, provider: claude }
    strategic: { size: heavy,    complexity: complex, tier_floor: high, provider: claude }
EOF
NofABLE="$(env -u LEADV2_THINK_MODEL LEADV2_MODEL_CAPABILITY_YAML="$TMP/cap-no-fable.yaml" \
  ROUTE_TEST_QUOTA="$HEALTHY" bash "$ROUTER" think-model --class Heavy 2>/dev/null)"
if [[ "$NofABLE" == "opus" ]]; then
  pass "kill-switched fable drops from the arbiter pool (heavy -> opus)"
else
  fail "kill switch not filtering pool: got '$NofABLE'"
fi
# BOTH floor arms kill-switched: the floor is dropped, never a dead end —
# the free auction answers glm. The hardcode answers fable/opus, reddens here.
cat >"$TMP/cap-no-both.yaml" <<'EOF'
fable:
  unavailable: true
opus:
  unavailable: true
think_stakes:
  default_class: heavy
  classes:
    light:     { size: standard, complexity: trivial }
    standard:  { size: standard, complexity: standard }
    heavy:     { size: heavy,    complexity: complex, tier_floor: high, provider: claude }
    strategic: { size: heavy,    complexity: complex, tier_floor: high, provider: claude }
EOF
FLOORDROP="$(env -u LEADV2_THINK_MODEL LEADV2_MODEL_CAPABILITY_YAML="$TMP/cap-no-both.yaml" \
  ROUTE_TEST_QUOTA="$HEALTHY" bash "$ROUTER" think-model --class Heavy 2>/dev/null)"
if [[ "$FLOORDROP" == "glm" ]]; then
  pass "empty floor pool drops the floor, arbiter still answers (heavy -> glm)"
else
  fail "floor-drop broken: got '$FLOORDROP'"
fi

# ── (4) stdout purity: one line, one vocabulary token ────────────────────────
OUT_LINES="$(think "$HEALTHY" --class Light | wc -l | tr -d ' ')"
OUT_TOK="$(think "$HEALTHY" --class Light)"
if [[ "$OUT_LINES" -eq 1 && "$OUT_TOK" =~ ^(fable|opus|glm|sonnet|haiku|codex)$ ]]; then
  pass "stdout is exactly one arm token ('$OUT_TOK') — existing \$() captures unaffected"
else
  fail "stdout impure: lines=$OUT_LINES token='$OUT_TOK'"
fi

# ── (5) fail-open: a dead probe never stalls thinking ────────────────────────
cat >"$TMP/dead.sh" <<'EOF'
#!/usr/bin/env bash
echo "probe exploded" >&2
exit 9
EOF
chmod +x "$TMP/dead.sh"
FAILOPEN="$(env -u LEADV2_THINK_MODEL LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/dead.sh" \
  bash "$ROUTER" think-model 2>/dev/null)"
if [[ "$FAILOPEN" == "fable" || "$FAILOPEN" == "opus" ]]; then
  pass "dead quota probe fails open to the R6 ladder ($FAILOPEN)"
else
  fail "fail-open broken: got '$FAILOPEN'"
fi
if sink_lines | grep -q "reason=fail_open_legacy_arbiter_fail_open"; then
  pass "fail-open journalled with the arbiter reason token"
else
  fail "fail-open reason token missing from sink: $(sink_lines | tail -1)"
fi

# ── (6) test-context guard: no census row into the real sink from a suite ────
rm -rf "$TMP/home/.claude"
env -u LEADV2_THINK_DECISIONS_FILE LEADV2_TEST_CONTEXT=1 \
  ROUTE_TEST_QUOTA="$HEALTHY" bash "$ROUTER" think-model --class Light >/dev/null 2>"$TMP/guard.err"
if [[ ! -f "$TMP/home/.claude/leadv2-state/leadv2/think-model-decisions.log" ]] \
   && grep -q "test context: think census write skipped" "$TMP/guard.err"; then
  pass "test context refuses the real census sink (loudly)"
else
  fail "census guard leaked: file exists or no warning"
fi

# ── (7) lane journal surface: --task-id lands the line in the task journal ──
rm -rf "$TMP/root"; mkdir -p "$TMP/root"
env -u LEADV2_THINK_MODEL LEADV2_PROJECT_ROOT="$TMP/root" CLAUDE_PROJECT_ROOT="$TMP/root" \
  ROUTE_TEST_QUOTA="$HEALTHY" bash "$ROUTER" think-model --class Light --task-id THINKT1 >/dev/null 2>&1
JPATH="$(env LEADV2_PROJECT_ROOT="$TMP/root" CLAUDE_PROJECT_ROOT="$TMP/root" bash "$JOURNAL" path THINKT1 2>/dev/null || true)"
if [[ -n "${JPATH:-}" && -f "$JPATH" ]] && grep -q 'think_model_resolved' "$JPATH"; then
  pass "task-scoped call journals think_model_resolved into the lane journal"
else
  fail "lane journal line missing (path='${JPATH:-<empty>}')"
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: %s pass, %s fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
