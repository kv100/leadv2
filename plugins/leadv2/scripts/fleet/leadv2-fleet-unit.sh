#!/usr/bin/env bash
# leadv2-fleet-unit.sh — FLEET-RUNTIME-UNATTENDED-01
#
# Installs/updates a systemd USER unit + timer per lead-session instance,
# parameterised by repo path and lane cap. `Restart=always` on the service;
# reboot/disconnect survival via `loginctl enable-linger`. Two instances on
# the target host per the plan: ~/leadv2 cap 2, ~/pe-fleet cap 1 — this
# script installs ONE instance per invocation; call it twice for the pair.
#
# No `while true` polling loop lives in this file or in the unit it writes:
# the unit's ExecStart is leadv2-fleet-runner.sh (sequential lane taker,
# see that file's header), and maintenance runs on a separate systemd TIMER
# calling leadv2-fleet-guard.sh — never inside the long-running unit itself.
#
# systemctl/loginctl are resolved from PATH by default so a test can stub
# them by prepending a directory to PATH; LEADV2_FLEET_SYSTEMCTL_BIN /
# LEADV2_FLEET_LOGINCTL_BIN are explicit overrides for the same purpose.
#
# --dry-run prints the unit files and the exact command sequence WITHOUT
# executing systemctl/loginctl at all — this is what lets the guard suite
# (macOS, no systemd) inspect generated content deterministically.
#
# --lane-cmd (round-2 fix H2): renders `Environment=LEADV2_FLEET_LANE_CMD=...`
# into the service unit so a real install can actually take a lane — round 1
# shipped a unit with zero Environment= lines, so leadv2-fleet-runner.sh
# self-stopped as "unwired" on every boot. Optional because the real
# dispatch entry point is owned by another lane this session (mission
# off-limits); omitting it installs a unit that runs and self-stops with a
# named, truthful reason (`unwired`) instead of silently doing nothing —
# `install` without it prints a loud warning and the exact re-install
# command to wire it later.
#
# Usage:
#   leadv2-fleet-unit.sh install --repo <path> --name <instance> --cap <N>
#                                 [--lane-cmd <cmd>] [--restart always|no] [--dry-run]
#   leadv2-fleet-unit.sh print-unit --repo <path> --name <instance> --cap <N>
#                                    [--lane-cmd <cmd>] [--restart always|no]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMCTL_BIN="${LEADV2_FLEET_SYSTEMCTL_BIN:-systemctl}"
LOGINCTL_BIN="${LEADV2_FLEET_LOGINCTL_BIN:-loginctl}"
UNIT_DIR="${LEADV2_FLEET_UNIT_DIR:-${HOME}/.config/systemd/user}"

REPO=""
NAME=""
CAP=1
RESTART="always"
LANE_CMD=""
DRY_RUN=0
SUB=""

usage() {
  cat <<'EOF'
usage: leadv2-fleet-unit.sh {install|print-unit} --repo <path> --name <instance>
                             [--cap N] [--lane-cmd <cmd>] [--restart always|no] [--dry-run]
EOF
}

[[ $# -gt 0 ]] || { usage; exit 2; }
SUB="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --lane-cmd) LANE_CMD="$2"; shift 2 ;;
    --restart) RESTART="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "leadv2-fleet-unit.sh: unknown arg $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${REPO}" && -n "${NAME}" ]] || { usage; exit 2; }

_service_name() { printf 'leadv2-fleet-%s.service\n' "$1"; }
_timer_name() { printf 'leadv2-fleet-%s-guard.timer\n' "$1"; }
_guard_service_name() { printf 'leadv2-fleet-%s-guard.service\n' "$1"; }

_render_service() { # <name> <repo> <cap> <restart> [<lane_cmd>]
  local env_line=""
  [[ -n "${5:-}" ]] && env_line="Environment=LEADV2_FLEET_LANE_CMD=${5}"
  cat <<EOF
[Unit]
Description=leadv2 fleet runner (${1})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory="${2}"
${env_line}
ExecStart="${SCRIPT_DIR}/leadv2-fleet-runner.sh" --repo "${2}" --name "${1}" --cap "${3}"
Restart=${4} # c1-mut: restart policy passthrough
RestartSec=30

[Install]
WantedBy=default.target
EOF
}

_render_guard_service() { # <name> <repo>
  cat <<EOF
[Unit]
Description=leadv2 fleet guard pass (${1})

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/leadv2-fleet-guard.sh --repo ${2} --name ${1}
EOF
}

_render_guard_timer() { # <name>
  cat <<EOF
[Unit]
Description=leadv2 fleet guard timer (${1})

[Timer]
OnUnitActiveSec=5min
OnBootSec=2min
Unit=$(_guard_service_name "${1}")

[Install]
WantedBy=timers.target
EOF
}

cmd_print_unit() {
  printf '# %s\n' "$(_service_name "${NAME}")"
  _render_service "${NAME}" "${REPO}" "${CAP}" "${RESTART}" "${LANE_CMD}"
  printf '\n# %s\n' "$(_guard_service_name "${NAME}")"
  _render_guard_service "${NAME}" "${REPO}"
  printf '\n# %s\n' "$(_timer_name "${NAME}")"
  _render_guard_timer "${NAME}"
}

cmd_install() {
  local svc guard_svc timer svc_path guard_path timer_path
  svc="$(_service_name "${NAME}")"
  guard_svc="$(_guard_service_name "${NAME}")"
  timer="$(_timer_name "${NAME}")"
  svc_path="${UNIT_DIR}/${svc}"
  guard_path="${UNIT_DIR}/${guard_svc}"
  timer_path="${UNIT_DIR}/${timer}"

  if [[ -z "${LANE_CMD}" ]]; then
    echo "[fleet-unit] WARNING: --lane-cmd not given — installed unit will self-stop (reason: unwired) until wired. Re-run with --lane-cmd '<dispatch entry point>' to fix without a fresh reboot: 'leadv2-fleet-unit.sh install --repo ${REPO} --name ${NAME} --cap ${CAP} --lane-cmd <cmd>'" >&2
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] would write ${svc_path}"
    _render_service "${NAME}" "${REPO}" "${CAP}" "${RESTART}" "${LANE_CMD}"
    echo "[dry-run] would write ${guard_path}"
    _render_guard_service "${NAME}" "${REPO}"
    echo "[dry-run] would write ${timer_path}"
    _render_guard_timer "${NAME}"
    echo "[dry-run] would run: ${LOGINCTL_BIN} enable-linger \"\$(whoami)\""
    echo "[dry-run] would run: ${SYSTEMCTL_BIN} --user daemon-reload"
    echo "[dry-run] would run: ${SYSTEMCTL_BIN} --user enable --now ${svc}"
    echo "[dry-run] would run: ${SYSTEMCTL_BIN} --user enable --now ${timer}"
    return 0
  fi

  mkdir -p "${UNIT_DIR}"
  _render_service "${NAME}" "${REPO}" "${CAP}" "${RESTART}" "${LANE_CMD}" > "${svc_path}"
  _render_guard_service "${NAME}" "${REPO}" > "${guard_path}"
  _render_guard_timer "${NAME}" > "${timer_path}"

  "${LOGINCTL_BIN}" enable-linger "$(whoami)"
  "${SYSTEMCTL_BIN}" --user daemon-reload
  "${SYSTEMCTL_BIN}" --user enable --now "${svc}"
  "${SYSTEMCTL_BIN}" --user enable --now "${timer}"
}

case "${SUB}" in
  install) cmd_install ;;
  print-unit) cmd_print_unit ;;
  *) usage; exit 2 ;;
esac
