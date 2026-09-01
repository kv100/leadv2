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
_lv2_epilogue_lane_writes() {
  local run_dir="$1" line paths_part p trimmed
  line="$(grep -m1 -E '^LANE_WRITES:' "${run_dir}/prompt.txt" 2>/dev/null || true)"
  [[ -n "${line}" ]] || return 0
  paths_part="${line#LANE_WRITES:}"
  IFS=',' read -ra _lv2_ep_paths <<< "${paths_part}"
  for p in "${_lv2_ep_paths[@]}"; do
    trimmed="$(printf '%s' "${p}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${trimmed}" ]] && printf '%s\n' "${trimmed}"
  done
}

# Is <path> equal to, or nested under, one of the newline-separated prefixes
# in <lane_writes_file>?
_lv2_epilogue_path_in_scope() {
  local path="$1" lw_file="$2" lw
  while IFS= read -r lw; do
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
leadv2_worker_commit_epilogue() {
  local run_dir="$1" cwd_dir="$2" label="${3:-lane}"

  git -C "${cwd_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local status_out
  status_out="$(git -C "${cwd_dir}" status --porcelain 2>/dev/null || true)"
  if [[ -z "${status_out}" ]]; then
    echo "worker_exit=clean auto_committed=0 foreign_dirty=0" >> "${run_dir}/progress.log" 2>/dev/null || true
    { echo "worker_exit: clean"; echo "auto_committed: 0"; } >> "${run_dir}/meta.yaml" 2>/dev/null || true
    return 0
  fi

  local lw_file
  lw_file="$(mktemp 2>/dev/null || echo "${run_dir}/.epilogue_lw.tmp")"
  _lv2_epilogue_lane_writes "${run_dir}" > "${lw_file}" 2>/dev/null || true

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
