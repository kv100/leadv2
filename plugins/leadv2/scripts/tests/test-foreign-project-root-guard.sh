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
# The behavior-changing part of the fix is OPT-IN (LEADV2_FOREIGN_ROOT_GUARD=1):
# an env-provided root that is itself a real, DIFFERENT git repo from cwd is
# structurally IDENTICAL, from inside this script, to the deliberate pattern
# 50+ existing suites use (git-init a throwaway fixture repo under mktemp,
# point CLAUDE_PROJECT_ROOT/CLAUDE_PROJECT_DIR at it, run from the real
# checkout's own cwd) -- enabling the override unconditionally left stray
# docs/handoff/dispatch-*/ rows under this very worktree the first time it was
# tried (test-dispatch-architect-prepass-late-artifact.sh). So the default
# (flag unset) must stay byte-identical to pre-fix behavior; only an explicit
# opt-in activates detection.
#
# Case 1 (flag ON): cwd is a real git repo A, CLAUDE_PROJECT_DIR points at a
# DIFFERENT real git repo B -> PROJECT_ROOT resolves to A (cwd), with a loud
# stderr warning naming both roots.
# Case 2 (regression guard, flag OFF / default): the exact same foreign-repo
# shape as case 1, but WITHOUT the opt-in flag -> no warning, no override --
# byte-identical to legacy precedence (env wins). This is what keeps the
# existing test-fixture convention from silently breaking.
# Case 3: env root is a bare tmpdir (no .git, the shape most fixtures actually
# use) with the flag ON -> still no false-positive warning either way.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# ---- Case 1: flag ON, real repo cwd, real DIFFERENT repo in env -------------
case_foreign_repo_env_flag_on() {
  local d repo_a repo_b out
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"; repo_b="${d}/repo-b"
  mkdir -p "${repo_a}" "${repo_b}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${repo_b}" && git init -q && git commit -q --allow-empty -m init )

  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${repo_b}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_FOREIGN_ROOT_GUARD=1 bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    ok "flag ON: warns loudly on foreign env root (real repo B != cwd repo A)"
  else
    bad "flag ON: expected FOREIGN-PROJECT-ROOT-GUARD-01 warning (got: ${out})"
  fi

  local real_a real_b
  real_a="$(cd "${repo_a}" && pwd -P)"
  real_b="$(cd "${repo_b}" && pwd -P)"
  if printf '%s' "${out}" | grep -q "${real_a}" && ! printf '%s' "${out}" | grep -qE "cwd_root=${real_b}|env=${real_a}"; then
    ok "flag ON: warning names cwd repo A as the winner, not repo B"
  else
    bad "flag ON: expected warning to name repo A as cwd/winner (got: ${out})"
  fi

  rm -rf "${d}"
}

# ---- Case 2: flag OFF (default) -- same shape, must NOT warn or override ----
case_foreign_repo_env_flag_off() {
  local d repo_a repo_b out
  d="$(mktemp -d)"
  repo_a="${d}/repo-a"; repo_b="${d}/repo-b"
  mkdir -p "${repo_a}" "${repo_b}"
  ( cd "${repo_a}" && git init -q && git commit -q --allow-empty -m init )
  ( cd "${repo_b}" && git init -q && git commit -q --allow-empty -m init )

  out="$(cd "${repo_a}" && CLAUDE_PROJECT_DIR="${repo_b}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    bad "flag OFF (default): must NOT warn -- this is the existing test-fixture shape (got: ${out})"
  else
    ok "flag OFF (default): no warning, legacy env-wins precedence preserved (zero regression risk)"
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
    LEADV2_FOREIGN_ROOT_GUARD=1 bash "${DC}" status 2>&1)"

  if printf '%s' "${out}" | grep -q 'FOREIGN-PROJECT-ROOT-GUARD-01'; then
    bad "bare-tmpdir override must NOT trigger the foreign-root guard even with the flag ON (got: ${out})"
  else
    ok "bare-tmpdir override (no .git) passes through unchanged even with the flag ON"
  fi

  rm -rf "${d}"
}

case_foreign_repo_env_flag_on
case_foreign_repo_env_flag_off
case_bare_tmpdir_override_untouched

printf '[test-foreign-project-root-guard] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
