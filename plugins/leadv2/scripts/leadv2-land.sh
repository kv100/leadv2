#!/usr/bin/env bash
# leadv2-land.sh — LAND-PATH-IS-BROKEN-01
#
# The single landing runner. 94% of close attempts terminate in a state that
# has no landing path by construction (blocked/fail never merge, never
# enqueue, never write a land-failure record), and the one automated path
# that does fire (the T11 block of leadv2-dispatch-product-close.sh) merges
# locally and never pushes, records nothing in a ledger that holds 1 row all
# time, and runs inside the main checkout only when that checkout happens to
# be clean. This script is the runner a `pass` verdict (or a lead) can call:
#
#   hygiene -> merge-safety gate -> ff main -> push -> land-ledger row
#
# Contract (brief §3/§5 — split with LANE-SALVAGE-TOOL-01):
#   - land takes ONE branch that is already a descendant of current main
#     (behind <= LEADV2_LAND_MAX_BEHIND, default 0). Anything further behind
#     is refused with reason=behind_main and named over to
#     plugins/leadv2/scripts/leadv2-lane-salvage.sh, which owns REBASING
#     THE PAST. land owns LANDING THE PRESENT. Not one line of the salvage
#     tool is imported, sourced or duplicated here — the contract between
#     them is that salvage's output branch is land's input.
#   - Deploy is NOT this script's job. leadv2-deploy-merge.sh's conflation
#     of merge and deploy is exactly why its rc=1 means two different
#     things. land ends at the push.
#
# Usage:
#   leadv2-land.sh <lane-branch> [--dry-run] [--no-ff]
#
# Environment:
#   LEADV2_LAND_MAX_BEHIND  max allowed behind-main count (default 0)
#   LEADV2_LAND_WRITE_SET   the lane's write set for the merged-tree check
#                           inside land_safety_gate (W-LEAD-LAST-MILE-01 §1):
#                           either a comma/colon-separated list of
#                           repo-relative paths, or a path to an existing
#                           file holding one path per line (# comments and
#                           blank lines ignored). A path is inside the set
#                           on exact match or when the entry is a directory
#                           prefix. Unset -> derived from the lane's own
#                           diff (merge-base..LANE_TIP), which is
#                           self-consistent by construction; the DECLARED
#                           form is what catches a lane touching main files
#                           outside its mission.
#   --no-ff                 merge with a real merge commit carrying the
#                           Landed-lane: / Landed-branch: trailers instead
#                           of ff (the lead's close-ritual shape). Default
#                           stays ff-only.
#   LEADV2_LAND_TASK_ID     task id for the merge-blocker.flag mirror
#                           (default: lane branch minus a leading "worktree-")
#   LEADV2_MERGE_TIMEOUT_SEC / _POLL_SEC / _STALE_SEC   passed through to
#                           leadv2-merge-queue.sh (its own env; defaults fine)
#   LEADV2_STATE_BASE / LEADV2_STATE_ROOT   passed through to
#                           leadv2-state-path.sh for the land-ledger location
#
# Land ledger (brief §4): one append-only JSONL row per land ATTEMPT, success
# or failure, at <control-plane>/land-ledger/<repo-slug>.jsonl — never inside
# docs/leadv2/ (that directory is un-committable and symlinked to /tmp
# mid-run). The row is PRE-WRITTEN pessimistically (outcome=failed
# reason=trap) the moment the attempt is identifiable, and the EXIT trap
# rewrites that same line with the final outcome. SIGKILL runs no trap at
# all, so the pre-written row is the only mechanism by which a kill -9
# mid-run still leaves outcome=failed in the ledger — by design.
#
# Exit codes: 0 = landed (all four §4 conditions verified against the repo,
# not asserted from a return code); 1 = refused or failed (see the row's
# reason); 2 = usage.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ROOT is normally the PRIMARY checkout (dirname of the git common dir), never
# a lane worktree. The product-close probe may run from a consumer repo whose
# plugin script is symlinked from the canonical checkout, so it supplies ROOT.
if [[ -n "${LEADV2_LAND_PROBE_ROOT:-}" ]]; then
  ROOT="$(cd "${LEADV2_LAND_PROBE_ROOT}" 2>/dev/null && pwd)"
else
  _COMMON_DIR="$(git -C "${SCRIPT_DIR}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "${_COMMON_DIR}" ]]; then
    printf 'leadv2-land: cannot resolve git common dir from %s\n' "${SCRIPT_DIR}" >&2
    exit 1
  fi
  ROOT="$(cd "$(dirname "${_COMMON_DIR}")" && pwd)"
fi
if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'leadv2-land: cannot resolve repository root %s\n' "${ROOT:-unset}" >&2
  exit 1
fi
REPO_SLUG="$(basename "${ROOT}")"

# shellcheck source=leadv2-branch-merged.sh
source "${SCRIPT_DIR}/leadv2-branch-merged.sh"

usage() {
  printf 'Usage: %s <lane-branch> [--dry-run] [--no-ff] | %s --root-dirt-check <lane-branch>\n' \
    "$(basename "$0")" "$(basename "$0")" >&2
}

DRY_RUN=0
NO_FF=0
ROOT_DIRT_CHECK=0
LANE=""
for _a in "$@"; do
  case "${_a}" in
    --dry-run) DRY_RUN=1 ;;
    --no-ff) NO_FF=1 ;;
    --root-dirt-check) ROOT_DIRT_CHECK=1 ;;
    -*) usage; exit 2 ;;
    *)
      if [[ -n "${LANE}" ]]; then usage; exit 2; fi
      LANE="${_a}"
      ;;
  esac
done
[[ -n "${LANE}" ]] || { usage; exit 2; }

MAX_BEHIND="${LEADV2_LAND_MAX_BEHIND:-0}"
[[ "${MAX_BEHIND}" =~ ^[0-9]+$ ]] || { printf 'leadv2-land: LEADV2_LAND_MAX_BEHIND must be a non-negative integer (got %s)\n' "${MAX_BEHIND}" >&2; exit 2; }

# ── ledger row state ─────────────────────────────────────────────────────────
L_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
L_LANE="${LANE}"
L_TIP="unknown"
L_MAIN_BEFORE="unknown"
L_MAIN_AFTER="same"
L_BEHIND=-1
L_AHEAD=-1
L_MODE="refused"
L_OUTCOME="failed"
L_REASON="trap"
L_FILES=0
L_PUSHED=false
L_HYGIENE=()
QUEUE_ID=""
QUEUE_ACQUIRED=0
TMP_BASE=""
WT_DIR=""
LEDGER=""
ROW_LINE=""

if [[ ${DRY_RUN} -eq 0 && ${ROOT_DIRT_CHECK} -eq 0 ]]; then
  LEDGER="$(PROJECT_ROOT="${ROOT}" "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link "land-ledger/${REPO_SLUG}.jsonl" 2>/dev/null || true)"
  if [[ -z "${LEDGER}" ]]; then
    printf 'leadv2-land: cannot resolve land-ledger path via leadv2-state-path.sh (repo %s)\n' "${ROOT}" >&2
    exit 1
  fi
fi

_jesc() { # <string> -> JSON-escaped string on stdout
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

_ledger_row() {
  local hy="" h
  for h in ${L_HYGIENE[@]+"${L_HYGIENE[@]}"}; do
    hy="${hy}\"$(_jesc "${h}")\","
  done
  hy="[${hy%,}]"
  printf '{"ts":"%s","lane":"%s","lane_tip":"%s","main_before":"%s","main_after":"%s","behind":%s,"ahead":%s,"mode":"%s","outcome":"%s","reason":"%s","files":%s,"pushed":%s,"hygiene":%s}' \
    "$(_jesc "${L_TS}")" "$(_jesc "${L_LANE}")" "$(_jesc "${L_TIP}")" "$(_jesc "${L_MAIN_BEFORE}")" "$(_jesc "${L_MAIN_AFTER}")" \
    "${L_BEHIND}" "${L_AHEAD}" "$(_jesc "${L_MODE}")" "$(_jesc "${L_OUTCOME}")" "$(_jesc "${L_REASON}")" \
    "${L_FILES}" "$(_jesc "${L_PUSHED}")" "${hy}"
}

# Pre-write the row as the pessimistic default. If the process dies in a way
# no trap can catch (kill -9), THIS is the row that remains: outcome=failed
# reason=trap. Every controlled exit rewrites the same line via
# _ledger_finalize in the EXIT trap, so a completed attempt still has
# exactly one row.
_ledger_prewrite() {
  [[ ${DRY_RUN} -eq 0 && -n "${LEDGER}" ]] || return 0
  mkdir -p "$(dirname "${LEDGER}")" 2>/dev/null || true
  local cur=0
  if [[ -f "${LEDGER}" ]]; then
    cur="$(wc -l < "${LEDGER}")"
    cur="${cur// /}"
  fi
  ROW_LINE=$((cur + 1))
  local saved_outcome="${L_OUTCOME}" saved_reason="${L_REASON}" saved_mode="${L_MODE}"
  L_OUTCOME="failed"; L_REASON="trap"; L_MODE="refused"
  printf '%s\n' "$(_ledger_row)" >> "${LEDGER}"
  L_OUTCOME="${saved_outcome}"; L_REASON="${saved_reason}"; L_MODE="${saved_mode}"
}

_ledger_finalize() {
  [[ ${DRY_RUN} -eq 0 && -n "${LEDGER}" ]] || return 0
  local row
  row="$(_ledger_row)"
  if [[ -n "${ROW_LINE}" && -f "${LEDGER}" ]]; then
    python3 - "${LEDGER}" "${ROW_LINE}" "${row}" <<'PY' 2>/dev/null || printf '%s\n' "${row}" >> "${LEDGER}"
import os, sys, tempfile
path, n, row = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with open(path) as f:
    lines = f.readlines()
if 0 < n <= len(lines):
    lines[n - 1] = row + "\n"
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as t:
        t.writelines(lines)
    os.rename(tmp, path)
else:
    with open(path, "a") as f:
        f.write(row + "\n")
PY
  else
    printf '%s\n' "${row}" >> "${LEDGER}"
  fi
}

# The EXIT-trap ledger row (brief §7.1 mutation-control target): one named
# body whose removal or disabling must turn the suite red.
land_ledger_finalize_row() {
  _ledger_finalize # EXIT-TRAP-LEDGER-ROW
}

_on_exit() {
  local _rc=$?
  if [[ -n "${QUEUE_ID}" && ${QUEUE_ACQUIRED} -eq 1 ]]; then
    # PROJECT_ROOT so the queue's own state-path resolution lands in THIS
    # repo's control-plane dir regardless of the caller's cwd.
    PROJECT_ROOT="${ROOT}" "${SCRIPT_DIR}/leadv2-merge-queue.sh" release "${QUEUE_ID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WT_DIR}" ]]; then
    # Remove ONLY the throwaway this script created, by explicit path.
    # NEVER `git worktree prune` — it killed two live lanes here once.
    git -C "${ROOT}" worktree remove --force "${WT_DIR}" >/dev/null 2>&1 || rm -rf "${WT_DIR}"
  fi
  [[ -n "${TMP_BASE}" ]] && rm -rf "${TMP_BASE}" 2>/dev/null
  land_ledger_finalize_row
  exit "${_rc}"
}
trap '_on_exit' EXIT
# EXIT alone never fires on an untrapped TERM/INT; route them through exit()
# so the trap (queue release, throwaway removal, ledger row) still runs.
trap 'exit 143' TERM
trap 'exit 130' INT

_lane_files() { # files touched by the lane itself (informative on refusals)
  if [[ "${L_TIP}" != "unknown" ]]; then
    L_FILES="$(git -C "${ROOT}" diff --name-only "${DEFAULT}..${L_TIP}" 2>/dev/null | wc -l | tr -d ' ')"
  fi
}

DEFAULT="$(lv2_default_branch "${ROOT}")"
if ! git -C "${ROOT}" rev-parse --verify --quiet "${DEFAULT}^{commit}" >/dev/null 2>&1; then
  printf 'leadv2-land: cannot resolve default branch %s in %s\n' "${DEFAULT}" "${ROOT}" >&2
  exit 1
fi
L_MAIN_BEFORE="$(git -C "${ROOT}" rev-parse "${DEFAULT}")"

LANE_TIP="$(git -C "${ROOT}" rev-parse --verify --quiet "${LANE}^{commit}" 2>/dev/null || true)"
if [[ -z "${LANE_TIP}" ]]; then
  L_OUTCOME="refused"; L_REASON="no_branch"; L_MODE="refused"; L_FILES=0
  printf 'leadv2-land: REFUSED reason=no_branch: lane branch %s does not exist\n' "${LANE}" >&2
  _ledger_prewrite
  exit 1
fi
L_TIP="${LANE_TIP}"
L_TASK="${LEADV2_LAND_TASK_ID:-${LANE#worktree-}}"
L_BEHIND="$(git -C "${ROOT}" rev-list --count "${LANE}..${DEFAULT}" 2>/dev/null || printf -- '-1')"
L_AHEAD="$(git -C "${ROOT}" rev-list --count "${DEFAULT}..${LANE}" 2>/dev/null || printf -- '-1')"
_ledger_prewrite

# ── step: refuse behind-main (the salvage handoff) ───────────────────────────
land_refuse_behind() {
  if [[ "${L_BEHIND}" -gt "${MAX_BEHIND}" ]]; then
    L_OUTCOME="refused"; L_REASON="behind_main"; L_MODE="refused"
    _lane_files
    printf 'leadv2-land: REFUSED reason=behind_main: %s is %s commit(s) behind %s (LEADV2_LAND_MAX_BEHIND=%s). Rebase the past with plugins/leadv2/scripts/leadv2-lane-salvage.sh (it carries stale lane commits onto salvage/%s from current %s), then land THAT branch with this script.\n' \
      "${LANE}" "${L_BEHIND}" "${DEFAULT}" "${MAX_BEHIND}" "${LANE}" "${DEFAULT}" >&2
    exit 1
  fi
}

# ── THE ONE LIST of pre-land state paths (brief §5 step 5) ───────────────────
# State paths remain relevant to throwaway untracking below. They are NOT a
# separate root-dirt exception list: root dirt is judged solely against the
# prospective merged tree, so unrelated state writes are left untouched.
_is_state_path() { # <path> -> rc 0 = on the list
  case "$1" in
    docs/leadv2|docs/leadv2/*|docs/LEAD_V2_STATE.md|docs/handoff/dispatch-nw*)
      return 0
      ;;
  esac
  return 1
}

land_hygiene_state() { # merged-tree root-dirt gate; leaves unrelated dirt untouched
  if ! land_root_dirt_check "${LAND_TIP}"; then
    L_OUTCOME="refused"; L_REASON="root_dirty_merge_intersection"; L_MODE="refused"
    _lane_files
    printf 'leadv2-land: REFUSED reason=root_dirty_merge_intersection: shared checkout dirt overlaps this lane merged tree\n' >&2
    exit 1
  fi
}

# ── step: derived untracking, inside the throwaway on the lane tip ───────────
# Files the lane tracks that must NOT land as tracked on main:
#   (a) derived: not tracked on main, and ignored per the ignore rules of the
#       tree that is about to land (the lane tip — which, at behind<=MAX, is
#       a superset of main's own rules). Probed with `git add --dry-run`
#       ONLY: `git check-ignore` exits 0 on a negation match and silently
#       mislabels every such file.
#   (b) belt: on the state list above and not tracked on main — stripped
#       even when nothing ignores them, because the brief's un-committable
#       list is a rule, not a prediction.
# Files already tracked on main are NEVER untracked here: dropping them would
# land a deletion of a main file — the exact silently-reverts-main shape
# leadv2-merge-safety-gate.sh exists to refuse.
land_throwaway_untrack() { # prints the tip to land (original, or hygiene-advanced)
  local changed f out rc untrack=""
  changed="$(git -C "${WT_DIR}" diff --name-only "${DEFAULT}" "${LANE_TIP}" 2>/dev/null || true)"
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    # only paths present in the lane tip, absent from main's tree
    git -C "${WT_DIR}" cat-file -e "${LANE_TIP}:${f}" 2>/dev/null || continue
    git -C "${ROOT}" cat-file -e "${DEFAULT}:${f}" 2>/dev/null && continue
    if _is_state_path "${f}"; then
      git -C "${WT_DIR}" rm --cached -q -- "${f}" 2>/dev/null || true
      untrack="${untrack}${f}\n"
      continue
    fi
    git -C "${WT_DIR}" rm --cached -q -- "${f}" 2>/dev/null || true
    out="$(git -C "${WT_DIR}" add --dry-run -- "${f}" 2>&1)"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
      # not ignored — put the identical content back in the index
      git -C "${WT_DIR}" add -- "${f}" 2>/dev/null || true
    elif printf '%s' "${out}" | grep -q 'ignored by one of your .gitignore'; then
      untrack="${untrack}${f}\n"
    else
      # probe inconclusive (e.g. pathspec did not match) — keep it tracked
      git -C "${WT_DIR}" add -- "${f}" 2>/dev/null || true
    fi
  done <<< "${changed}"
  if [[ -n "${untrack}" ]] && ! git -C "${WT_DIR}" diff --cached --quiet 2>/dev/null; then
    git -C "${WT_DIR}" commit -q -m "leadv2-land: untrack state/ignored-on-main files before ff to ${DEFAULT}" >/dev/null 2>&1
  fi
  git -C "${WT_DIR}" rev-parse HEAD
}

# ── the lane's write set (W-LEAD-LAST-MILE-01 §1) ───────────────────────────
# Repo-relative paths this lane is allowed to change on the default branch.
# LEADV2_LAND_WRITE_SET declares them (csv/colon list or a file, one per
# line); unset falls back to the lane's own diff from its merge-base, which
# is self-consistent by construction — the DECLARED form is the instrument
# that catches a lane touching main files outside its mission.
LAND_WRITE_SET=()
land_write_set_load() {
  local spec="${LEADV2_LAND_WRITE_SET:-}" item f base
  LAND_WRITE_SET=()
  if [[ -n "${spec}" && -f "${spec}" ]]; then
    while IFS= read -r f; do
      f="${f%%#*}"
      f="${f#"${f%%[![:space:]]*}"}"
      f="${f%"${f##*[![:space:]]}"}"
      [[ -n "${f}" ]] && LAND_WRITE_SET=(${LAND_WRITE_SET[@]+"${LAND_WRITE_SET[@]}"} "${f}")
    done < "${spec}"
  elif [[ -n "${spec}" ]]; then
    local IFS=',:'
    for item in ${spec}; do
      [[ -n "${item}" ]] && LAND_WRITE_SET=(${LAND_WRITE_SET[@]+"${LAND_WRITE_SET[@]}"} "${item}")
    done
  else
    base="$(git -C "${ROOT}" merge-base "${DEFAULT}" "${LANE_TIP}" 2>/dev/null || printf '%s' "${DEFAULT}")"
    # --no-renames: a rename is TWO paths (old + new); both are the lane's.
    while IFS= read -r f; do
      [[ -n "${f}" ]] && LAND_WRITE_SET=(${LAND_WRITE_SET[@]+"${LAND_WRITE_SET[@]}"} "${f}")
    done < <(git -C "${ROOT}" diff --name-only --no-renames "${base}" "${LANE_TIP}" 2>/dev/null)
  fi
}

land_in_write_set() { # <path> -> rc 0 = the lane may change this path
  local w
  for w in ${LAND_WRITE_SET[@]+"${LAND_WRITE_SET[@]}"}; do
    if [[ "$1" == "${w}" || "$1" == "${w}"/* ]]; then return 0; fi
  done
  return 1
}

# ── product-close root-dirt instrument (W18-ROOT-DIRTY-GATE-01) ────────────
# A whole-root porcelain check permanently blocks a shared checkout with harmless
# unrelated untracked residue. Build the exact clean merged tree first, then
# reuse land_in_write_set against THAT tree's changed-path set. Tracked dirt
# blocks only when this merge changes it; untracked dirt blocks only when the
# resulting tree needs that pathname. land_hygiene_state calls this same probe,
# so product-close and leadv2-land cannot drift into separate dirt policies.
land_root_dirt_check() { # <tip-to-land>; rc 0 safe, 1 conflict/error
  local tip="$1" mt_out mt_tree rc rec xy path old_path offenders=""
  mt_out="$(git -C "${ROOT}" merge-tree --write-tree --no-messages "${DEFAULT}" "${tip}" 2>&1)"
  rc=$?
  mt_tree="$(printf '%s\n' "${mt_out}" | head -1)"
  if [[ ${rc} -ne 0 || ! "${mt_tree}" =~ ^[0-9a-f]{7,40}$ ]]; then
    printf 'leadv2-land: REFUSED reason=root_dirty_merge_tree_unavailable: git merge-tree --write-tree %s %s produced no clean tree (rc=%s)\n' \
      "${DEFAULT}" "${tip}" "${rc}" >&2
    return 1
  fi

  # This deliberately reuses the same array and predicate as the landing
  # merged-tree gate above; a second path-membership rule would drift.
  LAND_WRITE_SET=()
  while IFS= read -r path; do
    [[ -n "${path}" ]] && LAND_WRITE_SET=(${LAND_WRITE_SET[@]+"${LAND_WRITE_SET[@]}"} "${path}")
  done < <(git -C "${ROOT}" diff --name-only --no-renames "${DEFAULT}" "${mt_tree}" 2>/dev/null)

  while IFS= read -r -d '' rec; do
    xy="${rec:0:2}"
    path="${rec:3}"
    # Porcelain v1 -z records the pre-rename path as a second NUL item.
    case "${xy}" in R*|C*|*R|*C) IFS= read -r -d '' old_path || true ;; esac
    if land_in_write_set "${path}"; then
      offenders="${offenders}${path}\n"
    fi
  done < <(git -C "${ROOT}" status --porcelain --untracked-files=all -z 2>/dev/null)

  if [[ -n "${offenders}" ]]; then
    printf 'leadv2-land: REFUSED reason=root_dirty_merge_intersection: shared checkout dirt intersects the merged-tree path set:\n%b' \
      "${offenders}" >&2
    return 1
  fi
  return 0
}

# ── merged-tree instrument (W-LEAD-LAST-MILE-01 §1) ─────────────────────────
# The only honest answer to "would merging this lane delete or revert main
# files outside its write set" is the tree `git merge-tree --write-tree`
# would actually produce — not a tip-to-tip file list. Entries the merge
# ADDS (A) are new lane files, never a main-file loss; every other entry
# (D = deletion, M/T = content overwrite/revert) must be inside the write
# set or the land is refused, one line per offending file.
land_merged_tree_check() { # <tip-to-land>
  local tip="$1" mt_out mt_tree rc st path offenders=""
  mt_out="$(git -C "${ROOT}" merge-tree --write-tree --no-messages "${DEFAULT}" "${tip}" 2>&1)"
  rc=$?
  mt_tree="$(printf '%s\n' "${mt_out}" | head -1)"
  if [[ ${rc} -ne 0 || ! "${mt_tree}" =~ ^[0-9a-f]{7,40}$ ]]; then
    L_OUTCOME="refused"; L_MODE="refused"; L_REASON="merged_tree_conflict"
    _lane_files
    printf 'leadv2-land: REFUSED reason=merged_tree_conflict: git merge-tree --write-tree %s %s produced no clean tree (rc=%s)\n' \
      "${DEFAULT}" "${tip}" "${rc}" >&2
    exit 1
  fi
  while IFS=$'\t' read -r st path; do
    [[ -n "${path}" ]] || continue
    [[ "${st}" == A* ]] && continue
    if ! land_in_write_set "${path}"; then
      offenders="${offenders} ${path}"
      printf 'leadv2-land: merged-tree %s outside the lane write set: %s\n' \
        "$([[ "${st}" == D* ]] && printf 'deletes main file' || printf 'changes main file')" "${path}" >&2
    fi
  done < <(git -C "${ROOT}" diff --name-status --no-renames "${DEFAULT}" "${mt_tree}" 2>/dev/null)
  if [[ -n "${offenders}" ]]; then
    L_OUTCOME="refused"; L_MODE="refused"; L_REASON="merged_tree_outside_write_set"
    _lane_files
    printf 'leadv2-land: REFUSED reason=merged_tree_outside_write_set: merging %s would touch main files outside the lane write set:%s (write set: %s entry(ies), %s)\n' \
      "${tip}" "${offenders}" "${#LAND_WRITE_SET[@]}" \
      "$([[ -n "${LEADV2_LAND_WRITE_SET:-}" ]] && printf 'declared' || printf 'derived')" >&2
    exit 1
  fi
}

# ── step: merge-safety gate (rc 0 safe / 1 refused / >=2 error) ──────────────
land_safety_gate() {
  local grc
  bash "${SCRIPT_DIR}/leadv2-merge-safety-gate.sh" "${ROOT}" "${LANE}" "${DEFAULT}" >/dev/null 2>&1
  grc=$?
  if [[ ${grc} -ne 0 ]]; then
    L_OUTCOME="refused"; L_MODE="refused"
    _lane_files
    if [[ ${grc} -eq 1 ]]; then
      L_REASON="safety_gate_refused"
      mkdir -p "${ROOT}/docs/handoff/${L_TASK}"
      # write_blocker shape, verbatim from leadv2-deploy-merge.sh
      printf -- 'merge_blocked: true\nreason: %s\nfailed_at: %s\ntask_id: %s\n' \
        "safety_gate_refused" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${L_TASK}" \
        > "${ROOT}/docs/handoff/${L_TASK}/merge-blocker.flag"
      printf 'leadv2-land: REFUSED reason=safety_gate_refused (mirror written to docs/handoff/%s/merge-blocker.flag)\n' "${L_TASK}" >&2
    else
      L_REASON="safety_gate_error"
      printf 'leadv2-land: REFUSED reason=safety_gate_error (gate rc=%s)\n' "${grc}" >&2
    fi
    exit 1
  fi
  land_write_set_load
  land_merged_tree_check "${LAND_TIP}" # MERGED-TREE-INSTRUMENT: removing this call must redden test-land-merged-tree.sh (W-LEAD-LAST-MILE-01 §1)
  return 0
}

# ── step: the four landing conditions (brief §4), against the repo ───────────
# 1. outcome=landed (reaching here means ff+push both returned 0)
# 2. main_after != main_before
# 3. merge-base --is-ancestor <lane_tip> <remote tip>
# 4. pushed: the remote's LIVE tip (ls-remote, not a local remote-tracking
#    ref, not a push return code) == main_after
land_verify_landed() {
  local remote_sha
  remote_sha="$(git -C "${ROOT}" ls-remote origin "refs/heads/${DEFAULT}" 2>/dev/null | awk '{print $1}' | head -1)"
  if [[ "${L_MAIN_AFTER}" == "${L_MAIN_BEFORE}" ]]; then
    printf 'leadv2-land: FAILED reason=verify_failed: main did not move (%s)\n' "${L_MAIN_AFTER}" >&2
    return 1
  fi
  if ! git -C "${ROOT}" merge-base --is-ancestor "${LANE_TIP}" "${remote_sha}" 2>/dev/null; then
    printf 'leadv2-land: FAILED reason=verify_failed: lane tip %s is not an ancestor of remote %s (%s)\n' \
      "${LANE_TIP}" "${DEFAULT}" "${remote_sha:-unresolved}" >&2
    return 1
  fi
  if [[ -z "${remote_sha}" || "${remote_sha}" != "${L_MAIN_AFTER}" ]]; then
    printf 'leadv2-land: FAILED reason=verify_failed: remote tip %s != main_after %s\n' \
      "${remote_sha:-unresolved}" "${L_MAIN_AFTER}" >&2
    return 1
  fi
  L_PUSHED=true
  return 0
}

# ── flow ─────────────────────────────────────────────────────────────────────
if [[ ${ROOT_DIRT_CHECK} -eq 1 ]]; then
  land_root_dirt_check "${LANE_TIP}"
  exit $?
fi

land_refuse_behind

# The ff runs in the primary checkout; it may only do so ON the default branch.
if [[ "$(git -C "${ROOT}" symbolic-ref --short -q HEAD 2>/dev/null || printf 'DETACHED')" != "${DEFAULT}" ]]; then
  L_OUTCOME="refused"; L_REASON="main_not_checked_out"; L_MODE="refused"
  _lane_files
  printf 'leadv2-land: REFUSED reason=main_not_checked_out: primary checkout HEAD is not on %s\n' "${DEFAULT}" >&2
  exit 1
fi

QUEUE_ID="land-${LANE}"
if [[ ${DRY_RUN} -eq 0 ]]; then
  # Both existing call sites of the queue swallow acquire's rc (brief §1a);
  # this one does not. PROJECT_ROOT for the same cwd-independence as the
  # release in the EXIT trap.
  if ! PROJECT_ROOT="${ROOT}" "${SCRIPT_DIR}/leadv2-merge-queue.sh" acquire "${QUEUE_ID}" >/dev/null 2>&1; then
    L_OUTCOME="refused"; L_REASON="queue_acquire_failed"; L_MODE="refused"
    _lane_files
    printf 'leadv2-land: REFUSED reason=queue_acquire_failed: merge-queue acquire %s did not return 0\n' "${QUEUE_ID}" >&2
    exit 1
  fi
  QUEUE_ACQUIRED=1
fi

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-land.XXXXXX")"
WT_DIR="${TMP_BASE}/wt"
if ! git -C "${ROOT}" worktree add "${WT_DIR}" --detach "${LANE_TIP}" >/dev/null 2>&1; then
  L_OUTCOME="failed"; L_REASON="worktree_failed"; L_MODE="refused"
  _lane_files
  printf 'leadv2-land: FAILED reason=worktree_failed: git worktree add on %s failed\n' "${LANE_TIP}" >&2
  exit 1
fi

LAND_TIP="$(land_throwaway_untrack)"

land_safety_gate
land_hygiene_state

if [[ ${DRY_RUN} -eq 1 ]]; then
  if [[ ${NO_FF} -eq 1 ]]; then
    printf 'leadv2-land: DRY-RUN ok — would merge --no-ff %s onto %s (trailers Landed-lane: %s / Landed-branch: %s) and push origin %s (state restored: %d file(s); land tip %s)\n' \
      "${LAND_TIP}" "${DEFAULT}" "${L_TASK}" "${LANE}" "${DEFAULT}" "${#L_HYGIENE[@]}" "${LAND_TIP}" >&2
  else
    printf 'leadv2-land: DRY-RUN ok — would ff %s to %s and push origin %s (state restored: %d file(s); land tip %s)\n' \
      "${DEFAULT}" "${LAND_TIP}" "${DEFAULT}" "${#L_HYGIENE[@]}" "${LAND_TIP}" >&2
  fi
  exit 0
fi

if [[ ${NO_FF} -eq 1 ]]; then
  # The lead's close-ritual shape (W-LEAD-LAST-MILE-01 §3): a real merge
  # commit carrying the Landed-lane: / Landed-branch: trailers instead of
  # ff. Still the SAME lander — queue, ledger, push and verification are
  # unchanged; only the merge command differs.
  if [[ "${L_AHEAD}" -eq 0 ]]; then
    L_OUTCOME="refused"; L_REASON="noop_land"; L_MODE="refused"
    _lane_files
    printf 'leadv2-land: REFUSED reason=noop_land: %s is 0 commit(s) ahead of %s — --no-ff would land an empty merge\n' \
      "${LANE}" "${DEFAULT}" >&2
    exit 1
  fi
  L_MODE="no_ff"
  if ! git -C "${ROOT}" merge --no-ff -m "merge: lane ${L_TASK} landed

Landed-lane: ${L_TASK}
Landed-branch: ${LANE}" "${LAND_TIP}" >/dev/null 2>&1; then
    L_OUTCOME="failed"; L_REASON="merge_failed"
    _lane_files
    printf 'leadv2-land: FAILED reason=merge_failed: git merge --no-ff %s failed\n' "${LAND_TIP}" >&2
    exit 1
  fi
else
  if ! git -C "${ROOT}" merge --ff-only "${LAND_TIP}" >/dev/null 2>&1; then
    L_OUTCOME="failed"; L_REASON="ff_failed"; L_MODE="ff"
    _lane_files
    printf 'leadv2-land: FAILED reason=ff_failed: git merge --ff-only %s failed\n' "${LAND_TIP}" >&2
    exit 1
  fi
fi
L_MAIN_AFTER="$(git -C "${ROOT}" rev-parse "${DEFAULT}")"

if ! git -C "${ROOT}" push origin "${DEFAULT}" >/dev/null 2>&1; then
  # main has already moved locally; the row records that honestly
  L_OUTCOME="failed"; L_REASON="push_failed"; L_MODE="$([[ ${NO_FF} -eq 1 ]] && printf 'no_ff' || printf 'ff')"
  L_PUSHED=false
  L_FILES="$(git -C "${ROOT}" diff --name-only "${L_MAIN_BEFORE}..${L_MAIN_AFTER}" 2>/dev/null | wc -l | tr -d ' ')"
  printf 'leadv2-land: FAILED reason=push_failed: main moved to %s locally but the push was refused\n' "${L_MAIN_AFTER}" >&2
  exit 1
fi

L_OUTCOME="landed"; L_REASON="ok"; L_MODE="$([[ ${NO_FF} -eq 1 ]] && printf 'no_ff' || printf 'ff')"
if ! land_verify_landed; then
  L_OUTCOME="failed"; L_REASON="verify_failed"; L_MODE="ff"
  exit 1
fi
L_FILES="$(git -C "${ROOT}" diff --name-only "${L_MAIN_BEFORE}..${L_MAIN_AFTER}" 2>/dev/null | wc -l | tr -d ' ')"
printf 'leadv2-land: LANDED %s onto %s (%s -> %s, files=%s, hygiene=%d)\n' \
  "${LANE}" "${DEFAULT}" "${L_MAIN_BEFORE}" "${L_MAIN_AFTER}" "${L_FILES}" "${#L_HYGIENE[@]}" >&2
exit 0
