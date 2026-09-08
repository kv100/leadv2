#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/p1b-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export LEADV2_TEST_CONTEXT=1
export LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state"
export LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger"
export LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events"
export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/quota.sh"
export LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh"
cat > "$TMP/quota.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$QUOTA"
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/free.sh"
source "$ROOT/scripts/lib/leadv2-route-arbiter.sh"
for state in unmetered unknown ok; do
  export QUOTA
  QUOTA="$(python3 - "$ROOT/scripts/leadv2-quota-read.py" "$state" <<'PY'
import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('quota',sys.argv[1]); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
state=sys.argv[2]
a={'account_label':'work','active':True,'status':'unknown','subscription_type':'team','http':401,
   'account_state':m.classify_account_state('team' if state=='unmetered' else 'pro',401)}
if state=='ok': a.update(status='ok',account_state='ok',five_hour_pct=20,seven_day_pct=20)
print(json.dumps({'anthropic':{'status':'ok' if state=='ok' else 'unknown','accounts':[a]},'codex':{'status':'unknown'},'glm':{'status':'unknown'}}))
PY
)"
  out="$(route_arbiter worker '{"kind":"docs","size":"standard","task":"unmetered-probe","arm_pool":["haiku","sonnet","codex"],"launchable_arms":["haiku","sonnet","codex"]}')"
  printf '%s\n' "$out"
  python3 - "$out" "$state" <<'PY'
import sys
line,state=sys.argv[1:]
f=dict(t.split('=',1) for t in line.split() if '=' in t)
penalty=float(f['claude_probe_penalty'])
print('PENALTY state=%s actual=%g expected=%g' % (state,penalty,50 if state=='unknown' else 0))
assert penalty==(50 if state=='unknown' else 0), 'PENALTY_MISMATCH usable account charged %g' % penalty
if state=='unmetered':
    assert f['arm'] in ('haiku','sonnet'), 'unmetered Claude must win this auction'
    assert f['util_claude']=='unmetered'
    assert f['claude_priced_from']=='configured_allowance_conservative'
    assert float(f['headroom_w'])==0.2, 'conservative configured weight must apply'
PY
done
echo 'PASS unmetered penalty=0; unknown penalty=50; measured penalty=0'
