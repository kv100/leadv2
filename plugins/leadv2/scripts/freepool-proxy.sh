#!/usr/bin/env bash
# freepool-proxy.sh — start/stop wrapper for the free-claude-code local proxy
# (T19). The proxy (github.com/Alishahryar1/free-claude-code) translates the
# Anthropic Messages API to free-tier upstream providers (OpenRouter/Groq/NIM
# — UNVERIFIED: exact provider set; verify against the cloned repo's README
# once installed via freepool-install.sh). freepool-coder.sh (the dispatch
# arm's launcher) points `claude -p` at this proxy's ANTHROPIC_BASE_URL; this
# script only manages the proxy PROCESS — pidfile + health probe, nothing
# about mission dispatch.
#
# Env names this script and the proxy need (documented per T19 instructions —
# do NOT put real values in git):
#   FREEPOOL_INSTALL_DIR   default ~/tools/free-claude-code (venv + checkout)
#   FREEPOOL_PROXY_PORT    default 8317 (must match freepool-coder.sh's
#                          FREEPOOL_PROXY_URL host:port)
#   Upstream provider keys consumed by the proxy's OWN .env inside
#   FREEPOOL_INSTALL_DIR (never read directly by this wrapper) — the exact
#   names are whatever the cloned repo's .env.example declares; until keys
#   exist there the proxy has nothing to serve and health_check() below fails
#   closed, which is exactly the "disabled-by-health" posture this task asks
#   for.
set -euo pipefail

readonly FREEPOOL_INSTALL_DIR="${FREEPOOL_INSTALL_DIR:-${HOME}/tools/free-claude-code}"
readonly FREEPOOL_PROXY_PORT="${FREEPOOL_PROXY_PORT:-8317}"
readonly FREEPOOL_STATE_DIR="${LEADV2_FREEPOOL_STATE_DIR:-${HOME}/.claude/leadv2-state}"
readonly FREEPOOL_PIDFILE="${FREEPOOL_STATE_DIR}/freepool-proxy.pid"
readonly FREEPOOL_LOGFILE="${FREEPOOL_STATE_DIR}/freepool-proxy.log"
readonly FREEPOOL_HEALTH_URL="http://127.0.0.1:${FREEPOOL_PROXY_PORT}/health"
readonly FREEPOOL_VENV="${FREEPOOL_INSTALL_DIR}/.venv"

log() { echo "[freepool-proxy] $*" >&2; }

_running_pid() {
  [[ -f "${FREEPOOL_PIDFILE}" ]] || return 1
  local pid
  pid="$(cat "${FREEPOOL_PIDFILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null && { echo "${pid}"; return 0; }
  return 1
}

health_check() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${FREEPOOL_HEALTH_URL}" 2>/dev/null | grep -q '^2'
}

cmd_start() {
  mkdir -p "${FREEPOOL_STATE_DIR}"
  local existing
  if existing="$(_running_pid)"; then
    log "already running (pid ${existing})"
    exit 0
  fi
  if [[ ! -d "${FREEPOOL_INSTALL_DIR}" ]]; then
    log "install dir absent: ${FREEPOOL_INSTALL_DIR} — run freepool-install.sh first"
    exit 1
  fi
  if [[ ! -x "${FREEPOOL_VENV}/bin/python3" ]]; then
    log "venv absent at ${FREEPOOL_VENV} — run freepool-install.sh first"
    exit 1
  fi
  # ENTRYPOINT resolution — detected in this order, logged at start:
  #   1. FREEPOOL_ENTRYPOINT override (operator-set) — always wins.
  #   2. ${FREEPOOL_INSTALL_DIR}/.venv/bin/fcc-server, if present and
  #      executable — current upstream (free-claude-code, pinned commit
  #      6b3f16f) console script, package `free_claude_code`, port read from
  #      env var PORT (not a CLI flag).
  #   3. legacy `python3 -m server --port ${FREEPOOL_PROXY_PORT}`, if the
  #      `server` module is still importable in that venv — keeps anyone
  #      pinned to an older upstream checkout working unchanged.
  #   4. neither candidate found — fail fast rather than start a process
  #      known to die instantly (was: silent ModuleNotFoundError, health
  #      never comes up, status just says "stopped" with no cause surfaced).
  local entrypoint="" entrypoint_needs_port_env=0 branch=""
  if [[ -n "${FREEPOOL_ENTRYPOINT:-}" ]]; then
    entrypoint="${FREEPOOL_ENTRYPOINT}"
    branch="override (FREEPOOL_ENTRYPOINT)"
  elif [[ -x "${FREEPOOL_VENV}/bin/fcc-server" ]]; then
    entrypoint="${FREEPOOL_VENV}/bin/fcc-server"
    entrypoint_needs_port_env=1
    branch="fcc-server (current upstream)"
  elif "${FREEPOOL_VENV}/bin/python3" -c 'import server' >/dev/null 2>&1; then
    entrypoint="python3 -m server --port ${FREEPOOL_PROXY_PORT}"
    branch="legacy python -m server (older upstream checkout)"
  else
    log "no usable entrypoint found — tried ${FREEPOOL_VENV}/bin/fcc-server (absent/not executable) and 'python -m server' (not importable) in ${FREEPOOL_INSTALL_DIR}"
    log "set FREEPOOL_ENTRYPOINT to override, or re-run freepool-install.sh against a supported upstream commit"
    exit 1
  fi
  log "entrypoint resolved via: ${branch}"
  log "starting: ${entrypoint} (cwd=${FREEPOOL_INSTALL_DIR})"
  (
    cd "${FREEPOOL_INSTALL_DIR}"
    # shellcheck disable=SC1091
    source "${FREEPOOL_VENV}/bin/activate"
    # PORT is exported only inside this backgrounded subshell, so it never
    # leaks into the caller's shell — consuming repos' own apps (e.g. this
    # repo's Hono server) read PORT themselves and must not see it changed.
    if [[ "${entrypoint_needs_port_env}" == "1" ]]; then
      export PORT="${FREEPOOL_PROXY_PORT}"
    fi
    exec ${entrypoint} >>"${FREEPOOL_LOGFILE}" 2>&1
  ) &
  local pid=$!
  disown "${pid}" 2>/dev/null || true
  echo "${pid}" > "${FREEPOOL_PIDFILE}"
  log "started pid=${pid}, waiting for health..."
  local i
  for i in $(seq 1 15); do
    if health_check; then
      log "healthy after ${i}s"
      exit 0
    fi
    sleep 1
  done
  if kill -0 "${pid}" 2>/dev/null; then
    log "did not become healthy within 15s — leaving process running, gate will report arm_down until it recovers"
  else
    log "process exited during startup (pid ${pid} is gone) — last 15 lines of ${FREEPOOL_LOGFILE}:"
    tail -n 15 "${FREEPOOL_LOGFILE}" >&2 2>/dev/null || log "logfile unavailable: ${FREEPOOL_LOGFILE}"
  fi
  exit 0
}

cmd_stop() {
  local pid
  if ! pid="$(_running_pid)"; then
    log "not running"
    rm -f "${FREEPOOL_PIDFILE}"
    exit 0
  fi
  log "stopping pid=${pid}"
  kill -TERM "${pid}" 2>/dev/null || true
  sleep 2
  kill -KILL "${pid}" 2>/dev/null || true
  rm -f "${FREEPOOL_PIDFILE}"
}

cmd_status() {
  local pid
  if pid="$(_running_pid)"; then
    if health_check; then
      echo "status: running_healthy pid=${pid} url=${FREEPOOL_HEALTH_URL}"
    else
      echo "status: running_unhealthy pid=${pid} url=${FREEPOOL_HEALTH_URL}"
    fi
  else
    echo "status: stopped"
  fi
}

case "${1:-status}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  restart) cmd_stop; sleep 1; cmd_start ;;
  *) echo "usage: freepool-proxy.sh [start|stop|status|restart]" >&2; exit 64 ;;
esac
