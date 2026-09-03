#!/usr/bin/env bash
# leadv2-brain-record.sh — BRAIN-CLASS-LIVE-01 (ROUTER-BRAIN-01 lane 1).
#
# Sourced (never executed) by leadv2-dispatch-code.sh, right after
# lib/leadv2-admission-class.sh. Owns exactly two things:
#   1. the declared-class-is-a-floor journal vocabulary (class_escalated /
#      class_floor_held) that names WHY a dispatch's class moved, on top of
#      the class map leadv2-admission-class.sh already computes;
#   2. docs/handoff/<task>/brain.yaml — one decision record per task, the
#      single `brain_decision` journal line, and the read-back helper so a
#      later re-entry (_phase_precondition_guard, _admission_classify's own
#      task-floor lookup) prefers this record over re-deriving anything.
#
# This file does NOT call the judge and does NOT compute the class map --
# that is leadv2-task-judge.sh + leadv2-admission-class.sh's job (already on
# the default path via _admission_classify, unconditionally, since
# PHASE-DISCIPLINE-01 / COMPLEXITY-ESTIMATOR-IS-OFF-01). This file's whole
# job is to make the ALREADY-COMPUTED decision loud, in the exact vocabulary
# ROUTER-BRAIN-01 §A specifies, and durable across re-entries.
#
# Bash 3.2 safe: no mapfile, no ${var^^}, no declare -A, no associative traps.
_brain_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_BRAIN_ADMISSION_CLASS_SH="${_brain_lib_dir}/leadv2-admission-class.sh"
[[ -f "${_BRAIN_ADMISSION_CLASS_SH}" ]] || _BRAIN_ADMISSION_CLASS_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-admission-class.sh"
if [[ -f "${_BRAIN_ADMISSION_CLASS_SH}" ]]; then
  # shellcheck disable=SC1090
  source "${_BRAIN_ADMISSION_CLASS_SH}" || return 1
else
  printf '[leadv2-brain-record] ERROR: admission-class lib unavailable local=%s canonical=%s\n' \
    "${_brain_lib_dir}/leadv2-admission-class.sh" "${_BRAIN_ADMISSION_CLASS_SH}" >&2
  return 1
fi

# <estimate-json> -> stdout: "field:value" — the single signal that most
# plausibly drove the mapped class, for the class_escalated `because=` field.
# Same precedence order as leadv2_admission_map_class's Heavy branch.
leadv2_brain_top_signal() {
  python3 -c '
import json, sys
try:
    e = json.loads(sys.argv[1])
except Exception:
    print("unknown"); sys.exit(0)
risk = e.get("risk_class", "")
try:
    subs = int(e.get("subsystems_touched", 0))
except (TypeError, ValueError):
    subs = 0
complexity = e.get("complexity", "")
if risk == "safety_publish_payments":
    print("risk_class:%s" % risk)
elif subs >= 4:
    print("subsystems_touched:%s" % subs)
elif complexity == "complex":
    print("complexity:complex")
elif complexity == "standard":
    print("complexity:standard")
else:
    print("complexity:%s" % (complexity or "unknown"))
' "$1" 2>/dev/null
}

# <phase-record-bin> <class> [<writes-csv>] -> stdout: comma-joined MANDATORY
# phase names for the class. plan-for only accepts Trivial|Light|Standard|
# Heavy (PHASE-DISCIPLINE-01 §4) -- Strategic queries Heavy's table pending
# BRAIN-PHASES-BY-CLASS-01 (lane 2), which owns the per-class phase table
# itself. rc 1 + a conservative fallback list on ANY phase-record failure --
# brain.yaml must never block a dispatch on this being informational.
leadv2_brain_phases_for_class() {
  local bin="$1" cls="$2" writes="${3:-}" query="$2" out rc
  case "$cls" in
    Trivial|Light|Standard|Heavy) query="$cls" ;;
    Strategic) query="Heavy" ;;
    *) query="Standard" ;;
  esac
  if [[ -f "$bin" ]]; then
    out="$(bash "$bin" plan-for --class "$query" --writes "$writes" 2>/dev/null)"; rc=$?
  else
    out=""; rc=1
  fi
  if [[ $rc -ne 0 || -z "$out" ]]; then
    printf 'classify,plan,gate1,build,test,review,close'
    return 1
  fi
  printf '%s\n' "$out" | awk '$1=="MANDATORY"{print $2}' | paste -sd, - 2>/dev/null
  return 0
}

# <root> <task-id> -> stdout: class recorded in brain.yaml, empty if absent.
# The read-back half of D3 in the brief: "_phase_precondition_guard and
# leadv2-admission-class.sh read the class from brain.yaml when present,
# else fall back to today's behaviour."
leadv2_brain_read_class() {
  local root="$1" task_id="$2" f
  [[ -n "${task_id}" ]] || { printf ''; return 1; }
  f="${root}/docs/handoff/${task_id}/brain.yaml"
  [[ -f "$f" ]] || { printf ''; return 1; }
  local c
  c="$(sed -n 's/^class:[[:space:]]*//p' "$f" | head -1)"
  [[ -n "$c" ]] || return 1
  printf '%s' "$c"
  return 0
}

# <root> <task-id> <class> <class-source> <estimate-json> <phases-csv> <reason>
# Writes docs/handoff/<task-id>/brain.yaml atomically (tmp+mv). Never
# overwrites destructively mid-write (a crash leaves the old file, not a
# half one) but DOES overwrite on a legitimate re-call — unlike the
# admission receipt, brain.yaml is a live decision record, not a once-only
# stamp (a re-classified re-entry should see its own new class here).
leadv2_brain_write_yaml() {
  local root="$1" task_id="$2" cls="$3" src="$4" estimate="$5" phases="$6" reason="$7"
  [[ -n "${task_id}" ]] || return 0
  [[ -n "${estimate}" ]] || estimate='{}'
  local dir="${root}/docs/handoff/${task_id}" tmp
  mkdir -p "${dir}" 2>/dev/null || return 1
  tmp="${dir}/.brain.$$.tmp"
  local complexity risk_class work_kind subsystems duration_class estimate_source
  complexity="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("complexity",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  risk_class="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("risk_class",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  work_kind="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("work_kind",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  subsystems="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("subsystems_touched",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  duration_class="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("duration_class",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  estimate_source="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("estimate_source",""))
except Exception: print("")' <<<"${estimate}" 2>/dev/null)"
  {
    printf 'brain_v: 1\n'
    printf 'task_id: %s\n' "${task_id}"
    printf 'class: %s\n' "${cls}"
    printf 'class_source: %s\n' "${src}"
    printf 'reason: %s\n' "${reason}"
    printf 'phases: %s\n' "${phases}"
    printf 'estimate:\n'
    printf '  complexity: %s\n' "${complexity}"
    printf '  risk_class: %s\n' "${risk_class}"
    printf '  work_kind: %s\n' "${work_kind}"
    printf '  subsystems_touched: %s\n' "${subsystems}"
    printf '  duration_class: %s\n' "${duration_class}"
    printf '  estimate_source: %s\n' "${estimate_source}"
    printf 'recorded_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${tmp}" 2>/dev/null || { rm -f "${tmp}" 2>/dev/null; return 1; }
  mv -f "${tmp}" "${dir}/brain.yaml" 2>/dev/null || { rm -f "${tmp}" 2>/dev/null; return 1; }
  return 0
}

# leadv2_brain_record <root> <sig8> <task-id> <declared-raw> <flagged 0|1>
#   <final-class> <admission-source> <estimate-json> <phase-record-bin>
#   [<writes-csv>]
#
# Caller (leadv2-dispatch-code.sh's _admission_classify) must have `emit()`
# in scope — this is sourced INTO that journaling context, one inode of
# "what class, and why" truth, not a parallel ledger. Emits, in order:
#   - class_escalated / class_floor_held (only when flagged=1 — with no
#     explicit --task-class there is no declared floor to compare against);
#   - on judge failure (admission-source=classifier_error): neither of the
#     above — class_source goes straight to declared_fallback per the brief's
#     "judge error or timeout -> declared class used, never a refusal";
#   - exactly ONE brain_decision line, always;
# then writes brain.yaml.
leadv2_brain_record() {
  local root="$1" sig8="$2" task_id="$3" declared_raw="$4" flagged="$5" \
        final_class="$6" admission_source="$7" estimate_json="$8" \
        phase_record_bin="$9" writes="${10:-}"
  local declared class_source="computed" reason="no_explicit_class"
  declared="$(_lv2_class_canonical "${declared_raw}")"

  if [[ "${admission_source}" == "classifier_error" ]]; then
    class_source="declared_fallback"
    reason="judge_unavailable"
  elif [[ "${flagged}" == "1" ]]; then
    local mapped rank_declared rank_mapped
    mapped="$(leadv2_admission_map_class "${estimate_json}")"
    [[ -n "${mapped}" ]] || mapped="${declared}"
    rank_declared="$(_lv2_class_rank "${declared}")"
    rank_mapped="$(_lv2_class_rank "${mapped}")"
    if (( rank_mapped > rank_declared )); then
      class_source="escalated"
      reason="$(leadv2_brain_top_signal "${estimate_json}")"
      [[ -n "${reason}" ]] || reason="unknown"
      emit decision "class_escalated task=${sig8} from=${declared} to=${final_class} because=${reason}"
    else
      class_source="floor_held"
      reason="declared_floor"
      emit decision "class_floor_held task=${sig8} declared=${declared} computed=${mapped}"
    fi
  fi

  local phases_csv phases_rc
  phases_csv="$(leadv2_brain_phases_for_class "${phase_record_bin}" "${final_class}" "${writes}")"; phases_rc=$?
  [[ ${phases_rc} -eq 0 ]] || emit decision "brain_phases_fallback task=${sig8} class=${final_class} reason=phase_record_unavailable"

  emit decision "brain_decision task=${sig8} class=${final_class} class_source=${class_source} phases=${phases_csv} reason=${reason}"

  leadv2_brain_write_yaml "${root}" "${task_id}" "${final_class}" "${class_source}" "${estimate_json}" "${phases_csv}" "${reason}"
}
