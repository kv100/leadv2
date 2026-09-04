#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-active-registry.sh leadv2-state-path.sh leadv2-dod-gate.sh
#
# tests/test-dod-gate-lane-state-md.sh — DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01.
#
# Makes the lane's negative control permanent. The harness used to write its
# LEAD_V2_STATE.md session registry INTO the lane worktree, and the DoD gate's
# check (d) then killed the lane for a file the harness itself had just
# written (6/6 lanes died on that one path). The fix on this branch
# (leadv2-active-registry.sh routed through leadv2-state-path.sh) moved the
# write to the shared state root beside active.yaml; until this suite existed
# the only proof was a hand demonstration (lane commit f495f881) that CI
# never selected — worthless by the standing rule that a suite CI does not
# run does not exist.
#
# Pinned here, through the PRODUCTION gate entry and a PRODUCTION-shaped
# diff:
#   red   — a lane worktree dirty in docs/LEAD_V2_STATE.md (the harness
#           registry write restored) next to a legitimate lane edit must
#           fail lv2_dod_gate_run with the exact line
#           "dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md";
#   green — the same tree with the registry dirt removed (the write lives at
#           the shared root now) must pass check (d) with rc=0.
# The red half is what dies if the gate's _DOD_RUNTIME_STATE_REGEX ever drops
# docs/LEAD_V2_STATE.md — the rejected symptom-suppression direction — or if
# the diff-path parse stops naming the file.
#
# The diff is built exactly as leadv2-dispatch-product-close.sh builds
# review.diff on the plain path: `git -C <lane worktree> diff HEAD`.
# Every fixture lives under a mktemp dir; nothing here touches the real repo
# tree.
#
# Run: bash plugins/leadv2/scripts/tests/test-dod-gate-lane-state-md.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOD_GATE_SH="${PLUGIN_SCRIPTS}/lib/leadv2-dod-gate.sh"
ACTIVE_REGISTRY_SH="${PLUGIN_SCRIPTS}/leadv2-active-registry.sh"
STATE_PATH_SH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/dod-gate-lane-state.XXXXXX")"
cleanup() { rm -rf "${FIXTURE}"; }
trap cleanup EXIT INT TERM

# ── syntax floor: the gate lib plus both trigger carriers (macOS bash 3.2) ──
for _sh in "${DOD_GATE_SH}" "${ACTIVE_REGISTRY_SH}" "${STATE_PATH_SH}"; do
  if bash -n "${_sh}" 2>/dev/null && /bin/bash -n "${_sh}" 2>/dev/null; then
    pass "bash -n $(basename "${_sh}") (incl. 3.2)"
  else
    fail "bash -n $(basename "${_sh}")"
  fi
done

# ── source the gate lib (BASH_SOURCE[0] != $0 keeps it non-executing) ──────
# shellcheck source=/dev/null
source "${DOD_GATE_SH}"

# ── fixture: a lane-shaped git repo — main parked at base, work on lane ────
REPO="${FIXTURE}/lane"
mkdir -p "${REPO}/docs" "${REPO}/plugins/leadv2/scripts"
( cd "${REPO}" \
  && git init -q -b main \
  && printf '# leadv2 active sessions\n\n(regenerated index — live rows in active.yaml)\n' > docs/LEAD_V2_STATE.md \
  && printf 'placeholder\n' > plugins/leadv2/scripts/leadv2-worker-epilogue.sh \
  && git add -A \
  && git -c user.email=t@t -c user.name=t commit -q -m base \
  && git checkout -q -b lane )

TASK_DIR="${REPO}/docs/handoff/T1"
mkdir -p "${TASK_DIR}"
# No paste-lines and no report request in the brief, so checks (a)/(b) pass
# and this suite exercises check (d) in isolation — same fixture shape
# test-worker-dod-gate.sh uses for its lv2_dod_gate_run section.
printf 'Nothing further needed from the worker for this fixture.\n' > "${TASK_DIR}/brief.md"
OUT_MD="${FIXTURE}/dod-gate-out.md"
DIFF_FILE="${FIXTURE}/review.diff"

dod_scenario() { # runs the production gate on the lane tree's current dirt
  git -C "${REPO}" diff HEAD > "${DIFF_FILE}"   # review.diff construction, product-close plain path
  lv2_dod_gate_run "${REPO}" "${TASK_DIR}" "${DIFF_FILE}" "${OUT_MD}"
}

# ---------------------------------------------------------------------------
# NEG — the hand demonstration, made permanent: the harness registry write
# is back in the lane worktree, alongside the lane's own legitimate edit.
# ---------------------------------------------------------------------------
LANE_CODE="${REPO}/plugins/leadv2/scripts/leadv2-worker-epilogue.sh"
printf 'placeholder\nlane work\n' > "${LANE_CODE}"
printf '# leadv2 active sessions\n\n- session abc123 phase=build\n' > "${REPO}/docs/LEAD_V2_STATE.md"

if git -C "${REPO}" diff HEAD --name-only | grep -qx 'docs/LEAD_V2_STATE.md'; then
  pass "fixture: harness write is uncommitted dirt in the lane tree"
else
  fail "fixture: harness write is uncommitted dirt in the lane tree"
fi

RED_LINE='dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md'
gate_out="$(dod_scenario)"; rc=$?
if [[ ${rc} -eq 1 ]] \
   && printf '%s' "${gate_out}" | grep -qF "${RED_LINE}" \
   && grep -qF "${RED_LINE}" "${OUT_MD}"; then
  pass "NEG: registry write dirty in lane worktree -> rc=1, exact line '${RED_LINE}'"
else
  fail "NEG: registry write dirty in lane worktree -> rc=1 + '${RED_LINE}' (got rc=${rc} out=${gate_out})"
fi

# ---------------------------------------------------------------------------
# green — the relocation's world: the registry write lands at the shared
# state root, so the lane tree's copy returns to its committed state while
# the lane's own edit stays. The same diff body that just killed the gate
# must now pass check (d).
# ---------------------------------------------------------------------------
git -C "${REPO}" checkout -- docs/LEAD_V2_STATE.md
if git -C "${REPO}" diff HEAD --name-only | grep -qx 'docs/LEAD_V2_STATE.md'; then
  fail "fixture: registry dirt should be gone after restore"
else
  pass "fixture: registry dirt removed, lane edit kept"
fi

gate_out="$(dod_scenario)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q 'dod_pass check=runtime_state' "${OUT_MD}"; then
  pass "green: registry dirt removed (write lives at shared root) -> rc=0, dod_pass check=runtime_state"
else
  fail "green: registry dirt removed -> rc=0 (got rc=${rc} out=${gate_out})"
fi

log "----"
log "pass=${PASS} fail=${FAIL}"
if [[ ${FAIL} -eq 0 ]]; then
  exit 0
fi
exit 1
