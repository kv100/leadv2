#!/usr/bin/env bash
# Does the FIVE-HOUR window decide who gets the work, when the WEEKLY window
# says otherwise? Founder order 2026-09-16: weekly is the allocation key, the
# five-hour window is an admission constraint only.
set -uo pipefail
# Resolve the repo from THIS file, so a lane worktree probes ITS OWN arbiter,
# not main's. A hardcoded $HOME path would silently grade the wrong tree.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LV2="$(cd "$HERE/../../.." && pwd)"
ARBITER="$LV2/plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh"
[ -f "$ARBITER" ] || { echo "no arbiter at $ARBITER"; exit 2; }
TMP="$(mktemp -d /private/tmp/probe-arb5h.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "$TMP/free.sh" "$TMP/live.sh"

cat >"$TMP/routing.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 95, review_pct: 95}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  cost: {glm: 1.0, codex: 1.0, anthropic: null, freepool: 1.0}
  cost_unpriced_policy: matrix_median
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, protected: true, sizes: [standard], kinds: [code]}
YML

# glm : LOTS of weekly left (20% used), five-hour fresh and far from reset.
# codex: LITTLE weekly left (70% used), but a five-hour bucket that is mostly
#        unused and about to reset -- exactly what a burn-before-reset rule
#        rewards. Under the founder's model glm must win: it has the weekly
#        room, and codex's expiring 5h bucket is not a reason to prefer it.
Q="$(python3 - <<'PY'
import json
def un(pct,hours): return max(0.0,100.0-pct)/max(hours,1.0)
print(json.dumps({
 'glm':{'status':'ok',
        'five_hour':{'pct':10,'hours_to_reset':4.5,'usable_now':un(10,4.5)},
        'weekly':{'pct':40,'hours_to_reset':100,'usable_now':un(40,100)}},
 'codex':{'status':'ok','binding_window':'weekly','windows':[
   {'kind':'five_hour','used_percent':15,'hours_to_reset':0.2,'usable_now':un(15,0.2)},
   {'kind':'weekly','used_percent':45,'hours_to_reset':100,'usable_now':un(45,100)}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':{'pct':10},'seven_day':{'pct':10}}]}
}))
PY
)"

OUT="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 \
  ROUTE_TEST_QUOTA="$Q" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" \
  '{"kind":"code","size":"standard","allowed_arms":["glm","codex"]}' 2>&1)"

printf '%s\n' "$OUT" | tr ' ' '\n' | grep -E "^(arm|headroom_priced|reset_urgency|ecost)" | head -8
printf '%s\n' "$OUT" | head -3
echo "---"
if printf '%s' "$OUT" | grep -qE '(^|[^a-z])arm=glm'; then
  echo "GREEN: glm won (weekly reserve decided)"; exit 0
else
  echo "RED: glm did NOT win -- the expiring five-hour bucket decided"; exit 1
fi
