#!/usr/bin/env bash
# D1-401-IS-NOT-A-DEAD-ACCOUNT (PRE-WAVES-PLAN D1, lane 60fdbb5be2c6,
# 2026-09-08): a 401 from /api/oauth/usage on an account whose credential
# resolved a token is NOT evidence of a dead credential, for max any more
# than for team. The probe sends a STORED access token (the DPoP refresh is
# not wired -- read_anthropic's no-accounts branch says so), so the 401
# measures only "this token cannot read usage data"; launchability is tested
# only by launching, and a failed launch is already parked by the arbiter's
# failure-memory/lockout machinery. classify_account_state therefore prices
# every MEASURED 401 class (team, max) as `unmetered`: reachable, priced at
# the least-generous configured allowance weight, never excluded by
# UNKNOWN_PROBE_PENALTY.
#
# The auction mirrors the 2026-09-07 incident shape (glm probe failed, codex
# probe failed, claude arms all read through the same usage endpoint):
#   haiku cost 2, sonnet cost 5, glm cost 1.
#   claude unknown   -> haiku 2+50=52, sonnet 55, glm 1+50=51 -> glm wins.
#   claude unmetered -> haiku 2/0.2=10, sonnet 25, glm 51     -> haiku wins.
#
# Case 1 SYMPTOM (E2E-KILLRATE-01): subscription_type=max + http 401 must
#   WIN the selection -- the arm the arbiter RETURNS is asserted, not a log
#   line. Red before the classifier fix, green after.
# Case 2 GUARD: subscription_type=pro + http 401 must still LOSE that same
#   auction and keep the 50 penalty -- the P1b boundary; widening past it is
#   the founder's ruling, not a lane's.
# Case 3 MUTATION CONTROL (inside classify_account_state's body): the final
#   `return ACCOUNT_STATE_UNKNOWN` is rewritten to unmetered -- "everything
#   is usable" -- and the same guard values must then disagree, proving case
#   2 reddens on a value (arm= / claude_probe_penalty=), never on a missing
#   key. A leadv2-mutation-control.sh artifact under docs/audits/
#   mutation-control/ backs the same mutation via the runner.
# run-all-triggers: leadv2-quota-read leadv2-route-arbiter
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/d1-401-test.XXXXXX")"
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

# run_case <quota_read_module_path> <subscription_type> -> decision line.
# The quota JSON is built by the module UNDER TEST's own classifier, so the
# case exercises producer and consumer together, hermetically (no keychain,
# no network; every account field is synthetic).
run_case() {
  local module="$1" sub="$2"
  QUOTA="$(python3 - "$module" "$sub" <<'PY'
import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('quota',sys.argv[1]); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
sub=sys.argv[2]
a={'account_label':'work','active':True,'status':'unknown','subscription_type':sub,'http':401,
   'account_state':m.classify_account_state(sub,401)}
print(json.dumps({'anthropic':{'status':'ok','accounts':[a]},'codex':{'status':'unknown'},'glm':{'status':'unknown'}}))
PY
  )"
  export QUOTA
  # complexity=simple (flag-sourced, conf 0.7 -> req_eff 2.3) puts EVERY arm
  # in fit_bucket 0 (haiku cap 2 >= 2.3-0.5), so the auction is decided on
  # effective cost alone and the numbers in the header comment hold exactly.
  route_arbiter worker '{"kind":"docs","size":"standard","task":"d1-401-launchability","complexity":"simple","complexity_source":"flag","arm_pool":["haiku","sonnet","glm"],"launchable_arms":["haiku","sonnet","glm"]}'
}

# ── Case 1 (symptom): max+401 must be SELECTED ─────────────────────────────
out="$(run_case "$ROOT/scripts/leadv2-quota-read.py" max)"
printf '%s\n' "$out"
python3 - "$out" <<'PY'
import sys
f=dict(t.split('=',1) for t in sys.argv[1].split() if '=' in t)
assert f['arm']=='haiku', 'SYMPTOM max+401 claude lost the auction to a probe-failed competitor: arm=%s' % f.get('arm')
assert f['claude_account_state']=='unmetered', 'max+401 must classify unmetered, got %s' % f.get('claude_account_state')
assert float(f['claude_probe_penalty'])==0, 'max+401 must carry no unknown-probe penalty, got %s' % f.get('claude_probe_penalty')
assert f['util_claude']=='unmetered', 'util_claude=%s' % f.get('util_claude')
assert f['claude_priced_from']=='configured_allowance_conservative', f.get('claude_priced_from')
assert float(f.get('headroom_w','nan'))==0.2, 'conservative configured weight must apply: headroom_w=%s' % f.get('headroom_w')
print('SYMPTOM-OK max+401 -> arm=%s penalty=%s state=%s' % (f['arm'],f['claude_probe_penalty'],f['claude_account_state']))
PY

# ── Case 2 (guard): pro+401 must still lose and keep the penalty ──────────
out="$(run_case "$ROOT/scripts/leadv2-quota-read.py" pro)"
printf '%s\n' "$out"
python3 - "$out" <<'PY'
import sys
f=dict(t.split('=',1) for t in sys.argv[1].split() if '=' in t)
assert f['arm']=='glm', 'GUARD pro+401 must lose to the probe-failed competitor on penalty, got arm=%s' % f.get('arm')
assert f['claude_account_state']=='unknown', 'pro+401 stays the guarded boundary, got %s' % f.get('claude_account_state')
assert float(f['claude_probe_penalty'])==50, 'GUARD pro+401 must keep UNKNOWN_PROBE_PENALTY=50, got %s' % f.get('claude_probe_penalty')
print('GUARD-OK pro+401 -> arm=%s penalty=%s state=%s' % (f['arm'],f['claude_probe_penalty'],f['claude_account_state']))
PY

# ── Case 3 (mutation control): everything-usable must redden case 2 ────────
MUTANT="$TMP/leadv2-quota-read-everything-usable.py"
python3 - "$ROOT/scripts/leadv2-quota-read.py" "$MUTANT" <<'PY'
import sys
src=open(sys.argv[1]).read()
target="    return ACCOUNT_STATE_UNKNOWN"
mutated="    return ACCOUNT_STATE_UNMETERED  # MUTATED-NEGATIVE-CONTROL: everything non-200 is usable"
if src.count(target)!=1:
    sys.stderr.write('mutation anchor not found exactly once (found %d)\n' % src.count(target)); sys.exit(1)
open(sys.argv[2],'w').write(src.replace(target,mutated,1))
PY
out="$(run_case "$MUTANT" pro)"
printf '%s\n' "$out"
python3 - "$out" <<'PY'
import sys
f=dict(t.split('=',1) for t in sys.argv[1].split() if '=' in t)
caught = (f.get('arm') in ('haiku','sonnet')) or (f.get('claude_probe_penalty')!='50') or (f.get('claude_account_state')!='unknown')
assert caught, 'NEGATIVE CONTROL FAILED: everything-usable mutant still loses the pro auction -- the guard does not detect the widening'
print('MUTATION-CONTROL-OK everything-usable -> arm=%s penalty=%s state=%s (guard reddens on these values)' % (f.get('arm'),f.get('claude_probe_penalty'),f.get('claude_account_state')))
PY
echo 'PASS d1-401: max+401 selectable (claude wins the auction); pro+401 still excluded; everything-usable mutation caught'
