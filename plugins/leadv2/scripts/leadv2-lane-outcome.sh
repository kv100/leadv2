#!/usr/bin/env bash
# leadv2-lane-outcome.sh <run_dir> <exit_code> [work_delta]
# N-3 (TURN-CAP-OUTCOME-01): pure-ish classifier + artifact writer. Joins the bound
# (turn_count/no_progress/wall_clock/max_turns/none), the N-2 work-delta signal, and
# the .no-deliverable gate into exactly one outcome token -- completed |
# died-with-work | died-clean | parked -- and writes it where the lead reads it
# without opening the run directory. See docs/handoff/dispatch-6ad1f33d/architect-prepass.md
# for the full design; this is the canonical port of persona-engine's
# scripts/lane-death-classify.sh, extended with bound detection.
#
# work_delta (optional 3rd arg) is yes|no|skip, normally passed in by glm-coder.sh /
# kimi-coder.sh from their own run-scoped work_delta_present() so the delta has exactly
# one implementation. When omitted, this script derives it itself from <run_dir>/.workbase
# (same comparison), falling back to a plain git probe on meta_get cwd when .workbase is
# unavailable ("skip") -- degrading to work=no (conservative) if that git probe itself
# can't be performed.
#
# stdout: exactly one token -- completed | died-with-work | died-clean | parked.
# Side effect: writes <run_dir>/.outcome, appends one line to <run_dir>/progress.log and
# three keys to <run_dir>/meta.yaml. Never throws under `set -euo pipefail` -- like
# deadhand_check (R6), a probe failure degrades the probe, not the whole script; internal
# failures are swallowed with `|| true` on individual best-effort steps, never with an
# early exit that could skip artifact writing.
#
# Usage: leadv2-lane-outcome.sh <run_dir> <exit_code> [work_delta]

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: leadv2-lane-outcome.sh <run_dir> <exit_code> [work_delta]" >&2
  exit 2
fi

RUN_DIR="$1"
EXIT_CODE="$2"
WORK_DELTA_ARG="${3:-}"
PARKED_DETECT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/leadv2-parked-detect.sh"
if [[ -f "${PARKED_DETECT_SH}" ]]; then
  # shellcheck source=lib/leadv2-parked-detect.sh
  source "${PARKED_DETECT_SH}" || true
fi

_lane_outcome_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    cksum | cut -d' ' -f1
  fi
}

_lane_outcome_meta_get() {
  local key="$1"
  { grep "^${key}:" "${RUN_DIR}/meta.yaml" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^ //'; } || true
}

# ---- 1. bound: first-hit-wins, per §2.2 ----
_resolve_bound() {
  local reason
  if [[ -s "${RUN_DIR}/.bound_reason" ]]; then
    reason="$(cat "${RUN_DIR}/.bound_reason" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "${reason}" ]] && { echo "${reason}"; return 0; }
  fi
  if [[ "${EXIT_CODE}" == "124" ]]; then
    echo "wall_clock"
    return 0
  fi
  local stream
  stream="${RUN_DIR}/journal.jsonl"
  if [[ -f "${stream}" && -r "${stream}" ]]; then
    local hit
    hit="$(tail -c 65536 "${stream}" 2>/dev/null | python3 -c '
import json, sys
lines = [raw for raw in sys.stdin.buffer.read().splitlines() if raw.strip()]
if not lines:
    raise SystemExit(1)
try:
    event = json.loads(lines[-1])
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit(1)
terminal = event.get("terminal_reason") == "max_turns"
subtype = event.get("subtype") == "error_max_turns"
raise SystemExit(0 if terminal or subtype else 1)
' 2>/dev/null && echo hit || true)"
    if [[ "${hit}" == "hit" ]]; then
      echo "max_turns"
      return 0
    fi
  fi
  echo "none"
}

# ---- 2. work_delta: yes|no|skip, per §2.1 (own derivation when not passed in) ----
_derive_work_delta() {
  case "${WORK_DELTA_ARG}" in
    yes|no|skip)
      echo "${WORK_DELTA_ARG}"
      return 0
      ;;
  esac
  [[ -f "${RUN_DIR}/.workbase" ]] || { echo skip; return 0; }
  local cwd_dir
  cwd_dir="$(_lane_outcome_meta_get cwd)"
  [[ -n "${cwd_dir}" ]] || { echo skip; return 0; }
  git -C "${cwd_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo skip; return 0; }
  local base_head base_dirty cur_head cur_dirty
  base_head="$(grep '^head=' "${RUN_DIR}/.workbase" 2>/dev/null | head -1 | cut -d= -f2-)"
  base_dirty="$(grep '^dirty=' "${RUN_DIR}/.workbase" 2>/dev/null | head -1 | cut -d= -f2-)"
  cur_head="$(git -C "${cwd_dir}" rev-parse HEAD 2>/dev/null || true)"
  cur_dirty="$(git -C "${cwd_dir}" status --porcelain -- . ':(exclude)docs/' 2>/dev/null | _lane_outcome_sha256 || true)"
  if [[ "${cur_head}" != "${base_head}" || "${cur_dirty}" != "${base_dirty}" ]]; then
    echo yes
  else
    echo no
  fi
}

# ---- 3. work: yes|no, resolving a "skip" delta via the persona-engine git probe ----
_resolve_work() {
  local delta="$1"
  case "${delta}" in
    yes) echo yes; return 0 ;;
    no) echo no; return 0 ;;
  esac
  # delta == skip: fall back to meta_get cwd -- dirty tracked tree OR commits ahead
  # of upstream => yes; missing cwd / not a git tree => no (conservative).
  local cwd_dir
  cwd_dir="$(_lane_outcome_meta_get cwd)"
  if [[ -z "${cwd_dir}" || ! -d "${cwd_dir}" ]]; then
    echo no
    return 0
  fi
  if ! git -C "${cwd_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo no
    return 0
  fi
  if [[ -n "$(git -C "${cwd_dir}" status --porcelain 2>/dev/null)" ]]; then
    echo yes
    return 0
  fi
  local ahead
  ahead="$(git -C "${cwd_dir}" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  if [[ "${ahead}" =~ ^[0-9]+$ ]] && [[ "${ahead}" -gt 0 ]]; then
    echo yes
    return 0
  fi
  echo no
}

BOUND="$(_resolve_bound || echo none)"
WORK_DELTA="$(_derive_work_delta || echo skip)"
WORK="$(_resolve_work "${WORK_DELTA}" || echo no)"
PARKED=0
if [[ "${EXIT_CODE}" == "0" && "${BOUND}" == "none" ]] \
   && declare -F lv2_parked_text_file >/dev/null 2>&1 \
   && lv2_parked_text_file "${RUN_DIR}/result.md"; then
  PARKED=1
fi

# ---- 4. outcome decision table, per §2.3 ----
OUTCOME=""
if [[ "${BOUND}" != "none" ]]; then
  [[ "${WORK}" == "yes" ]] && OUTCOME="died-with-work" || OUTCOME="died-clean"
elif [[ "${PARKED}" == "1" && -f "${RUN_DIR}/.deliverable" && -f "${RUN_DIR}/.no-deliverable" ]]; then
  OUTCOME="parked"
elif [[ -f "${RUN_DIR}/.no-deliverable" ]]; then
  [[ "${WORK}" == "yes" ]] && OUTCOME="died-with-work" || OUTCOME="died-clean"
elif [[ "${EXIT_CODE}" == "0" ]]; then
  OUTCOME="completed"
else
  [[ "${WORK}" == "yes" ]] && OUTCOME="died-with-work" || OUTCOME="died-clean"
fi

case "${OUTCOME}" in
  died-with-work) NEXT="continue" ;;
  parked) NEXT="continue" ;;
  died-clean) NEXT="respawn" ;;
  *) NEXT="none" ;;
esac

AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ---- 4b. WORKER-DOD-GATE-01 soft signal ----
# lv2_dod_retry_or_finalize() (lib/leadv2-worker-epilogue.sh) writes
# worker_dod=pass|fail:<checks> to progress.log once its retries are
# exhausted. Named reader only -- this is informational surfacing, never a
# gate: the actual round refusal happens at the hard gate in
# leadv2-dispatch-product-close.sh, independently of this script.
DOD="$(grep -m1 -E '^worker_dod=' "${RUN_DIR}/progress.log" 2>/dev/null | cut -d= -f2- || true)"

# ---- 5. artifacts, per §2.4 -- best-effort, never aborts the script ----
{
  printf 'outcome=%s\n' "${OUTCOME}"
  printf 'bound=%s\n' "${BOUND}"
  printf 'work=%s\n' "${WORK}"
  printf 'next=%s\n' "${NEXT}"
  printf 'at=%s\n' "${AT}"
} > "${RUN_DIR}/.outcome" 2>/dev/null \
  || echo "LEADV2_LANE_OUTCOME_WRITE_FAILED outcome_sentinel" >> "${RUN_DIR}/progress.log" 2>/dev/null || true

if [[ "${DOD}" == fail:* ]]; then
  printf 'LEADV2_LANE_OUTCOME outcome=%s bound=%s work=%s next=%s dod=%s\n' \
    "${OUTCOME}" "${BOUND}" "${WORK}" "${NEXT}" "${DOD}" >> "${RUN_DIR}/progress.log" 2>/dev/null || true
else
  printf 'LEADV2_LANE_OUTCOME outcome=%s bound=%s work=%s next=%s\n' \
    "${OUTCOME}" "${BOUND}" "${WORK}" "${NEXT}" >> "${RUN_DIR}/progress.log" 2>/dev/null || true
fi

{
  printf 'outcome: %s\n' "${OUTCOME}"
  printf 'outcome_bound: %s\n' "${BOUND}"
  printf 'outcome_next: %s\n' "${NEXT}"
  [[ "${DOD}" == fail:* ]] && printf 'outcome_dod: %s\n' "${DOD}"
} >> "${RUN_DIR}/meta.yaml" 2>/dev/null || true

echo "${OUTCOME}"
exit 0
