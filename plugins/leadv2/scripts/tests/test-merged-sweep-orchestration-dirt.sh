#!/usr/bin/env bash
# test-merged-sweep-orchestration-dirt.sh — NESTED-LANE-WORKTREES-01, half 2.
#
# WHY THIS TEST EXISTS: the SessionStart merged-sweep shipped on 2026-08-21 removed a
# lane only when `git worktree remove` accepted it without --force, i.e. when the tree
# was spotless. But every lane the plugin runs is dirty with files the PLUGIN ITSELF
# writes — docs/leadv2/, docs/handoff/, LEAD_V2_STATE.md, __pycache__ — so in practice
# it swept nothing. Found live on 2026-08-22: lane 641321b5 was merged (ahead=0) and
# its ONLY diff was docs/leadv2/open-threads.md.
#
# The assertions that matter: orchestration-only dirt is swept, REAL uncommitted
# work is never swept, an unmerged lane is never swept whatever its dirt, and (added
# 2026-08-24, NEWBORN-GUARD-01) a lane that was JUST created is never swept even
# though it is byte-for-byte identical git state to an already-merged clean lane --
# `ahead=0` + no dirt describes both. Reproduced live 2/2 the same day: dispatch
# creates the lane worktree, spawns the child session, and the child's own
# SessionStart hooks (this one included) ran before it wrote a single byte, deleting
# the directory it was about to work in ~7s after creation.
#
# Because a real merged-and-ready-to-reap lane is, by definition, not 0 seconds old,
# the sweep-positive cases below back-date each lane's creation-stamped git metadata
# (`<common-git-dir>/worktrees/<name>/gitdir`, written once by `git worktree add` and
# never rewritten by later commits/status calls in that worktree -- verified) before
# invoking the hook, so they exercise the newborn guard's "old enough" branch rather
# than accidentally depending on `LEADV2_SWEEP_MIN_AGE_S` being overridden to 0. The
# newborn case does the opposite: it deliberately leaves the metadata untouched (age
# 0) and asserts the lane survives and the advisory names it as too young.
#
# The second and third are the safety direction — a sweep that eats a deliverable
# costs far more than one that keeps a stale directory.
#
# The exclusion regex is READ OUT OF THE HOOK, and separately compared with its twin
# in leadv2-dispatch-product-close.sh, because two hand-kept copies of one pattern is
# the exact defect that produced a false lane refusal earlier the same day.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-merged-worktree-sweep.sh"
CLOSE_SH="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mw-sweep.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_HOOK="${WORK}/pre-hook.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh" > "${PRE_HOOK}" 2>/dev/null || : > "${PRE_HOOK}"
fi
if [[ -s "${PRE_HOOK}" ]]; then chmod +x "${PRE_HOOK}"; else PRE_HOOK=""; fi

# Back-date a lane worktree's CREATION-stamped git metadata so it reads as an hour
# old, matching the guard in leadv2-merged-worktree-sweep.sh: `git worktree add`
# writes `<common-git-dir>/worktrees/<name>/gitdir` exactly once and never rewrites
# it (unlike HEAD/index/logs in that same dir, which change on every commit/status
# call inside the worktree) -- verified empirically when the guard was built. Any
# case exercising the "should be swept" path must age the lane this way, or it is
# really testing `LEADV2_SWEEP_MIN_AGE_S` being large enough to cover a 0-second-old
# fixture by luck, not the sweep logic.
_backdate_lane_meta() { # <dir>
  local d="$1" meta_dir old_ts
  meta_dir="$(git -C "$d/.claude/worktrees/lane" rev-parse --git-dir 2>/dev/null)"
  [[ -n "$meta_dir" && -f "$meta_dir/gitdir" ]] || return 1
  old_ts="$(date -v-1H +%Y%m%d%H%M.%S 2>/dev/null || date -d '-1 hour' +%Y%m%d%H%M.%S)"
  touch -t "${old_ts%.*}" "$meta_dir/gitdir"
}

# A repo with one lane worktree, merged or not, dirty however the case wants.
_mk() { # <dir> <merged:yes|no> <dirt:orch|real|none> <age:old|new (default old)>
  local d="$1" merged="$2" dirt="$3" age="${4:-old}"
  mkdir -p "$d/docs/leadv2" && git -C "$d" init -q -b main
  git -C "$d" config user.email t@t && git -C "$d" config user.name t
  echo seed > "$d/seed.txt"; echo notes > "$d/docs/leadv2/open-threads.md"
  git -C "$d" add -A && git -C "$d" commit -qm seed
  mkdir -p "$d/.claude/worktrees"
  git -C "$d" worktree add -q -b worktree-lane "$d/.claude/worktrees/lane" main 2>/dev/null
  if [[ "$merged" == "no" ]]; then
    echo work > "$d/.claude/worktrees/lane/feature.txt"
    git -C "$d/.claude/worktrees/lane" add -A
    git -C "$d/.claude/worktrees/lane" commit -qm "unmerged work"
  fi
  case "$dirt" in
    orch) echo touched >> "$d/.claude/worktrees/lane/docs/leadv2/open-threads.md" ;;
    real) echo "uncommitted deliverable" > "$d/.claude/worktrees/lane/SAMPLES.md" ;;
  esac
  [[ "$age" == "old" ]] && _backdate_lane_meta "$d"
  return 0
}

_swept() { # <hook> <repo> -> 0 if the lane is gone
  local hook="$1" repo="$2"
  ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$hook" >/dev/null 2>&1 )
  [[ ! -d "$repo/.claude/worktrees/lane" ]]
}

# --- the fix: a merged lane dirty ONLY with orchestration files is swept ---------
case_orch_swept() { # <hook>
  local repo="${WORK}/o$RANDOM$RANDOM"; _mk "$repo" yes orch || return 2
  _swept "$1" "$repo"
}

# --- safety: real uncommitted work is NEVER swept -------------------------------
case_real_work_kept() { # <hook>
  local repo="${WORK}/r$RANDOM$RANDOM"; _mk "$repo" yes real || return 2
  _swept "$1" "$repo" && return 1
  [[ -f "$repo/.claude/worktrees/lane/SAMPLES.md" ]] || return 1
  return 0
}

# --- safety: an UNMERGED lane is never swept, orchestration dirt or not ----------
case_unmerged_kept() { # <hook>
  local repo="${WORK}/u$RANDOM$RANDOM"; _mk "$repo" no orch || return 2
  _swept "$1" "$repo" && return 1
  git -C "$repo/.claude/worktrees/lane" log --oneline -1 2>/dev/null | grep -q 'unmerged work'
}

# --- the regression this whole change exists to prevent: a lane that was JUST
# created (age 0, gitdir metadata NOT back-dated) is byte-for-byte the same git
# state as an already-merged clean lane -- ahead=0, no dirt but the plugin's own
# bookkeeping. Without the newborn guard this is exactly the sweep-positive path,
# and it is exactly what killed tasks e5be9e72 / 77ea471a on 2026-08-24: the hook
# ran as the child's own SessionStart hook and deleted the worktree the child was
# about to use, seconds after `leadv2-dispatch-code.sh` created it.
case_newborn_kept() { # <hook>
  local repo="${WORK}/n$RANDOM$RANDOM" out
  _mk "$repo" yes orch new || return 2
  out="$( ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$1" ) 2>&1 )"
  [[ -d "$repo/.claude/worktrees/lane" ]] || return 1
  echo "$out" | grep -qi "young" || return 1
  return 0
}

# --- no drift: the hook's regex and the close script's must stay identical -------
case_no_regex_drift() { # <hook>
  local a b
  a="$(grep -oE "_MW_ORCH_RE='[^']*'" "$1" 2>/dev/null | head -1 | sed "s/^_MW_ORCH_RE=//")"
  b="$(grep -oE "_PC_PORCELAIN_EXCLUDE_RE='[^']*'" "${CLOSE_SH}" 2>/dev/null | head -1 | sed "s/^_PC_PORCELAIN_EXCLUDE_RE=//")"
  [[ -n "$a" && -n "$b" ]] || return 1
  [[ "$a" == "$b" ]]
}

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_HOOK}" ]]; then "${fn}" "${PRE_HOOK}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${HOOK}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- also passed pre-fix; a safety invariant, not evidence of this fix"
    return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n leadv2-merged-worktree-sweep.sh"
bash -n "${HOOK}" || { log "FAIL: bash -n"; exit 1; }

run_case "merged-lane-with-orchestration-dirt-is-swept" case_orch_swept
run_case "real-uncommitted-work-is-never-swept"         case_real_work_kept
run_case "unmerged-lane-is-never-swept"                 case_unmerged_kept
run_case "newborn-lane-age-0-is-never-swept"            case_newborn_kept
run_case "exclusion-regex-matches-its-twin"             case_no_regex_drift

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
