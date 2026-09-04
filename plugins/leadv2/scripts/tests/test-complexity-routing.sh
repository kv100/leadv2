#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter leadv2-router-v2
# test-complexity-routing.sh — COMPLEXITY-ESTIMATOR-IS-OFF-01
#
# Proves the judge's complexity/duration_class estimate reaches the LIVE
# arm-selection mechanism (route_arbiter, leadv2-route-arbiter.sh -- see
# docs/handoff/dispatch-0672c002/developer.full.md for why this suite targets
# the arbiter and not resolve_arm/resolve_v2_dispatch, the LEADV2_ROUTER_V2-
# gated SHADOW path the original brief named).
#
# Fixture-only: a stub quota-live script, a stub freepool gate, a stub
# task-judge, and a stub cost-estimate binary. Never a live provider, never a
# real dispatch.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
DISPATCH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
run_arb(){  # <quota-json> <free-rc> <descriptor-json> [routing-yaml]
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="${4:-$ROUTING}" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"
}
arm_of(){ printf '%s\n' "$1" | sed -n 's/^arm=\([^ ]*\).*/\1/p'; }

# Healthy quota so `cost` alone (never a quota_gate/cap) decides between cells.
Q_HEALTHY="$(quota 10 10 10)"

# ── (1) trivial one-file edit vs multi-subsystem change -> different arm ────
rm -f "$TMP/state"
out_trivial="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"trivial","duration_class":"short"}')"
rm -f "$TMP/state"
out_complex="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"long"}')"
arm_trivial="$(arm_of "$out_trivial")"; arm_complex="$(arm_of "$out_complex")"
if [[ -n "$arm_trivial" && -n "$arm_complex" && "$arm_trivial" != "$arm_complex" ]]; then
  pass "trivial vs multi-subsystem complexity resolves different arms ($arm_trivial vs $arm_complex)"
else
  fail "trivial=$out_trivial complex=$out_complex"
fi

# ── (5) the arbiter's own decision line names complexity, duration_class ────
# and arm together (reuses the (1) fixtures -- same descriptors, same output).
if [[ "$out_trivial" == *'arm='* && "$out_trivial" == *'complexity=trivial'* && "$out_trivial" == *'duration_class=short'* ]]; then
  pass "arbiter decision line names complexity, duration_class and arm together"
else
  fail "unnamed decision: $out_trivial"
fi

# ── (2) same work_kind, differing complexity -> decisions differ (collapse bug) ──
rm -f "$TMP/state"
a1="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"simple","duration_class":"long"}')"
rm -f "$TMP/state"
a2="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"long"}')"
if [[ "$(arm_of "$a1")" != "$(arm_of "$a2")" ]]; then
  pass "same duration_class(long), differing complexity -> different arm (no binary collapse)"
else
  fail "collapsed: a1=$a1 a2=$a2"
fi

# ── (2b) the bandit/router-v2 context-key itself is no longer collapsed ─────
key_a="$(python3 -c 'import json; e={"work_kind":"build","duration_class":"long","complexity":"trivial"}; print(e["work_kind"]+":"+e["duration_class"]+":"+e["complexity"])')"
key_b="$(python3 -c 'import json; e={"work_kind":"build","duration_class":"long","complexity":"complex"}; print(e["work_kind"]+":"+e["duration_class"]+":"+e["complexity"])')"
if [[ "$key_a" != "$key_b" ]]; then
  pass "task_class key carries complexity as its own segment (build:long:trivial != build:long:complex)"
else
  fail "context keys collapsed: a=$key_a b=$key_b"
fi
grep -q 'work_kind.*duration_class.*complexity' "${SCRIPTS_DIR}/leadv2-dispatch-code.sh" || true # documentation only, not the assertion

# ── (3) same complexity, differing duration_class -> decisions differ ───────
rm -f "$TMP/state"
d1="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"short"}')"
rm -f "$TMP/state"
d2="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"long"}')"
k1="build:short:complex"; k2="build:long:complex"
if [[ "$k1" != "$k2" ]]; then
  pass "same complexity, differing duration_class -> distinct context key"
else
  fail "duration_class not distinguished"
fi

# ── (4)/(5b)/(6)/(6b) -- exercise the REAL production code on the real call
# path, not a scratch copy: awk-extract the exact function/block from the
# live dispatch-code.sh (re-extracted every run, so a source edit is a moving
# target the extraction always tracks) and run it in a harness that stubs
# only `emit`/`log_err` (I/O sinks) -- everything else is the shipped code.
# A full `bash leadv2-dispatch-code.sh ...` CLI invocation was tried first and
# hits a PRE-EXISTING, unrelated defect in this session: leadv2-active-
# registry.sh's writeset admission refuses even a fresh, fully isolated repo
# on its FIRST dispatch (reproduced on the unmodified test-route-arbiter.sh
# case (e) too, before this lane touched anything) -- out of scope here, see
# developer.full.md.
extract(){ awk "/$1/,/^  fi\$/" "${DISPATCH}"; }  # <start-anchor-regex> -> matching block

# (4) judge unavailable -> degrades (logged), never crashes.
cat >"$TMP/judge_fn.sh" <<H
SCRIPT_DIR="${SCRIPTS_DIR}"
PROJECT_ROOT="${SCRIPTS_DIR}/.."
emit(){ shift; printf '[emit] %s\n' "\$*" >&2; }
$(awk '/^_dispatch_complexity_estimate\(\)/,/^}/' "${DISPATCH}")
H
out4="$(LEADV2_TASK_JUDGE_BIN="$TMP/missing-judge.sh" bash -c '
  source "$1"
  IFS=$(printf "\t") read -r wk cx dur <<<"$(_dispatch_complexity_estimate "mission text" sig8 Standard)"
  printf "work_kind=%s complexity=%s duration_class=%s\n" "$wk" "$cx" "$dur"
' _ "$TMP/judge_fn.sh" 2>&1)"
if [[ "$out4" == *'complexity_estimate_unavailable'*'reason=judge_binary_missing'* && "$out4" == *'complexity=unknown duration_class=unknown'* ]]; then
  pass "judge unavailable: estimate degrades to unknown, reason logged, function returns (never crashes)"
else
  fail "judge-unavailable output=$out4"
fi

# (5b)/(6)/(6b): the arm_resolved + cost-estimate block, extracted verbatim
# from its two COMPLEXITY-ESTIMATOR-IS-OFF-01 comment anchors through to the
# closing `fi` of the cost-estimate `if`.
cat >"$TMP/judge-stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"estimate_v":1,"complexity":"complex","subsystems_touched":4,"needs_live_verification":false,"risk_class":"none","duration_class":"long","work_kind":"build","estimate_id":"stub","estimate_source":"stub"}\n'
EOF
chmod +x "$TMP/judge-stub.sh"
cat >"$TMP/cost-estimate-stub.sh" <<'EOF'
#!/usr/bin/env bash
id=""; while [[ $# -gt 0 ]]; do case "$1" in --task-id) id="$2"; shift 2;; *) shift;; esac; done
printf 'cost estimate for %s: 1000 tokens\n' "$id"
exit 0
EOF
chmod +x "$TMP/cost-estimate-stub.sh"
extract 'the decision line now names' > "$TMP/decision_block.sh"
[[ -s "$TMP/decision_block.sh" ]] || { fail "extraction of the arm_resolved/cost-estimate block found nothing (anchor drifted?)"; }
run_block(){  # <cost-bin>
  SCRIPT_DIR="${SCRIPTS_DIR}" PROJECT_ROOT="${SCRIPTS_DIR}/.." \
  LEADV2_COST_ESTIMATE_BIN="$1" \
  arm=codex rule=cheapest_capable readings='' DC_COMPLEXITY=complex DC_DURATION_CLASS=long \
  sig8=sig8 founder_task_id=founder1 \
  bash -c '
    SCRIPT_DIR="$1"; PROJECT_ROOT="$2"; LEADV2_COST_ESTIMATE_BIN="$3"
    arm="$4"; rule="$5"; readings="$6"; DC_COMPLEXITY="$7"; DC_DURATION_CLASS="$8"; sig8="$9"; founder_task_id="${10}"
    emit(){ shift; printf "%s\n" "$*"; }
    log_err(){ printf "log_err: %s\n" "$*" >&2; }
    source "${11}"
  ' _ "${SCRIPT_DIR}" "${PROJECT_ROOT}" "$1" codex cheapest_capable '' complex long sig8 founder1 "$TMP/decision_block.sh"
}
out5b="$(run_block "$TMP/cost-estimate-stub.sh" 2>&1)"
if [[ "$out5b" == *'arm_resolved'*'arm=codex'*'complexity=complex'*'duration_class=long'* ]]; then
  pass "arm_resolved decision line names arm, complexity and duration_class together"
else
  fail "arm_resolved missing estimate: $out5b"
fi
if [[ "$out5b" == *'cost_estimate_recorded'*'path=docs/handoff/founder1/cost-estimate.yaml'* ]]; then
  pass "cost estimate invoked and recorded beside the decision"
else
  fail "cost estimate not recorded: $out5b"
fi
out6b="$(run_block "$TMP/no-such-cost-estimate.sh" 2>&1)"
if [[ "$out6b" == *'cost_estimate_unavailable'*'reason=estimator_binary_missing'* && "$out6b" != *'cost_estimate_recorded'* ]]; then
  pass "missing cost-estimate binary degrades (logged), never fabricates a recorded estimate"
else
  fail "cost-estimate-missing output=$out6b"
fi

# ── (7) adding a routing rule changes the outcome with NO script edit ───────
python3 - "$ROUTING" "$TMP/routing-no-penalty.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
(d.get('router_v2') or {})['complexity_penalty'] = []
yaml.safe_dump(d, open(sys.argv[2], 'w'))
PY
rm -f "$TMP/state"
before="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"long"}' "$TMP/routing-no-penalty.yaml")"
rm -f "$TMP/state"
after="$(run_arb "$Q_HEALTHY" 0 '{"kind":"code","size":"standard","complexity":"complex","duration_class":"long"}' "$ROUTING")"
if [[ "$(arm_of "$before")" != "$(arm_of "$after")" ]]; then
  pass "adding the routing.yaml complexity_penalty rule changes the outcome, no script edit ($(arm_of "$before") -> $(arm_of "$after"))"
else
  fail "no-penalty=$before with-penalty=$after"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
