#!/usr/bin/env bash
# FORK-STORM-KILLS-HOOKS-01 — the watcher loop, consumer side + hygiene side.
#
# The closed loop (measured live 2026-09-01, docs/handoff/FORK-STORM-KILLS-HOOKS-01/
# fix-round-2.md): a dispatch re-pins its lane's active.yaml row to the lane-pulse
# watcher's pid; the watcher outlives the dispatch (ppid=1); lane liveness reads
# that pid as WORKER liveness and answers live; the next dispatch refuses with
# lane_is_live / terminates skipped:plan_source_absent; its own watcher arms —
# return to 1. 11 of the last 12 lane terminals were that skip, ~30s apart.
#
# These fixtures prove the three acceptance additions:
#   8/9 (consumer): a row whose only pinned pid is watcher-role is NOT live —
#       identical fixtures differing ONLY in worker_pid_role resolve opposite
#       verdicts (control worker -> starting:*, watcher -> dead:*), and the
#       probe contract carries watcher_only=1 so placement can reap instead
#       of refuse;
#   8 (hygiene): the real leadv2-lane-pulse-watch.sh self-terminates when the
#       registry row still pins ITS pid as a watcher and the row has frozen
#       (LEADV2_LANE_PULSE_WATCH_ORPHAN_MAX_S);
#  10: the skip cause is distinct (plan_source_absent_stale_watcher, never bare)
#       when the dispatch got this far only by reaping a stale watcher — driven
#       against the REAL _deliver_plan_into_lane body, extracted from the
#       shipped script (no copy).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_PATH="${PLUGIN_SCRIPTS}/leadv2-state-path.sh"
LIVENESS="${PLUGIN_SCRIPTS}/leadv2-lane-liveness.sh"
WATCHER="${PLUGIN_SCRIPTS}/leadv2-lane-pulse-watch.sh"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-fskh-XXXXXX)"
cleanup() {
  [[ -n "${KEEP_PID:-}" ]] && kill "${KEEP_PID}" 2>/dev/null || true
  [[ -n "${WATCH_PID:-}" ]] && kill "${WATCH_PID}" 2>/dev/null || true
  [[ -n "${LEADV2_TEST_KEEP_SANDBOX:-}" ]] || rm -rf "${SANDBOX}"
}
trap cleanup EXIT

export LEADV2_STATE_ROOT="${SANDBOX}/state"
export LEADV2_STATE_BASE="${SANDBOX}/state"
ROOT="${SANDBOX}/proj"
mkdir -p "${ROOT}/docs/leadv2"
ACTIVE_YAML="$(PROJECT_ROOT="${ROOT}" bash "${STATE_PATH}" active.yaml 2>/dev/null || true)"
[[ -n "${ACTIVE_YAML}" ]] || ACTIVE_YAML="${ROOT}/docs/leadv2/active.yaml"

# One live process to pin: a sleep the fixtures keep alive until cleanup.
sleep 300 & KEEP_PID=$!

write_row() {  # <lane-id> <role> <pid> <updated_at>
  python3 - "$ACTIVE_YAML" "$1" "$2" "$3" "$4" <<'PY'
import sys, yaml
path, tid, role, pid, updated = sys.argv[1:6]
data = {"sessions": [{"task_id": tid, "session_id": "t", "lead_session_id": "t",
                      "worktree": tid, "phase": "build", "pid": int(pid),
                      "pid_birth": "", "pid_role": role,
                      "worker_pid": int(pid), "worker_pid_birth": "",
                      "worker_pid_role": role,
                      "started_at": updated, "updated_at": updated,
                      "dead_at": None, "lane_events": []}]}
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
PY
}

field() {  # <json> <key>
  printf '%s' "$1" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
    v = r.get(sys.argv[1])
    if v is not None: print(v)
except Exception:
    pass
' "$2" 2>/dev/null || true
}

OLD_TS="2026-08-30T00:00:00Z"   # frozen long before the test runs

# ── Acceptance 8/9: identical lane, ONLY the pid role differs ────────────────
# The loop's real shape: every retry's idempotent re-registration REFRESHES
# the row, so started_at is always recent — the rows here carry a fresh
# started_at exactly like a lane mid-storm does.
RECENT_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Control: worker-role live pid (the pre-FORK-STORM reading) -> starting grace.
write_row "CTRL-LANE" "worker" "${KEEP_PID}" "${RECENT_TS}"
OUT_CTRL="$(bash "${LIVENESS}" --project-root "${ROOT}" --lane "CTRL-LANE" --no-codex --json 2>/dev/null || true)"
V_CTRL="$(field "${OUT_CTRL}" verdict)"
case "${V_CTRL}" in
  starting:*|alive|silent:*) ok "control: worker-role live pid still reads live-ish (verdict=${V_CTRL:-none})" ;;
  *) bad "control: worker-role pid should keep prior live-ish verdict, got '${V_CTRL:-none}'" ;;
esac

# Fixture: watcher-role pid, same freshness — must NOT read live (acc 9).
write_row "WATCH-LANE" "watcher" "${KEEP_PID}" "${RECENT_TS}"
OUT_WATCH="$(bash "${LIVENESS}" --project-root "${ROOT}" --lane "WATCH-LANE" --no-codex --json 2>/dev/null || true)"
V_WATCH="$(field "${OUT_WATCH}" verdict)"
WO="$(field "${OUT_WATCH}" watcher_only)"
case "${V_WATCH}" in
  alive|starting:*) bad "acc9: watcher-only row read LIVE (verdict=${V_WATCH})" ;;
  dead:*) ok "acc9: watcher-only row is NOT live (verdict=${V_WATCH})" ;;
  *) bad "acc9: unexpected verdict '${V_WATCH:-none}'" ;;
esac
if [[ "${WO}" == "1" ]]; then
  ok "acc9/probe-contract: watcher_only=1 present for placement probe"
else
  bad "acc9/probe-contract: watcher_only missing/!=1 (got '${WO:-none}')"
fi

# Mutation kill A: if the starting-rung guard is removed, WATCH-LANE re-earns
# starting:* and this fixture must go red. Verified in report.md by flipping
# `not row.get("watcher_only")` -> `True` (see fix-round-3 notes).

# ── Acceptance 8 (hygiene): the real watcher self-terminates on a frozen ────
# watcher-only row that pins ITS pid.
WROOT="${SANDBOX}/wproj"
WSTATE="${SANDBOX}/wstate"
mkdir -p "${WROOT}/docs/leadv2" "${WSTATE}"
WJOURNAL="${WROOT}/docs/leadv2/tasks/dispatch-fskh0001/journal.md"
mkdir -p "$(dirname "${WJOURNAL}")"
printf -- '- 2026-09-01T00:00:00Z [decision] worker_spawned task=fskh0001\n' > "${WJOURNAL}"
WACTIVE="$(PROJECT_ROOT="${WROOT}" LEADV2_STATE_ROOT="${WSTATE}" LEADV2_STATE_BASE="${WSTATE}" bash "${STATE_PATH}" active.yaml 2>/dev/null || true)"
[[ -n "${WACTIVE}" ]] || WACTIVE="${WROOT}/docs/leadv2/active.yaml"

WLOG="${SANDBOX}/watcher.err"
LEADV2_STATE_ROOT="${WSTATE}" LEADV2_STATE_BASE="${WSTATE}" LEADV2_PROJECT_ROOT="${WROOT}" \
  LEADV2_LANE_PULSE_BIN="/bin/true" \
  bash "${WATCHER}" --sig fskh0001 --root "${WROOT}" --interval 1 --timeout 120 \
  >"${WLOG}" 2>&1 &
WATCH_PID=$!
# Wait for the watcher's own pidfile, then pin THAT pid as a frozen watcher.
# (PID_DIR nests: state-path returns <root>/lane-pulse-watch, the watcher adds
# its own lane-pulse-watch/ — so find, never glob a guessed depth.)
WPID=""
for _ in $(seq 1 40); do
  WPID="$(find "${WSTATE}" -name 'fskh0001.pid' -maxdepth 4 2>/dev/null | head -1 | xargs cat 2>/dev/null | tr -d ' ' || true)"
  [[ "${WPID}" =~ ^[0-9]+$ ]] && break
  sleep 0.25
done
if [[ "${WPID}" =~ ^[0-9]+$ ]] && kill -0 "${WPID}" 2>/dev/null; then
  python3 - "${WACTIVE}" "${WPID}" <<'PY'
import sys, yaml
path, pid = sys.argv[1], int(sys.argv[2])
data = {"sessions": [{"task_id": "dispatch-fskh0001", "session_id": "t", "lead_session_id": "t",
                      "worktree": "w", "phase": "build", "pid": pid, "pid_birth": "",
                      "pid_role": "watcher", "worker_pid": pid, "worker_pid_birth": "",
                      "worker_pid_role": "watcher", "started_at": "2026-08-30T00:00:00Z",
                      "updated_at": "2026-08-30T00:00:00Z", "dead_at": None, "lane_events": []}]}
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
PY
  # ORPHAN_MAX=2s, frozen since 2026-08-30 -> must exit within ~2 intervals.
  WATCH_DEAD=0
  for _ in $(seq 1 40); do
    kill -0 "${WATCH_PID}" 2>/dev/null || { WATCH_DEAD=1; break; }
    sleep 0.25
  done
  if [[ "${WATCH_DEAD}" == "1" ]]; then
    ok "acc8: orphaned watcher self-terminated on frozen watcher-only row (pid=${WPID})"
  else
    bad "acc8: watcher still alive 10s after row froze (pid=${WPID})"
    kill "${WATCH_PID}" 2>/dev/null || true
  fi
else
  bad "acc8: watcher never wrote its pidfile; fixture could not pin it (stderr: $(tail -c 300 "${WLOG}" 2>/dev/null || true))"
fi
WATCH_PID=""

# ── Acceptance 10: distinct skip cause when a stale watcher was reaped ───────
# Drives the REAL _deliver_plan_into_lane body, extracted from the shipped
# dispatch-code (never a copy), with stub emit/_dl_note sinks.
DC_EXT="${SANDBOX}/dc-extract.sh"
{
  printf 'emit() { printf "%%s\\n" "$*" >> "%s/emit.log"; }\n' "${SANDBOX}"
  printf '_dl_note() { printf "%%s:%%s:%%s\\n" "$1" "$2" "$3" >> "%s/dl.log"; }\n' "${SANDBOX}"
  printf 'LANE_LOCAL_PLAN_LINE=""; LANE_PLAN_DELIVERY_STATUS=""; WORK_ROOT="%s"; PROJECT_ROOT="%s"; STALE_WATCHER_REAPED=1\n' "${SANDBOX}/nowork" "${ROOT}"
  sed -n "/^_deliver_plan_into_lane() {/,/^}$/p" "${DISPATCH}"
  printf '_deliver_plan_into_lane "$@"\n'
} > "${DC_EXT}"
mkdir -p "${SANDBOX}/nowork"
# No docs/handoff/<task>/context.yaml at the source -> source_absent branch.
bash "${DC_EXT}" fskh0002 fskh0002 >/dev/null 2>&1
DL="$(cat "${SANDBOX}/dl.log" 2>/dev/null || true)"
if [[ "${DL}" == *"fskh0002:skipped:plan_source_absent_stale_watcher"* ]]; then
  ok "acc10: stale-watcher skip carries distinct cause (got: ${DL})"
elif [[ "${DL}" == *"fskh0002:skipped:plan_source_absent"* ]]; then
  bad "acc10: skip cause was BARE plan_source_absent with STALE_WATCHER_REAPED=1 (got: ${DL})"
else
  bad "acc10: no skip terminal recorded (dl.log: '${DL}'); extraction broken?"
fi
# Negative control: without the reap flag the bare cause must come back.
{
  printf 'emit() { printf "%%s\\n" "$*" >> "%s/emit.log"; }\n' "${SANDBOX}"
  printf '_dl_note() { printf "%%s:%%s:%%s\\n" "$1" "$2" "$3" >> "%s/dl.log"; }\n' "${SANDBOX}"
  printf 'LANE_LOCAL_PLAN_LINE=""; LANE_PLAN_DELIVERY_STATUS=""; WORK_ROOT="%s"; PROJECT_ROOT="%s"; STALE_WATCHER_REAPED=0\n' "${SANDBOX}/nowork" "${ROOT}"
  sed -n "/^_deliver_plan_into_lane() {/,/^}$/p" "${DISPATCH}"
  printf '_deliver_plan_into_lane "$@"\n'
} > "${DC_EXT}"
: > "${SANDBOX}/dl.log"
bash "${DC_EXT}" fskh0003 fskh0003 >/dev/null 2>&1
DL2="$(cat "${SANDBOX}/dl.log" 2>/dev/null || true)"
if [[ "${DL2}" == *"fskh0003:skipped:plan_source_absent"* && "${DL2}" != *"stale_watcher"* ]]; then
  ok "acc10 control: genuine skip keeps the bare cause (${DL2})"
else
  bad "acc10 control: expected bare plan_source_absent, got '${DL2}'"
fi

printf '\n[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
