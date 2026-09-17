#!/usr/bin/env bash
# test-fleet-runtime-guards.sh — FLEET-RUNTIME-UNATTENDED-01
# run-all-triggers: leadv2-fleet-unit leadv2-fleet-guard leadv2-fleet-state leadv2-fleet-runner leadv2-fleet-lib
#
# Pins the three controls the mission requires. Runs on a machine WITHOUT
# systemd (this repo's CI and the lead's macOS): systemctl/loginctl are
# never invoked by these cases (install is exercised in --dry-run mode, or
# via a stub on PATH for the unit-content cases) — the unit LAYER is
# stubbed, never skipped, per the mission's explicit instruction. Claim 1's
# "systemd restarts a killed process" is emulated by a minimal test-local
# mini-systemd harness that reads the REAL generated unit's Restart= field
# and drives a real kill/relaunch cycle against the REAL ExecStart command
# — this is the honest boundary of what our code owns (the unit's declared
# config) versus what only a real systemd instance can prove (that PID1
# honors it); the report names this boundary explicitly.
#
# DECLARED NEGATIVE CONTROL for Claim 2 (stop flag), applied by
# leadv2-mutation-control.sh to the marked line inside
# leadv2-fleet-runner.sh's main loop:
#   bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
#     plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh \
#     plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh \
#     's|if fleet_stop_flag_present; then # c2-mut: stop-flag gate|if false; then # c2-mut: stop-flag gate|' \
#     plugins/leadv2/scripts/tests
# Must turn the "stop flag: only one lane runs, status stopped" case red
# (a second lane starts after the flag is touched).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "${SCRIPT_DIR}/../fleet" && pwd)"
UNIT_SH="${FLEET_DIR}/leadv2-fleet-unit.sh"
GUARD_SH="${FLEET_DIR}/leadv2-fleet-guard.sh"
STATE_SH="${FLEET_DIR}/leadv2-fleet-state.sh"
RUNNER_SH="${FLEET_DIR}/leadv2-fleet-runner.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fleet-guard-suite.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# Group A: unit-content statics (no systemctl/loginctl invocation at all —
# print-unit never shells out).
# ---------------------------------------------------------------------------
printf 'group A: generated unit content\n'

REPO_A="${TMP_ROOT}/repo-a"
mkdir -p "${REPO_A}"

unit_always="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart always)"
if printf '%s\n' "${unit_always}" | grep -q '^Restart=always$'; then
  pass "print-unit --restart always emits Restart=always"
else
  fail "print-unit --restart always missing Restart=always: ${unit_always}"
fi

unit_no="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart no)"
if printf '%s\n' "${unit_no}" | grep -q '^Restart=no$'; then
  pass "print-unit --restart no emits Restart=no (Claim 1 negative control)"
else
  fail "print-unit --restart no missing Restart=no: ${unit_no}"
fi

if printf '%s\n' "${unit_always}" | grep -q "ExecStart=${FLEET_DIR}/leadv2-fleet-runner.sh --repo ${REPO_A} --name a1 --cap 2"; then
  pass "ExecStart points at leadv2-fleet-runner.sh with repo/name/cap"
else
  fail "ExecStart missing or malformed"
fi

if printf '%s\n' "${unit_always}" | grep -q '^leadv2-fleet-a1-guard.timer$' \
   || printf '%s\n' "${unit_always}" | grep -q 'leadv2-fleet-a1-guard.timer'; then
  pass "guard timer unit is generated alongside the service"
else
  fail "guard timer unit missing from print-unit output"
fi

# dry-run install: must not touch the real systemctl/loginctl binaries at all.
FAKE_BAD_BIN="${TMP_ROOT}/bad-systemctl-should-never-run"
cat > "${FAKE_BAD_BIN}" <<'EOF'
#!/usr/bin/env bash
echo "SYSTEMCTL WAS INVOKED DURING DRY-RUN" >> "${DRYRUN_CANARY}"
EOF
chmod +x "${FAKE_BAD_BIN}"
export DRYRUN_CANARY="${TMP_ROOT}/dryrun-canary.log"
: > "${DRYRUN_CANARY}"
LEADV2_FLEET_SYSTEMCTL_BIN="${FAKE_BAD_BIN}" LEADV2_FLEET_LOGINCTL_BIN="${FAKE_BAD_BIN}" \
  LEADV2_FLEET_UNIT_DIR="${TMP_ROOT}/units-dryrun" \
  bash "${UNIT_SH}" install --repo "${REPO_A}" --name a1 --cap 2 --dry-run >/dev/null
if [[ ! -s "${DRYRUN_CANARY}" ]]; then
  pass "--dry-run install never invokes systemctl/loginctl"
else
  fail "--dry-run install invoked a binary it must not touch"
fi

# ---------------------------------------------------------------------------
# Group B: Claim 1 — the unit restarts a killed session (mini-systemd stub,
# driven by the REAL generated unit content).
# ---------------------------------------------------------------------------
printf 'group B: Claim 1 — restart-on-kill via generated Restart= field\n'

mini_systemd_once() { # <unit-content-file> -> prints RESTARTED / NOT_RESTARTED
  local unit="$1" execstart restart pid
  execstart="$(grep '^ExecStart=' "${unit}" | head -1 | cut -d= -f2-)"
  restart="$(grep '^Restart=' "${unit}" | head -1 | cut -d= -f2-)"
  eval "${execstart}" >/dev/null 2>&1 &
  pid=$!
  sleep 0.4
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "NOT_RESTARTED (process exited before kill — setup bug)"
    return
  fi
  kill -9 "${pid}" 2>/dev/null
  wait "${pid}" 2>/dev/null
  if [[ "${restart}" == "always" ]]; then
    eval "${execstart}" >/dev/null 2>&1 &
    pid=$!
    sleep 0.4
    if kill -0 "${pid}" 2>/dev/null; then
      echo "RESTARTED"
      kill -9 "${pid}" 2>/dev/null
      wait "${pid}" 2>/dev/null
    else
      echo "NOT_RESTARTED"
    fi
  else
    echo "NOT_RESTARTED"
  fi
}

REPO_B="${TMP_ROOT}/repo-b"
mkdir -p "${REPO_B}"
export LEADV2_FLEET_STATE_ROOT="${TMP_ROOT}/state-b"
export LEADV2_FLEET_ZAI_ENV="${TMP_ROOT}/zai-b.env"
printf 'ZAI_AUTH_TOKEN=stub-token-not-real\n' > "${LEADV2_FLEET_ZAI_ENV}"
export LEADV2_FLEET_ARMS="glm"
export LEADV2_FLEET_LANE_CMD="sleep 30"
export LEADV2_FLEET_STATE_BIN="${STATE_SH}"

unit_file_always="${TMP_ROOT}/unit-b-always.txt"
bash "${UNIT_SH}" print-unit --repo "${REPO_B}" --name b1 --cap 1 --restart always \
  | sed -n '2,10p' > "${unit_file_always}"
result_always="$(mini_systemd_once "${unit_file_always}")"
if [[ "${result_always}" == "RESTARTED" ]]; then
  pass "Restart=always: killed runner process comes back (mini-systemd: ${result_always})"
else
  fail "Restart=always: expected RESTARTED, got ${result_always}"
fi

unit_file_no="${TMP_ROOT}/unit-b-no.txt"
bash "${UNIT_SH}" print-unit --repo "${REPO_B}" --name b1 --cap 1 --restart no \
  | sed -n '2,10p' > "${unit_file_no}"
result_no="$(mini_systemd_once "${unit_file_no}")"
if [[ "${result_no}" == "NOT_RESTARTED" ]]; then
  pass "Claim 1 negative control — Restart=no: killed process stays dead (mini-systemd: ${result_no})"
else
  fail "Claim 1 negative control failed: expected NOT_RESTARTED, got ${result_no}"
fi

# ---------------------------------------------------------------------------
# Group C: Claim 2 — the stop flag stops BETWEEN lanes, not inside one.
# ---------------------------------------------------------------------------
printf 'group C: Claim 2 — stop flag between lanes\n'

REPO_C="${TMP_ROOT}/repo-c"
mkdir -p "${REPO_C}"
STATE_ROOT_C="${TMP_ROOT}/state-c"
STOP_FLAG_C="${TMP_ROOT}/FLEET-STOP-c"
LANE_LOG_C="${TMP_ROOT}/lane-log-c.txt"
: > "${LANE_LOG_C}"

cat > "${TMP_ROOT}/fake-lane-c.sh" <<EOF
#!/usr/bin/env bash
echo "lane-start \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LANE_LOG_C}"
sleep 1
echo "lane-end \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LANE_LOG_C}"
exit 0
EOF
chmod +x "${TMP_ROOT}/fake-lane-c.sh"

run_claim2() { # <expect-only-one-lane: 0|1> -> prints PASS/FAIL detail via echo
  local expect_gate_active="$1" lanes_started
  rm -f "${STOP_FLAG_C}"
  : > "${LANE_LOG_C}"
  rm -rf "${STATE_ROOT_C}"; mkdir -p "${STATE_ROOT_C}"
  (
    export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_C}"
    export LEADV2_FLEET_STOP_FLAG="${STOP_FLAG_C}"
    export LEADV2_FLEET_ZAI_ENV="${LEADV2_FLEET_ZAI_ENV}"
    export LEADV2_FLEET_ARMS="glm"
    export LEADV2_FLEET_LANE_CMD="${TMP_ROOT}/fake-lane-c.sh"
    export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
    bash "${RUNNER_SH}" --repo "${REPO_C}" --name c1 >/dev/null 2>&1 &
    echo $! > "${TMP_ROOT}/runner-c.pid"
  )
  # touch the flag mid-first-lane (lane sleeps 1s; flag lands at 0.3s)
  sleep 0.3
  touch "${STOP_FLAG_C}"
  # wait for the runner to exit on its own (it must — no kill from us)
  local runner_pid tries=0
  runner_pid="$(cat "${TMP_ROOT}/runner-c.pid")"
  while kill -0 "${runner_pid}" 2>/dev/null; do
    tries=$((tries + 1))
    [[ "${tries}" -gt 50 ]] && break   # 5s ceiling
    sleep 0.1
  done
  lanes_started="$(grep -c '^lane-start' "${LANE_LOG_C}" 2>/dev/null || echo 0)"
  local status_line
  status_line="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_C}" bash "${STATE_SH}" read --name c1 | head -1)"
  echo "lanes_started=${lanes_started} status_line=${status_line}"
}

out_positive="$(run_claim2 1)"
lanes_positive="$(printf '%s\n' "${out_positive}" | grep -o 'lanes_started=[0-9]*' | cut -d= -f2)"
status_positive="$(printf '%s\n' "${out_positive}" | grep -o 'status_line=.*')"
printf '%s\n' "${out_positive}"
if [[ "${lanes_positive}" == "1" ]] && printf '%s\n' "${status_positive}" | grep -q 'stopped (reason: stop_flag)'; then
  pass "stop flag: current lane finished (exactly 1 lane ran) and no new lane started; status=stopped/stop_flag"
else
  fail "stop flag positive case: expected exactly 1 lane + status stopped/stop_flag, got: ${out_positive}"
fi

# ---------------------------------------------------------------------------
# Group D: Claim 3 — the disk floor refuses a new lane start.
# ---------------------------------------------------------------------------
printf 'group D: Claim 3 — disk floor refusal\n'

REPO_D="${TMP_ROOT}/repo-d"
mkdir -p "${REPO_D}"
STATE_ROOT_D="${TMP_ROOT}/state-d"

# Positive: an impossibly high floor (bigger than any real filesystem) must refuse.
rm -rf "${STATE_ROOT_D}"; mkdir -p "${STATE_ROOT_D}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_D}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-d"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${LEADV2_FLEET_ZAI_ENV}"
  export LEADV2_FLEET_LANE_CMD="true"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  bash "${RUNNER_SH}" --repo "${REPO_D}" --name d1 --floor-kb 999999999999 >/dev/null 2>&1
)
status_d_high="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_D}" bash "${STATE_SH}" read --name d1 | head -1)"
if printf '%s\n' "${status_d_high}" | grep -q 'stopped (reason: disk_floor'; then
  pass "disk floor (impossible floor-kb) refuses with named reason: ${status_d_high}"
else
  fail "disk floor positive case failed: ${status_d_high}"
fi

# Negative control (mission's own suggestion): floor-kb=0 must start (no refusal).
rm -rf "${STATE_ROOT_D}"; mkdir -p "${STATE_ROOT_D}"
LANE_RAN_D="${TMP_ROOT}/lane-ran-d"
rm -f "${LANE_RAN_D}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_D}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-d2"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${LEADV2_FLEET_ZAI_ENV}"
  export LEADV2_FLEET_LANE_CMD="touch ${LANE_RAN_D}"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  export LEADV2_FLEET_MAX_ITERATIONS=1
  bash "${RUNNER_SH}" --repo "${REPO_D}" --name d2 --floor-kb 0 >/dev/null 2>&1
)
if [[ -f "${LANE_RAN_D}" ]]; then
  pass "Claim 3 negative control — floor-kb=0: a lane starts (disk floor does not block)"
else
  fail "Claim 3 negative control failed: floor-kb=0 should have let a lane start"
fi

printf '\n%s of %s passed (fleet guard suite, macOS Darwin, no systemd — unit layer stubbed per mission)\n' "${PASS}" "$((PASS + FAIL))"
[[ "${FAIL}" -eq 0 ]]
