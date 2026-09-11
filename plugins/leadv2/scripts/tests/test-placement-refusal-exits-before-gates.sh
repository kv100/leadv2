#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# DUPLICATE-DISPATCHER-RECORDS-A-TERMINAL-FOR-A-LANE-IT-NEVER-PLACED-01.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${LEADV2_DISPATCH_CODE_FILE:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

D="$(mktemp -d /tmp/leadv2-placement-refusal-XXXXXX)"
trap 'rm -rf "${D}"' EXIT
R="${D}/repo" W="${R}/.claude/worktrees/owner-lane"
mkdir -p "${R}"
(cd "${R}" && git init -q -b main && git config user.email t@e && git config user.name t && printf seed > seed && git add seed && git commit -qm seed)
mkdir -p "$(dirname "${W}")"; (cd "${R}" && git worktree add -q "${W}" -b worktree-owner-lane)
cat > "${D}/live.sh" <<'SH'
#!/usr/bin/env bash
printf '{"verdict":"starting:25","reason":"process_alive","age_s":25,"pid_alive":true}\n'
SH
cat > "${D}/dead.sh" <<'SH'
#!/usr/bin/env bash
printf '{"verdict":"dead:silent","reason":"log_silent_no_process","age_s":9999,"pid_alive":false}\n'
SH
cat > "${D}/journal.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '${D}/journal.log'
SH
chmod +x "${D}/live.sh" "${D}/dead.sh" "${D}/journal.sh"

LEADV2_DISPATCH_SOURCE_ONLY=1 source "${DC}"
PROJECT_ROOT="${R}"; LANE_WORKTREE_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"
JOURNAL_BIN="${D}/journal.sh"; JOURNAL_TASK=dispatch-dup00001; sig8=dup00001
placement_lane_ref=owner-lane; placement_path=""; LEADV2_DISPATCH_LANE_LIVENESS_BIN="${D}/live.sh"; LANE_LIVENESS_BIN="${D}/live.sh"
WORK_ROOT=""; PLACEMENT_PINNED=0
_resolve_pinned_placement >"${D}/refusal.out" 2>&1; rc=$?
if [[ ${rc} -eq 5 ]]; then ok 'case 5 placement refusal returns rc=5 to caller'; else bad "case 5 placement refusal returns rc=5 to caller (got ${rc})"; fi
if ! grep -q 'e2e_gate\|dispatch_terminal' "${D}/journal.log" 2>/dev/null && ! grep -q 'e2e_gate\|dispatch_terminal' "${D}/refusal.out"; then
  ok 'case 5 refused duplicate writes neither e2e_gate nor dispatch_terminal'
else
  bad 'case 5 refusal leaked into a downstream gate or terminal'
fi

LEADV2_DISPATCH_LANE_LIVENESS_BIN="${D}/dead.sh"; LANE_LIVENESS_BIN="${D}/dead.sh"; WORK_ROOT=""; PLACEMENT_PINNED=0
_resolve_pinned_placement >"${D}/granted.out" 2>&1; rc=$?
if [[ ${rc} -eq 0 && "${PLACEMENT_PINNED}" == 1 && "${WORK_ROOT}" == "$(cd "${W}" && pwd -P)" ]]; then
  ok 'case 6 granted placement reaches the normal pinned continuation boundary'
else
  bad "case 6 placement was not granted (rc=${rc}, root=${WORK_ROOT})"
fi

# The refused caller left no terminal residue; a real owner can still append its own.
printf 'append dispatch-dup00001 decision dispatch_terminal task=dup00001 terminal=landed cause=owner\n' >> "${D}/journal.log"
if grep -q 'terminal=landed cause=owner' "${D}/journal.log" && ! grep -q 'terminal_already_recorded' "${D}/journal.log"; then
  ok 'case 7 owner terminal remains recordable after duplicate refusal'
else
  bad 'case 7 duplicate left terminal residue'
fi

printf 'test-placement-refusal-exits-before-gates: %d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
