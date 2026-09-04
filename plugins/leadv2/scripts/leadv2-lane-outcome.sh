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

# ---- 3. work: yes|no|unknown, resolving a "skip" delta via the persona-engine git probe ----
# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01 fix: a work state that
# cannot be DETERMINED (no cwd on record, or cwd is not a git tree) used to
# default to "no" -- the "conservative" label was backwards: silently
# defaulting an undeterminable state to "no work" is exactly how died-clean
# throws real work away downstream. Only an ACTUAL clean-tree, up-to-date
# git probe may report "no"; every case where the probe itself could not run
# reports "unknown" so the decision table (below) can refuse to guess.
_resolve_work() {
  local delta="$1"
  case "${delta}" in
    yes) echo yes; return 0 ;;
    no) echo no; return 0 ;;
  esac
  # delta == skip: fall back to meta_get cwd -- dirty tracked tree OR commits ahead
  # of upstream => yes; missing cwd / not a git tree => unknown (the probe
  # itself could not run -- this is NOT the same fact as a clean tree).
  local cwd_dir
  cwd_dir="$(_lane_outcome_meta_get cwd)"
  if [[ -z "${cwd_dir}" || ! -d "${cwd_dir}" ]]; then
    echo unknown
    return 0
  fi
  if ! git -C "${cwd_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo unknown
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

# ---- 0. verdict: highest-priority input, per
# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01 §2. A recorded gate verdict
# (review/dod/e2e) outranks everything else when present.
#
# HONESTY NOTE (measured, not aspirational): as of this change, NO shipped
# caller writes ${RUN_DIR}/.gate-verdict. leadv2-lane-outcome.sh is invoked
# by glm-coder.sh/kimi-coder.sh/freepool-coder.sh from inside their own
# finalize path, immediately at raw worker exit -- strictly BEFORE
# leadv2-dispatch-product-close.sh's review_gate/dod-gate machinery ever
# runs (grep 'leadv2-lane-outcome.sh' plugins/leadv2/scripts/*.sh shows all
# three call sites are pre-review; review artifacts live under
# docs/handoff/dispatch-<task>/, a path this script is never handed). So no
# gate verdict CAN exist at the moment this script runs today. This hook is
# a forward-compatible seam -- if a future caller (or a resumed
# classification of the same run_dir) has a real verdict, it now wins
# unconditionally; it is not a claim that one is available today.
_resolve_verdict() { # -> outcome token, or empty if none recorded
  local f="${RUN_DIR}/.gate-verdict" outcome
  [[ -s "${f}" ]] || { printf ''; return 0; }
  outcome="$(sed -n 's/^outcome=//p' "${f}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  case "${outcome}" in
    completed|died-with-work|died-clean|parked|unknown) printf '%s' "${outcome}"; return 0 ;;
  esac
  printf ''
}

VERDICT="$(_resolve_verdict || true)"
BOUND="$(_resolve_bound || echo none)"
WORK_DELTA="$(_derive_work_delta || echo skip)"
WORK="$(_resolve_work "${WORK_DELTA}" || echo unknown)"

# Wording probe is LAST RESORT, subordinate to both the verdict and the work
# state (LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01 §2): it may only be
# consulted when there is no recorded verdict AND the work state was
# actually determined (never asked to arbitrate an "unknown"), and it can
# never be reached at all once a bound/died-* path is already decided
# (EXIT_CODE==0 && BOUND==none guards that structurally, same as before).
PARKED=0
if [[ -z "${VERDICT}" && "${WORK}" != "unknown" \
   && "${EXIT_CODE}" == "0" && "${BOUND}" == "none" ]] \
   && declare -F lv2_parked_text_file >/dev/null 2>&1 \
   && lv2_parked_text_file "${RUN_DIR}/result.md"; then
  PARKED=1
fi

# ---- 4. outcome decision table, per §2.3, extended by
# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01: verdict first, then
# state (bound + work), then wording last -- and an undetermined work state
# is never silently resolved to the safer-sounding "died-clean"/"no".
OUTCOME=""
if [[ -n "${VERDICT}" ]]; then
  OUTCOME="${VERDICT}"
elif [[ "${BOUND}" != "none" ]]; then
  case "${WORK}" in
    yes) OUTCOME="died-with-work" ;;
    unknown) OUTCOME="unknown" ;;
    *) OUTCOME="died-clean" ;;
  esac
elif [[ "${PARKED}" == "1" && "${WORK}" != "yes" \
     && -f "${RUN_DIR}/.deliverable" && -f "${RUN_DIR}/.no-deliverable" ]]; then
  OUTCOME="parked"
elif [[ -f "${RUN_DIR}/.no-deliverable" ]]; then
  case "${WORK}" in
    yes) OUTCOME="died-with-work" ;;
    unknown) OUTCOME="unknown" ;;
    *) OUTCOME="died-clean" ;;
  esac
elif [[ "${EXIT_CODE}" == "0" ]]; then
  OUTCOME="completed"
else
  case "${WORK}" in
    yes) OUTCOME="died-with-work" ;;
    unknown) OUTCOME="unknown" ;;
    *) OUTCOME="died-clean" ;;
  esac
fi

case "${OUTCOME}" in
  died-with-work) NEXT="continue" ;;
  parked) NEXT="continue" ;;
  died-clean) NEXT="respawn" ;;
  *) NEXT="none" ;;  # includes "unknown" and "completed" -- never auto-respawn an undetermined lane
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
