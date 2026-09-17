#!/usr/bin/env bash
# leadv2-fleet-runner.sh — FLEET-RUNTIME-UNATTENDED-01
#
# The systemd unit's ExecStart target: a foreground loop that takes lanes
# one at a time to completion and checks the stop flag and the three
# self-stop conditions BETWEEN lanes, never mid-lane. Process-level
# supervision (bring the process back if it dies) is systemd's job
# (Restart=always in the generated unit, see leadv2-fleet-unit.sh).
#
# Restart=always means exactly that: systemd relaunches this script after
# ANY exit, clean or not — a controlled stop is not exempt (round-2 fix:
# H1 in the round-1 review found the runner's header claiming otherwise,
# and the resulting flap: set alive, re-detect the same stop condition,
# set stopped, exit, repeat every RestartSec). The fix is on THIS side, not
# systemd's: the loop below never writes status=alive until EVERY
# self-stop check has already passed for this iteration, so a restarted
# process that finds the same stop condition still true goes straight back
# to `stopped` with the same reason and never visibly flaps through
# `alive`. Removing the stop flag (or the disk/streak/quota condition
# clearing) lets the next restart proceed normally — no reinstall needed.
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
# hook must honor, not the dispatch internals themselves:
#   rc 0        lane landed — resets the no-landing streak
#   rc != 0     lane reached a terminal without landing — increments the streak
#   stdout      an optional line `FLEET_WORKTREE=<path>` names the lane's
#               worktree; when present, this script touches
#               `<path>/.fleet-terminal` the moment the lane cmd returns
#               (either rc), which is the marker leadv2-fleet-guard.sh reaps
#               on (round-2 fix: H5 — nothing wrote this marker in round 1,
#               so the guard's reap step was dead code in production).
# `LEADV2_FLEET_LANE_CMD` unset/empty is a runner-level wiring gap, not a
# lane outcome: it is detected BEFORE any lane is attempted (never counted
# against the no-landing streak, round-2 fix H2) and self-stops immediately
# with reason `unwired`, exit 2, so Restart=always keeps retrying it (and
# keeps reporting `unwired` truthfully) rather than a fresh install silently
# racking up a false `no_landing_streak` diagnosis.
#
# --cap (round-2 fix H3): this runner is deliberately sequential (never two
# lanes in flight per instance — see above) — "cap" is not this script's own
# concurrency knob. It is exported as LEADV2_FLEET_CAP to the pluggable lane
# hook so the real per-repo concurrency owner (leadv2-active-registry.sh /
# leadv2-dispatch-code.sh, both off-limits this session) can read it once
# wired. Round 1 rendered --cap into the unit and never read it anywhere,
# which the review correctly called a documented lie; this is the "forward,
# don't consume" resolution the review offered as one of its two acceptable
# fixes (the other being real N-way concurrency, out of scope while the
# dispatch hook itself is unwired).
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

LANE_WORKTREE=""

_run_lane_cmd() { # (LEADV2_FLEET_LANE_CMD already validated non-empty by the caller)
  local outfile
  LANE_WORKTREE=""
  outfile="$(mktemp "${TMPDIR:-/tmp}/leadv2-fleet-lane.XXXXXX")"
  # shellcheck disable=SC2086
  eval "${LEADV2_FLEET_LANE_CMD}" | tee "${outfile}"
  local rc="${PIPESTATUS[0]}"
  LANE_WORKTREE="$(grep -m1 '^FLEET_WORKTREE=' "${outfile}" 2>/dev/null | cut -d= -f2-)"
  rm -f "${outfile}"
  return "${rc}"
}

iterations=0

while true; do
  if fleet_stop_flag_present; then # c2-mut: stop-flag gate
    _stop "stop_flag"
    exit 0
  fi

  if ! floor_reason="$(fleet_disk_floor_ok "${REPO}" "${FLOOR_KB}")"; then
    _stop "disk_floor: ${floor_reason}"
    exit 0
  fi

  if [[ -z "${LEADV2_FLEET_LANE_CMD:-}" ]]; then
    echo "[fleet-runner] FATAL: LEADV2_FLEET_LANE_CMD not set — no dispatch entry point wired (expected: the dispatch-owning lane wires this)" >&2
    _stop "unwired: LEADV2_FLEET_LANE_CMD not set"
    exit 2
  fi

  streak="$("${STATE_BIN}" read-raw --name "${NAME}" | grep -m1 '^consecutive_no_landing=' | cut -d= -f2-)"
  streak="${streak:-0}"
  if [[ "${streak}" -ge "${MAX_STREAK}" ]]; then
    _stop "no_landing_streak: ${streak} consecutive lanes without landing (max ${MAX_STREAK})"
    exit 0
  fi

  if ! arm="$(fleet_any_arm_available)"; then
    _stop "$(fleet_stop_kind_for_no_arm): $(fleet_no_arm_reasons)"
    exit 0
  fi

  # All self-stop checks passed for this iteration — only now is it true.
  if [[ "${arm}" != "claude" ]]; then
    "${STATE_BIN}" set-status --name "${NAME}" --status alive --reason "" --mode "degraded:${arm}" >/dev/null
    printf '[fleet-runner] degrade: claude unusable, continuing on %s\n' "${arm}"
  else
    "${STATE_BIN}" set-status --name "${NAME}" --status alive --reason "" --mode normal >/dev/null
  fi

  "${STATE_BIN}" inc-field --name "${NAME}" --field lanes_in_flight --by 1 >/dev/null
  LEADV2_FLEET_ARM="${arm}" LEADV2_FLEET_CAP="${CAP}" _run_lane_cmd
  lane_rc=$?
  "${STATE_BIN}" inc-field --name "${NAME}" --field lanes_in_flight --by -1 >/dev/null

  if [[ -n "${LANE_WORKTREE}" && -d "${LANE_WORKTREE}" ]]; then
    : > "${LANE_WORKTREE}/.fleet-terminal"
  fi

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
