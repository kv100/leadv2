#!/usr/bin/env bash
# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 round 4, root cause #2 — an async arm
# (glm/glm-flash/kimi/codex/freepool) confirms spawn and this dispatcher
# process exits, but the launcher is NOT a local fork of this process: the
# active.yaml row was left carrying the dispatcher's OWN pre-spawn
# registration pid (lib/leadv2-lane-state.sh's alive() os.kill()s it and it
# is dead within seconds of dispatch returning) even though the async worker
# keeps running for up to an hour. The sonnet arm never had this bug (it
# stamps its own forked pid); this test proves the SAME survives-dispatcher-
# exit guarantee now holds for a non-sonnet arm too, via the lane-pulse
# watcher's own (independently backgrounded, nohup'd) pid.
#
# Sandbox pattern lifted from test-landed-at-spawn.sh (stub GLM bg/status
# launcher, LEADV2_ROUTER_V2=0 + GLM_POLICY_RESOLVER="" forces arm=glm).
# LEADV2_DISPATCH_LANE_PULSE_WATCH_BIN is stubbed with a script that just
# sleeps — same detached-nohup shape as the real leadv2-lane-pulse-watch.sh,
# staying alive well past this dispatcher's own exit.

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"
LANE_STATE_LIB="${PLUGIN_SCRIPTS}/lib/leadv2-lane-state.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-lrod-XXXXXX)"
WATCH_PIDFILE="${SANDBOX}/watch.pid"
WATCH_STOPFILE="${SANDBOX}/watch.stop"
cleanup() {
  if [[ -f "${WATCH_PIDFILE}" ]]; then
    kill "$(cat "${WATCH_PIDFILE}" 2>/dev/null)" 2>/dev/null || true
  fi
  [[ -n "${LEADV2_TEST_KEEP_SANDBOX:-}" ]] || rm -rf "${SANDBOX}"
}
trap cleanup EXIT

TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

export LEADV2_STATE_ROOT="${SANDBOX}/state"
export LEADV2_STATE_BASE="${SANDBOX}/state"
export LEADV2_DISPATCH_CACHE_DIR="${SANDBOX}/cache"

# ── Stub GLM binary (bg creates a fake run record, status checks it) ────────
GLM_STUB="${SANDBOX}/glm-stub.sh"
STUB_RUNS="${SANDBOX}/glm-runs"
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg)
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"
    exit 0
    ;;
  status)
    [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0
    exit 1
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "${GLM_STUB}"

JOURNAL_STUB="${SANDBOX}/journal-stub.sh"
cat > "${JOURNAL_STUB}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${JOURNAL_STUB}"

# ── Stub lane-pulse watcher: same detached-background shape as the real
# leadv2-lane-pulse-watch.sh -- it just sleeps, recording its own pid so the
# test (and cleanup) can find it, and outlives the dispatcher process that
# backgrounds it.
WATCH_STUB="${SANDBOX}/watch-stub.sh"
cat > "${WATCH_STUB}" <<SH
#!/usr/bin/env bash
echo \$\$ > "${WATCH_PIDFILE}"
# This fixture owns the stop file.  Removing its liveness this way avoids
# signalling the test runner's shared process group on macOS while still
# making the registered PID exit under the fixture's exclusive control.
while [[ ! -e "${WATCH_STOPFILE}" ]]; do sleep 0.1; done
SH
chmod +x "${WATCH_STUB}"

ACTIVE_PRESEED="$(PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" LEADV2_STATE_BASE="${LEADV2_STATE_BASE}" \
  bash "${STATE_PATH}" --no-link active.yaml 2>/dev/null)"
if [[ -n "${ACTIVE_PRESEED}" ]]; then
  mkdir -p "$(dirname "${ACTIVE_PRESEED}")"
  printf 'sessions: []\n' > "${ACTIVE_PRESEED}"
fi

TID="dispatch-lrod0001"
MISSION="LROD01: sandbox mission for lane-registry-outlives-dispatcher test"

setup_env() {
  export CLAUDE_PROJECT_DIR="${TARGET}"
  export CLAUDE_PROJECT_ROOT="${TARGET}"
  unset PROJECT_ROOT 2>/dev/null || true
  export LEADV2_LANE_WORK_ROOT="${TARGET}"
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"
  export LEADV2_STUB_GLM_RUNS="${STUB_RUNS}"
  export LEADV2_JOURNAL_BIN="${JOURNAL_STUB}"
  export LEADV2_DISPATCH_LEDGER_BIN="${PLUGIN_SCRIPTS}/leadv2-dispatch-ledger.sh"
  export LEADV2_STATE_PATH_BIN="${STATE_PATH}"
  export LEADV2_ROUTER_V2=0
  export GLM_POLICY_RESOLVER=""
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  export LEADV2_DISPATCH_LANE_PULSE_WATCH_BIN="${WATCH_STUB}"
  export LEADV2_PULSE_MODE=1
  export LEADV2_SINGLE_LEAD_BEAT=0
  # Force arm=glm -- the T17 route_arbiter (cheapest-capable pick) would
  # otherwise reroute to freepool/codex regardless of LEADV2_ROUTER_V2; point
  # its lib at a real inert file so the dispatcher's canonical-source fallback
  # cannot load route_arbiter and `declare -F route_arbiter` fails closed
  # and the legacy resolver's arm=glm survives, same shape as test-landed-at-
  # spawn.sh's own working glm-arm fixture.
  : > "${SANDBOX}/inert-arbiter.sh"
  export LEADV2_ROUTE_ARBITER_LIB="${SANDBOX}/inert-arbiter.sh"
  export LEADV2_EXCLUDED_ARMS="freepool codex sonnet kimi glm-flash"
}

active_yaml_path() {
  PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" LEADV2_STATE_BASE="${LEADV2_STATE_BASE}" \
    bash "${STATE_PATH}" --no-link active.yaml 2>/dev/null
}

# alive() as lib/leadv2-lane-state.sh defines it: is the row for TID's pid
# (whatever it currently is) something os.kill(pid,0) still finds?
row_alive() {
  local active; active="$(active_yaml_path)"
  [[ -f "${active}" ]] || { echo "no-active-yaml"; return 1; }
  PROJECT_ROOT="${TARGET}" LEADV2_STATE_ROOT="${LEADV2_STATE_ROOT}" LEADV2_STATE_BASE="${LEADV2_STATE_BASE}" \
    LEADV2_PROJECT_ROOT="${TARGET}" \
    bash -c "source '${LANE_STATE_LIB}'; lane_alive '${TID}'"
}

# ════════════════════════════════════════════════════════════════════════════
# Spawn a lane via the glm arm, let the dispatcher process exit, then assert
# the registry entry (a) is STILL registered (no dead_at), (b) records the
# watcher pid, and (c) becomes dead when this test kills THAT watcher.  The
# latter two assertions isolate this fixture from _lv2_durable_pid: an
# inherited durable parent may be alive forever, but cannot be the watcher
# process this fixture owns and kills.
# ════════════════════════════════════════════════════════════════════════════
setup_env
dispatch_rc=0
( cd "${TARGET}" && bash "${DC}" --kind tooling --task-id "${TID}" "${MISSION}" ) >"${SANDBOX}/dc-out.log" 2>&1 || dispatch_rc=$?
[[ -n "${LEADV2_TEST_DEBUG:-}" ]] && cat "${SANDBOX}/dc-out.log" >&2

if [[ ${dispatch_rc} -eq 0 ]]; then
  ok "dispatch exited 0 (glm spawn confirmed)"
else
  bad "dispatch exited ${dispatch_rc} (expected 0)"
fi

# Give the backgrounded watcher stub a moment to write its pidfile.
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "${WATCH_PIDFILE}" ]] && break
  sleep 0.3
done

if [[ -s "${WATCH_PIDFILE}" ]]; then
  ok "lane-pulse watcher stub started and recorded its own pid"
  WATCH_PID="$(cat "${WATCH_PIDFILE}" 2>/dev/null || true)"
else
  bad "lane-pulse watcher stub never started -- cannot prove the fix (check LEADV2_DISPATCH_LANE_PULSE_WATCH_BIN wiring)"
  WATCH_PID=""
fi

ACTIVE="$(active_yaml_path)"
if [[ -f "${ACTIVE}" ]] && grep -q "task_id: ${TID}" "${ACTIVE}" 2>/dev/null; then
  ok "registry row for ${TID} exists after dispatcher exit"
else
  bad "registry row for ${TID} missing after dispatcher exit"
fi

if [[ -f "${ACTIVE}" ]] && grep -A20 "task_id: ${TID}" "${ACTIVE}" | grep -q "dead_at: null"; then
  ok "registry row carries dead_at: null (never explicitly deregistered)"
else
  bad "registry row is missing dead_at: null: $(grep -A20 "task_id: ${TID}" "${ACTIVE}" 2>/dev/null)"
fi

ROW_PID="$(python3 - "${ACTIVE}" "${TID}" <<'PY'
import sys
try:
    import yaml
    doc = yaml.safe_load(open(sys.argv[1])) or {}
    for row in doc.get("sessions") or []:
        if isinstance(row, dict) and row.get("task_id") == sys.argv[2]:
            print(row.get("pid") or "")
            break
except Exception:
    pass
PY
)"
if [[ -n "${WATCH_PID}" && "${ROW_PID}" == "${WATCH_PID}" ]]; then
  ok "registry pid is the watcher pid controlled by this test"
else
  bad "registry pid is not the controlled watcher pid (row=${ROW_PID:-none} watcher=${WATCH_PID:-none})"
fi

if [[ -n "${WATCH_PID}" ]]; then
  : > "${WATCH_STOPFILE}"
  for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "${WATCH_PID}" 2>/dev/null || break
    sleep 0.1
  done
fi

verdict="$(row_alive; echo "rc=$?")"
if [[ "${verdict}" != *"rc=0"* ]]; then
  ok "lane_alive(${TID}) becomes dead after the controlled watcher exits"
else
  bad "lane_alive(${TID}) stayed alive after the controlled watcher exited (${verdict})"
fi

printf '\n[LANE-REGISTRY-OUTLIVES-DISPATCHER-01] passed=%d failed=%d\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
