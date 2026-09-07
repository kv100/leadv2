#!/usr/bin/env bash
# ARBITER-SCORING-DESIGN-01 step4 follow-up (Leadmain, 2026-09-07): fable has
# never won a real routing decision on its own since FABLE-RESTORE-01
# (2026-09-06/07) -- every real journal line carrying arm=fable to date is
# either an explicit pin (reason=explicit_requested_capable) or a refusal
# (requested_arm_incapable / not_in_allowed_arms). That is "no traffic yet",
# not "cannot win" -- and a week from now nobody could tell those two apart
# from the live corpus alone. This suite pins the mechanism down permanently:
# fable (cost=8) genuinely outranks opus (cost=9) on cheapest_capable when
# both are the only allowed candidates for a kind/size fable actually covers
# (plan/audit/review, standard/heavy) -- and, just as importantly, fable does
# NOT win a kind it has no capability_matrix cell for (code) even when it is
# the only allowed arm -- the kinds restriction is real, not a rubber stamp.
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${ROOT}/scripts/lib/leadv2-route-arbiter.sh"
ROUTING="${ROOT}/config/leadv2-routing.yaml"
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

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

HEALTHY='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}'

run(){ # <descriptor-json>
  local descriptor="$1"
  rm -f "$TMP/state"
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$HEALTHY" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$descriptor"
}
tok(){ printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/.*=//'; }

# ── positive: fable is cheapest among the ALLOWED candidates, no explicit pin ──
# allowed_arms restricts the pool to [fable, opus] -- both cover kind=plan,
# size=heavy -- so cost order alone (fable=8 < opus=9) must pick fable, and
# because no `requested_arm` field is set, reason must be cheapest_capable,
# never explicit_requested_capable. This is the exact construction Leadmain
# reviewed live on 2026-09-07 (rc=0, arm=fable, reason=cheapest_capable).
set +e
out="$(run '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","allowed_arms":["fable","opus"],"task":"fable-pos"}')"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(tok "$out" arm)" == "fable" && "$(tok "$out" reason)" == "cheapest_capable" ]]; then
  pass 'fable wins kind=plan/heavy over opus on cost (8<9) among allowed candidates, reason=cheapest_capable (not a pin)'
else
  fail "positive rc=$rc out=$out"
fi

# ── negative control: fable has no capability_matrix cell for kind=code ────────
# Even as the ONLY allowed arm, fable must be refused for a kind outside its
# declared kinds (plan/audit/review) -- proves the kinds gate is enforced, not
# a rubber stamp that lets fable through whenever it's the sole candidate.
set +e
out="$(run '{"kind":"code","size":"heavy","complexity":"standard","complexity_source":"heuristic","allowed_arms":["fable"],"task":"fable-nc"}')"
rc=$?
set -e
if [[ ${rc} -eq 68 && "$(tok "$out" arm)" == "refuse" && "$(tok "$out" reason)" == "no_capable_cell" ]]; then
  pass 'NC: fable alone-allowed is still refused for kind=code (no matrix cell), rc=68 reason=no_capable_cell -- kinds gate is real'
else
  fail "negative control rc=$rc out=$out"
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
