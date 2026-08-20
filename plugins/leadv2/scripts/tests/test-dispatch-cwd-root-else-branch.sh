#!/usr/bin/env bash
# FOREIGN-ROOT-ELSE-BRANCH-01 — falsifying harness (dispatch-b4042501-review, blocker 1).
#
# Live regression, proven by the critic against the checkpointed diff: the
# Fault-2 guard's rewrite left `_LV2_CWD_GIT_ROOT` assigned ONLY inside the
# `if [[ -n "${_LV2_ENV_ROOT}" ]]` branch (and only further nested inside the
# `LEADV2_FOREIGN_ROOT_GUARD=1` sub-branch). The `else` branch --
# `PROJECT_ROOT="${_LV2_CWD_GIT_ROOT:-$(pwd)}"` -- always saw an EMPTY
# `_LV2_CWD_GIT_ROOT`, so any invocation with NONE of CLAUDE_PROJECT_ROOT /
# CLAUDE_PROJECT_DIR / PROJECT_ROOT / LEADV2_PROJECT_ROOT set, launched from a
# SUBDIRECTORY of a git repo, rooted the entire control plane (journal,
# docs/handoff, active.yaml, cache, ledger) at the subdirectory instead of the
# repo's real git toplevel -- a silent regression on the DEFAULT/no-env-set
# path, same disease class as Fault 2 itself.
#
# Fix: `_LV2_CWD_GIT_ROOT` is now resolved once, unconditionally, before the
# if/else -- so the else branch's `${_LV2_CWD_GIT_ROOT:-$(pwd)}` sees the real
# value on every path, restoring the pre-guard behavior
# (`git rev-parse --show-toplevel || pwd`).
#
# Why `status` + the ledger slug is NOT the right probe here: repo_slug()
# is basename(LEDGER_REPO_ROOT:-PROJECT_ROOT), and LEDGER_REPO_ROOT
# independently re-derives the git toplevel via `git rev-parse
# --git-common-dir` FROM WORK_ROOT -- which self-corrects even when
# PROJECT_ROOT itself is wrong, as long as cwd is still somewhere inside the
# same repo. That masks the bug entirely. Case 1 instead dispatches a real
# --kind product mission (spawn=1, stubbed launcher) and checks the
# filesystem location of `docs/handoff/dispatch-<sig8>/lane-mission.md`,
# which is written directly under `${PROJECT_ROOT}` (leadv2-dispatch-code.sh
# ~4678) with no self-correcting re-derivation -- a direct, unmasked readout.
#
# Case 1: no env root vars set, cwd is a SUBDIRECTORY of a git repo ->
# lane-mission.md must land under the repo's toplevel, NOT the subdirectory.
# Case 2: no env root vars set, cwd is NOT inside any git repo (bare tmpdir)
# -> PROJECT_ROOT must fall back to cwd itself (pwd), matching legacy
# `git rev-parse --show-toplevel || pwd` semantics (non-regression companion;
# passes on both pristine and fixed code since there is no git repo to
# self-correct from either way).

set -uo pipefail
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
unset LEADV2_PROJECT_ROOT 2>/dev/null || true
unset CLAUDE_PROJECT_ROOT 2>/dev/null || true
unset CLAUDE_PROJECT_DIR 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

write_fake_subsession_bin() {
  local f="$1"
  cat > "${f}" <<'EOS'
#!/usr/bin/env bash
printf 'PID=%s LABEL=test SESSION_ID=test\n' "${LV2_TEST_ALIVE_PID:?LV2_TEST_ALIVE_PID unset}"
exit 0
EOS
  chmod +x "${f}"
}

# ---- Case 1: subdir of a real git repo, no env root vars --------------------
case_subdir_no_env_lane_mission_lands_at_toplevel() {
  local d repo sub stub out
  d="$(mktemp -d)"
  repo="${d}/myrepo"; sub="${repo}/sub/deeper"
  mkdir -p "${sub}" "${repo}/.claude/ref"
  ( cd "${repo}" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed )
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "${repo}/.claude/ref/leadv2-routing.yaml"
  stub="${d}/fake-subsession.sh"; write_fake_subsession_bin "${stub}"

  ( sleep 30 ) & local alive_pid=$!

  out="$(cd "${sub}" && env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u LEADV2_LANE_WORK_ROOT \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=1 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="${stub}" LV2_TEST_ALIVE_PID="${alive_pid}" \
    bash "${DC}" "cwd-root else-branch probe mission" --kind product 2>&1)"
  local sig8
  sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"
  kill "${alive_pid}" 2>/dev/null; wait "${alive_pid}" 2>/dev/null

  if [[ -z "${sig8}" ]]; then
    bad "case1 setup: could not extract sig8 from dispatch output (${out})"
    rm -rf "${d}"; return
  fi

  if [[ -f "${repo}/docs/handoff/dispatch-${sig8}/lane-mission.md" ]]; then
    ok "subdir + no-env: lane-mission.md lands under the git toplevel (myrepo), not the subdirectory"
  elif [[ -f "${sub}/docs/handoff/dispatch-${sig8}/lane-mission.md" ]]; then
    bad "subdir + no-env: lane-mission.md landed under the SUBDIRECTORY (${sub}) -- PROJECT_ROOT else-branch regression reproduced"
  else
    bad "subdir + no-env: lane-mission.md not found under either candidate root (out: ${out})"
  fi

  rm -rf "${d}"
}

# ---- Case 2: no git repo at all, no env root vars ----------------------------
case_no_git_no_env_falls_back_to_pwd() {
  local d work out slug
  d="$(mktemp -d)"
  work="${d}/plainwork"; mkdir -p "${work}"
  slug="$(basename "${work}" | tr -cd 'A-Za-z0-9._-')"

  out="$(cd "${work}" && env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u LEADV2_LANE_WORK_ROOT \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -qF "/${slug}.jsonl"; then
    ok "no-git + no-env: PROJECT_ROOT falls back to pwd (slug=${slug})"
  else
    bad "no-git + no-env: expected ledger slug=${slug} (pwd fallback), got: ${out}"
  fi

  rm -rf "${d}"
}

case_subdir_no_env_lane_mission_lands_at_toplevel
case_no_git_no_env_falls_back_to_pwd

printf '[test-dispatch-cwd-root-else-branch] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
