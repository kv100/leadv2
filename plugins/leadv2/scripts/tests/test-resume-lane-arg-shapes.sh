#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code.sh
# RESUME-LANE-ACCEPTS-PATH-01 — --resume-lane placement resolver test.
#
# Five cases (fixture worktrees only; stub GLM/journal/liveness/quota — never a
# real lane, never a real dispatch). LEADV2_DISPATCH_SPAWN=0 keeps the runner
# out of the post-spawn wait: resolution is proven by the placement decision
# lines the dispatcher prints to stderr.
#   A1  bare lane name of an existing lane -> rc 0, pinned to it (regression).
#   A2  absolute path to that same lane's worktree -> rc 0, pinned to the SAME
#       lane (key=RESUME-ME-01).
#   A3  absolute paths that are not a lane worktree -> rc 5, refusal names the
#       accepted shapes and echoes what was given.
#   A4  absolute path to a FOREIGN repo's worktree (the measured defect input)
#       -> rc 5, refusal NEVER contains a doubled `.claude/worktrees/` segment.
#   A5  bare name matching no lane -> rc 5, refusal names the accepted shapes.
#   Round 3 (review-glm):
#   A6  --resume-lane <PROJECT_ROOT> itself -> rc 5 (never a lane worktree).
#   A7  --resume-lane <in-repo subdirectory> -> rc 5.
#   A8  foreign env root + cwd in another repo, no pin -> the guard WARNs and
#       falls back to the cwd-derived root; project_root_guard telemetry fires.
#   + source grep-gates: WARN text, telemetry assignments, and the
#     linked-worktree porcelain helper must all co-exist in the dispatcher.

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-rlap-XXXXXX)"
cleanup() { rm -rf "${SANDBOX}"; }
trap cleanup EXIT

# -- Fixture repos ------------------------------------------------------------
TARGET="${SANDBOX}/target"
FOREIGN="${SANDBOX}/foreign"

new_repo() {
  local root="$1"
  mkdir -p "${root}"
  ( cd "${root}" && git init -q -b main \
    && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
}

new_repo "${TARGET}"
new_repo "${FOREIGN}"
# Physical spellings: the guard compares realpath forms (macOS /tmp hop), so
# the A8 assertions must grep for the physical roots, not the /tmp strings.
TARGET_PHYS="$(cd "${TARGET}" 2>/dev/null && pwd -P)"
FOREIGN_PHYS="$(cd "${FOREIGN}" 2>/dev/null && pwd -P)"

# The lane worktree of TARGET both shapes must resolve to.
RESUME_WT="${TARGET}/.claude/worktrees/RESUME-ME-01"
mkdir -p "$(dirname "${RESUME_WT}")"
( cd "${TARGET}" && git worktree add -q "${RESUME_WT}" -b worktree-RESUME-ME-01 ) 2>/dev/null
( cd "${RESUME_WT}" && printf 'lane work\n' > lane.txt && git add lane.txt && git commit -qm lane-seed )
RESUME_PHYS="$(cd "${RESUME_WT}" 2>/dev/null && pwd -P)"

# A foreign repo's worktree — an absolute path under .claude/worktrees/ that is
# NOT a lane of TARGET. Under the old code this input was refused with
# looked_for=<TARGET>/.claude/worktrees/<abs-path> — the doubled segment.
FOREIGN_WT="${FOREIGN}/.claude/worktrees/OTHER-01"
mkdir -p "${FOREIGN}/.claude/worktrees"
( cd "${FOREIGN}" && git worktree add -q "${FOREIGN_WT}" -b worktree-OTHER-01 ) 2>/dev/null

# A plain directory that exists but is not a git worktree.
NOT_A_WT="${SANDBOX}/plain-dir"
mkdir -p "${NOT_A_WT}"

# RESUME-LANE-ACCEPTS-PATH-01 round 4 (review-glm H1): an in-repo subdirectory
# whose BASENAME collides with the lane id ("RESUME-ME-01") but is not the
# worktree itself. The old basename-only compare accepted this.
COLLISION_DIR="${TARGET}/docs/handoff/RESUME-ME-01"
mkdir -p "${COLLISION_DIR}"

# -- Sandbox state + cache dirs -----------------------------------------------
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"

QUOTA_LIVE_STUB="${SANDBOX}/quota-live-stub.sh"
JOURNAL_STUB="${SANDBOX}/journal-stub.sh"
LIVENESS_STUB="${SANDBOX}/liveness-stub.sh"
GLM_STUB="${SANDBOX}/glm-stub.sh"

cat > "${QUOTA_LIVE_STUB}" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":10,"seven_day_pct":10}]}}'
SH
chmod +x "${QUOTA_LIVE_STUB}"

printf '#!/usr/bin/env bash\nexit 0\n' > "${JOURNAL_STUB}"
chmod +x "${JOURNAL_STUB}"

cat > "${LIVENESS_STUB}" <<'SH'
#!/usr/bin/env bash
printf '{"lane":"%s","verdict":"dead:silent_9999s_no_process","age_s":9999,"pid_alive":false}\n' "${LEADV2_STUB_LANE:-lane}"
exit 0
SH
chmod +x "${LIVENESS_STUB}"

printf '#!/usr/bin/env bash\nexit 0\n' > "${GLM_STUB}"
chmod +x "${GLM_STUB}"

# Admission/cost model seams: the dispatcher shells out to a live `claude -p`
# judge unless stubbed — the judge is one haiku call (leadv2-task-judge.sh:6)
# whose latency varies with machine load, so it is stubbed for determinism.
TASK_JUDGE_STUB="${SANDBOX}/task-judge-stub.sh"
cat > "${TASK_JUDGE_STUB}" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"complexity":"simple","subsystems_touched":1,"needs_live_verification":false,"risk_class":"none","duration_class":"short","work_kind":"build"}'
exit 0
SH
chmod +x "${TASK_JUDGE_STUB}"

# -- Per-case dispatch env (unique session id: the 2-live-lane cap is real) ---
_LAP_SESSION_SEQ=0
setup_env() {
  _LAP_SESSION_SEQ=$((_LAP_SESSION_SEQ + 1))
  export LEADV2_LEAD_SESSION_ID="rlap-test-session-${_LAP_SESSION_SEQ}"
  export CLAUDE_PROJECT_DIR="${TARGET}"
  export CLAUDE_PROJECT_ROOT="${TARGET}"
  unset PROJECT_ROOT 2>/dev/null || true
  unset LEADV2_PROJECT_ROOT 2>/dev/null || true
  unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
  # Round 3, measured: an ambient LEADV2_PROJECT_ROOT (this session exports the
  # real leadv2 root) outranks PROJECT_ROOT inside lane-state's
  # _lv2_lane_state_root, so every dispatch's lane_reconcile ran
  # `ps -axo` once per leadv2 worktree (116 worktrees on this machine ->
  # ~10s per dispatch, ~90s of pure reconcile in this suite). Unset it so the
  # reconcile roots at the fixture: one worktree, already known -> no ps scan.
  export LEADV2_DISPATCH_SPAWN=0
  export LEADV2_PULSE_MODE=0
  export LEADV2_SINGLE_LEAD_BEAT=0
  export LEADV2_DISPATCH_LANE_PULSE_WATCH_BIN="${JOURNAL_STUB}"
  export LEADV2_DISPATCH_BEAT_LOOP_BIN="${JOURNAL_STUB}"
  export LEADV2_SUITE_LOCK_DISABLE=1
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
  export LEADV2_TASK_JUDGE_BIN="${TASK_JUDGE_STUB}"
  export LEADV2_COST_ESTIMATE_BIN="${JOURNAL_STUB}"
  export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
  export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
  export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
  export LEADV2_DISPATCH_LANE_LIVENESS_BIN="${LIVENESS_STUB}"
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_QUOTA_LIVE="${QUOTA_LIVE_STUB}"
  export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${QUOTA_LIVE_STUB}"
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  # Round 3: the dispatch-ledger sweep dominates wall time (~8.5s per
  # invocation, measured) and the suite asserts stderr decision lines, never
  # ledger rows -- so run the dispatcher with ledger writes off.
  export LEADV2_DISPATCH_TERMINAL_LEDGER=0
}

# resolve_ok <label> <stderr-file> <rc> — rc 0 + pinned to the fixture lane
resolve_ok() {
  local label="$1" errfile="$2" rc="$3"
  [[ ${rc} -eq 0 ]] && ok "${label}: dispatch exited 0" || bad "${label}: dispatch exited ${rc} (expected 0)"
  if grep -qF "mode=resume-lane path=${RESUME_PHYS} key=RESUME-ME-01" "${errfile}" 2>/dev/null; then
    ok "${label}: lane_placement_pinned to RESUME-ME-01"
  else
    bad "${label}: expected pinned line 'path=${RESUME_PHYS} key=RESUME-ME-01'"
  fi
}

# refuse_ok <label> <rc> <errfile> <given> — rc 5 + accepted shapes + echo
refuse_ok() {
  local label="$1" rc="$2" errfile="$3" given="$4"
  [[ ${rc} -eq 5 ]] && ok "${label}: dispatch exited 5" || bad "${label}: dispatch exited ${rc} (expected 5)"
  if ! grep -q 'lane_placement_refused' "${errfile}" 2>/dev/null; then
    bad "${label}: no lane_placement_refused in output"
    return 0
  fi
  ok "${label}: refusal emitted"
  if grep -q 'accepted_shapes=bare_lane_name|absolute_worktree_path' "${errfile}" 2>/dev/null; then
    ok "${label}: refusal names the accepted shapes"
  else
    bad "${label}: refusal missing accepted_shapes"
  fi
  if grep -qF "given=${given}" "${errfile}" 2>/dev/null; then
    ok "${label}: refusal echoes what was given"
  else
    bad "${label}: refusal does not echo the given value"
  fi
}

# ==============================================================================
# A1: bare lane name -> resolves to the lane (regression guard)
# ==============================================================================
# All cases launch CONCURRENTLY, each against its OWN state base: the
# dispatcher serializes on the state dir's flock and admission applies a
# 2-live-lane cap, so concurrent cases sharing one state base contend and
# time out (measured: pair-parallel on a shared base ran slower than
# sequential). One fixture repo pair (TARGET/FOREIGN) is shared; only the
# throwaway state/cache dirs are per-case.
#
# Per-case cwd choice (matters for the FOREIGN-PROJECT-ROOT-GUARD-01 guard;
# a non-git cwd breaks the dispatcher itself, measured rc=127):
#   cwd=FOREIGN  — env root (TARGET) differs from cwd's repo, so the guard is
#                  ACTIVE: A1/A2 exercise the pin preflight (keeps the A2
#                  MUTATION-ANCHOR below lethal), A3/A5 exercise the
#                  cwd-derived-root fallback.
#   cwd=TARGET   — env == cwd repo, guard inert: A4/A6/A7 assert pure
#                  resolver refusals against env-rooted PROJECT_ROOT.
mkdir -p "${TARGET}/plugins"

_LAP_CASE_SEQ=0
launch_case() {
  # launch_case <tag> <cwd> <env-root-or-''> <dc-args...> — dispatcher in a
  # subshell with a fresh session id and private state base; rc lands in
  # rc_<tag>.  env-root overrides CLAUDE_PROJECT_* after setup_env.
  local tag="$1" cwd="$2" envroot="$3"; shift 3
  _LAP_CASE_SEQ=$((_LAP_CASE_SEQ + 1))
  (
    setup_env
    export LEADV2_STATE_BASE="${SANDBOX}/state-${_LAP_CASE_SEQ}"
    export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache-${_LAP_CASE_SEQ}"
    if [[ -n "${envroot}" ]]; then
      export CLAUDE_PROJECT_DIR="${envroot}"
      export CLAUDE_PROJECT_ROOT="${envroot}"
    fi
    cd "${cwd}" || exit 99
    timeout -k 5 60 bash "${DC}" "$@" >/dev/null 2>"${SANDBOX}/${tag}-stderr.txt"
  ) &
  eval "PID_${tag}=\$!"
}
_await_all() {
  local t
  for t in a1 a2 a3nope a3plain a4 a5 a6 a7 a8 a9; do
    eval "rc_${t}=0"
    eval "wait \"\$PID_${t}\" || rc_${t}=\$?"
  done
}

# --- launches ----------------------------------------------------------------
launch_case a1 "${FOREIGN}" "" --kind tooling --resume-lane RESUME-ME-01 \
  "A1 resume-lane bare name shape test fix the build"
launch_case a2 "${FOREIGN}" "" --kind tooling --resume-lane "${RESUME_WT}" \
  "A2 resume-lane absolute path shape test refactor the validator"
launch_case a3nope "${FOREIGN}" "" --kind tooling --resume-lane "/nope/nothing-rlap" \
  "A3 resume-lane bad absolute path test a3 nope"
launch_case a3plain "${FOREIGN}" "" --kind tooling --resume-lane "${NOT_A_WT}" \
  "A3 resume-lane bad absolute path test a3 plain"
launch_case a4 "${TARGET}" "" --kind tooling --resume-lane "${FOREIGN_WT}" \
  "A4 resume-lane foreign worktree path test document the gate"
launch_case a5 "${FOREIGN}" "" --kind tooling --resume-lane NOPE-RLAP-01 \
  "A5 resume-lane unknown bare name test tidy the docs"
# A6/A7 (RESUME-LANE-ACCEPTS-PATH-01 round 3): the absolute-path branch used
# to validate only "git-common-dir parent == PROJECT_ROOT", so it accepted
# PROJECT_ROOT itself and any in-repo subdirectory as a "lane worktree".
launch_case a6 "${TARGET}" "" --kind tooling --resume-lane "${TARGET}" \
  "A6 resume-lane project root itself must be refused"
launch_case a7 "${TARGET}" "" --kind tooling --resume-lane "${TARGET}/plugins" \
  "A7 resume-lane in-repo subdirectory must be refused"
# A8 (round 3, review-glm H1): foreign ENV root, cwd inside TARGET, NO pin
# -> guard warns and falls back to the cwd-derived root.
launch_case a8 "${TARGET}" "${FOREIGN}" --kind tooling \
  "A8 foreign env root falls back to cwd root test verify the gate"
# A9 (round 4, review-glm H1): basename collision with the lane id, not the
# worktree path itself -> must be refused.
launch_case a9 "${TARGET}" "" --kind tooling --resume-lane "${COLLISION_DIR}" \
  "A9 resume-lane basename collision must be refused"

# _await_all blocks on each PID in turn; the nine dispatchers still run
# concurrently. (A bare `wait` here would reap every job first, and the
# per-PID waits would then report 127 "not a child of this shell" — measured.)
_await_all

resolve_ok "A1" "${SANDBOX}/a1-stderr.txt" "${rc_a1}"

resolve_ok "A2" "${SANDBOX}/a2-stderr.txt" "${rc_a2}"
# MUTATION-ANCHOR (RESUME-LANE-ACCEPTS-PATH-01 round 2): this is the assertion
# that dies when the absolute-path branch of the FOREIGN-PROJECT-ROOT-GUARD-01
# pin preflight (leadv2-dispatch-code.sh, _LV2_PIN_VALUE == /*) is removed.
# Without that branch the guard concatenates the worktrees dir onto the given
# absolute path, cd fails, the pin is discarded, and the guard falls back to
# the cwd-derived root with a loud WARN — control plane rooted in the wrong
# tree (the FOREIGN-PROJECT-ROOT-GUARD-01 incident class). Assert the WARN is
# absent: with the branch live, the pin is proven to belong to the env repo
# and PROJECT_ROOT is pinned to the lane's owning repository.
if grep -qF 'foreign project root detected' "${SANDBOX}/a2-stderr.txt" 2>/dev/null; then
  bad "A2: foreign-root guard discarded the absolute-path pin (cwd-derived-root fallback WARN)"
else
  ok "A2: foreign-root guard accepted the absolute-path pin"
fi
# round-3 grep-gate (review-glm H1: "no half-deleted mechanism"): the guard
# RESTORES the cwd-derived-root fallback when no pin proves the env root, so
# the WARN text must say exactly that, the _LV2_FOREIGN_ROOT_* telemetry
# assignments must stay live (the project_root_guard reader consumes them),
# and the porcelain helper behind the round-3 absolute-branch check must exist.
RLAP_DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
if grep -qF -- '-- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)' "${RLAP_DC}"; then
  ok "round3: WARN text names the cwd-derived-root fallback"
else
  bad "round3: WARN text does not match the restored fallback behavior"
fi
if grep -qF '_LV2_FOREIGN_ROOT_ENV="${_LV2_ENV_GIT_ROOT}"' "${RLAP_DC}" \
   && grep -qF '_LV2_FOREIGN_ROOT_CWD="${_LV2_CWD_GIT_ROOT}"' "${RLAP_DC}" \
   && grep -qF 'PROJECT_ROOT="${_LV2_CWD_GIT_ROOT}"' "${RLAP_DC}"; then
  ok "round3: foreign-root telemetry assignments + fallback are live in source"
else
  bad "round3: telemetry assignments or fallback missing (half-deleted mechanism)"
fi
if grep -qF '_lv2_is_lane_worktree_path' "${RLAP_DC}" \
   && grep -qF 'worktree list --porcelain' "${RLAP_DC}"; then
  ok "round3: absolute-branch check uses the linked-worktree porcelain helper"
else
  bad "round3: porcelain linked-worktree check missing from source"
fi

refuse_ok "A3[/nope/nothing-rlap]" "${rc_a3nope}" "${SANDBOX}/a3nope-stderr.txt" "/nope/nothing-rlap"
refuse_ok "A3[${NOT_A_WT}]" "${rc_a3plain}" "${SANDBOX}/a3plain-stderr.txt" "${NOT_A_WT}"

refuse_ok "A4" "${rc_a4}" "${SANDBOX}/a4-stderr.txt" "${FOREIGN_WT}"
if grep -q '\.claude/worktrees/\.claude/worktrees/' "${SANDBOX}/a4-stderr.txt" 2>/dev/null; then
  bad "A4: refusal contains a doubled .claude/worktrees/ segment"
else
  ok "A4: refusal has no doubled segment"
fi

refuse_ok "A5" "${rc_a5}" "${SANDBOX}/a5-stderr.txt" "NOPE-RLAP-01"

refuse_ok "A6" "${rc_a6}" "${SANDBOX}/a6-stderr.txt" "${TARGET}"

refuse_ok "A7" "${rc_a7}" "${SANDBOX}/a7-stderr.txt" "${TARGET}/plugins"

# A9 (round 4, review-glm H1): the collision case — an in-repo subdir whose
# basename equals the lane id but whose PATH is not the worktree — must be
# refused with the shape-naming message, while the worktree's own path (A2)
# stays accepted.
refuse_ok "A9" "${rc_a9}" "${SANDBOX}/a9-stderr.txt" "${COLLISION_DIR}"

# ==============================================================================
# A8 assertions (round 3, review-glm H1): the a8 case launched above runs with
# a foreign ENV root and cwd inside TARGET, NO pin -> the guard warns AND
# falls back to the cwd-derived root, and the project_root_guard telemetry
# fires with both roots (proves the _LV2_FOREIGN_ROOT_* assignments are live,
# not half-deleted).
# ==============================================================================
[[ ${rc_a8} -eq 0 ]] && ok "A8: dispatch exited 0" || bad "A8: dispatch exited ${rc_a8} (expected 0)"
if grep -qF -- '-- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)' "${SANDBOX}/a8-stderr.txt" \
   && grep -qF "cwd=${TARGET_PHYS}" "${SANDBOX}/a8-stderr.txt"; then
  ok "A8: foreign-root WARN names the cwd-derived fallback"
else
  bad "A8: expected cwd-derived-root WARN naming cwd=${TARGET_PHYS}"
fi
if grep -q "status=foreign_env_overridden env_root=${FOREIGN_PHYS}" "${SANDBOX}/a8-stderr.txt" \
   && grep -qF "cwd_root=${TARGET_PHYS}" "${SANDBOX}/a8-stderr.txt"; then
  ok "A8: project_root_guard telemetry fired with both roots"
else
  bad "A8: project_root_guard foreign_env_overridden telemetry missing or wrong roots"
fi

printf 'test-resume-lane-arg-shapes: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
