#!/usr/bin/env bash
# leadv2-fleet-runner.sh — FLEET-RUNTIME-UNATTENDED-01
#
# The systemd unit's ExecStart target: a foreground loop that takes lanes
# one at a time to completion and checks the stop flag and the three
# self-stop conditions BETWEEN lanes, never mid-lane. Process-level
# supervision (bring the process back if it dies) is systemd's job
# (Restart=always in the generated unit, see leadv2-fleet-unit.sh) — this
# script's own job ends the moment it decides "no new lane", at which point
# it exits 0 and systemd, seeing a clean exit, does not restart it (that is
# the whole point of the stop flag: a controlled stop, not a crash).
#
# This is deliberately NOT the supervisor daemon retired 2026-08-17
# (leadv2-fanout.sh / leadv2-supervise-loop.sh): it holds no health-check
# loop over a running session, does no polling of a live process, and never
# runs two lanes concurrently per instance. It is sequential: take one lane,
# run it to ITS OWN terminal synchronously, then decide about the next one.
#
# Lane execution is a pluggable hook (LEADV2_FLEET_LANE_CMD) rather than a
# direct call into leadv2-dispatch-code.sh: that script and
# leadv2-active-registry.sh are owned by other lanes this session (mission
# off-limits) and are still under concurrent edit. Wiring the real
# dispatch entry point into this hook is follow-up work for whichever lane
# owns dispatch-code.sh; this script defines and tests the CONTRACT the
# hook must honor (rc 0 = landed, rc != 0 = reached a terminal without
# landing), not the dispatch internals themselves.
#
# Contract for LEADV2_FLEET_LANE_CMD (default: prints a FATAL and exits 2 —
# fails loudly rather than silently no-op looping):
#   rc 0        lane landed — resets the no-landing streak
#   rc != 0     lane reached a terminal without landing — increments the streak
#
# No `claude` invocation directly in this file's control-flow decisions
# (arm selection is via leadv2-fleet-lib.sh's local, non-network probes);
# the lane command itself is what actually runs a Claude/GLM session, which
# is expected and is not what the off-limits rule (guard/state reader) covers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-fleet-lib.sh
. "${SCRIPT_DIR}/leadv2-fleet-lib.sh"
STATE_BIN="${LEADV2_FLEET_STATE_BIN:-${SCRIPT_DIR}/leadv2-fleet-state.sh}"

REPO=""
NAME=""
CAP=1
FLOOR_KB="${FLEET_DISK_FLOOR_KB_DEFAULT}"
MAX_STREAK="${LEADV2_FLEET_MAX_NO_LANDING_STREAK:-5}"
MAX_ITERATIONS="${LEADV2_FLEET_MAX_ITERATIONS:-0}"   # 0 = unbounded (real use); tests bound this

usage() {
  cat <<'EOF'
usage: leadv2-fleet-runner.sh --repo <path> --name <instance> [--cap N]
                               [--floor-kb N] [--max-streak N]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --floor-kb) FLOOR_KB="$2"; shift 2 ;;
    --max-streak) MAX_STREAK="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "leadv2-fleet-runner.sh: unknown arg $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${REPO}" && -n "${NAME}" ]] || { usage; exit 2; }

_stop() { # <reason>
  "${STATE_BIN}" set-status --name "${NAME}" --status stopped --reason "$1" >/dev/null
  printf '[fleet-runner] stop reason=%s\n' "$1"
}

_run_lane_cmd() {
  local cmd="${LEADV2_FLEET_LANE_CMD:-}"
  if [[ -z "${cmd}" ]]; then
    echo "[fleet-runner] FATAL: LEADV2_FLEET_LANE_CMD not set — no dispatch entry point wired (expected: the dispatch-owning lane wires this)" >&2
    return 2
  fi
  # shellcheck disable=SC2086
  eval "${cmd}"
}

iterations=0
"${STATE_BIN}" set-status --name "${NAME}" --status alive --reason "" --mode normal >/dev/null

while true; do
  if fleet_stop_flag_present; then # c2-mut: stop-flag gate
    _stop "stop_flag"
    exit 0
  fi

  if ! floor_reason="$(fleet_disk_floor_ok "${REPO}" "${FLOOR_KB}")"; then
    _stop "disk_floor: ${floor_reason}"
    exit 0
  fi

  streak="$("${STATE_BIN}" read-raw --name "${NAME}" | grep -m1 '^consecutive_no_landing=' | cut -d= -f2-)"
  streak="${streak:-0}"
  if [[ "${streak}" -ge "${MAX_STREAK}" ]]; then
    _stop "no_landing_streak: ${streak} consecutive lanes without landing (max ${MAX_STREAK})"
    exit 0
  fi

  if ! arm="$(fleet_any_arm_available)"; then
    _stop "quota_window: no configured arm ($(fleet_configured_arms)) is usable"
    exit 0
  fi

  if [[ "${arm}" != "claude" ]]; then
    "${STATE_BIN}" set-field --name "${NAME}" --field mode --value "degraded:${arm}" >/dev/null
    printf '[fleet-runner] degrade: claude unusable, continuing on %s\n' "${arm}"
  else
    "${STATE_BIN}" set-field --name "${NAME}" --field mode --value "normal" >/dev/null
  fi

  "${STATE_BIN}" inc-field --name "${NAME}" --field lanes_in_flight --by 1 >/dev/null
  LEADV2_FLEET_ARM="${arm}" _run_lane_cmd
  lane_rc=$?
  "${STATE_BIN}" inc-field --name "${NAME}" --field lanes_in_flight --by -1 >/dev/null

  if [[ "${lane_rc}" -eq 0 ]]; then
    "${STATE_BIN}" set-field --name "${NAME}" --field consecutive_no_landing --value 0 >/dev/null
    "${STATE_BIN}" inc-field --name "${NAME}" --field landed_today --by 1 >/dev/null
  else
    "${STATE_BIN}" inc-field --name "${NAME}" --field consecutive_no_landing --by 1 >/dev/null
  fi

  iterations=$((iterations + 1))
  if [[ "${MAX_ITERATIONS}" -gt 0 && "${iterations}" -ge "${MAX_ITERATIONS}" ]]; then
    printf '[fleet-runner] max-iterations reached (%s) — test/bounded mode exit\n' "${MAX_ITERATIONS}"
    exit 0
  fi
done
