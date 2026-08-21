#!/usr/bin/env bash
# test-lane-worktree-no-nesting.sh — NESTED-LANE-WORKTREES-01.
#
# WHY THIS TEST EXISTS (found 2026-08-22 while auditing the day's plugin fixes):
# `git worktree list` in persona-engine showed 13 lanes while only 6 existed under
# .claude/worktrees/. The other 7 lived at depth 2:
#
#   .claude/worktrees/5266d747/gitdir ->
#     /…/persona-engine/.claude/worktrees/14bd0c10/.claude/worktrees/5266d747/.git
#
# A worker running INSIDE lane 14bd0c10 spawned its own dispatch; resolve_root used
# `rev-parse --show-toplevel`, which inside a worktree returns the WORKTREE, so the
# child lane was created inside the parent lane. Nothing can reap those: `git worktree
# prune` sees live directories, and the SessionStart merged-sweep skips them because
# their parent is dirty. This is the mechanism by which the founder's 52-repo /
# 2000-uncommitted-change state rebuilt itself within a day of being cleaned.
#
# The fix normalizes any resolved root to the MAIN checkout via --git-common-dir, so a
# lane is created at the top level no matter whose cwd the dispatch inherited.
#
# Both directions are asserted: nesting must not happen, and the ordinary top-level
# case must keep working (a fix that broke normal dispatch would be worse than the bug).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../leadv2-lane-worktree.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-nest.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# The pre-fix script, straight out of git, so every case is falsified against it.
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_SUT="${WORK}/pre-sut.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/scripts/leadv2-lane-worktree.sh" > "${PRE_SUT}" 2>/dev/null || : > "${PRE_SUT}"
fi
if [[ -s "${PRE_SUT}" ]]; then chmod +x "${PRE_SUT}"; else PRE_SUT=""; fi

# A throwaway repo with one lane worktree already in it.
_mk_repo() { # <dir>
  local d="$1"
  mkdir -p "$d" && git -C "$d" init -q -b main 2>/dev/null
  git -C "$d" config user.email t@t && git -C "$d" config user.name t
  echo seed > "$d/seed.txt"
  git -C "$d" add -A && git -C "$d" commit -qm seed
  mkdir -p "$d/.claude/worktrees"
  git -C "$d" worktree add -q -b worktree-parent "$d/.claude/worktrees/parent" main 2>/dev/null
}

# Run `ensure` with cwd INSIDE the parent lane — the shape that produced the nesting.
# Env is scrubbed of LEADV2_PROJECT_ROOT the way a child dispatch inherits it: set to
# the PARENT LANE, which is exactly what a worker inside a lane exports.
_ensure_from_inside_lane() { # <sut> <repo>
  local sut="$1" repo="$2"
  ( cd "$repo/.claude/worktrees/parent" 2>/dev/null || exit 9
    LEADV2_PROJECT_ROOT="$repo/.claude/worktrees/parent" \
    LEADV2_LANE_WORKTREE_ERRF="${WORK}/err.log" \
      "$sut" ensure child 2>/dev/null )
}

_ensure_from_main() { # <sut> <repo>
  local sut="$1" repo="$2"
  ( cd "$repo" 2>/dev/null || exit 9
    LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_LANE_WORKTREE_ERRF="${WORK}/err.log" \
      "$sut" ensure plain 2>/dev/null )
}

# --- case 1: a lane created from inside a lane must NOT nest --------------------
case_no_nesting() { # <sut>
  local sut="$1" repo out
  repo="${WORK}/r$RANDOM$RANDOM"
  _mk_repo "$repo" || return 2
  out="$(_ensure_from_inside_lane "$sut" "$repo")" || return 1
  [[ -n "$out" ]] || return 1
  # Two occurrences of "worktrees/" in the path means depth 2 — the bug.
  local depth; depth="$(grep -o 'worktrees/' <<<"$out" | wc -l | tr -d ' ')"
  [[ "$depth" -le 1 ]] || return 1
  return 0
}

# --- case 2: git itself must not register a nested lane ------------------------
# Belt and braces: case 1 reads the printed path, this one reads git's own registry,
# which is what `worktree prune` and the sweep actually walk.
case_registry_flat() { # <sut>
  local sut="$1" repo
  repo="${WORK}/g$RANDOM$RANDOM"
  _mk_repo "$repo" || return 2
  _ensure_from_inside_lane "$sut" "$repo" >/dev/null || return 1
  local nested
  nested="$(git -C "$repo" worktree list --porcelain 2>/dev/null \
            | sed -n 's/^worktree //p' | grep -c 'worktrees/.*worktrees/')"
  [[ "${nested:-1}" == "0" ]] || return 1
  return 0
}

# --- case 3: the ordinary top-level dispatch still works -----------------------
case_plain_still_works() { # <sut>
  local sut="$1" repo out
  repo="${WORK}/p$RANDOM$RANDOM"
  _mk_repo "$repo" || return 2
  out="$(_ensure_from_main "$sut" "$repo")" || return 1
  [[ -d "$out" ]] || return 1
  [[ "$out" == "$repo/.claude/worktrees/plain" ]] || return 1
  return 0
}

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_SUT}" ]]; then "${fn}" "${PRE_SUT}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${SUT}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- also passed pre-fix (pre_rc=0); not evidence of this fix"
    return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n leadv2-lane-worktree.sh"
bash -n "${SUT}" || { log "FAIL: bash -n"; exit 1; }

run_case "lane-from-inside-lane-does-not-nest" case_no_nesting
run_case "git-registry-has-no-nested-lane"     case_registry_flat
run_case "top-level-dispatch-unaffected"       case_plain_still_works

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
