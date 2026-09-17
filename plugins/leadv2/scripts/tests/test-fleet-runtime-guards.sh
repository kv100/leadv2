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
# leadv2-fleet-runner.sh's main loop. Round-4 removed the `c2-mut` comment
# marker from the shipped script (a trailing comment on a code line is
# harmless in bash, but the equivalent markers in leadv2-fleet-unit.sh sat
# on a systemd directive line and made systemd ignore it — see edit 3 in
# the round-4 mission; all three markers were removed together so none of
# them could regrow). The mutation now targets the bare line text:
#   bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
#     plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh \
#     plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh \
#     's|if fleet_stop_flag_present; then|if false; then|' \
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

# Suite-wide GLM key fixture (read-only fact, not a mutable env leak): every
# group that needs the glm arm usable points LEADV2_FLEET_ZAI_ENV at this
# same file via its own scoped export/prefix-assignment (M5) rather than a
# top-level `export`.
ZAI_ENV_SUITE="${TMP_ROOT}/zai-suite.env"
printf 'ZAI_AUTH_TOKEN=stub-token-not-real\n' > "${ZAI_ENV_SUITE}"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# Group 0: mutation-target assertions (round-2 fix C2). Each of the three
# claims' negative control mutates a specific marked line; if the marker
# rots (renamed, refactored away) the control silently stops proving
# anything and reads as a permanent green. Fail the whole suite loudly
# before that can happen.
# ---------------------------------------------------------------------------
printf 'group 0: mutation-target markers present\n'
if grep -q 'if fleet_stop_flag_present; then$' "${RUNNER_SH}"; then
  pass "Claim 2 mutation target present in leadv2-fleet-runner.sh"
else
  fail "Claim 2 mutation target MISSING — control has rotted"
fi
if grep -q '^Restart=\${4}$' "${UNIT_SH}"; then
  pass "Claim 1 mutation target present in leadv2-fleet-unit.sh"
else
  fail "Claim 1 mutation target MISSING — control has rotted"
fi
if grep -q 'if \[\[ "\${free}" -lt "\${floor}" \]\]; then$' "${FLEET_DIR}/leadv2-fleet-lib.sh"; then
  pass "Claim 3 mutation target present in leadv2-fleet-lib.sh"
else
  fail "Claim 3 mutation target MISSING — control has rotted"
fi

# round-4 edit 3: the c1/c2/c3-mut comment markers themselves must never
# survive in the shipped fleet/ scripts — a trailing comment on the
# Restart= directive line in the generated unit made systemd ignore that
# directive entirely (the concrete defect edit 3 removes).
if ! grep -rn 'c[0-9]-mut' "${FLEET_DIR}"/*.sh >/dev/null 2>&1; then
  pass "no c*-mut marker survives anywhere under plugins/leadv2/scripts/fleet/"
else
  fail "c*-mut marker still present: $(grep -rn 'c[0-9]-mut' "${FLEET_DIR}"/*.sh)"
fi

# ---------------------------------------------------------------------------
# Group A: unit-content statics (no systemctl/loginctl invocation at all —
# print-unit never shells out).
# ---------------------------------------------------------------------------
printf 'group A: generated unit content\n'

REPO_A="${TMP_ROOT}/repo-a"
mkdir -p "${REPO_A}"

unit_always="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart always)"
if printf '%s\n' "${unit_always}" | grep -q '^Restart=always'; then
  pass "print-unit --restart always emits Restart=always"
else
  fail "print-unit --restart always missing Restart=always: ${unit_always}"
fi

unit_no="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart no)"
if printf '%s\n' "${unit_no}" | grep -q '^Restart=no'; then
  pass "print-unit --restart no emits Restart=no (Claim 1 negative control)"
else
  fail "print-unit --restart no missing Restart=no: ${unit_no}"
fi

if printf '%s\n' "${unit_always}" | grep -q "ExecStart=\"${FLEET_DIR}/leadv2-fleet-runner.sh\" --repo \"${REPO_A}\" --name \"a1\" --cap \"2\""; then
  pass "ExecStart points at leadv2-fleet-runner.sh with quoted repo/name/cap"
else
  fail "ExecStart missing or malformed: $(printf '%s\n' "${unit_always}" | grep ExecStart=)"
fi
if printf '%s\n' "${unit_always}" | grep -q '^Environment=LEADV2_FLEET_LANE_CMD='; then
  fail "print-unit without --lane-cmd must NOT emit an Environment= line"
else
  pass "no --lane-cmd given: no Environment=LEADV2_FLEET_LANE_CMD line emitted"
fi
unit_with_lane_cmd="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart always --lane-cmd 'echo hi')"
if printf '%s\n' "${unit_with_lane_cmd}" | grep -q '^Environment="LEADV2_FLEET_LANE_CMD=echo hi"$'; then
  pass "--lane-cmd renders a quoted Environment= assignment (H2 fix + round-4 edit 2)"
else
  fail "--lane-cmd did not render a quoted Environment= line: $(printf '%s\n' "${unit_with_lane_cmd}" | grep Environment=)"
fi

# round-4 edit 2: WorkingDirectory must NEVER be quoted — systemd takes the
# rest of the line literally for this directive, so quotes become part of
# the path value instead of being stripped, and a repo path containing a
# space needs the quoted form to survive unit-with-space repos too.
REPO_SPACE="${TMP_ROOT}/repo with space"
mkdir -p "${REPO_SPACE}"
unit_space="$(bash "${UNIT_SH}" print-unit --repo "${REPO_SPACE}" --name a1 --cap 2)"
if printf '%s\n' "${unit_space}" | grep -q "^WorkingDirectory=${REPO_SPACE}\$"; then
  pass "WorkingDirectory is unquoted (round-4 edit 2 — quotes there are invalid systemd syntax)"
else
  fail "WorkingDirectory malformed: $(printf '%s\n' "${unit_space}" | grep WorkingDirectory=)"
fi

# round-4 edit 1: default restart policy is on-failure, paired with
# SuccessExitStatus=<FLEET_STOP_EXIT_CODE> so a controlled stop is never
# respawned (Restart=always respawns after ANY exit, controlled or not).
FLEET_STOP_EXIT_CODE_A="$(grep -m1 '^FLEET_STOP_EXIT_CODE=' "${FLEET_DIR}/leadv2-fleet-lib.sh" | cut -d= -f2)"
unit_default="$(bash "${UNIT_SH}" print-unit --repo "${REPO_A}" --name a1 --cap 2)"
if printf '%s\n' "${unit_default}" | grep -q '^Restart=on-failure$'; then
  pass "print-unit default restart policy is on-failure (round-4 edit 1)"
else
  fail "default restart policy is not on-failure: $(printf '%s\n' "${unit_default}" | grep Restart=)"
fi
if printf '%s\n' "${unit_default}" | grep -q "^SuccessExitStatus=${FLEET_STOP_EXIT_CODE_A}\$"; then
  pass "print-unit emits SuccessExitStatus=${FLEET_STOP_EXIT_CODE_A} matching leadv2-fleet-lib.sh's FLEET_STOP_EXIT_CODE"
else
  fail "SuccessExitStatus missing/mismatched: $(printf '%s\n' "${unit_default}" | grep SuccessExitStatus=)"
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
  # Restart= carries a trailing `# c1-mut: ...` mutation-target comment in
  # the real rendered unit (Group 0) — strip it so the exact-match check
  # below compares against just the value, not "always # c1-mut: ...".
  restart="$(grep '^Restart=' "${unit}" | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//')"
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

# M5 fix: these vars are needed only while mini_systemd_once's eval'd
# ExecStart (which invokes leadv2-fleet-runner.sh) runs, so they're set via
# prefix-assignment on the call rather than top-level `export` — a bare
# `export` here would leak into Group C/D's environment for the rest of the
# suite (shellcheck SC2030/2031 on the round-1 shape).
unit_file_always="${TMP_ROOT}/unit-b-always.txt"
# L2 fix: mini_systemd_once already greps '^ExecStart=' / '^Restart=' with
# `head -1` out of the FULL print-unit output, so a fixed-line-number slice
# here is not just redundant but fragile — the H2 fix's optional
# Environment= line shifts every line number below it by one whenever
# --lane-cmd is empty (the round-1 slice silently sliced past ExecStart=
# entirely once that line was added). No slice needed: the runner service's
# ExecStart/Restart always sort first regardless of exact line position.
bash "${UNIT_SH}" print-unit --repo "${REPO_B}" --name b1 --cap 1 --restart always \
  > "${unit_file_always}"
result_always="$(LEADV2_FLEET_STATE_ROOT="${TMP_ROOT}/state-b" \
  LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}" LEADV2_FLEET_ARMS="glm" \
  LEADV2_FLEET_LANE_CMD="sleep 30" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  mini_systemd_once "${unit_file_always}")"
if [[ "${result_always}" == "RESTARTED" ]]; then
  pass "Restart=always: killed runner process comes back (mini-systemd: ${result_always})"
else
  fail "Restart=always: expected RESTARTED, got ${result_always}"
fi

unit_file_no="${TMP_ROOT}/unit-b-no.txt"
bash "${UNIT_SH}" print-unit --repo "${REPO_B}" --name b1 --cap 1 --restart no \
  > "${unit_file_no}"
result_no="$(LEADV2_FLEET_STATE_ROOT="${TMP_ROOT}/state-b" \
  LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}" LEADV2_FLEET_ARMS="glm" \
  LEADV2_FLEET_LANE_CMD="sleep 30" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  mini_systemd_once "${unit_file_no}")"
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
    export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
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
  lanes_started="$(grep -c '^lane-start' "${LANE_LOG_C}" 2>/dev/null)"
  lanes_started="${lanes_started:-0}"
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
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
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
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
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

# ---------------------------------------------------------------------------
# Group E: state contract — read is exactly 5 lines, unknown-field rejection,
# lock-steal via a provably dead pid (round-2 fixes M3/M7, C1(e) requirement).
# ---------------------------------------------------------------------------
printf 'group E: state file contract\n'

STATE_ROOT_E="${TMP_ROOT}/state-e"
rm -rf "${STATE_ROOT_E}"; mkdir -p "${STATE_ROOT_E}"
LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_E}" bash "${STATE_SH}" init --name e1 >/dev/null
read_lines_e="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_E}" bash "${STATE_SH}" read --name e1 | wc -l | tr -d ' ')"
if [[ "${read_lines_e}" == "5" ]]; then
  pass "state read --name prints exactly 5 lines (founder-facing contract)"
else
  fail "state read printed ${read_lines_e} lines, expected exactly 5"
fi

LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_E}" bash "${STATE_SH}" set-field --name e1 --field bogus_field --value 1 >/dev/null 2>&1
rc_bad_field=$?
if [[ "${rc_bad_field}" -eq 2 ]]; then
  pass "set-field on an unknown field rejects with rc=2"
else
  fail "set-field on an unknown field returned rc=${rc_bad_field}, expected 2"
fi
LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_E}" bash "${STATE_SH}" inc-field --name e1 --field bogus_field >/dev/null 2>&1
rc_bad_inc=$?
if [[ "${rc_bad_inc}" -eq 2 ]]; then
  pass "inc-field on an unknown field rejects with rc=2"
else
  fail "inc-field on an unknown field returned rc=${rc_bad_inc}, expected 2"
fi

# Lock-steal: a lock dir whose recorded pid is provably dead must be broken,
# not waited out to the 30s age fallback.
LOCK_E="${STATE_ROOT_E}/e1.state.lock"
rm -rf "${LOCK_E}"; mkdir -p "${LOCK_E}"
DEAD_PID=99999
while kill -0 "${DEAD_PID}" 2>/dev/null; do DEAD_PID=$((DEAD_PID + 1)); done
echo "${DEAD_PID}" > "${LOCK_E}/pid"
start_e=$(fleet_now_epoch 2>/dev/null || date +%s)
LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_E}" bash "${STATE_SH}" set-field --name e1 --field lanes_in_flight --value 3 >/dev/null 2>&1
rc_steal=$?
end_e=$(date +%s)
elapsed_e=$((end_e - start_e))
if [[ "${rc_steal}" -eq 0 && "${elapsed_e}" -lt 25 ]]; then
  pass "lock-steal: dead-pid lock broken quickly (elapsed=${elapsed_e}s), not the 30s age fallback"
else
  fail "lock-steal failed: rc=${rc_steal} elapsed=${elapsed_e}s"
fi

# ---------------------------------------------------------------------------
# Group F: runner self-stops — no_landing_streak, no_arm, quota_window,
# degrade-to-glm (round-2 fix M1/M2's reason breakdown; C1(a)-(c)).
# ---------------------------------------------------------------------------
printf 'group F: runner self-stop reasons and degrade\n'

REPO_F="${TMP_ROOT}/repo-f"
mkdir -p "${REPO_F}"

# (a) no_landing_streak: a lane cmd that always fails, max-streak 2.
STATE_ROOT_F1="${TMP_ROOT}/state-f1"
rm -rf "${STATE_ROOT_F1}"; mkdir -p "${STATE_ROOT_F1}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F1}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-f1"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
  export LEADV2_FLEET_LANE_CMD="false"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  bash "${RUNNER_SH}" --repo "${REPO_F}" --name f1 --max-streak 2 >/dev/null 2>&1
)
status_f1="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F1}" bash "${STATE_SH}" read --name f1 | head -1)"
if printf '%s\n' "${status_f1}" | grep -q 'stopped (reason: no_landing_streak: 2 '; then
  pass "no_landing_streak: stops after max-streak consecutive non-landing lanes: ${status_f1}"
else
  fail "no_landing_streak case failed: ${status_f1}"
fi

# (b) no_arm: only glm configured, no usable glm key.
STATE_ROOT_F2="${TMP_ROOT}/state-f2"
rm -rf "${STATE_ROOT_F2}"; mkdir -p "${STATE_ROOT_F2}"
EMPTY_ZAI_ENV="${TMP_ROOT}/zai-empty.env"
: > "${EMPTY_ZAI_ENV}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F2}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-f2"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${EMPTY_ZAI_ENV}"
  export LEADV2_FLEET_LANE_CMD="true"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  export LEADV2_CLAUDE_CREDENTIALS_FILE="${TMP_ROOT}/no-such-creds.json"
  bash "${RUNNER_SH}" --repo "${REPO_F}" --name f2 >/dev/null 2>&1
)
status_f2="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F2}" bash "${STATE_SH}" read --name f2 | head -1)"
if printf '%s\n' "${status_f2}" | grep -q 'stopped (reason: no_arm: glm=key_missing)'; then
  pass "no_arm: stops with per-arm cause, distinct from quota_window (M1 fix): ${status_f2}"
else
  fail "no_arm case failed: ${status_f2}"
fi

# (c) quota_window: claude configured alone, credential live but quota probe refuses.
STATE_ROOT_F3="${TMP_ROOT}/state-f3"
rm -rf "${STATE_ROOT_F3}"; mkdir -p "${STATE_ROOT_F3}"
CREDS_F3="${TMP_ROOT}/creds-f3.json"
future_ms=$(( ( $(date +%s) + 3600 ) * 1000 ))
printf '{"expiresAt": %s}\n' "${future_ms}" > "${CREDS_F3}"
QUOTA_REFUSE_BIN="${TMP_ROOT}/quota-refuse.sh"
cat > "${QUOTA_REFUSE_BIN}" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${QUOTA_REFUSE_BIN}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F3}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-f3"
  export LEADV2_FLEET_ARMS="claude"
  export LEADV2_CLAUDE_CREDENTIALS_FILE="${CREDS_F3}"
  export LEADV2_FLEET_QUOTA_STATUS_BIN="${QUOTA_REFUSE_BIN}"
  export LEADV2_FLEET_LANE_CMD="true"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  bash "${RUNNER_SH}" --repo "${REPO_F}" --name f3 >/dev/null 2>&1
)
status_f3="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F3}" bash "${STATE_SH}" read --name f3 | head -1)"
if printf '%s\n' "${status_f3}" | grep -q 'stopped (reason: quota_window: claude=quota_exhausted)'; then
  pass "quota_window: reserved for a live credential whose quota probe refuses (M1 fix): ${status_f3}"
else
  fail "quota_window case failed: ${status_f3}"
fi

# (d) degrade: claude unusable (no credentials), glm usable — lane runs on glm,
# status reports alive/degraded rather than a silent freeze.
STATE_ROOT_F4="${TMP_ROOT}/state-f4"
rm -rf "${STATE_ROOT_F4}"; mkdir -p "${STATE_ROOT_F4}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F4}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-f4"
  export LEADV2_FLEET_ARMS="claude glm"
  export LEADV2_CLAUDE_CREDENTIALS_FILE="${TMP_ROOT}/no-such-creds-f4.json"
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
  export LEADV2_FLEET_LANE_CMD="true"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  export LEADV2_FLEET_MAX_ITERATIONS=1
  bash "${RUNNER_SH}" --repo "${REPO_F}" --name f4 >/dev/null 2>&1
)
status_f4="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_F4}" bash "${STATE_SH}" read --name f4 | head -1)"
if printf '%s\n' "${status_f4}" | grep -q 'alive (degraded: glm)'; then
  pass "degrade: claude unusable, glm usable -> alive/degraded, never a silent freeze: ${status_f4}"
else
  fail "degrade case failed: ${status_f4}"
fi

# ---------------------------------------------------------------------------
# Group G: guard — reap (positive), reap_refused (negative/safety), stall
# detection + the `stalled` state field (round-2 fixes H4/M6; C1(d)).
# ---------------------------------------------------------------------------
printf 'group G: guard reap / reap_refused / stall\n'

REPO_G="${TMP_ROOT}/repo-g"
mkdir -p "${REPO_G}"
git -C "${REPO_G}" init -q
git -C "${REPO_G}" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init
WT_ROOT_G="${REPO_G}/.claude/worktrees"
mkdir -p "${WT_ROOT_G}"

# (positive) a worktree with a SIBLING .fleet-terminal marker must be
# reaped. The marker lives next to the worktree dir, never inside it
# (round-4 fix): guard's reaper is now non-forcing, and a non-forcing
# `git worktree remove` refuses on ANY untracked file in the tree — an
# in-tree marker would itself have permanently blocked every reap.
WT_TERMINAL="${WT_ROOT_G}/wt-terminal"
git -C "${REPO_G}" worktree add -q "${WT_TERMINAL}" -b wt-terminal-branch >/dev/null 2>&1
: > "${WT_TERMINAL%/}.fleet-terminal"
STATE_ROOT_G="${TMP_ROOT}/state-g"
rm -rf "${STATE_ROOT_G}"; mkdir -p "${STATE_ROOT_G}"
guard_out_g1="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_G}" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  bash "${GUARD_SH}" --repo "${REPO_G}" --name g1 2>&1)"
if [[ ! -d "${WT_TERMINAL}" ]] && printf '%s\n' "${guard_out_g1}" | grep -q 'reaped terminal worktree'; then
  pass "guard reap: a .fleet-terminal-marked worktree is removed"
else
  fail "guard reap positive case failed: dir_exists=$([[ -d "${WT_TERMINAL}" ]] && echo yes || echo no) output=${guard_out_g1}"
fi

# (negative/safety) a worktree that git refuses to remove must be LEFT IN
# PLACE, never rm -rf'd (H4) — simulated by removing the .git file inside
# the worktree so `git worktree remove` itself refuses/errors.
WT_REFUSED="${WT_ROOT_G}/wt-refused"
git -C "${REPO_G}" worktree add -q "${WT_REFUSED}" -b wt-refused-branch >/dev/null 2>&1
: > "${WT_REFUSED%/}.fleet-terminal"
rm -f "${WT_REFUSED}/.git"
echo "gitdir: /nonexistent/path/that/does/not/exist" > "${WT_REFUSED}/.git"
guard_out_g2="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_G}" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  bash "${GUARD_SH}" --repo "${REPO_G}" --name g2 2>&1)"
stall_log_g2="${STATE_ROOT_G}/g2.stalled.log"
if [[ -d "${WT_REFUSED}" ]] && grep -q 'reap_refused' "${stall_log_g2}" 2>/dev/null; then
  pass "guard reap_refused: a worktree git refuses to remove is left in place (H4 — no rm -rf fallback)"
else
  fail "guard reap_refused safety case failed: dir_exists=$([[ -d "${WT_REFUSED}" ]] && echo yes || echo no) log=$(cat "${stall_log_g2}" 2>/dev/null)"
fi
git -C "${REPO_G}" worktree remove --force "${WT_REFUSED}" >/dev/null 2>&1 || rm -rf "${REPO_G}/.git/worktrees/wt-refused" 2>/dev/null

# (stall) an old worktree past --stall-minutes must be logged and the
# `stalled` state field incremented.
WT_STALE="${WT_ROOT_G}/wt-stale"
git -C "${REPO_G}" worktree add -q "${WT_STALE}" -b wt-stale-branch >/dev/null 2>&1
old_epoch=$(( $(date +%s) - 7200 ))
old_stamp="$(date -u -r "${old_epoch}" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@${old_epoch}" +%Y%m%d%H%M.%S 2>/dev/null)"
touch -t "${old_stamp}" "${WT_STALE}" 2>/dev/null
STATE_ROOT_G3="${TMP_ROOT}/state-g3"
rm -rf "${STATE_ROOT_G3}"; mkdir -p "${STATE_ROOT_G3}"
guard_out_g3="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_G3}" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  bash "${GUARD_SH}" --repo "${REPO_G}" --name g3 --stall-minutes 30 2>&1)"
stalled_field_g3="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_G3}" bash "${STATE_SH}" read-raw --name g3 | grep -m1 '^stalled=' | cut -d= -f2-)"
if printf '%s\n' "${guard_out_g3}" | grep -q 'stalled lane recorded' && [[ "${stalled_field_g3}" -ge 1 ]]; then
  pass "guard stall detection: an untouched-past-threshold worktree is logged and stalled=${stalled_field_g3}"
else
  fail "guard stall case failed: output=${guard_out_g3} stalled_field=${stalled_field_g3}"
fi
git -C "${REPO_G}" worktree remove --force "${WT_STALE}" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Group H: mutation controls (C2's stronger requirement) — apply each of the
# three c1/c2/c3-mut sed patches to a SCRATCH copy of the fleet dir and prove
# the relevant scenario above goes RED against the mutated copy. Group 0
# already proved the marker text is present; this proves the mutation
# actually defeats the property, not just that the comment exists.
# ---------------------------------------------------------------------------
printf 'group H: mutation controls (scratch-copy, must go RED)\n'

MUT_DIR="${TMP_ROOT}/fleet-mut"
rm -rf "${MUT_DIR}"; mkdir -p "${MUT_DIR}"
cp "${FLEET_DIR}"/*.sh "${MUT_DIR}/"

# c1-mut: Restart= passthrough neutered -> a --restart always unit must no
# longer actually carry Restart=always.
sed 's/^Restart=\${4}$/Restart=no # (MUTATED)/' \
  "${FLEET_DIR}/leadv2-fleet-unit.sh" > "${MUT_DIR}/leadv2-fleet-unit.sh"
mut_unit_always="$(bash "${MUT_DIR}/leadv2-fleet-unit.sh" print-unit --repo "${REPO_A}" --name a1 --cap 2 --restart always)"
if printf '%s\n' "${mut_unit_always}" | grep -q '^Restart=always'; then
  fail "c1-mut control did not redden: mutated unit still emits Restart=always"
else
  pass "c1-mut control: mutating the c1-mut line defeats --restart always (RED as required)"
fi

# c2-mut: stop-flag gate neutered (`if false; then` instead of the real
# check) -> the runner must ignore FLEET-STOP and keep running lanes.
sed 's/if fleet_stop_flag_present; then$/if false; then # (MUTATED)/' \
  "${FLEET_DIR}/leadv2-fleet-runner.sh" > "${MUT_DIR}/leadv2-fleet-runner.sh"
STOP_FLAG_MUT="${TMP_ROOT}/FLEET-STOP-mut"
touch "${STOP_FLAG_MUT}"
STATE_ROOT_MUT="${TMP_ROOT}/state-mut"
rm -rf "${STATE_ROOT_MUT}"; mkdir -p "${STATE_ROOT_MUT}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_MUT}"
  export LEADV2_FLEET_STOP_FLAG="${STOP_FLAG_MUT}"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
  export LEADV2_FLEET_LANE_CMD="true"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  export LEADV2_FLEET_MAX_ITERATIONS=1
  bash "${MUT_DIR}/leadv2-fleet-runner.sh" --repo "${REPO_F}" --name mut-c2 >/dev/null 2>&1
)
status_mut_c2="$(LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_MUT}" bash "${STATE_SH}" read --name mut-c2 | head -1)"
if printf '%s\n' "${status_mut_c2}" | grep -q 'stopped (reason: stop_flag)'; then
  fail "c2-mut control did not redden: mutated runner still honored the stop flag"
else
  pass "c2-mut control: mutating the c2-mut line defeats the stop flag (RED as required): ${status_mut_c2}"
fi

# c3-mut: disk-floor gate neutered -> an impossible floor must stop refusing.
# Restore an unmutated runner first: the c2-mut step above overwrote
# MUT_DIR's copy, and this case must isolate the c3-mut lib change only.
cp "${FLEET_DIR}/leadv2-fleet-runner.sh" "${MUT_DIR}/leadv2-fleet-runner.sh"
sed 's/if \[\[ "\${free}" -lt "\${floor}" \]\]; then$/if false; then # (MUTATED)/' \
  "${FLEET_DIR}/leadv2-fleet-lib.sh" > "${MUT_DIR}/leadv2-fleet-lib.sh"
STATE_ROOT_MUT2="${TMP_ROOT}/state-mut2"
rm -rf "${STATE_ROOT_MUT2}"; mkdir -p "${STATE_ROOT_MUT2}"
LANE_RAN_MUT="${TMP_ROOT}/lane-ran-mut"
rm -f "${LANE_RAN_MUT}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_MUT2}"
  export LEADV2_FLEET_STOP_FLAG="${TMP_ROOT}/unused-stop-flag-mut2"
  export LEADV2_FLEET_ARMS="glm"
  export LEADV2_FLEET_ZAI_ENV="${ZAI_ENV_SUITE}"
  export LEADV2_FLEET_LANE_CMD="touch ${LANE_RAN_MUT}"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  export LEADV2_FLEET_MAX_ITERATIONS=1
  bash "${MUT_DIR}/leadv2-fleet-runner.sh" --repo "${REPO_D}" --name mut-c3 --floor-kb 999999999999 >/dev/null 2>&1
)
if [[ -f "${LANE_RAN_MUT}" ]]; then
  pass "c3-mut control: mutating the c3-mut line defeats the disk floor (RED as required — a lane ran past an impossible floor)"
else
  fail "c3-mut control did not redden: mutated lib still refused past the impossible floor"
fi

# ---------------------------------------------------------------------------
# Group I: round-4 edit 1 — a controlled stop exits with FLEET_STOP_EXIT_CODE,
# and Restart=on-failure + SuccessExitStatus=<code> (from the REAL generated
# unit) means systemd would never respawn it — a mini-systemd decision
# function, not a live systemd instance (none on this host).
# ---------------------------------------------------------------------------
printf 'group I: Claim 4 (round-4) — controlled stop is not restarted\n'

FLEET_STOP_EXIT_CODE_I="$(grep -m1 '^FLEET_STOP_EXIT_CODE=' "${FLEET_DIR}/leadv2-fleet-lib.sh" | cut -d= -f2)"
if [[ -n "${FLEET_STOP_EXIT_CODE_I}" ]]; then
  pass "mutation target present: FLEET_STOP_EXIT_CODE=${FLEET_STOP_EXIT_CODE_I} defined in leadv2-fleet-lib.sh"
else
  fail "FLEET_STOP_EXIT_CODE missing from leadv2-fleet-lib.sh — control has rotted"
fi

# would systemd, given Restart=<policy> and SuccessExitStatus=<csv>, respawn
# a process that just exited with <code>? Prints YES/NO.
mini_systemd_would_restart() { # <restart-policy> <success-exit-status-csv> <exit-code>
  local policy="$1" success_csv="$2" code="$3" s
  case "${policy}" in
    always) echo YES; return ;;
    no) echo NO; return ;;
    on-failure)
      [[ "${code}" -eq 0 ]] && { echo NO; return; }
      for s in ${success_csv//,/ }; do
        [[ "${code}" -eq "${s}" ]] && { echo NO; return; }
      done
      echo YES
      ;;
    *) echo UNKNOWN ;;
  esac
}

REPO_I="${TMP_ROOT}/repo-i"
mkdir -p "${REPO_I}"
STOP_FLAG_I="${TMP_ROOT}/FLEET-STOP-i"
touch "${STOP_FLAG_I}"   # pre-set: runner must self-stop on its very first check
STATE_ROOT_I="${TMP_ROOT}/state-i"
rm -rf "${STATE_ROOT_I}"; mkdir -p "${STATE_ROOT_I}"
(
  export LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_I}"
  export LEADV2_FLEET_STOP_FLAG="${STOP_FLAG_I}"
  export LEADV2_FLEET_STATE_BIN="${STATE_SH}"
  bash "${RUNNER_SH}" --repo "${REPO_I}" --name i1 >/dev/null 2>&1
)
runner_rc_i=$?

unit_i_onfailure="$(bash "${UNIT_SH}" print-unit --repo "${REPO_I}" --name i1)"
restart_i_onfailure="$(printf '%s\n' "${unit_i_onfailure}" | grep -m1 '^Restart=' | cut -d= -f2-)"
success_i="$(printf '%s\n' "${unit_i_onfailure}" | grep -m1 '^SuccessExitStatus=' | cut -d= -f2-)"

if [[ "${runner_rc_i}" == "${FLEET_STOP_EXIT_CODE_I}" ]]; then
  pass "controlled stop (FLEET-STOP) exits with FLEET_STOP_EXIT_CODE=${runner_rc_i}"
else
  fail "controlled stop exited rc=${runner_rc_i}, expected FLEET_STOP_EXIT_CODE=${FLEET_STOP_EXIT_CODE_I}"
fi

decision_i="$(mini_systemd_would_restart "${restart_i_onfailure}" "${success_i}" "${runner_rc_i}")"
if [[ "${decision_i}" == "NO" ]]; then
  pass "Restart=${restart_i_onfailure} + SuccessExitStatus=${success_i}: a controlled stop (rc=${runner_rc_i}) would NOT be respawned"
else
  fail "expected NO respawn for a controlled stop, mini-systemd says: ${decision_i} (restart=${restart_i_onfailure} success=${success_i} rc=${runner_rc_i})"
fi

# Negative control (mission's own suggestion): put Restart=always back
# (same REAL unit.sh, just --restart always) and show the SAME controlled-
# stop exit code WOULD be respawned.
unit_i_always="$(bash "${UNIT_SH}" print-unit --repo "${REPO_I}" --name i1 --restart always)"
restart_i_always="$(printf '%s\n' "${unit_i_always}" | grep -m1 '^Restart=' | cut -d= -f2-)"
decision_i_neg="$(mini_systemd_would_restart "${restart_i_always}" "${success_i}" "${runner_rc_i}")"
if [[ "${decision_i_neg}" == "YES" ]]; then
  pass "negative control: Restart=always respawns the SAME controlled-stop exit (rc=${runner_rc_i}) — reproduces the round-2/3 defect (RED as required)"
else
  fail "negative control did not redden: Restart=always unexpectedly did not respawn (${decision_i_neg})"
fi

# ---------------------------------------------------------------------------
# Group J: round-4 edit 2 — the generated unit passes verification. No
# systemd on this host, so systemd-analyze is used when present and a
# structural parser stub otherwise (per the mission's own wording); either
# way this is a real syntax check, not a string-equality echo of the fix.
# ---------------------------------------------------------------------------
printf 'group J: Claim 4 (round-4) — generated unit passes verification\n'

verify_unit_stub() { # <unit-text-file> -> prints VALID or an INVALID reason; rc 0/1
  local f="$1" wd_line env_line
  wd_line="$(grep -m1 '^WorkingDirectory=' "${f}")"
  if [[ "${wd_line}" == *'="'* || "${wd_line}" == *'"' ]]; then
    echo "INVALID: WorkingDirectory value is quoted — systemd takes the rest of the line literally for this directive, so the quotes become part of the path"
    return 1
  fi
  env_line="$(grep -m1 '^Environment=' "${f}")"
  if [[ -n "${env_line}" ]] && [[ "${env_line}" != 'Environment="'*'"' ]]; then
    echo "INVALID: Environment= assignment is not fully quoted — a value containing a space splits into extra directive tokens"
    return 1
  fi
  echo "VALID"
  return 0
}

verify_unit() { # <unit-text-file>
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$1" 2>&1 && echo VALID || echo "INVALID: systemd-analyze verify failed"
  else
    verify_unit_stub "$1"
  fi
}

UNIT_TEXT_J="${TMP_ROOT}/unit-j.txt"
printf '%s\n' "${unit_i_onfailure}" > "${UNIT_TEXT_J}"
verify_j="$(verify_unit "${UNIT_TEXT_J}")"
if [[ "${verify_j}" == "VALID" ]]; then
  pass "generated unit passes verification: ${verify_j}"
else
  fail "generated unit failed verification: ${verify_j}"
fi

# Negative control: reintroduce the quoted WorkingDirectory (the round-1..3
# shape) in a scratch copy of leadv2-fleet-unit.sh and show verification
# rejects it.
MUT_DIR_WD="${TMP_ROOT}/fleet-mut-wd"
rm -rf "${MUT_DIR_WD}"; mkdir -p "${MUT_DIR_WD}"
cp "${FLEET_DIR}"/*.sh "${MUT_DIR_WD}/"
sed 's/^WorkingDirectory=\${2}$/WorkingDirectory="\${2}"/' \
  "${FLEET_DIR}/leadv2-fleet-unit.sh" > "${MUT_DIR_WD}/leadv2-fleet-unit.sh"
if ! grep -q '^WorkingDirectory="\${2}"$' "${MUT_DIR_WD}/leadv2-fleet-unit.sh"; then
  fail "WorkingDirectory mutation did not land — control target text missing"
else
  mut_unit_j="$(bash "${MUT_DIR_WD}/leadv2-fleet-unit.sh" print-unit --repo "${REPO_I}" --name i1)"
  UNIT_TEXT_J_MUT="${TMP_ROOT}/unit-j-mut.txt"
  printf '%s\n' "${mut_unit_j}" > "${UNIT_TEXT_J_MUT}"
  verify_j_mut="$(verify_unit "${UNIT_TEXT_J_MUT}")"
  if [[ "${verify_j_mut}" == VALID ]]; then
    fail "negative control did not redden: quoted WorkingDirectory still verified VALID"
  else
    pass "negative control: reintroducing quoted WorkingDirectory fails verification (RED as required): ${verify_j_mut}"
  fi
fi

# ---------------------------------------------------------------------------
# Group K: round-4 edit 4 — the reaper must refuse (never force) removal of
# an uncommitted lane worktree. `--force` silently overrides the exact git
# safety check "leave it in place on refusal" depends on, so it can destroy
# in-flight work — worse than no reaper at all.
# ---------------------------------------------------------------------------
printf 'group K: Claim 4 (round-4) — reaper never force-deletes a dirty worktree\n'

if ! grep -n 'worktree remove --force' "${FLEET_DIR}/leadv2-fleet-guard.sh" >/dev/null 2>&1; then
  pass "mutation target present: leadv2-fleet-guard.sh no longer runs 'worktree remove --force'"
else
  fail "leadv2-fleet-guard.sh still runs worktree remove --force: $(grep -n 'worktree remove --force' "${FLEET_DIR}/leadv2-fleet-guard.sh")"
fi

REPO_K="${TMP_ROOT}/repo-k"
mkdir -p "${REPO_K}"
git -C "${REPO_K}" init -q
git -C "${REPO_K}" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init
WT_ROOT_K="${REPO_K}/.claude/worktrees"
mkdir -p "${WT_ROOT_K}"

make_dirty_worktree() { # <path> <branch>
  git -C "${REPO_K}" worktree add -q "$1" -b "$2" >/dev/null 2>&1
  echo "uncommitted work — must never be deleted" >> "$1/UNCOMMITTED.txt"
  git -C "$1" add UNCOMMITTED.txt >/dev/null 2>&1
  : > "${1%/}.fleet-terminal"
}

WT_DIRTY="${WT_ROOT_K}/wt-dirty"
make_dirty_worktree "${WT_DIRTY}" wt-dirty-branch
STATE_ROOT_K="${TMP_ROOT}/state-k"
rm -rf "${STATE_ROOT_K}"; mkdir -p "${STATE_ROOT_K}"
LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_K}" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
  bash "${GUARD_SH}" --repo "${REPO_K}" --name k1 >/dev/null 2>&1
if [[ -f "${WT_DIRTY}/UNCOMMITTED.txt" ]] && grep -q 'reap_refused' "${STATE_ROOT_K}/k1.stalled.log" 2>/dev/null; then
  pass "guard (fixed, non-forcing): a dirty terminal-marked worktree is refused and left in place, uncommitted work intact"
else
  fail "guard reap must-refuse case failed: file_exists=$([[ -f "${WT_DIRTY}/UNCOMMITTED.txt" ]] && echo yes || echo no) log=$(cat "${STATE_ROOT_K}/k1.stalled.log" 2>/dev/null)"
fi
git -C "${REPO_K}" worktree remove --force "${WT_DIRTY}" >/dev/null 2>&1 || rm -rf "${REPO_K}/.git/worktrees/wt-dirty" 2>/dev/null

# Negative control: reintroduce --force (the round-1..3 shape) on a scratch
# copy of guard.sh — must delete the dirty worktree, reproducing the exact
# data-loss regression edit 4 removes.
sed 's/worktree remove "\${wt_trim}"/worktree remove --force "\${wt_trim}"/' \
  "${FLEET_DIR}/leadv2-fleet-guard.sh" > "${MUT_DIR}/leadv2-fleet-guard.sh"
if ! grep -q -- '--force "\${wt_trim}"' "${MUT_DIR}/leadv2-fleet-guard.sh"; then
  fail "guard --force mutation did not land — control target text missing"
else
  WT_DIRTY2="${WT_ROOT_K}/wt-dirty2"
  make_dirty_worktree "${WT_DIRTY2}" wt-dirty2-branch
  STATE_ROOT_K2="${TMP_ROOT}/state-k2"
  rm -rf "${STATE_ROOT_K2}"; mkdir -p "${STATE_ROOT_K2}"
  LEADV2_FLEET_STATE_ROOT="${STATE_ROOT_K2}" LEADV2_FLEET_STATE_BIN="${STATE_SH}" \
    bash "${MUT_DIR}/leadv2-fleet-guard.sh" --repo "${REPO_K}" --name k2 >/dev/null 2>&1
  if [[ ! -d "${WT_DIRTY2}" ]]; then
    pass "guard --force mutation control: reintroducing --force deletes the dirty worktree (RED as required — reproduces the pre-fix data-loss defect)"
  else
    fail "guard --force mutation control did not redden: dirty worktree survived even with --force reintroduced"
    git -C "${REPO_K}" worktree remove --force "${WT_DIRTY2}" >/dev/null 2>&1 || rm -rf "${REPO_K}/.git/worktrees/wt-dirty2" 2>/dev/null
  fi
fi

printf '\n%s of %s passed (fleet guard suite, macOS Darwin, no systemd — unit layer stubbed per mission)\n' "${PASS}" "$((PASS + FAIL))"
[[ "${FAIL}" -eq 0 ]]
