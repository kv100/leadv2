#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-routing.yaml
# SMART-ARBITER-01: the CANONICAL routing.yaml's glm_policy.sonnet_exceptions
# must NOT carry `safety_gate_publish_payments when: protected_path`. That row
# predates GLM-DOES-ANY-WORK-01 (founder 2026-09-04: «дай глм право делать
# любую работу, вообще любую, во всех репо») and still forced sonnet-primary +
# glm-excluded on every protected/safety task: the capability_matrix's
# glm protected:true cell could never win that path (84 live sonnet-at-cost-5
# decisions 2026-09-03/04 while glm idled at util 13-31; direct arm_excluded
# lines in dispatch-07401216's journal). The resolver's exc-id gate
# (leadv2-glm-policy-resolve.py: rid not in exc_ids -> cannot fire) makes this
# row's ABSENCE the enforcement -- this suite grades the canonical yaml
# itself, never a fixture copy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
RESOLVER="${SCRIPTS_DIR}/lib/leadv2-glm-policy-resolve.py"
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

verdict="$(python3 - "$ROUTING" "$RESOLVER" <<'PY'
import sys, yaml, importlib.util
routing = yaml.safe_load(open(sys.argv[1])) or {}
spec = importlib.util.spec_from_file_location('glmpolicy', sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
gp = (routing.get('router') or {}).get('glm_policy') or {}
exc_ids = [e.get('id') for e in (gp.get('sonnet_exceptions') or []) if isinstance(e, dict)]
def resolve(signals):
    return mod.resolve_glm_policy(gp, signals, 'build')
bad = []
# The removed row's id must be absent from the canonical list (its absence is
# the enforcement; presence with a silent resolver would be a phantom guard).
if 'safety_gate_publish_payments' in exc_ids:
    bad.append('row-still-present')
# protected / safety tasks resolve glm primary (founder: any work, any repo).
r = resolve({'protected_path': True})
if r.get('arm') != 'glm' or r.get('rule') != 'none':
    bad.append('protected_path->%s/%s' % (r.get('arm'), r.get('rule')))
r = resolve({'safety_touched': True})
if r.get('arm') != 'glm' or r.get('rule') != 'none':
    bad.append('safety_touched->%s/%s' % (r.get('arm'), r.get('rule')))
# Every KEPT exception still fires sonnet: the removal must be surgical.
for sig, rule_id in (({'subsystem_count': 4}, 'integration_critical_4subsystems'),
                     ({'ui_design_judgment': True}, 'ui_design_judgment'),
                     ({'glm_failure_count': 2}, 'glm_failed_twice'),
                     ({'glm_lock_busy': True}, 'glm_lock_busy_no_second_channel')):
    r = resolve(sig)
    if r.get('arm') != 'sonnet' or r.get('rule') != rule_id:
        bad.append('%s->%s/%s' % (rule_id, r.get('arm'), r.get('rule')))
print('; '.join(bad) if bad else 'OK')
sys.exit(0)
PY
)" || true

if [[ "${verdict}" == "OK" ]]; then
  pass 'canonical yaml: protected/safety resolve glm; all kept exceptions still fire sonnet'
else
  fail 'canonical sonnet_exceptions drifted:' "${verdict}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
