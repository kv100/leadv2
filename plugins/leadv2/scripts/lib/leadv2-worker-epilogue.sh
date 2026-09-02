#!/usr/bin/env bash
# leadv2-worker-epilogue.sh — WORKERS-MUST-COMMIT-01
#
# Sourced by an arm's coder wrapper (glm-coder.sh __run_child's finalize
# path) after the model process exits and BEFORE the outcome classifier
# (leadv2-lane-outcome.sh) and work_delta_present() run. Root cause this
# closes: five lanes in one session (PROMISE-GUARD-TURN-IT-ON-01 x2,
# PLUGIN-PAPERCUTS-01 x2, BRAIN-CLASS-LIVE-01, FABLE-THINK-TIER-01) reported
# `LEADV2_LANE_OUTCOME ... work=yes` while leaving their diff UNCOMMITTED in
# the lane worktree — the lead had to `git add -A && git commit` by hand
# before review could start. An uncommitted exit is not evidence of nothing
# (that's what a clean tree already means); it is a worker that quit before
# finishing its own contract.
#
# Scope discipline: only files inside the mission's own LANE_WRITES (parsed
# from prompt.txt, same `^LANE_WRITES:` line and comma-split convention as
# mission_is_code_shaped() in glm-coder.sh/kimi-coder.sh/freepool-coder.sh)
# are ever staged and committed here. Anything dirty OUTSIDE that list is
# left untouched and reported as foreign_dirty — auto-committing a file the
# mission never claimed would silently absorb another lane's concurrent edit
# into this one's history (same hazard class as REQUIRE_LANE_WRITES guards
# elsewhere in this repo).
#
# Never aborts: every step is best-effort so a probe failure degrades the
# probe, never the caller's finalize path (same convention as
# leadv2-lane-outcome.sh and deadhand_check()).

# List this run's declared LANE_WRITES paths, one per line. Empty output
# means "no LANE_WRITES declared" — the caller must NOT guess a scope.
# $2 (optional) overrides the mission-file path; defaults to
# <run_dir>/prompt.txt (glm/kimi/freepool-coder.sh convention). claude-
# subsession.sh has no run_dir/prompt.txt shape -- it passes its own
# MISSION_FILE path here instead.
_lv2_epilogue_lane_writes() {
  local run_dir="$1" prompt_file="${2:-${run_dir}/prompt.txt}" line paths_part p trimmed
  line="$(grep -m1 -E '^LANE_WRITES:' "${prompt_file}" 2>/dev/null || true)"
  [[ -n "${line}" ]] || return 0
  paths_part="${line#LANE_WRITES:}"
  IFS=',' read -ra _lv2_ep_paths <<< "${paths_part}"
  for p in "${_lv2_ep_paths[@]}"; do
    trimmed="$(printf '%s' "${p}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${trimmed}" ]] && printf '%s\n' "${trimmed}"
  done
}

# Is <path> equal to, or nested under, one of the newline-separated prefixes
# in <lane_writes_file>? A LANE_WRITES row may be authored with a trailing
# `/`, `/**` or `/*` (glob-style scoping) — normalize those off before the
# case match, else a row like "docs/handoff/TASK-01/" or "plugins/x/**" never
# matches anything and reads as FOREIGN (WORKER-DOD-GATE-01 plan step 1: this
# defect made 3 of that task's own 8 original LANE_WRITES rows read as
# FOREIGN, including its own report.md path).
_lv2_epilogue_path_in_scope() {
  local path="$1" lw_file="$2" lw
  while IFS= read -r lw; do
    [[ -z "${lw}" ]] && continue
    case "${lw}" in
      */\*\*) lw="${lw%/\*\*}" ;;
      */\*) lw="${lw%/\*}" ;;
      */) lw="${lw%/}" ;;
    esac
    [[ -z "${lw}" ]] && continue
    case "${path}" in
      "${lw}"|"${lw}"/*) return 0 ;;
    esac
  done < "${lw_file}"
  return 1
}

# leadv2_worker_commit_epilogue <run_dir> <cwd_dir> [label]
#
# If <cwd_dir> has tracked/untracked changes at exit, auto-commits only the
# subset inside this run's LANE_WRITES as a single commit; files outside
# LANE_WRITES are left dirty and named in progress.log as foreign_dirty.
# Writes worker_exit=clean|dirty, auto_committed=<n>, foreign_dirty=<n> to
# both progress.log and meta.yaml so the outcome classifier and any human
# reading the run dir see the same facts. Always returns 0.
# $4 (optional): mission/prompt-file path to read LANE_WRITES from, when it
# is not <run_dir>/prompt.txt (claude-subsession.sh passes its MISSION_FILE).
leadv2_worker_commit_epilogue() {
  local run_dir="$1" cwd_dir="$2" label="${3:-lane}" prompt_file="${4:-${run_dir}/prompt.txt}"

  if ! git -C "${cwd_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # No lane worktree at this cwd (e.g. --protected mode writes elsewhere).
    echo "worker_exit=no_lane auto_committed=0 foreign_dirty=0" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: no_lane"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
    return 0
  fi

  local status_out
  status_out="$(git -C "${cwd_dir}" status --porcelain --untracked-files=all 2>/dev/null || true)"
  if [[ -z "${status_out}" ]]; then
    echo "worker_exit=clean auto_committed=0 foreign_dirty=0" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: clean"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
    return 0
  fi

  local lw_file
  lw_file="$(mktemp 2>/dev/null || echo "${run_dir}/.epilogue_lw.tmp")"
  _lv2_epilogue_lane_writes "${run_dir}" "${prompt_file}" > "${lw_file}" 2>/dev/null || true

  if [[ ! -s "${lw_file}" ]]; then
    # No LANE_WRITES declared -- cannot scope a safe auto-commit. Report and
    # stop; never guess which dirty files belong to this mission.
    echo "worker_exit=dirty auto_committed=0 foreign_dirty=undeclared_lane_writes" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: dirty"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
    rm -f "${lw_file}" 2>/dev/null || true
    return 0
  fi

  local in_scope=() foreign=()
  local raw path
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    path="${raw:3}"
    case "${path}" in
      *' -> '*) path="${path#*' -> '}" ;;  # rename entries: keep the new path
    esac
    if _lv2_epilogue_path_in_scope "${path}" "${lw_file}"; then
      in_scope+=("${path}")
    else
      foreign+=("${path}")
    fi
  done <<< "${status_out}"

  rm -f "${lw_file}" 2>/dev/null || true

  if [[ "${#in_scope[@]}" -eq 0 ]]; then
    echo "worker_exit=dirty auto_committed=0 foreign_dirty=${#foreign[@]}" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: dirty"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
    if [[ "${#foreign[@]}" -gt 0 ]]; then
      printf 'foreign_dirty=%s\n' "$(IFS=,; echo "${foreign[*]}")" >> "${run_dir}/progress.log" 2>/dev/null || true
    fi
    return 0
  fi

  if git -C "${cwd_dir}" add -- "${in_scope[@]}" >/dev/null 2>&1 \
     && git -C "${cwd_dir}" commit -m "${label}: auto-commit (worker exited dirty)" >/dev/null 2>&1; then
    echo "worker_exit=dirty auto_committed=${#in_scope[@]} foreign_dirty=${#foreign[@]}" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: dirty"; printf 'auto_committed: %s\n' "${#in_scope[@]}"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
  else
    echo "worker_exit=dirty auto_committed=0 foreign_dirty=${#foreign[@]} commit_failed=1" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: dirty"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
  fi
  if [[ "${#foreign[@]}" -gt 0 ]]; then
    printf 'foreign_dirty=%s\n' "$(IFS=,; echo "${foreign[*]}")" >> "${run_dir}/progress.log" 2>/dev/null || true
  fi
  return 0
}

# Best-effort diff of this lane's committed work, for the soft DoD probe
# below. Not the authoritative round diff (that is computed by the lane
# orchestrator and passed explicitly to the hard gate in
# leadv2-dispatch-product-close.sh) -- a merge-base miss here just means
# check (c)/(d) see less diff context, never a crash.
_lv2_dod_round_diff() {
  local cwd_dir="$1" out="$2" base
  base="$(git -C "${cwd_dir}" merge-base HEAD main 2>/dev/null || true)"
  [[ -z "${base}" ]] && base="$(git -C "${cwd_dir}" merge-base HEAD origin/main 2>/dev/null || true)"
  [[ -z "${base}" ]] && base="$(git -C "${cwd_dir}" rev-parse HEAD~1 2>/dev/null || true)"
  if [[ -n "${base}" ]]; then
    git -C "${cwd_dir}" diff "${base}" HEAD -- . > "${out}" 2>/dev/null || : > "${out}"
  else
    : > "${out}"
  fi
}

# Best-effort founder task dir (docs/handoff/<TASK_ID>, where brief.md/
# report.md live) for wrappers that never receive it explicitly (glm/kimi/
# freepool-coder.sh only know a per-arm run_dir, not the founder task dir).
# Reuses capture_deliverable()'s existing .deliverable artifact (written
# before child spawn from a docs/handoff/... path parsed out of prompt.txt)
# rather than inventing a second path-extraction convention. Falls back to
# cwd_dir when absent -- lib/leadv2-dod-gate.sh's checks already degrade to
# not_required/skip when no brief.md is found there, never a crash.
_lv2_dod_task_dir() {
  local run_dir="$1" cwd_dir="$2" deliverable
  deliverable="$(cat "${run_dir}/.deliverable" 2>/dev/null || true)"
  if [[ -n "${deliverable}" ]]; then
    dirname "${deliverable}"
    return 0
  fi
  printf '%s\n' "${cwd_dir}"
}

# lv2_dod_retry_or_finalize <run_dir> <cwd_dir> <task_dir> [retry_hook_fn]
#
# WORKER-DOD-GATE-01 §7: runs lib/leadv2-dod-gate.sh against this lane's
# just-committed HEAD. PASS -> worker_dod=pass. FAIL with attempts under
# LEADV2_DOD_GATE_MAX_RETRIES (default 2) AND a real retry_hook_fn declared
# -> increments the attempt counter, feeds the gate's reason lines to
# retry_hook_fn, returns (the contract: retry_hook_fn must give the worker
# one more turn via the wrapper's OWN loop and return before this proceeds).
# FAIL with attempts exhausted, or no retry_hook_fn -> writes the unchanged
# soft signal worker_dod=fail:<checks> and returns.
#
# RISK R9: none of the 4 current call sites (glm-coder.sh, kimi-coder.sh,
# freepool-coder.sh, claude-subsession.sh) sit inside a re-enterable turn
# loop -- confirmed by reading each wrapper's control flow around its
# leadv2_worker_commit_epilogue call: the child model process has already
# exited and finalize_meta/deadhand_check have already run by the time this
# function is reachable, with no loop left to spawn another turn from. All 4
# therefore call this function with retry_hook_fn omitted, which degrades
# straight to the soft-fail signal on first hard-check failure -- never a
# crash, never a silent skip of the hard gate in
# leadv2-dispatch-product-close.sh (which enforces independently of this).
# This function never invokes a model or dispatch process itself.
lv2_dod_retry_or_finalize() {
  local run_dir="$1" cwd_dir="$2" task_dir="$3" retry_hook_fn="${4:-}"
  local dod_gate_sh
  dod_gate_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-dod-gate.sh"
  [[ -f "${dod_gate_sh}" ]] || return 0

  local diff_file
  diff_file="$(mktemp 2>/dev/null || echo "${run_dir}/.dod_diff.tmp")"
  _lv2_dod_round_diff "${cwd_dir}" "${diff_file}"

  local out_md="${task_dir}/dod-gate.md" gate_out gate_rc
  gate_out="$(bash "${dod_gate_sh}" "${cwd_dir}" "${task_dir}" "${diff_file}" "${out_md}" 2>&1)"
  gate_rc=$?
  rm -f "${diff_file}" 2>/dev/null || true

  if [[ "${gate_rc}" -eq 0 ]]; then
    echo "worker_dod=pass" >> "${run_dir}/progress.log" 2>/dev/null || true
    return 0
  fi
  if [[ "${gate_rc}" -eq 2 ]]; then
    # undetermined -- never counted as a mechanical fail against retries
    return 0
  fi

  local checks
  checks="$(printf '%s\n' "${gate_out}" | sed -n 's/^dod_fail check=\([a-z_]*\).*/\1/p' | paste -sd, - 2>/dev/null)"
  [[ -z "${checks}" ]] && checks="unknown"

  local attempt_file="${task_dir}/.dod-attempt" attempts=0
  [[ -f "${attempt_file}" ]] && attempts="$(cat "${attempt_file}" 2>/dev/null || echo 0)"
  [[ "${attempts}" =~ ^[0-9]+$ ]] || attempts=0
  local max_retries="${LEADV2_DOD_GATE_MAX_RETRIES:-2}"

  if [[ "${attempts}" -lt "${max_retries}" && -n "${retry_hook_fn}" ]] \
     && declare -F "${retry_hook_fn}" >/dev/null 2>&1; then
    attempts=$((attempts + 1))
    echo "${attempts}" > "${attempt_file}" 2>/dev/null || true
    "${retry_hook_fn}" "${gate_out}"
    return 0
  fi

  echo "worker_dod=fail:${checks}" >> "${run_dir}/progress.log" 2>/dev/null || true
  echo "worker_dod: fail:${checks}" >> "${run_dir}/meta.yaml" 2>/dev/null || true
  return 0
}
