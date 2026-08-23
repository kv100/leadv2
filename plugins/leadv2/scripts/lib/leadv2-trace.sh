# leadv2-trace.sh — opt-in lane trace writer (LEADV2_TRACE=1).
#
# Sourced only when LEADV2_TRACE=1 (see load protocol in each instrumented
# script). Off-path cost when unsourced: one string comparison + three
# no-op function defs, no file open. Design: docs/handoff/dispatch-f72c8c9c
# (Mission B — unified lane trace).
#
# Public API: lv2_trace_begin, lv2_trace_end, lv2_trace_arm_exit. All three
# always return 0 -- a trace failure must never change a host script's
# control flow or exit code.

LV2_TRACE_SINK=""
LV2_TRACE_CLOCK_SRC=""
LV2_TRACE_STACK=()
LV2_TRACE_STACK_T=()
_LV2_PREV_EXIT_TRAP=""

_lv2_trace_id_valid() {
  [[ "$1" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

# Resolves LEADV2_TRACE_ID once per process. On any failure the trace
# self-disables (LV2_TRACE_SINK stays empty) but never touches the host's
# control flow.
_lv2_trace_resolve_id() {
  local id="${LEADV2_TRACE_ID:-}"
  if [[ -z "$id" ]]; then
    local i=1 a
    for a in "$@"; do
      case "$a" in
        --task=*|--task-id=*) id="${a#*=}" ;;
        --task|--task-id)
          local -a _args=("$@")
          local next_i=$((i))
          [[ "$next_i" -lt "${#_args[@]}" ]] && id="${_args[$next_i]}"
          ;;
      esac
      i=$((i+1))
    done
  fi
  if [[ -z "$id" ]]; then
    id="ambient-$(date -u +%Y%m%d 2>/dev/null || echo unknown)"
    LV2_TRACE_AMBIENT=1
  else
    LV2_TRACE_AMBIENT=0
  fi
  if ! _lv2_trace_id_valid "$id"; then
    echo "[trace] disabled: LEADV2_TRACE_ID '$id' fails charset/length check" >&2
    return 1
  fi
  LEADV2_TRACE_ID="$id"
  export LEADV2_TRACE_ID
  return 0
}

_lv2_trace_resolve_clock() {
  if command -v perl >/dev/null 2>&1; then
    LV2_TRACE_CLOCK_SRC="monotonic_perl"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    LV2_TRACE_CLOCK_SRC="monotonic_python"
    return 0
  fi
  echo "[trace] disabled: no perl and no python3 found for a monotonic clock" >&2
  return 1
}

_lv2_trace_now_ns() {
  local v=""
  case "$LV2_TRACE_CLOCK_SRC" in
    monotonic_perl)
      v="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC)*1e9' 2>/dev/null)" ;;
    monotonic_python)
      v="$(python3 -c 'import time;print(time.monotonic_ns())' 2>/dev/null)" ;;
  esac
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%s\n' "$v"
}

# Resolves the sink file once per process: sink_dir via leadv2-state-path.sh
# --no-link traces (never a hardcoded path, never the STANDARD/link set),
# then <sink_dir>/<trace_id>.ndjson.
_lv2_trace_resolve_sink() {
  local bin="${LEADV2_STATE_PATH_BIN:-}"
  # Falls back to the sibling of THIS library file, never the host's own
  # SCRIPT_DIR convention (which several call sites spell differently or
  # don't define at all — DEFECT-A-TRACE-SEAM-SILENCE-01, dispatch-dfbbd78d
  # architect prepass §4.1). ${BASH_SOURCE[0]} inside this file is always
  # the lib path in every sourcing context, so its sibling is always right.
  [[ -n "$bin" && -x "$bin" ]] || bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-state-path.sh"
  [[ -x "$bin" ]] || bin="$(command -v leadv2-state-path.sh 2>/dev/null || true)"
  if [[ -z "$bin" || ! -x "$bin" ]]; then
    echo "[trace] disabled: leadv2-state-path.sh not found/executable" >&2
    return 1
  fi
  local dir
  dir="$("$bin" --no-link traces 2>/dev/null)" || {
    echo "[trace] disabled: sink unresolvable (leadv2-state-path.sh failed)" >&2
    return 1
  }
  [[ -n "$dir" ]] || return 1
  mkdir -p "$dir" 2>/dev/null || { echo "[trace] disabled: sink dir not writable" >&2; return 1; }
  [[ -w "$dir" ]] || { echo "[trace] disabled: sink dir not writable" >&2; return 1; }
  LV2_TRACE_SINK="${dir}/${LEADV2_TRACE_ID}.ndjson"
  return 0
}

# Lazily resolves id + clock + sink exactly once per process. Sets
# LV2_TRACE_READY=1 on success, 0 on any failure (self-disable, S4/S5).
_lv2_trace_init() {
  [[ -n "${LV2_TRACE_READY:-}" ]] && return 0
  LV2_TRACE_READY=0
  if _lv2_trace_resolve_id "$@" && _lv2_trace_resolve_clock && _lv2_trace_resolve_sink; then
    LV2_TRACE_READY=1
  fi
  return 0
}

lv2_trace_begin() {
  local span="$1"
  _lv2_trace_init "$@" || true
  [[ "$LV2_TRACE_READY" == "1" ]] || return 0
  local t0
  t0="$(_lv2_trace_now_ns)" || return 0
  LV2_TRACE_STACK+=("$span")
  LV2_TRACE_STACK_T+=("$t0")
  return 0
}

lv2_trace_end() {
  local exit_code="${1:-$?}"
  [[ "${LV2_TRACE_READY:-0}" == "1" ]] || return 0
  local n=${#LV2_TRACE_STACK[@]}
  [[ "$n" -gt 0 ]] || return 0
  local span="${LV2_TRACE_STACK[$((n-1))]}"
  local t0="${LV2_TRACE_STACK_T[$((n-1))]}"
  unset 'LV2_TRACE_STACK[$((n-1))]' 'LV2_TRACE_STACK_T[$((n-1))]'
  local parent="null"
  local pn=${#LV2_TRACE_STACK[@]}
  [[ "$pn" -gt 0 ]] && parent="\"${LV2_TRACE_STACK[$((pn-1))]}\""

  local t1 instr_start instr_end
  instr_start="$(_lv2_trace_now_ns)" || return 0
  t1="$instr_start"
  instr_end="$(_lv2_trace_now_ns)" || instr_end="$instr_start"
  local instrument_ns=$(( instr_end - instr_start ))

  local dur_ms
  dur_ms="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000}' 2>/dev/null)"
  [[ -n "$dur_ms" ]] || dur_ms=0

  local script; script="$(basename "${BASH_SOURCE[1]:-unknown}")"
  local ambient="false"
  [[ "${LV2_TRACE_AMBIENT:-0}" == "1" ]] && ambient="true"

  local rec
  rec=$(printf '{"trace_id":"%s","span":"%s","script":"%s","pid":%d,"ppid":%d,"parent_span":%s,"t_start_ns":%s,"t_end_ns":%s,"duration_ms":%s,"exit_code":%s,"child_exec_count":null,"clock_source":"%s","instrument_ns":%s,"ambient":%s,"wall_iso":"%s"}' \
    "$LEADV2_TRACE_ID" "$span" "$script" "$$" "${PPID:-0}" "$parent" \
    "$t0" "$t1" "$dur_ms" "${exit_code:-0}" "$LV2_TRACE_CLOCK_SRC" "$instrument_ns" \
    "$ambient" "$(date -u +%FT%TZ 2>/dev/null || echo unknown)")

  if [[ ${#rec} -gt 512 ]]; then
    echo "[trace] dropped: record exceeds 512 bytes for span '$span'" >&2
    return 0
  fi
  printf '%s\n' "$rec" >> "$LV2_TRACE_SINK" 2>/dev/null || {
    echo "[trace] dropped: append failed to $LV2_TRACE_SINK" >&2
  }
  return 0
}

# lv2_trace_arm_exit <span> — begins <span> and installs a chained EXIT trap
# that (1) captures $? first, (2) closes the span, (3) re-runs whatever EXIT
# trap was already installed (never clobber it -- see §1.2/§3.5 of the
# design: several host scripts release locks/registry tokens in their own
# EXIT trap and losing it leaks state), (4) re-exits with the original $?.
#
# MUST be called AFTER any host-owned `trap ... EXIT` is installed, never
# before -- installing earlier would make bash's single EXIT-trap slot keep
# this trace trap instead of the host's, silently disabling the host's own
# cleanup. See design §3.5 point 3.
lv2_trace_arm_exit() {
  local span="$1"; shift
  lv2_trace_begin "$span" "$@"
  local prev
  prev="$(trap -p EXIT)"
  if [[ -n "$prev" ]]; then
    prev="${prev#trap -- \'}"
    prev="${prev%\' EXIT}"
  fi
  _LV2_PREV_EXIT_TRAP="$prev"
  # (exit "$_lv2_rc") right before the eval restores $? to the ORIGINAL exit
  # code for any prev-trap body that itself reads $? (e.g. status-collector's
  # own `_ec=$?; rm -rf ...; exit $_ec`) -- without it, $? at eval time is
  # whatever the drain loop/if-check last returned (usually 0), and a prev
  # trap that re-derives its exit code from $? would silently report success
  # on failure. This is the exact "status timer starts reporting success on
  # failure" hazard named in the design (§1.2).
  trap '_lv2_rc=$?; while [[ ${#LV2_TRACE_STACK[@]} -gt 0 ]]; do lv2_trace_end "$_lv2_rc"; done; if [[ -n "${_LV2_PREV_EXIT_TRAP:-}" ]]; then ( exit "$_lv2_rc" ); eval "$_LV2_PREV_EXIT_TRAP"; fi; exit "$_lv2_rc"' EXIT
  return 0
}
