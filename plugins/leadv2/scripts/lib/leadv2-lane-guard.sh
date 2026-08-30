#!/usr/bin/env bash
# Shared lane cleanliness and post-hoc containment checks.  Sourced by the
# close gate and terminal ledger; keep the porcelain grammar in one place.

_PC_PORCELAIN_EXCLUDE_RE='^.. "?docs/leadv2/|^.. "?docs/handoff/|^.. "?docs/LEAD_V2_STATE\.md|^.. "?.*__pycache__/|^.. "?.*\.pyc$'
_PC_BOOTSTRAP_PREFIX_RE='^\.claude/(commands|scripts|agents)(/|$)'

_lv2_norm_write() { printf '%s' "$1" | sed -e 's#^\\./##' -e 's#/$##'; }
_lv2_class_rank() { case "$1" in Trivial) printf 0;; Light) printf 1;; Standard) printf 2;; Heavy) printf 3;; Strategic) printf 4;; *) printf 2;; esac; }
_lv2_class_canonical() {
  case "$1" in
    trivial|Trivial) printf Trivial ;; light|Light) printf Light ;; standard|Standard|bulk|Bulk|'') printf Standard ;;
    heavy|Heavy) printf Heavy ;; strategic|Strategic) printf Strategic ;; *) printf Standard ;;
  esac
}

_lv2_path_in_write_set() { # <porcelain path> <csv writes>
  local path="$1" csv="$2" write old_ifs="$IFS"
  IFS=','
  for write in $csv; do
    write="$(_lv2_norm_write "${write}")"
    [[ -n "${write}" ]] || continue
    [[ "${path}" == "${write}" || "${path}" == "${write}/"* ]] && { IFS="$old_ifs"; return 0; }
  done
  IFS="$old_ifs"
  return 1
}

_pc_drop_bootstrap_dirt() { # <lane-root>; filters stdin porcelain -> stdout
  local root="$1" line field rest path task_lines=() kept_lines=() task_declared=0 has_other_work=0 w
  if [[ -z "${root}" || ! -d "${root}" ]]; then cat; return 0; fi
  IFS=',' read -r -a _pc_task_writes <<< "${WRITES_CSV:-}"
  for w in "${_pc_task_writes[@]:-}"; do
    w="$(_lv2_norm_write "${w}")"
    [[ "${w}" == "docs/tasks.yaml" ]] && task_declared=1
  done
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    field="${line:0:2}"; rest="${line:3}"; path="${rest##* -> }"
    path="${path%\"}"; path="${path#\"}"
    if [[ "${path}" == "docs/tasks.yaml" ]]; then task_lines+=("${line}"); continue; fi
    if [[ "${field}" == "??" && "${rest}" =~ ${_PC_BOOTSTRAP_PREFIX_RE} && -L "${root}/${path}" ]]; then continue; fi
    kept_lines+=("${line}"); has_other_work=1
  done
  if (( task_declared == 1 || has_other_work == 0 )); then kept_lines+=(${task_lines[@]+"${task_lines[@]}"}); fi
  for line in ${kept_lines[@]+"${kept_lines[@]}"}; do printf '%s\n' "${line}"; done
  return 0
}

lv2_lane_dirty() { # <root> -> rc0 when worker-owned dirt remains
  # The two-stage filter is runtime-tested by test-scope-gate-orchestration-dirt.sh.
  local root="$1" status
  [[ -n "${root}" && -d "${root}" ]] || return 1
  git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  status="$(git -C "${root}" status --porcelain --untracked-files=all 2>/dev/null | grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "${root}")"
  [[ -n "${status}" ]]
}

_lv2_phys() { ( cd -P "$1" 2>/dev/null && pwd -P ); }
LV2_LANE_TOPLEVEL=""
lv2_lane_root_is_own_worktree() { # <root>
  local root="$1" top
  LV2_LANE_TOPLEVEL=""
  [[ -n "${root}" && -d "${root}" ]] || return 1
  top="$(git -C "${root}" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "${top}" ]] || return 1
  LV2_LANE_TOPLEVEL="${top}"
  [[ "$(_lv2_phys "${top}")" == "$(_lv2_phys "${root}")" ]]
}

_lv2_containment_excluded() { # git porcelain path
  case "$1" in
    docs/handoff/*|docs/leadv2/*|docs/LEAD_V2_STATE.md|.git|.git/*) return 0 ;;
    .claude/state/*|.claude/journals/*|.claude/active.yaml|.claude/event-ledger/*|.claude/questions/*) return 0 ;;
  esac
  return 1
}

# rc0 means a new, non-control-plane path appeared in the main checkout.
lv2_lane_containment_violation() { # <sig8> <work-root> <project-root> <declared-writes-csv>
  local sig8="$1" work_root="$2" project_root="$3" writes_csv="${4:-}" base path
  [[ -n "${sig8}" && -n "${work_root}" && -n "${project_root}" && "${work_root}" != "${project_root}" ]] || return 1
  # Main-checkout porcelain is shared state. Without this lane's declared
  # write set, a changed path is unattributed, never a refusal.
  [[ -n "${writes_csv}" ]] || return 1
  base="${project_root}/docs/handoff/dispatch-${sig8}/main-dirt.base"
  [[ -f "${base}" ]] || return 1
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    grep -Fqx -- "${path}" "${base}" 2>/dev/null && continue
    _lv2_containment_excluded "${path}" && continue
    _lv2_path_in_write_set "${path}" "${writes_csv}" && return 0
  done < <(git -C "${project_root}" status --porcelain --untracked-files=all 2>/dev/null | sed -E 's/^.. //; s/^"//; s/"$//')
  return 1
}
