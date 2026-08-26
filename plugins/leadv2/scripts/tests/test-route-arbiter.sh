#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
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
run(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"; }

# (a) Codex capped: a capable non-Codex worker is selected, never parked.
out="$(run "$(quota 10 99 20)" 1 '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'arm=glm '* || "$out" == *'arm=sonnet '* ]]; then pass 'codex 99% routes to a capable non-codex arm'; else fail "codex 99% output=$out"; fi

# (b) all windows capped (and freepool health down) gives the honest refusal.
out="$(run "$(quota 99 99 99)" 1 '{"kind":"code","size":"standard"}' || true)"
if [[ "$out" == *'arm=refuse '* && "$out" == *'reason=all_arms_capped'* ]]; then pass 'all capped refuses all_arms_capped'; else fail "all capped output=$out"; fi

# (c) protected tasks cannot enter either untrusted arm.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"standard","protected":true}')"
chain="$(printf '%s\n' "$out" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
if [[ "$out" != *'arm=glm '* && "$out" != *'arm=freepool '* && ",${chain}," != *',glm,'* && ",${chain}," != *',freepool,'* ]]; then pass 'protected chain excludes glm and freepool'; else fail "protected output=$out"; fi

# (d) Anti-stickiness: fixed live readings still rotate equal-cost GLM/freepool.
rm -f "$TMP/state"
one="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"standard"}')"
two="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"standard"}')"
three="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"standard"}')"
arms="$(printf '%s\n%s\n%s\n' "$one" "$two" "$three" | sed -n 's/.*arm=\([^ ]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')"
if [[ "$arms" -gt 1 ]]; then pass 'anti-sticky identical tasks rotate arms'; else fail "anti-sticky outputs=$one | $two | $three"; fi

# (e) The dispatcher must retain the ladder when its arbiter file is absent.
REPO="$TMP/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
touch "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
WORKER="$TMP/worker.sh"; printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' >"$WORKER"; chmod +x "$WORKER"
out="$(CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$TMP/cache" LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_ROUTE_ARBITER_LIB="$TMP/deleted-route-arbiter.sh" GLM_POLICY_RESOLVER="$TMP/missing.py" bash "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 'fallback test' --kind code --protected --no-spawn --writes src/x.py 2>&1 || true)"
if [[ "$out" == *'arbiter_broken'* && "$out" == *'route_resolved'* ]]; then pass 'missing arbiter falls open to ladder and dispatch resolves'; else fail "fallback output=$out"; fi

# (f) T17 C1: an out-of-vocabulary --kind (the real caller values
# fanout-class-funnel/backlog-pump are now first-class matrix entries, so use
# a value no caller sends at all) normalizes to `code` and resolves an arm
# instead of refusing with no_capable_cell.
out="$(run "$(quota 10 20 20)" 0 '{"kind":"some-future-caller-kind","size":"standard"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'unknown --kind normalizes to code and resolves'; else fail "unknown-kind output=$out"; fi

# (f2) T17 C1: the real fanout-class-funnel/backlog-pump vocabulary resolves
# directly (matrix rows added in config/leadv2-routing.yaml), not merely via
# the code-normalization fallback above.
out="$(run "$(quota 10 20 20)" 0 '{"kind":"fanout-class-funnel","size":"bulk"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'fanout-class-funnel kind resolves an arm'; else fail "fanout-class-funnel output=$out"; fi
out="$(run "$(quota 10 20 20)" 0 '{"kind":"backlog-pump","size":"bulk"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'backlog-pump kind resolves an arm'; else fail "backlog-pump output=$out"; fi

# (g) T17 C3: a provider whose quota probe reports status != 'ok' must be
# fail-CLOSED (pessimistic, never selected as the "cheapest" arm) even though
# every OTHER capable provider looks worse on paper. freepool is disabled
# here (free_rc=1) so it cannot tie-break glm out of the picture on cost --
# without that, glm's own cost=1 vs freepool's cost=1 tie (broken by arm-name
# sort) would mask the mutation this case exists to catch. With freepool
# capped, glm competes against codex(20%)/claude(20%) only: if the broken
# probe were still scored optimistic (the pre-fix util()=0.0 on status!=ok),
# glm's cost=1 would win outright and this case would go red.
quota_broken_glm(){ python3 - "$1" "$2" <<'PY'
import json,sys
c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'error'},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
out="$(run "$(quota_broken_glm 20 20)" 1 '{"kind":"code","size":"standard"}')"
if [[ "$out" != *'arm=glm '* && "$out" == *'util_glm=unknown_capped'* ]]; then pass 'broken glm probe (status!=ok) is fail-closed, never selected'; else fail "broken-glm-probe output=$out"; fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
