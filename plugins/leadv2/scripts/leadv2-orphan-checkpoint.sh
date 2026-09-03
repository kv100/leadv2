#!/usr/bin/env bash
# leadv2-orphan-checkpoint.sh — D4-NO-PATH-LOSES-WORK-01
#
# WHY THIS EXISTS: six times recently a worker died mid-edit and a human had
# to manually rescue the dirty worktree; then a host-app crash took seven
# lanes at once (1-2 commits, 11-20 dirty files each), nothing committed,
# nothing announced. The three checkpoint mechanisms that already existed —
# leadv2_worker_commit_epilogue (lib/leadv2-worker-epilogue.sh),
# pc_stop_gate_autocommit (leadv2-dispatch-product-close.sh), and
# leadv2-turncap-checkpoint-commit.sh — ALL run inside the worker's own
# process tree, so a SIGKILL (or a full host-tree death) takes every one of
# them down with the process it was meant to protect. This script is the
# fix: an EXTERNAL periodic sweeper, run outside any lane's process tree,
# that finds dirty worktrees whose worker has ACTUALLY exited (never mtime,
# never a bare pgrep — see lib/leadv2-lane-worker-alive.sh for why both give
# false answers) and checkpoints them so a died-mid-edit lane's work is a
# durable git commit, not a directory a human has to rescue by hand.
#
# NEVER a replacement for the in-process mechanisms above — this is a
# last-resort backstop for the case those three cannot reach: process is
# already gone. Ordering matters: this MUST run before any worktree-removal
# sweep (leadv2-merged-worktree-sweep.sh, leadv2-phase8-close.sh's own sweep
# block) ever looks at the same worktree — checkpoint-then-sweep, never the
# reverse (b413968c discard-then-remove incident; see wiring comments at
# both call sites).
#
# Per-worktree decision (a-g):
#   a. Liveness — skip ANY worktree whose worker is still alive (D2-D5,
#      lib/leadv2-lane-worker-alive.sh). Never race a live worker.
#   b. Clean — skip a worktree with no dirty tracked/untracked files. No
#      empty commits, ever.
#   c. Scope resolution — best-effort recovery of the lane's own declared
#      LANE_WRITES from its coder-wrapper run cache (~/.claude/cache/
#      {glm,kimi,freepool}-runs/*/meta.yaml, matched by `cwd:`), reusing
#      lib/leadv2-mission-writeset.sh's coverage-matching semantics (exact /
#      directory-prefix / glob / tail match) rather than reinventing that
#      comparison here (D7). If no run cache entry can be matched to this
#      worktree, LANE_WRITES is unknowable — the WHOLE dirty set is treated
#      as IN-SCOPE (committed straight to the lane's own branch, see (e))
#      rather than quarantined or skipped: this is the common case (a
#      one-off/manual worktree, or a run cache that has already been
#      cleaned up) and quarantining it would leave real work sitting on a
#      side branch nobody looks at first, which is worse than the (rare)
#      false-positive of committing an out-of-scope file straight to the
#      lane branch. Quarantine (g) is reserved for paths PROVEN
#      out-of-scope by an actually-recovered LANE_WRITES declaration.
#   d. Partition dirty paths into in_scope[] / out_scope[] using (c).
#   e. In-scope commit onto the lane's OWN checked-out branch, using the
#      SAME temp-index discipline as pc_stop_gate_autocommit (D7): a
#      throwaway GIT_INDEX_FILE seeded from `read-tree HEAD`, `add` the
#      concrete dirty paths, `diff --cached --quiet` as the no-op guard,
#      commit, then `reset HEAD --` those paths in the REAL index so the
#      worktree reads clean afterward (idempotent — A3).
#   f. Out-of-scope commit onto a side branch `orphan-quarantine/<lane>`
#      (D8), built via commit-tree/update-ref so the worktree's checked-out
#      branch and real index are never touched — a lane's in-flight state is
#      never perturbed by quarantining files it never claimed.
#   g. Journal + one-line human summary + the exact resume command.
#
# Kill switches (D12, one-flag rollback, no commits made):
#   LEADV2_ORPHAN_CHECKPOINT=0   — disable entirely
#   --dry-run                    — report what WOULD be checkpointed, commit nothing
#
# Commit message token: "(ORPHAN)" (D6) — deliberately distinct from
# pc_stop_gate_autocommit's "(STOP-GATE)" so leadv2-dispatch-code.sh:3175's
# exact-string grep for the STOP-GATE message and leadv2-lane-liveness.sh's
# "landed" heuristic are both unaffected by this script's commits.
#
# Bash 3.2 safe. D5: no bare unquoted `for p in $pids` anywhere in this file
# or in lib/leadv2-lane-worker-alive.sh — always `while IFS= read -r`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${LEADV2_ORPHAN_CHECKPOINT:-1}" == "0" ]] && { echo "[orphan-checkpoint] disabled via LEADV2_ORPHAN_CHECKPOINT=0"; exit 0; }

DRY_RUN=0
PROJECT_ROOT=""
ONLY_LANE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --lane) ONLY_LANE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "${PROJECT_ROOT}" ]]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "${PWD}")"
fi
[[ -d "${PROJECT_ROOT}" ]] || { echo "[orphan-checkpoint] project root not found: ${PROJECT_ROOT}" >&2; exit 1; }

# shellcheck source=lib/leadv2-lane-worker-alive.sh
source "${SCRIPT_DIR}/lib/leadv2-lane-worker-alive.sh"
# shellcheck source=lib/leadv2-mission-writeset.sh
source "${SCRIPT_DIR}/lib/leadv2-mission-writeset.sh"

JOURNAL_BIN="${SCRIPT_DIR}/leadv2-journal.sh"

_oc_log() { printf '[orphan-checkpoint] %s\n' "$*" >&2; }

# _lv2_orphan_lane_id <wt_path> -> lane id (basename of the worktree dir),
# the same identifier used throughout this repo as the lane/task id.
_lv2_orphan_lane_id() { basename "$1"; }

# _lv2_orphan_find_run_meta <wt_path> -> stdout: path to the matching
# meta.yaml, or nothing if none found. Best-effort: searches the durable,
# on-disk coder-wrapper run caches (outside any process tree, so this
# survives the exact SIGKILL this script exists to recover from) for a
# `cwd:` line equal to <wt_path>. Picks the most recently modified match
# when more than one round left a cache entry.
_lv2_orphan_find_run_meta() {
  local wt_path="$1" cache_root="${LEADV2_ORPHAN_RUN_CACHE_ROOT:-${HOME}/.claude/cache}" f best="" best_m=-1 m
  local -a globs=("${cache_root}"/glm-runs/*/meta.yaml "${cache_root}"/kimi-runs/*/meta.yaml "${cache_root}"/freepool-runs/*/meta.yaml)
  local recorded_cwd
  for f in "${globs[@]}"; do
    [[ -f "${f}" ]] || continue
    # Compare canonically, not by exact string: the wrapper records $PWD
    # (bash's LOGICAL cwd, symlink-preserving) at meta_dir/cwd-write time,
    # which can differ from wt_path's resolved form on any host where the
    # worktree root was reached through a symlink (macOS /tmp, $TMPDIR).
    # An exact-string grep silently drops a real run-meta match in exactly
    # the case this script exists to handle: the worker already died, so
    # nobody is left to have written a canonical cwd for it.
    recorded_cwd="$(grep -m1 '^cwd:' "${f}" 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
    [[ -n "${recorded_cwd}" ]] || continue
    [[ "$(_lv2_lane_realpath "${recorded_cwd}")" == "${wt_path}" ]] || continue
    m="$( [[ "$(uname -s)" == "Darwin" ]] && stat -f '%m' "${f}" 2>/dev/null || stat -c '%Y' "${f}" 2>/dev/null || echo 0)"
    [[ "${m}" =~ ^[0-9]+$ ]] || m=0
    if (( m > best_m )); then best_m="${m}"; best="${f}"; fi
  done
  [[ -n "${best}" ]] && printf '%s\n' "${best}"
}

# _lv2_orphan_lane_writes_csv <meta_yaml> -> stdout: LANE_WRITES csv, or
# empty. Same convention as _lv2_epilogue_lane_writes
# (lib/leadv2-worker-epilogue.sh) and leadv2_writeset_missing's own internal
# fallback (lib/leadv2-mission-writeset.sh) — a `^LANE_WRITES:` line in the
# mission/prompt text, comma-split.
_lv2_orphan_lane_writes_csv() {
  local meta="$1" prompt_file dir
  dir="$(dirname "${meta}")"
  prompt_file="$(grep -m1 '^prompt_file:' "${meta}" 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
  [[ -z "${prompt_file}" || ! -f "${prompt_file}" ]] && prompt_file="${dir}/prompt.txt"
  [[ -f "${prompt_file}" ]] || return 0
  grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${prompt_file}" 2>/dev/null \
    | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I'
}

# _lv2_orphan_recorded_pid <meta_yaml> -> stdout: pid, or empty.
_lv2_orphan_recorded_pid() {
  grep -m1 '^pid:' "$1" 2>/dev/null | cut -d: -f2- | sed 's/^ //' | grep -E '^[0-9]+$' || true
}

# _lv2_orphan_out_of_scope <lane_writes_csv> <dirty_paths_file> -> stdout:
# the subset of dirty_paths NOT covered by lane_writes_csv, one per line.
# D7: reuses leadv2_writeset_missing's exact coverage-matching semantics
# (exact / directory-prefix / glob / relative-tail match) rather than
# reimplementing that comparison — this file constructs a minimal "## Done
# means" mission fragment naming each dirty path as a backticked, >=2-
# segment token (leadv2_writeset_extract_required's own requirement) and
# lets the shared library decide coverage.
_lv2_orphan_out_of_scope() {
  local lane_writes_csv="$1" dirty_file="$2" fake_mission path
  fake_mission="## Done means"$'\n'
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    fake_mission+=$'\n'"- \`${path}\`"
  done < "${dirty_file}"
  printf '%s\n' "${fake_mission}" | leadv2_writeset_missing "${lane_writes_csv}"
}

# _lv2_orphan_inscope_commit <lane_root> <lane_id> <path...> -> rc0
# committed, rc2 nothing-to-commit (already clean at these paths), rc1
# failure. Verbatim discipline copy of pc_stop_gate_autocommit's temp-index
# pattern (D7): throwaway GIT_INDEX_FILE seeded from `read-tree HEAD`,
# concrete `add`, `diff --cached --quiet` as the no-op guard, commit, then
# `reset HEAD --` the real index so the worktree reads clean afterward.
#
# NEGATIVE CONTROL TARGET (D10): deleting the `diff --cached --quiet` guard
# below turns A4 (clean lane -> HEAD unchanged, no empty commit) RED.
_lv2_orphan_inscope_commit() {
  local lane_root="$1" lane_id="$2"
  shift 2
  local -a files=("$@")
  [[ ${#files[@]} -gt 0 ]] || return 2

  local idx
  idx="$(mktemp "${TMPDIR:-/tmp}/leadv2-orphan-checkpoint-index.XXXXXX")" || return 1
  if ! GIT_INDEX_FILE="${idx}" git -C "${lane_root}" read-tree HEAD >/dev/null 2>&1 \
     || ! GIT_INDEX_FILE="${idx}" git -C "${lane_root}" add -- "${files[@]}" >/dev/null 2>&1; then
    rm -f "${idx}"
    return 1
  fi
  if GIT_INDEX_FILE="${idx}" git -C "${lane_root}" diff --cached --quiet 2>/dev/null; then
    rm -f "${idx}"
    return 2
  fi
  if GIT_INDEX_FILE="${idx}" git -C "${lane_root}" commit -q -m "wip(${lane_id}): orphan-checkpoint after worker exit (ORPHAN)" >/dev/null 2>&1; then
    git -C "${lane_root}" reset -q HEAD -- "${files[@]}" >/dev/null 2>&1 || true
    rm -f "${idx}"
    return 0
  fi
  rm -f "${idx}"
  return 1
}

# _lv2_orphan_quarantine_commit <lane_root> <lane_id> <path...> -> rc0
# committed, rc2 unchanged-since-last-quarantine, rc1 failure. D8: builds a
# commit on `orphan-quarantine/<lane_id>` via commit-tree/update-ref so the
# worktree's checked-out branch and real index are NEVER touched — a lane's
# own in-flight state is not perturbed by quarantining files it never
# claimed as its own write-set.
_lv2_orphan_quarantine_commit() {
  local lane_root="$1" lane_id="$2" quarantine_branch
  quarantine_branch="orphan-quarantine/${lane_id}"
  shift 2
  local -a files=("$@")
  [[ ${#files[@]} -gt 0 ]] || return 2

  local base_sha
  base_sha="$(git -C "${lane_root}" rev-parse --verify -q "refs/heads/${quarantine_branch}" 2>/dev/null || true)"

  local idx
  idx="$(mktemp "${TMPDIR:-/tmp}/leadv2-orphan-quarantine-index.XXXXXX")" || return 1
  if [[ -n "${base_sha}" ]]; then
    GIT_INDEX_FILE="${idx}" git -C "${lane_root}" read-tree "${base_sha}" >/dev/null 2>&1 || true
  else
    GIT_INDEX_FILE="${idx}" git -C "${lane_root}" read-tree HEAD >/dev/null 2>&1 || true
  fi
  if ! GIT_INDEX_FILE="${idx}" git -C "${lane_root}" add -- "${files[@]}" >/dev/null 2>&1; then
    rm -f "${idx}"
    return 1
  fi
  if [[ -n "${base_sha}" ]] && GIT_INDEX_FILE="${idx}" git -C "${lane_root}" diff --cached --quiet "${base_sha}" 2>/dev/null; then
    rm -f "${idx}"
    return 2
  fi

  local tree_sha commit_sha
  tree_sha="$(GIT_INDEX_FILE="${idx}" git -C "${lane_root}" write-tree 2>/dev/null)"
  rm -f "${idx}"
  [[ -n "${tree_sha}" ]] || return 1

  local -a parent_args=()
  [[ -n "${base_sha}" ]] && parent_args=(-p "${base_sha}")
  # bash 3.2 + set -u: "${parent_args[@]}" on a declared-but-EMPTY array
  # (no prior quarantine commit) throws "unbound variable" pre-4.4 — the
  # same hazard leadv2_writeset_missing's own decls loop guards against
  # (lib/leadv2-mission-writeset.sh H1). ${arr[@]+"${arr[@]}"} expands to
  # nothing instead of erroring when the array is empty.
  commit_sha="$(git -C "${lane_root}" commit-tree "${tree_sha}" ${parent_args[@]+"${parent_args[@]}"} \
    -m "wip(${lane_id}): orphan-checkpoint quarantine out-of-scope dirty files (ORPHAN)" 2>/dev/null)"
  [[ -n "${commit_sha}" ]] || return 1
  git -C "${lane_root}" update-ref "refs/heads/${quarantine_branch}" "${commit_sha}" || return 1
  return 0
}

# lv2_orphan_checkpoint_lane <wt_path> -> the per-worktree decision (a-g).
# Always returns 0 — a probe/commit failure degrades to a journaled skip,
# never aborts the caller's sweep of other worktrees.
lv2_orphan_checkpoint_lane() {
  local wt_path="$1" lane_id
  # Canonicalize once, up front: a coder wrapper's `cd` into the worktree can
  # leave a non-canonical (symlinked) cwd recorded in its run-cache
  # meta.yaml (macOS /tmp -> /private/tmp, $TMPDIR -> /private/var/...),
  # while `git worktree list --porcelain` (this script's own enumeration)
  # always returns the resolved form. Normalizing here propagates the SAME
  # canonical path into every downstream comparison -- the lsof cwd-liveness
  # check (already normalized in lv2_lane_worker_alive) and the run-meta
  # `cwd:` match (_lv2_orphan_find_run_meta) below -- so neither false-alives
  # a dead lane's checkpoint nor false-loses its LANE_WRITES scope.
  wt_path="$(_lv2_lane_realpath "${wt_path}")"
  lane_id="$(_lv2_orphan_lane_id "${wt_path}")"

  [[ -d "${wt_path}/.git" || -f "${wt_path}/.git" ]] 2>/dev/null || { _oc_log "skip ${lane_id}: not-a-worktree"; return 0; }

  # (a) liveness — never race a live worker.
  local meta pid_list=""
  meta="$(_lv2_orphan_find_run_meta "${wt_path}")"
  [[ -n "${meta}" ]] && pid_list="$(_lv2_orphan_recorded_pid "${meta}")"
  if lv2_lane_alive_combined "${wt_path}" "${pid_list}"; then
    _oc_log "skip ${lane_id}: skipped_alive"
    return 0
  fi

  # (b) clean — never an empty commit. D10 negative-control target #1:
  # changing --untracked-files=all to --untracked-files=no here makes an
  # untracked-only dirty lane invisible, turning A1/A2 RED (nothing to
  # commit is indistinguishable from "clean").
  local status_out
  status_out="$(git -C "${wt_path}" status --porcelain --untracked-files=all 2>/dev/null || true)"
  if [[ -z "${status_out}" ]]; then
    _oc_log "skip ${lane_id}: skipped_clean"
    return 0
  fi

  local dirty_file
  dirty_file="$(mktemp "${TMPDIR:-/tmp}/leadv2-orphan-dirty.XXXXXX")" || return 0
  local raw path
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    path="${raw:3}"
    case "${path}" in
      *' -> '*) path="${path#*' -> '}" ;;
      \"*\") path="${path#\"}"; path="${path%\"}" ;;
    esac
    [[ -n "${path}" ]] && printf '%s\n' "${path}" >> "${dirty_file}"
  done <<< "${status_out}"

  if [[ ! -s "${dirty_file}" ]]; then
    rm -f "${dirty_file}"
    _oc_log "skip ${lane_id}: skipped_clean"
    return 0
  fi

  # (c) scope resolution — best-effort LANE_WRITES recovery; unknown scope
  # means the WHOLE dirty set is IN-SCOPE (committed to the lane's own
  # branch), never quarantined or skipped (see header comment (c)).
  # Quarantine is reserved for paths PROVEN out-of-scope by an
  # actually-recovered LANE_WRITES declaration.
  local lane_writes_csv="" out_scope_file in_scope_file
  [[ -n "${meta}" ]] && lane_writes_csv="$(_lv2_orphan_lane_writes_csv "${meta}")"
  out_scope_file="$(mktemp "${TMPDIR:-/tmp}/leadv2-orphan-outscope.XXXXXX")" || { rm -f "${dirty_file}"; return 0; }
  in_scope_file="$(mktemp "${TMPDIR:-/tmp}/leadv2-orphan-inscope.XXXXXX")" || { rm -f "${dirty_file}" "${out_scope_file}"; return 0; }

  if [[ -n "${lane_writes_csv}" ]]; then
    _lv2_orphan_out_of_scope "${lane_writes_csv}" "${dirty_file}" > "${out_scope_file}"
    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      if grep -q -F -x "${path}" "${out_scope_file}" 2>/dev/null; then
        :
      else
        printf '%s\n' "${path}" >> "${in_scope_file}"
      fi
    done < "${dirty_file}"
  else
    # No recoverable LANE_WRITES declaration: never guess an EXCLUSION
    # either — the entire dirty set is treated as in-scope instead.
    cp "${dirty_file}" "${in_scope_file}"
  fi

  local -a in_scope=() out_scope=()
  [[ -s "${in_scope_file}" ]] && while IFS= read -r path; do [[ -n "${path}" ]] && in_scope+=("${path}"); done < "${in_scope_file}"
  [[ -s "${out_scope_file}" ]] && while IFS= read -r path; do [[ -n "${path}" ]] && out_scope+=("${path}"); done < "${out_scope_file}"
  rm -f "${dirty_file}" "${out_scope_file}" "${in_scope_file}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    _oc_log "dry-run ${lane_id}: would_commit in_scope=${#in_scope[@]} out_scope=${#out_scope[@]}"
    return 0
  fi

  local committed_sha="" quarantine_sha="" did_anything=0

  if [[ ${#in_scope[@]} -gt 0 ]]; then
    if _lv2_orphan_inscope_commit "${wt_path}" "${lane_id}" "${in_scope[@]}"; then
      committed_sha="$(git -C "${wt_path}" rev-parse --short HEAD 2>/dev/null)"
      did_anything=1
      _oc_log "checkpointed ${lane_id}: files=${#in_scope[@]} sha=${committed_sha}"
      [[ -f "${JOURNAL_BIN}" ]] && bash "${JOURNAL_BIN}" append "${lane_id}" note \
        "orphan_checkpoint_committed files=${#in_scope[@]} sha=${committed_sha}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ ${#out_scope[@]} -gt 0 ]]; then
    _lv2_orphan_quarantine_commit "${wt_path}" "${lane_id}" "${out_scope[@]}"
    local qrc=$?
    if [[ "${qrc}" == "0" ]]; then
      quarantine_sha="$(git -C "${wt_path}" rev-parse --short "refs/heads/orphan-quarantine/${lane_id}" 2>/dev/null)"
      did_anything=1
      _oc_log "quarantined ${lane_id}: files=${#out_scope[@]} branch=orphan-quarantine/${lane_id} sha=${quarantine_sha}"
      [[ -f "${JOURNAL_BIN}" ]] && bash "${JOURNAL_BIN}" append "${lane_id}" note \
        "orphan_checkpoint_quarantined files=${#out_scope[@]} branch=orphan-quarantine/${lane_id} sha=${quarantine_sha}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${did_anything}" == "1" ]]; then
    printf 'RESUME: cd %s && git log -1 --stat  # orphan-checkpoint sha=%s quarantine_sha=%s (%s)\n' \
      "${wt_path}" "${committed_sha:-none}" "${quarantine_sha:-none}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  return 0
}

# ---- main: sweep every lane worktree ---------------------------------------
if [[ -n "${ONLY_LANE}" ]]; then
  wt="${PROJECT_ROOT}/.claude/worktrees/${ONLY_LANE}"
  [[ -d "${wt}" ]] && lv2_orphan_checkpoint_lane "${wt}"
  exit 0
fi

while IFS= read -r wt; do
  [[ -n "${wt}" ]] || continue
  case "${wt}" in
    */.claude/worktrees/*) ;;
    *) continue ;;
  esac
  [[ -d "${wt}" ]] || continue
  lv2_orphan_checkpoint_lane "${wt}"
done < <(git -C "${PROJECT_ROOT}" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

exit 0
