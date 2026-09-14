#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# DISPATCH-REENTRY-SELF-RACE
#
# leadv2-dispatch-code.sh's --worktree re-entry placement probe
# (_resolve_pinned_placement) refused itself as `lane_is_live` on a lane
# worktree it was pinning into: the ONLY "live" evidence in active.yaml was
# a `pid_source=lead_durable`, `starting:*` row this SAME run's own earlier
# phase (e.g. Gate 1's plan_gate_pre_dispatch registration) had written for
# that lane moments earlier, under the durable lead pid every retry shares.
# Every retry re-read that same self-written row and refused again.
#
# Fix: the placement probe now compares the row's `pid`/`pid_source` against
# this run's OWN durable identity (_lv2_durable_pid(), the same $PPID walk
# the registrar used to stamp the row) and ignores a match as self-evidence
# — never as proof the lane is free. A `lead_durable` row belonging to a
# DIFFERENT durable pid (a genuinely different lead session) must still
# refuse; that is the negative control below (R-b).
#
# Two assertions:
#   R-a  Self re-entry: probe returns pid_source=lead_durable with
#        pid == THIS run's own _lv2_durable_pid() → placement PROCEEDS
#        (rc=0, WORK_ROOT pinned to the lane worktree) even though the row
#        is starting:* and this run itself is about to register there.
#   R-b  Negative control: probe returns pid_source=lead_durable with a
#        DIFFERENT (foreign) pid, fresh starting:* → placement still
#        REFUSES lane_is_live (rc=5, WORK_ROOT never pinned).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${LEADV2_DISPATCH_CODE_FILE:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

D="$(mktemp -d /tmp/leadv2-reentry-self-race-XXXXXX)"
trap 'rm -rf "${D}"' EXIT
R="${D}/repo" W="${R}/.claude/worktrees/self-race-lane"
mkdir -p "${R}"
(cd "${R}" && git init -q -b main && git config user.email t@e && git config user.name t && printf seed > seed && git add seed && git commit -qm seed)
mkdir -p "$(dirname "${W}")"; (cd "${R}" && git worktree add -q "${W}" -b worktree-self-race-lane)

# This run's OWN durable identity, computed the SAME way dispatch-code.sh
# will compute it internally (_lv2_durable_pid() walks $PPID, and a
# command-substitution subshell's $PPID equals ITS caller's $$ — the exact
# shape dispatch-code.sh's own sourced call sees when invoked as a direct
# child of this test process, matching `_resolve_pinned_placement` called
# in-process below).
source "${SCRIPT_DIR}/leadv2-active-registry.sh" 2>/dev/null
SELF_DURABLE_PID="$(_lv2_durable_pid)"
if [[ -z "${SELF_DURABLE_PID}" ]]; then
  bad "setup: could not resolve this run's own durable pid"
  printf 'test-dispatch-reentry-self-race: %d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi
FOREIGN_PID=$((SELF_DURABLE_PID + 1))

cat > "${D}/live-self.sh" <<SH
#!/usr/bin/env bash
printf '{"verdict":"starting:5","reason":"registered_no_stream","age_s":5,"pid_alive":true,"pid":${SELF_DURABLE_PID},"pid_source":"lead_durable"}\n'
SH
cat > "${D}/live-foreign.sh" <<SH
#!/usr/bin/env bash
printf '{"verdict":"starting:5","reason":"registered_no_stream","age_s":5,"pid_alive":true,"pid":${FOREIGN_PID},"pid_source":"lead_durable"}\n'
SH
cat > "${D}/journal.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '${D}/journal.log'
SH
chmod +x "${D}/live-self.sh" "${D}/live-foreign.sh" "${D}/journal.sh"

LEADV2_DISPATCH_SOURCE_ONLY=1 source "${DC}"
PROJECT_ROOT="${R}"
JOURNAL_BIN="${D}/journal.sh"; JOURNAL_TASK=dispatch-rr000001; sig8=rr000001
placement_lane_ref=""; placement_path="${W}"

# ════════════════════════════════════════════════════════════════════════
# R-a: self row (pid == this run's own durable pid) → placement proceeds
# ════════════════════════════════════════════════════════════════════════
LEADV2_DISPATCH_LANE_LIVENESS_BIN="${D}/live-self.sh"; LANE_LIVENESS_BIN="${D}/live-self.sh"
WORK_ROOT=""; PLACEMENT_PINNED=0
_resolve_pinned_placement >"${D}/ra.out" 2>&1; rc=$?
W_PHYS="$(cd "${W}" && pwd -P)"
if [[ ${rc} -eq 0 ]]; then
  ok "R-a: self re-entry proceeds past placement (rc=0)"
else
  bad "R-a: self re-entry refused (rc=${rc}) — $(cat "${D}/ra.out")"
fi
if [[ "${PLACEMENT_PINNED}" == 1 && "${WORK_ROOT}" == "${W_PHYS}" ]]; then
  ok "R-a: WORK_ROOT pinned to the lane worktree"
else
  bad "R-a: WORK_ROOT not pinned (got '${WORK_ROOT}', pinned=${PLACEMENT_PINNED})"
fi
if grep -q 'lane_is_live' "${D}/ra.out" "${D}/journal.log" 2>/dev/null; then
  bad "R-a: lane_is_live refusal leaked despite the row being this run's own"
else
  ok "R-a: no lane_is_live refusal for this run's own row"
fi

# ════════════════════════════════════════════════════════════════════════
# R-b: negative control — foreign durable pid, same starting:* freshness
# → placement must still refuse lane_is_live
# ════════════════════════════════════════════════════════════════════════
: > "${D}/journal.log"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="${D}/live-foreign.sh"; LANE_LIVENESS_BIN="${D}/live-foreign.sh"
WORK_ROOT=""; PLACEMENT_PINNED=0
_resolve_pinned_placement >"${D}/rb.out" 2>&1; rc=$?
if [[ ${rc} -eq 5 ]]; then
  ok "R-b: foreign live lane still refuses (rc=5)"
else
  bad "R-b: foreign live lane did NOT refuse (rc=${rc}) — regression: guard silently disabled"
fi
if [[ "${PLACEMENT_PINNED}" == 0 && -z "${WORK_ROOT}" ]]; then
  ok "R-b: WORK_ROOT never pinned for the foreign row"
else
  bad "R-b: WORK_ROOT was pinned despite a foreign live row (got '${WORK_ROOT}')"
fi
if grep -q 'lane_is_live' "${D}/rb.out" "${D}/journal.log" 2>/dev/null; then
  ok "R-b: lane_is_live reason present for the foreign row"
else
  bad "R-b: lane_is_live reason missing for the foreign row"
fi

printf 'test-dispatch-reentry-self-race: %d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
