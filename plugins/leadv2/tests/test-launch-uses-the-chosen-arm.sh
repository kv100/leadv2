#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter
# Execute the production launch function and inspect the subsession's argv.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/p1b-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SCRIPT_DIR="$ROOT/scripts"
DISPATCH="$SCRIPT_DIR/leadv2-dispatch-code.sh"
eval "$(sed -n '/^_spawn_worker_body() {/,/^}/p' "$DISPATCH")"
PROJECT_ROOT="$TMP"; WORK_ROOT="$TMP"
SUBSESSION_BIN="$TMP/subsession.sh"
export CAPTURE="$TMP/argv" PROBE_PID="$$"
cat > "$SUBSESSION_BIN" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE"
printf 'PID=%s LABEL=fixture SESSION_ID=fixture\n' "$PROBE_PID"
SH
emit() { [[ "$*" == *code_intel_preamble* ]] && return 0; printf '%s\n' "$*"; }
log_err() { printf '%s\n' "$*" >&2; }
worker_mcp_preamble_for_arm() { return 3; }
_dl_attempt_token() { printf fixture; }
_emit_event() { :; }
_dispatch_register_arm() { :; }
_arm_lane_pulse_watch() { :; }
_arm_single_lead_beat() { :; }
refusal_reason() { :; }
_LEADV2_FOREGROUND_CONTRACT_MISSION=fixture
_LEADV2_EVIDENCE_CONTRACT_MISSION=fixture
_LEADV2_DOD_GATE_CONTRACT_MISSION=fixture
founder_task_id=; requested_profile=work
RESOLVED_EFFORT=high
for arm in sonnet haiku fable opus; do
  kind=plan; task_class=heavy
  [[ "$arm" == haiku ]] && kind=recon
  _spawn_worker_body "$arm" 'fixture mission' "argv-$arm" "$TMP/err"
  python3 - "$CAPTURE" "$arm" <<'PY'
import sys
argv=open(sys.argv[1]).read().splitlines()
arm=sys.argv[2]
print('SUBSESSION_ARGV arm=%s argv=%r' % (arm, argv))
assert argv[argv.index('--model')+1] == arm, 'ARGV_MISMATCH expected=%s actual=%s' % (arm, argv[argv.index('--model')+1])
assert argv[argv.index('--role')+1]=='developer'
assert argv[argv.index('--requested-profile')+1]=='work'
assert argv[argv.index('--effort')+1]=='high'
assert argv[argv.index('--task-id')+1]=='dispatch-argv-'+arm
PY
done
rm "$CAPTURE"
kind=code
rc=0
_spawn_worker_body fable 'incapable fixture' incapable "$TMP/err" || rc=$?
[[ "$rc" == 2 && ! -e "$CAPTURE" ]] || { echo 'FAIL registry miss did not refuse before subsession'; exit 1; }
echo 'PASS registry miss refuses before subsession; all four actual argv models match'
