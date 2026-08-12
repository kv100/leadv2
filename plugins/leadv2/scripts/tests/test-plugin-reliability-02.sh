#!/usr/bin/env bash
# PLUGIN-RELIABILITY-02: behavioural proof that the close-gate timeout path
# reaps the whole setsid worker group from its real sandbox run directory.
#
# Run normally for green.  To gate the historical broken script without
# editing the checkout:
#   LEADV2_PC_SCRIPT=/path/to/c6c44b5-product-close.sh bash "$0"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
CLOSE_SCRIPT="${LEADV2_PC_SCRIPT:-${PLUGIN_ROOT}/scripts/leadv2-dispatch-product-close.sh}"

TMP_ROOT="$(mktemp -d)"
LEADER_PID=""
CHILD_PID=""

cleanup() {
  # The red run deliberately leaves the child alive; never leak it from a test.
  if [[ -n "${LEADER_PID}" ]]; then kill -KILL -"${LEADER_PID}" 2>/dev/null || true; fi
  if [[ -n "${CHILD_PID}" ]]; then kill -KILL "${CHILD_PID}" 2>/dev/null || true; fi
  wait "${LEADER_PID:-0}" 2>/dev/null || true
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

wait_for_file() {
  local f="$1" i
  for i in $(seq 1 50); do
    [[ -s "$f" ]] && return 0
    sleep 0.1
  done
  return 1
}

process_is_dead() {
  local pid="$1" i
  # Give init a moment to reap the session child on platforms where kill -0
  # briefly succeeds for a just-exited zombie.
  for i in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

[[ -r "${CLOSE_SCRIPT}" ]] || fail "close script is unreadable: ${CLOSE_SCRIPT}"

# Mirror glm-coder's spawn record shape:
#   setsid_wrapper SELF __run_child ... &; echo $! > run_dir/pgid
#   echo repo_hash > run_dir/.lockref; echo $! > .lock-repo_hash/pgid
# Python supplies the portable os.setsid equivalent on macOS, where setsid(1)
# is absent.  Its exec'd bash is the session/group leader and forks sleep, so
# CHILD_PID is a real *group child*, not the leader being reaped directly.
RUNS_ROOT="${TMP_ROOT}/cache"
HANDLE="timeout-reap-proof"
RUN_DIR="${RUNS_ROOT}/glm-runs/${HANDLE}"
LOCK_HASH="reliability02"
LOCK_DIR="${RUNS_ROOT}/glm-runs/.lock-${LOCK_HASH}"
CHILD_PID_FILE="${RUN_DIR}/child.pid"
mkdir -p "${RUN_DIR}" "${LOCK_DIR}"

python3 -c '
import os, sys
os.setsid()
os.chdir(os.path.dirname(sys.argv[1]))
os.execvp("bash", ["bash", "-c", "sleep 300 & echo $! > \"$1\"; wait", "bash", sys.argv[1]])
' "${CHILD_PID_FILE}" &
LEADER_PID=$!
wait_for_file "${CHILD_PID_FILE}" || fail "setsid group child did not start"
CHILD_PID="$(cat "${CHILD_PID_FILE}")"

printf '%s\n' "${LEADER_PID}" > "${RUN_DIR}/pgid"
printf '%s\n' "${LOCK_HASH}" > "${RUN_DIR}/.lockref"
printf '%s\n' "${LEADER_PID}" > "${LOCK_DIR}/pgid"
# `running` forces pc_worker_alive to enter the real timeout branch; do not
# record pid here because spawn's supervisor pid is distinct from its pgid.
printf 'status: running\n' > "${RUN_DIR}/meta.yaml"

# This is the production call site at product-close :1508-1516, not a copied
# _pc_reap_worker implementation.  rc=5 is the expected worker_timeout gate.
set +e
env \
  HOME="${TMP_ROOT}/home" \
  LEADV2_PC_RUNS_ROOT="${RUNS_ROOT}" \
  LEADV2_JOB_REGISTRY_ROOT="${TMP_ROOT}/jobs" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/dispatch-cache" \
  LEADV2_STATE_PATH_BIN="${TMP_ROOT}/missing-state-path" \
  LEADV2_JOURNAL_BIN="${TMP_ROOT}/missing-journal" \
  LEADV2_DISPATCH_TERMINAL_LEDGER="0" \
  LEADV2_PC_WORKER_MAX_WAIT_S=1 \
  LEADV2_PC_WORKER_POLL_S=1 \
  LEADV2_PC_WORKER_LOG_EVERY_S=1 \
  bash "${CLOSE_SCRIPT}" "${TMP_ROOT}/repo" "PLUGIN-RELIABILITY-02" glm "${HANDLE}" 0 0
GATE_RC=$?
set -e

[[ "${GATE_RC}" -eq 5 ]] || fail "close gate did not take worker_timeout path (rc=${GATE_RC})"
process_is_dead "${CHILD_PID}" || fail "setsid group child ${CHILD_PID} survived close-timeout reap"

printf 'ok: real close-timeout reap killed setsid group child (gate rc=%s)\n' "${GATE_RC}"
