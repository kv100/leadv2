#!/usr/bin/env bash
# LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01 — dispatcher e2e (S7).
#
# Proves at the dispatcher level that a finalized lane is ACCEPTED for resume
# (placement pinned), not refused with lane_is_live.  Uses the REAL
# leadv2-lane-liveness.sh (not a stub) so the sentinel path is exercised
# end-to-end.
#
# dispatch-a24b1588 round-1b item 3 verification (2026-08-06): the S7
# `rc == 0` tightening (from `rc != 5`) does NOT fail against a1afed9's own
# source -- a1afed9 genuinely returns rc=0 here, so this is a false-PASS-class
# removal, not a live bug fix. The correct evidence is a negative control on
# the clean a1afed9 baseline: fault-inject LEADV2_DISPATCH_GLM_BIN to hard-fail
# (exit 7, no PID/LABEL/SESSION_ID emitted), which drives real dispatch rc to 4
# (dispatch_rolled_back reason=all_arms_unavailable...glm_failed_launcher).
# Same source, same injected fault, opposite verdict: the OLD `rc != 5`
# assertion PASSES (4 != 5) while the NEW `rc == 0` assertion FAILS
# (rc=4, expected 0) -- proving the tightening catches a class of false PASS
# the old assertion could not. This is a negative-control demonstration, not a
# fail-against-HEAD run.
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"
LIVENESS="${PLUGIN_SCRIPTS}/leadv2-lane-liveness.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-drs-XXXXXX)"
cleanup() { rm -rf "${SANDBOX}"; }
trap cleanup EXIT

# A high pid that is extremely unlikely to exist — deterministic dead pgid.
find_unused_pid() {
  local p=99999
  while kill -0 "$p" 2>/dev/null; do p=$((p + 1)); done
  echo "$p"
}
DEAD_PGID="$(find_unused_pid)"

set_mtime_ago() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, secs = sys.argv[1], int(sys.argv[2])
t = time.time() - secs
os.utime(path, (t, t))
PY
}

# ── Fixture repo with linked worktree ────────────────────────────────────────
TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

LANE_REF="SENTINEL01"
RESUME_WT="${TARGET}/.claude/worktrees/${LANE_REF}"
mkdir -p "$(dirname "${RESUME_WT}")"
( cd "${TARGET}" && git worktree add -q "${RESUME_WT}" -b "worktree-${LANE_REF}" ) 2>/dev/null
( cd "${RESUME_WT}" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed )

# ── Handoff dir with a finalized run ─────────────────────────────────────────
# The dispatch probe checks "dispatch-${key}" and "${key}" spellings.
# We set up docs/handoff/dispatch-${LANE_REF}/ with a fresh stream (which on
# HEAD would resolve alive) plus a finalized run dir (which on the fixed code
# resolves dead:sentinel_finalized).
HANDOFF_DIR="${TARGET}/docs/handoff/dispatch-${LANE_REF}"
mkdir -p "${HANDOFF_DIR}"
printf '{"type":"assistant","text":"done"}\n' > "${HANDOFF_DIR}/developer.stream.jsonl"
set_mtime_ago "${HANDOFF_DIR}/developer.stream.jsonl" 300   # fresh (< 900s)

# GLM run dir with .finalized + dead pgid
GLM_RUNS="${SANDBOX}/glm-runs"
RUN_ID="260806-120000-sentinel-0001"
RUN_DIR="${GLM_RUNS}/${RUN_ID}"
mkdir -p "${RUN_DIR}"
touch "${RUN_DIR}/.finalized"; set_mtime_ago "${RUN_DIR/.finalized}" 600 2>/dev/null || true
touch "${RUN_DIR}/.finalized"; set_mtime_ago "${RUN_DIR}/.finalized" 600
printf '%s\n' "${DEAD_PGID}" > "${RUN_DIR}/pgid"
printf 'outcome=completed\n' > "${RUN_DIR}/.outcome"
printf '%s\n' "${RUN_ID}" > "${HANDOFF_DIR}/.glm-session-runner.run-id"

# active.yaml row
mkdir -p "${TARGET}/docs/leadv2"
printf 'sessions:\n  - task_id: dispatch-%s\n    pid: null\n    log_path: docs/handoff/dispatch-%s/developer.stream.jsonl\n' \
  "${LANE_REF}" "${LANE_REF}" > "${TARGET}/docs/leadv2/active.yaml"

# ── Stubs ────────────────────────────────────────────────────────────────────
GLM_STUB="${SANDBOX}/glm-stub.sh"
JOURNAL_STUB="${SANDBOX}/journal-stub.sh"

cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  bg)
    shift; mission="$1"; shift
    while [[ $# -gt 0 ]]; do case "$1" in --cwd) shift 2 ;; *) shift ;; esac; done
    printf 'PID=%s LABEL=fake SESSION_ID=fake\n' "$$"
    exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "${GLM_STUB}"

cat > "${JOURNAL_STUB}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${JOURNAL_STUB}"

# ── Dispatch env ─────────────────────────────────────────────────────────────
export CLAUDE_PROJECT_DIR="${TARGET}"
export CLAUDE_PROJECT_ROOT="${TARGET}"
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
# Use the REAL liveness probe (not a stub) — this is the whole point of S7.
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="${LIVENESS}"
export GLM_RUNS_DIR="${GLM_RUNS}"
export LEADV2_ROUTER_V2=0
export GLM_POLICY_RESOLVER=""
export LEADV2_LANE_SHAPE=off
export LEADV2_DISPATCH_E2E_GATE=0
export LEADV2_DISPATCH_REVIEW_GATE=0
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_PENDING_TTL_S=5
export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
export LEADV2_EXCLUDED_ARMS="__none__"

# ── S7: --resume-lane on a finalized lane → ACCEPTED ─────────────────────────
printf '\n=== S7: --resume-lane on finalized lane → accepted ===\n'

# First verify the liveness probe returns dead:sentinel_finalized
probe_out="$(bash "${LIVENESS}" --project-root "${TARGET}" --lane "dispatch-${LANE_REF}" --no-codex 2>/dev/null || true)"
if [[ "${probe_out}" == "dead:sentinel_finalized" ]]; then
  ok "S7-pre: liveness probe returns dead:sentinel_finalized"
else
  bad "S7-pre: liveness probe returned '${probe_out}', expected dead:sentinel_finalized"
fi

# Now run the dispatch with --resume-lane
dispatch_rc=0
dispatch_stderr_file="${SANDBOX}/s7-stderr.txt"
bash "${DC}" --kind tooling --resume-lane "${LANE_REF}" \
  "S7 sentinel resume test" 2>"${dispatch_stderr_file}" >/dev/null || dispatch_rc=$?

# dispatch-a24b1588 Item 3: rc != 5 only proves "not one of the six refusal
# reasons exit 5 covers" -- a future unrelated crash exiting any other nonzero
# code would false-PASS this. The observed rc really is 0 (confirmed below),
# so assert exactly what was observed, not a weaker superset of it.
if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "S7: dispatch resumed the finalized lane (rc=0)"
else
  bad "S7: dispatch did not resume the finalized lane (rc=${dispatch_rc}, expected 0)"
fi

if ! grep -q 'lane_is_live' "${dispatch_stderr_file}" 2>/dev/null; then
  ok "S7: no lane_is_live in stderr"
else
  bad "S7: lane_is_live found in stderr (should be absent for finalized lane)"
  cat "${dispatch_stderr_file}" >&2
fi

if grep -q 'lane_placement_pinned' "${dispatch_stderr_file}" 2>/dev/null \
  || grep -q 'lane_placement_pinned' "${SANDBOX}/cache/dispatch-decision-journal-"* 2>/dev/null; then
  ok "S7: placement was pinned (accepted)"
else
  # The journal is a stub, so the decision line might be in stderr only
  # (emit goes to the journal which is /bin/true). Check rc == 0 as the
  # primary assertion (same tightening as the main S7 assertion above), and
  # stderr as secondary.
  if [[ ${dispatch_rc} -eq 0 ]]; then
    ok "S7: placement accepted (rc=0, journal is a stub)"
  else
    bad "S7: no evidence of placement pin (rc=${dispatch_rc}, expected 0)"
  fi
fi

printf '\n=== Results: %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then exit 1; fi
