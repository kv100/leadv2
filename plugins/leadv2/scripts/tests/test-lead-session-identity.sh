#!/usr/bin/env bash
# D6-REGISTRY-LANE-OWNERSHIP-01 — lead_session_id stops lying.
#
# Before this lane, every real lead process fell through
# LEADV2_LEAD_SESSION_ID / LEADV2_PARENT_SESSION_ID / CLAUDE_SESSION_ID (none
# ever set in prod) to a single shared "direct" bucket, so
# lead_session_lane_cap accounted for every concurrent lead process as one.
#
# leadv2_lead_session_id() (lib/leadv2-lead-identity.sh) replaces the third
# fallback link with a resolver built on the already-proven
# _lv2_durable_pid()/_lv2_pid_birth() pair from leadv2-active-registry.sh.
#
# bash 3.2. No real spawns beyond `bash -c` subshells for distinct PIDs.
set -uo pipefail

# ${BASH_SOURCE[0]:-$0}: green under bash AND zsh (founder shell), failing on
# disagreement -- zsh has no BASH_SOURCE, and under `set -u` the bare form
# would abort the suite before any case ran.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
IDENTITY_SH="${PLUGIN_SCRIPTS}/lib/leadv2-lead-identity.sh"
LANE_STATE_SH="${PLUGIN_SCRIPTS}/lib/leadv2-lane-state.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

SANDBOX="$(mktemp -d /tmp/leadv2-lsi-XXXXXX)"
trap 'rm -rf "${SANDBOX}"' EXIT

TARGET="${SANDBOX}/target"
mkdir -p "${TARGET}"
( cd "${TARGET}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )

export LEADV2_STATE_ROOT="${SANDBOX}/state"
export LEADV2_STATE_BASE="${SANDBOX}/state"
mkdir -p "${LEADV2_STATE_ROOT}"
export PROJECT_ROOT="${TARGET}"
ACTIVE="${LEADV2_STATE_ROOT}/active.yaml"
printf 'sessions: []\n' > "${ACTIVE}"

# _lv2_durable_pid walks the REAL ancestry looking for a `claude`-comm
# process. Inside this very test harness that walk finds the actual Claude
# Code CLI process as a shared ancestor of every subshell we spawn, which
# would collapse two independent lead-process simulations onto one id for a
# reason that has nothing to do with the resolver under test (a sibling
# suite, test-lane-registry-outlives-dispatcher.sh, notes the same hazard:
# "an inherited durable parent may be alive forever"). Stub `ps` so the
# comm-walk never matches "claude" and the resolver falls through to its
# documented PPID fallback -- the path that is actually reachable in
# production, since prod lead processes are the durable `claude` process
# itself, not a descendant of one.
FAKEBIN="${SANDBOX}/fakebin"
mkdir -p "${FAKEBIN}"
cat > "${FAKEBIN}/ps" <<'PSSTUB'
#!/usr/bin/env bash
# Fully hermetic: host ps is unavailable inside this test sandbox.  The
# synthetic lstart includes pid, so separate simulated leads have distinct
# birth hashes while repeat observations of one pid remain stable.
field=""; pid=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    comm=|ppid=|lstart=) field="$1" ;;
    -p) shift; pid="${1:-}" ;;
  esac
  shift
done
case "${field}" in
  comm=) echo "bash" ;;
  ppid=) echo "1" ;;
  lstart=) printf 'Tue Jan 02 03:04:05 2024 %s\n' "${pid}" ;;
esac
PSSTUB
chmod +x "${FAKEBIN}/ps"
export PATH="${FAKEBIN}:${PATH}"

# ── 1. Distinct owners: two real processes resolve to different ids ────────
# Each resolver runs inside its own background job shell. The two job shells
# are two real forks (distinct pids BY CONSTRUCTION), so the resolver's
# $PPID fallback -- the branch actually reachable in production, where the
# lead process is the durable claude process itself, not a descendant of one
# -- lands on a different pid per invocation in bash AND zsh, regardless of
# either interpreter's $()/exec fork-optimization. The earlier
# ': noop; bash -c' nesting depended on that fork-exec luck: green under
# bash, both invocations collapsed onto one pid under zsh -- exactly the
# cross-shell disagreement class this suite is required to fail on, so the
# construction was replaced rather than the zsh result tolerated.
run_id_job() { # $1 = output file
  (
    OUT="$(bash -c "source '${IDENTITY_SH}'; leadv2_lead_session_id" 2>/dev/null)" \
      && printf '%s' "${OUT}" > "$1"
  ) &
}
run_id_job "${SANDBOX}/id_a"; JOB_A=$!
run_id_job "${SANDBOX}/id_b"; JOB_B=$!
wait "${JOB_A}" "${JOB_B}"
ID_A="$(cat "${SANDBOX}/id_a" 2>/dev/null)"
ID_B="$(cat "${SANDBOX}/id_b" 2>/dev/null)"
if [[ -n "${ID_A}" && -n "${ID_B}" && "${ID_A}" != "${ID_B}" ]]; then
  ok "distinct owners: ${ID_A} != ${ID_B}"
else
  bad "distinct owners: got A='${ID_A}' B='${ID_B}'"
fi

# ── 2. Cap proves the defect dead: LEADV2_LANE_CAP=1 ────────────────────────
# Registered in-process (not a subshell) so the recorded pid ($$, this test
# script) stays alive for the whole cap check -- a subshell's pid dies the
# instant it returns, which would make lane1's row look dead and silently
# pass the cap test for the wrong reason.
printf 'sessions: []\n' > "${ACTIVE}"
export LEADV2_LANE_CAP=1
source "${LANE_STATE_SH}"

lane_register lane1 "${ID_A}" "${TARGET}" spawning "$$" >/dev/null 2>&1
RC1=$?
lane_register lane2 "${ID_A}" "${TARGET}" spawning "$$" >/dev/null 2>&1
RC2=$?
lane_register lane3 "${ID_B}" "${TARGET}" spawning "$$" >/dev/null 2>&1
RC3=$?

if [[ "${RC1}" == "0" && "${RC2}" == "3" && "${RC3}" == "0" ]]; then
  ok "cap proves defect dead: lane1(same session)=0 lane2(same session)=${RC2}(refused) lane3(other session)=0"
else
  bad "cap proves defect dead: got lane1=${RC1} lane2=${RC2}(want 3) lane3=${RC3}(want 0)"
fi
unset LEADV2_LANE_CAP

# ── 3. lane_lead_alive corroboration: alive / birth-mismatch / dead ─────────
# Two-sided on purpose: an assertion of merely "rc != 0" cannot tell a dead
# owner from a broken wrapper (an arg-dropped mutation ALSO crashes rc!=0 and
# would survive). Three rows against this script's own live pid ($$):
#   3a correct birth      -> rc=0 (lead_pid/lead_pid_birth args 6/7 flowed
#                            through lane_register and corroborate)
#   3b wrong recorded birth -> rc=1 (corroboration must fail on mismatch)
#   3c owner process exited -> rc!=0 (the original orphan case)
printf 'sessions: []\n' > "${ACTIVE}"
LIVE_BIRTH="$(ps -o lstart= -p "$$" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
lane_register live-ok-task lead-live-ok "${TARGET}" spawning "$$" "$$" "${LIVE_BIRTH}" >/dev/null 2>&1
bash -c "source '${LANE_STATE_SH}'; lane_lead_alive lead-live-ok" >/dev/null 2>&1
ALIVE_OK_RC=$?
if [[ "${ALIVE_OK_RC}" == "0" ]]; then
  ok "lead alive corroboration: live owner + matching birth -> rc=0"
else
  bad "lead alive corroboration: live owner + matching birth got rc=${ALIVE_OK_RC} (want 0)"
fi

lane_register live-bad-birth-task lead-live-badbirthday "${TARGET}" spawning "$$" "$$" "Wed Dec 25 00:00:00 2020" >/dev/null 2>&1
bash -c "source '${LANE_STATE_SH}'; lane_lead_alive lead-live-badbirthday" >/dev/null 2>&1
ALIVE_BAD_RC=$?
if [[ "${ALIVE_BAD_RC}" == "1" ]]; then
  ok "lead alive corroboration: recorded birth mismatch -> rc=1 (not alive)"
else
  bad "lead alive corroboration: recorded birth mismatch got rc=${ALIVE_BAD_RC} (want 1)"
fi

CHILD_PID=""
( sleep 30 ) &
CHILD_PID=$!
CHILD_BIRTH="$(ps -o lstart= -p "${CHILD_PID}" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
bash -c "source '${LANE_STATE_SH}'; lane_register orphan-task orphan-lead '${TARGET}' spawning \$\$ '${CHILD_PID}' '${CHILD_BIRTH}'" >/dev/null 2>&1
kill "${CHILD_PID}" 2>/dev/null
wait "${CHILD_PID}" 2>/dev/null
# poll briefly for the OS to reap the pid
for _ in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "${CHILD_PID}" 2>/dev/null || break
  sleep 0.2
done
bash -c "source '${LANE_STATE_SH}'; lane_lead_alive orphan-lead" >/dev/null 2>&1
LEAD_ALIVE_RC=$?
if [[ "${LEAD_ALIVE_RC}" != "0" ]]; then
  ok "lead alive corroboration: dead owner reports not-alive (rc=${LEAD_ALIVE_RC})"
else
  bad "lead alive corroboration: lane_lead_alive still reports alive after owning process exited"
fi

# ── 4. Legacy rows resolve: a fixture row with lead_session_id: direct ─────
cat > "${ACTIVE}" <<'YAML'
sessions:
- task_id: legacy-task-1
  lead_session_id: direct
  session_id: direct
  worktree: /tmp/legacy
  phase: build
  pid: 999999
  pid_start_time: unknown
  started_at: '2026-01-01T00:00:00Z'
  updated_at: '2026-01-01T00:00:00Z'
  dead_at: null
  recovered: false
  lane_events: []
YAML
LEGACY_COUNT="$(bash -c "source '${LANE_STATE_SH}'; lane_count_live direct" 2>/dev/null)"
if [[ "${LEGACY_COUNT}" =~ ^[0-9]+$ ]]; then
  ok "legacy rows resolve: lane_count_live direct returned '${LEGACY_COUNT}' without exception"
else
  bad "legacy rows resolve: lane_count_live direct raised or returned non-numeric '${LEGACY_COUNT}'"
fi

printf '\n[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
