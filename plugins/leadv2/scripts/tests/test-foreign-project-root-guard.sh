#!/usr/bin/env bash
# FOREIGN-PROJECT-ROOT-GUARD-01 — falsifying harness.
#
# Live incident (V3-DISPATCHER-ACCEPTANCE-01 Fault 2): a bg bash was spawned
# from a persona-engine `claude` session. The human ran `cd ~/Projects/leadv2`
# in that bash before dispatching, but CLAUDE_PROJECT_DIR=~/Projects/persona-engine
# still leaked through from the parent session's env (bash inherits env, `cd`
# does not touch it). The old precedence put CLAUDE_PROJECT_DIR first, so
# PROJECT_ROOT resolved to persona-engine even though cwd was leadv2 — the lane
# worktree landed under persona-engine/.claude/worktrees/6632fad9 (no plugins/
# dir at all), and the worker ended up editing canonical ~/Projects/leadv2
# directly, uncommitted.
#
# review-round-2 (dispatch-b4042501-review, blocker 2): the guard is now
# DEFAULT-ON (LEADV2_FOREIGN_ROOT_GUARD defaults to "1"). An env-provided root
# that is itself a real, DIFFERENT git repo from cwd is structurally IDENTICAL,
# from inside this script, to the pattern most existing suites use (git-init a
# throwaway fixture repo under mktemp, point CLAUDE_PROJECT_ROOT/
# CLAUDE_PROJECT_DIR at it) -- but every one of those suites ALSO `cd`s into
# the throwaway repo before invoking dispatch, so cwd's own git toplevel
# already equals the env root and no mismatch is ever seen. The one suite that
# didn't (test-dispatch-architect-prepass-late-artifact.sh) was fixed to `cd`
# like the rest, not used as grounds to ship the live guard inert. Explicit
# LEADV2_FOREIGN_ROOT_GUARD=0 remains available as an escape hatch.
#
# Case 1 (default ON): cwd is a real git repo A, CLAUDE_PROJECT_DIR points at a
# DIFFERENT real git repo B -> PROJECT_ROOT resolves to A (cwd), with a loud
# stderr warning naming both roots.
# Case 2 (explicit opt-out): the exact same foreign-repo shape as case 1, but
# WITH LEADV2_FOREIGN_ROOT_GUARD=0 -> no warning, no override -- proves the
# escape hatch still works for a caller that explicitly wants legacy
# env-wins precedence.
# Case 3: env root is a bare tmpdir (no .git, the shape most fixtures actually
# use), guard at its default -- still no false-positive warning.
#
# FIX-ROUND-3 (dispatch-b4042501-review codex.r2):
# Case 4 (item 1, blocker): the override in case 1 above only proves the
# stderr WARN line; codex found the override was never proven to reach the
# task journal (leadv2-dispatch-code.sh journals it via
# `emit decision "project_root_guard ..."`, gated on JOURNAL_TASK, which only
# exists once a real dispatch computes a mission sig -- `status` never
# reaches it). Dispatch an actual mission with a foreign env root and assert
# the journal file, not just stdout/stderr, carries the line.
# Case 5 (item 4, medium): a symlinked env root must accept its genuine pin.
# Case 6 (item 4, medium): a parent spelling of that env root must also accept
# the pin and canonicalise the dispatcher back to the pin's owning repo.

set -uo pipefail
# Dev-shell hygiene (same pattern as test-lane-placement-pin.sh /
# test-dispatch-retry-dead.sh): every case below relies on CLAUDE_PROJECT_DIR
# as the fallback env-root signal (CLAUDE_PROJECT_ROOT > CLAUDE_PROJECT_DIR in
# leadv2-dispatch-code.sh's own precedence chain) -- if this suite itself runs
# inside a leadv2 lane session, CLAUDE_PROJECT_ROOT is already exported
# ambient and silently outranks every CLAUDE_PROJECT_DIR set per-call below,
# making cases 4/5 compare against the WRONG env root entirely.
unset CLAUDE_PROJECT_ROOT 2>/dev/null || true
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
unset LEADV2_PROJECT_ROOT 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# ---- Case 1: default (guard on), real repo cwd, real DIFFERENT repo in env --
case_foreign_repo_env_default_on() {
  local d repo_a repo_b out
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"; repo_b="${d}/repo-b"
  mkdir -p "${repo_a}" "${repo_b}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${repo_b}" && git init -q && git commit -q --allow-empty -m init )

  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${repo_b}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    ok "default (guard on): warns loudly on foreign env root (real repo B != cwd repo A)"
  else
    bad "default (guard on): expected FOREIGN-PROJECT-ROOT-GUARD-01 warning (got: ${out})"
  fi

  local real_a real_b
  real_a="$(cd "${repo_a}" && pwd -P)"
  real_b="$(cd "${repo_b}" && pwd -P)"
  if printf '%s' "${out}" | grep -q "${real_a}" && ! printf '%s' "${out}" | grep -qE "cwd_root=${real_b}|env=${real_a}"; then
    ok "default (guard on): warning names cwd repo A as the winner, not repo B"
  else
    bad "default (guard on): expected warning to name repo A as cwd/winner (got: ${out})"
  fi

  rm -rf "${d}"
}

# ---- Case 2: explicit opt-out (LEADV2_FOREIGN_ROOT_GUARD=0) -- must NOT warn ----
case_foreign_repo_env_explicit_opt_out() {
  local d repo_a repo_b out
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"; repo_b="${d}/repo-b"
  mkdir -p "${repo_a}" "${repo_b}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${repo_b}" && git init -q && git commit -q --allow-empty -m init )

  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${repo_b}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_FOREIGN_ROOT_GUARD=0 bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    bad "explicit opt-out (flag=0): must NOT warn -- the escape hatch must actually disable the guard (got: ${out})"
  else
    ok "explicit opt-out (flag=0): no warning, legacy env-wins precedence preserved"
  fi

  rm -rf "${d}"
}

# ---- Case 3: env root is a bare tmpdir (existing test-fixture shape) --------
case_bare_tmpdir_override_untouched() {
  local d root out
  d="$(mktemp -d)"
  root="${d}/root"
  mkdir -p "${root}"

  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    bad "bare-tmpdir override must NOT trigger the foreign-root guard at its default (got: ${out})"
  else
    ok "bare-tmpdir override (no .git) passes through unchanged at the guard's default"
  fi

  rm -rf "${d}"
}

# ---- Case 4 (item 1): the override's journal line lands in the task journal file, not just stdout ----
case_override_journals_to_task_file() {
  local d repo_a repo_b out sig8
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"; repo_b="${d}/repo-b"
  mkdir -p "${repo_a}/.claude/ref" "${repo_b}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${repo_b}" && git init -q && git commit -q --allow-empty -m init )
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${repo_a}/.claude/ref/leadv2-routing.yaml"

  local mission="FOREIGN-PROJECT-ROOT-GUARD-01 case4 journal-delivery mission"
  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${repo_b}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=0 \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"

  if [[ -z "${sig8}" ]]; then
    bad "case4: could not extract sig8 from dispatch output (${out})"
  else
    local journal_file="${repo_a}/docs/leadv2/tasks/dispatch-${sig8}/journal.md"
    if [[ -f "${journal_file}" ]] && grep -q 'project_root_guard.*status=foreign_env_overridden' "${journal_file}"; then
      ok "case4 (item 1): foreign-root override lands in the task journal file, not just stderr"
    else
      bad "case4 (item 1): expected project_root_guard status=foreign_env_overridden in ${journal_file} (present: $([[ -f "${journal_file}" ]] && echo yes || echo no))"
    fi
  fi

  rm -rf "${d}"
}

# ---- Case 5 (item 4): env root reached via a symlink must not falsely reject an explicit pin ----
case_symlinked_env_root_pin_not_rejected() {
  local d repo_a real_env link_env lane out
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"
  real_env="${d}/real-env"
  link_env="${d}/link-env"
  mkdir -p "${repo_a}" "${real_env}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${real_env}" && git init -q && git commit -q --allow-empty -m init )
  ln -s "${real_env}" "${link_env}"
  lane="${real_env}/.claude/worktrees/laneref"
  ( cd "${real_env}" && git worktree add -q "${lane}" -b lane-branch >/dev/null 2>&1 )

  # env root is the SYMLINK alias; the pin candidate is a genuine worktree of the
  # REAL (physical) repo behind it -- a realpath-string mismatch that the old
  # non-physical comparison misread as foreign.
  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${link_env}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    bash "${DC}" status --worktree "${lane}" 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    bad "case5 (item 4): symlinked env root + genuine pin was wrongly rejected as foreign (got: ${out})"
  else
    ok "case5 (item 4): symlinked env root's genuine worktree pin is not falsely rejected"
  fi

  rm -rf "${d}"
}

# ---- Case 6 (item 4): env root as a PARENT of the owning repo is contained ----
case_parent_env_root_pin_not_rejected() {
  local d repo_a real_env lane out rc
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"
  real_env="${d}/real-env"
  mkdir -p "${repo_a}" "${real_env}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${real_env}" && git init -q && git commit -q --allow-empty -m init )
  lane="${real_env}/.claude/worktrees/laneref"
  ( cd "${real_env}" && git worktree add -q "${lane}" -b lane-parent-branch >/dev/null 2>&1 )

  # `${d}` is deliberately the PARENT of the real repo, not a repository
  # itself.  The preflight must accept a pin physically contained by it and
  # set PROJECT_ROOT to `${real_env}`, rather than rerooting onto repo-a.
  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    bash "${DC}" status --worktree "${lane}" 2>&1)"; rc=$?
  if [[ ${rc} -eq 0 ]] && ! printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    ok "case6 (item 4): parent env root containing a genuine pin is not rejected"
  else
    bad "case6 (item 4): parent env root + genuine pin was rejected (rc=${rc}, out: ${out})"
  fi

  rm -rf "${d}"
}

case_foreign_repo_env_default_on
case_foreign_repo_env_explicit_opt_out
case_bare_tmpdir_override_untouched
case_override_journals_to_task_file
case_symlinked_env_root_pin_not_rejected
case_parent_env_root_pin_not_rejected

printf '[test-foreign-project-root-guard] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
