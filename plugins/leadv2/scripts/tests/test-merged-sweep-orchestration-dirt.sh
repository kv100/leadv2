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
# The three assertions that matter are: orchestration-only dirt is swept, REAL
# uncommitted work is never swept, and an unmerged lane is never swept whatever its
# dirt. The second and third are the safety direction — a sweep that eats a
# deliverable costs far more than one that keeps a stale directory.
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

# A repo with one lane worktree, merged or not, dirty however the case wants.
# SWEEPER-LANE-SAFETY-01: the hook now consults the lane-protection gate, so
# every fixture carries a control plane (empty active.yaml — a MISSING one
# fails closed and protects everything) and every run disables the age probe:
# a freshly created fixture worktree is younger than the 48h grace window by
# definition, and this test isolates the dirt-classification behaviour the
# grace window would otherwise mask. Protection itself has its own test:
# test-worktree-lane-safety.sh.
_mk() { # <dir> <merged:yes|no> <dirt:orch|real|none>
  local d="$1" merged="$2" dirt="$3"
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
  mkdir -p "$d/state" && printf 'sessions: []\n' > "$d/state/active.yaml"
}

_swept() { # <hook> <repo> -> 0 if the lane is gone
  local hook="$1" repo="$2"
  ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$repo/state" \
      LEADV2_SWEEP_MIN_AGE_H=0 bash "$hook" >/dev/null 2>&1 )
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
run_case "exclusion-regex-matches-its-twin"             case_no_regex_drift

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
