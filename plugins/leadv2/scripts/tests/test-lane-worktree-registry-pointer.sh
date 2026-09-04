#!/usr/bin/env bash
# test-lane-worktree-registry-pointer.sh — WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01
#
# THE DEFECT: the live lane registry lives OUTSIDE the repo at
# ~/.claude/leadv2-state/<slug>/active.yaml (resolved by leadv2-state-path.sh).
# On most worktree-* branches, docs/leadv2/active.yaml is still a stale
# TRACKED file left over from before LEAD-CONTROL-PLANE-01. When `git
# worktree add` checks out such a branch it materializes that frozen copy
# inside the new worktree, and every reader of docs/leadv2/active.yaml in the
# new worktree then sees stale/wrong data instead of the live registry -- a
# live lane can read back as dead and get re-dispatched.
#
# THE FIX (degrade_frozen_registry_copy() in leadv2-lane-worktree.sh, called
# from BOTH `git worktree add` sites -- fresh-branch and attach-to-existing):
# after the worktree exists, a REAL (non-symlink) docs/leadv2/active.yaml is
# replaced with a symlink to the live control-plane path and marked
# `--skip-worktree`. If the symlink cannot be created, the frozen file is
# overwritten with an obviously-not-YAML sentinel instead of being left in
# place looking authoritative.
#
# This suite is entirely self-contained scratch git repos (never this repo's
# own refs) and NEVER calls `git worktree prune` (would kill sibling live
# lanes in this shared tree). Every worktree this suite creates is removed
# via `git worktree remove` in its own cleanup, both on success and on
# early exit (trap).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_SH="${SCRIPT_DIR}/../leadv2-lane-worktree.sh"
STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

if ! bash -n "${LANE_SH}"; then
  fail "0: bash -n ${LANE_SH}"
  printf 'test-lane-worktree-registry-pointer: %d passed, %d failed\n' "${PASS}" "$((FAIL+1))"
  exit 1
fi
pass "0: bash -n ${LANE_SH}"

FIXTURES=()
WT_CLEANUP=()  # "repo-dir:worktree-path" pairs, removed in cleanup — never pruned
cleanup() {
  local pair repo wtp
  for pair in "${WT_CLEANUP[@]:-}"; do
    [[ -n "${pair}" ]] || continue
    repo="${pair%%:*}"; wtp="${pair#*:}"
    git -C "${repo}" worktree remove --force "${wtp}" >/dev/null 2>&1 || true
  done
  local d
  for d in "${FIXTURES[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done
}
trap cleanup EXIT

new_repo_with_frozen_registry() { # -> prints repo dir; main carries a REAL
                                   # tracked docs/leadv2/active.yaml (the
                                   # stale pre-LEAD-CONTROL-PLANE-01 artifact)
  local d
  d="$(mktemp -d)"
  FIXTURES+=("${d}")
  ( cd "${d}" \
      && git init -q -b main \
      && git config user.email t@example.com && git config user.name t \
      && mkdir -p docs/leadv2 \
      && printf 'lanes: {}\nstale_marker: true\n' > docs/leadv2/active.yaml \
      && git add docs/leadv2/active.yaml \
      && git commit -q -m "base (tracks stale active.yaml)" )
  printf '%s\n' "${d}"
}

run_ensure() { # <repo-dir> <task-id> <state-base> <outf> <errf>
  local d="$1" tid="$2" sbase="$3" outf="$4" errf="$5"
  ( cd "${d}" && LEADV2_PROJECT_ROOT="${d}" LEADV2_WORKTREE_DIR="${d}/lane-worktrees" \
      LEADV2_CODEX_WORKTREE_TRUST=off LEADV2_LANE_WORKTREE_ERRF="${errf}" \
      LEADV2_LANE_RESURRECT_GUARD=0 LEADV2_STATE_BASE="${sbase}" \
      bash -c "source '${LANE_SH}'; cmd_ensure '${tid}'" ) >"${outf}" 2>"${errf}"
}

live_active_yaml_path() { # <lane_path> <state-base> -> prints resolved live path
  local lp="$1" sbase="$2"
  PROJECT_ROOT="${lp}" LEADV2_STATE_BASE="${sbase}" "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null
}

outf="$(mktemp)"; errf="$(mktemp)"

# ── 1: fresh-branch site (worktree add -b) -- BEFORE shape is a frozen plain
#      file when the fix's helper is bypassed ────────────────────────────────
d="$(new_repo_with_frozen_registry)"
before_path="${d}/before-fresh"
if git -C "${d}" worktree add -b before-fresh-branch "${before_path}" main >/dev/null 2>&1; then
  WT_CLEANUP+=("${d}:${before_path}")
  if [[ -f "${before_path}/docs/leadv2/active.yaml" ]] && [[ ! -L "${before_path}/docs/leadv2/active.yaml" ]] \
     && grep -q stale_marker "${before_path}/docs/leadv2/active.yaml"; then
    pass "1: BEFORE (raw git worktree add, no degrade helper) -- frozen plain file resurrected, exactly the defect"
  else
    fail "1: BEFORE shape not as expected (file missing/symlink/content changed)"
  fi
else
  fail "1: setup — raw git worktree add failed"
fi

# ── 2: fresh-branch site, AFTER fix -- cmd_ensure resolves the symlink ──────
d="$(new_repo_with_frozen_registry)"
sbase="${d}/state-base"
run_ensure "${d}" "TASK-FRESH" "${sbase}" "${outf}" "${errf}"
lane_path="$(cat "${outf}")"
WT_CLEANUP+=("${d}:${lane_path}")
expect_target="$(live_active_yaml_path "${lane_path}" "${sbase}")"
actual_target=""
[[ -L "${lane_path}/docs/leadv2/active.yaml" ]] && actual_target="$(readlink "${lane_path}/docs/leadv2/active.yaml")"
if [[ -n "${expect_target}" ]] && [[ "${actual_target}" == "${expect_target}" ]]; then
  pass "2: AFTER (fresh-branch site) -- frozen file replaced by symlink to the live registry ($(basename "${expect_target}"))"
else
  fail "2: got symlink target='${actual_target}' want='${expect_target}' (stderr: $(cat "${errf}"))"
fi

skip_flag="$(git -C "${lane_path}" ls-files -v docs/leadv2/active.yaml 2>/dev/null | cut -c1)"
if [[ "${skip_flag}" == "S" ]]; then
  pass "2b: AFTER (fresh-branch site) -- git update-index --skip-worktree applied"
else
  fail "2b: expected skip-worktree flag 'S', got '${skip_flag}' (git ls-files -v)"
fi

# ── 3: attach-to-existing-branch site -- BEFORE shape ───────────────────────
d="$(new_repo_with_frozen_registry)"
( cd "${d}" && git branch before-attach-branch main )
before_path2="${d}/before-attach"
if git -C "${d}" worktree add "${before_path2}" before-attach-branch >/dev/null 2>&1; then
  WT_CLEANUP+=("${d}:${before_path2}")
  if [[ -f "${before_path2}/docs/leadv2/active.yaml" ]] && [[ ! -L "${before_path2}/docs/leadv2/active.yaml" ]]; then
    pass "3: BEFORE (raw git worktree add, attach site) -- frozen plain file resurrected"
  else
    fail "3: BEFORE shape (attach site) not as expected"
  fi
else
  fail "3: setup — raw git worktree add (attach) failed"
fi

# ── 4: attach-to-existing-branch site, AFTER fix ────────────────────────────
# TASK-ATTACH's branch (worktree-TASK-ATTACH) is created up front with NO
# worktree directory -- cmd_ensure's fresh-branch `worktree add -b` then
# fails (branch exists) and falls through to the attach site, exactly the
# "branch survived a prior aborted run" path the comment above it describes.
d="$(new_repo_with_frozen_registry)"
( cd "${d}" && git branch worktree-TASK-ATTACH main )
sbase2="${d}/state-base"
run_ensure "${d}" "TASK-ATTACH" "${sbase2}" "${outf}" "${errf}"
lane_path2="$(cat "${outf}")"
WT_CLEANUP+=("${d}:${lane_path2}")
expect_target2="$(live_active_yaml_path "${lane_path2}" "${sbase2}")"
actual_target2=""
[[ -L "${lane_path2}/docs/leadv2/active.yaml" ]] && actual_target2="$(readlink "${lane_path2}/docs/leadv2/active.yaml")"
if [[ -n "${expect_target2}" ]] && [[ "${actual_target2}" == "${expect_target2}" ]]; then
  pass "4: AFTER (attach-to-existing-branch site) -- frozen file replaced by symlink to the live registry"
else
  fail "4: got symlink target='${actual_target2}' want='${expect_target2}' (stderr: $(cat "${errf}"))"
fi

# ── 5: a branch that never tracked active.yaml is left alone (no-op path) ──
d="$(mktemp -d)"; FIXTURES+=("${d}")
( cd "${d}" && git init -q -b main && git config user.email t@example.com \
    && git config user.name t && git commit -q --allow-empty -m base )
sbase3="${d}/state-base"
run_ensure "${d}" "TASK-NOTRACK" "${sbase3}" "${outf}" "${errf}"
lane_path3="$(cat "${outf}")"
WT_CLEANUP+=("${d}:${lane_path3}")
if [[ ! -e "${lane_path3}/docs/leadv2/active.yaml" ]]; then
  pass "5: branch never tracked active.yaml -- left untouched (no phantom file created)"
else
  fail "5: expected no docs/leadv2/active.yaml at all, found one"
fi

rm -f "${outf}" "${errf}"

printf 'test-lane-worktree-registry-pointer: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
