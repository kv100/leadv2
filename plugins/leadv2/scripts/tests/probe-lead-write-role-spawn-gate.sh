#!/usr/bin/env bash
# Acceptance probe for LEAD-CAN-SPAWN-A-WRITE-ROLE-WITHOUT-THE-ARBITER-01.
#
# leadv2-routing-guard.sh is strict in exactly the wrong direction. Measured
# 2026-09-12, same hook, same payload, one field different:
#
#   caller = a SUBAGENT (agent_type present)
#     -> DENIED nested spawn: subagent_type="developer" is a write-capable role
#     -> rc=2
#   caller = the LEAD (no agent_type)
#     -> rc=0, no output at all
#
# The lead is the actor with the most leverage and the only one that can start
# a lane, and it is the one the guard waves through. The guard's own header
# says the lead path is "WARN-ONLY ... NEVER blocks (exits 0)", and the warning
# it does carry only covers architect/critic/security-auditor -- `developer`
# gets not even that. Four Claude-quota agents were spawned this way on
# 2026-09-12 while GLM sat at 48% weekly, skipping complexity estimation, the
# balancer, the arbiter and the phase ladder in one call.
#
# GREEN means: a write-capable role requested by the LEAD is refused with a
# reason, so the work has to go through leadv2-dispatch-code.sh and pick up
# estimate -> balancer -> arbiter -> phases on the way.
#
# Read-only: builds a synthetic hook payload, runs the hook, reads its rc.
set -uo pipefail

H="${LEADV2_ROUTING_GUARD:-$HOME/Projects/leadv2/plugins/leadv2/hooks/leadv2-routing-guard.sh}"
[[ -x "$H" ]] || { echo "PROBE CANNOT RUN: guard missing or not executable: $H"; exit 127; }

CWD="${LEADV2_PROBE_CWD:-$HOME/Projects/persona-engine}"
rc_all=0

# Every write-capable role the guard already names on the nested path. The lead
# path must refuse the same set, or the asymmetry just moves to another name.
for role in developer frontend-developer postgres-pro devops-engineer architect product-owner; do
  payload="{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"${role}\",\"model\":\"sonnet\",\"prompt\":\"x\"},\"cwd\":\"${CWD}\"}"
  out="$(printf '%s' "$payload" | bash "$H" 2>&1)"; rc=$?
  if [[ "$rc" -ne 2 ]]; then
    printf 'LEAD PATH UNGUARDED: subagent_type=%s rc=%s out=%s\n' "$role" "$rc" "${out:0:100}"
    rc_all=1
  fi
done

# Positive control, and it must keep holding: a read-only role stays allowed.
# A guard that refuses everything is not a fix, it is an outage.
payload="{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"Explore\",\"model\":\"haiku\",\"prompt\":\"x\"},\"cwd\":\"${CWD}\"}"
printf '%s' "$payload" | bash "$H" >/dev/null 2>&1; rc=$?
if [[ "$rc" -ne 0 ]]; then
  printf 'OVER-BLOCKED: a read-only Explore/haiku spawn from the lead was refused rc=%s\n' "$rc"
  rc_all=1
fi

[[ "$rc_all" -eq 0 ]] && echo PASS
exit "$rc_all"
