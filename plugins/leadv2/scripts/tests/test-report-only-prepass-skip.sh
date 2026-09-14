#!/usr/bin/env bash
# FABLE-CANNOT-TAKE-ANY-NON-PRODUCT-LANE-01: a lane whose --kind is not in
# LEADV2_NON_PRODUCT_KINDS (e.g. audit/review/plan -- the only kinds fable is
# registered capable of) classifies product_class=product (conservative_default)
# and hits the full architect prepass, even when the lane declared a validated
# `report:<path>` deliverable (REPORT-ONLY-GATE-01) and therefore has NO code
# design to produce. Before this fix the architect was still spawned, could
# never invent a LANE_WRITES line for a lane that writes nothing, and the lane
# parked after ARCHITECT_PREPASS_ATTEMPTS timeouts (measured live 2026-09-14:
# architect_prepass task=21d40adf status=parked reason=no_design_after_2_attempts
# worker_launched=0) -- a report-only diagnostic lane could never be dispatched
# under any kind fable is capable of.
#
# Case A (fix): --kind audit + --pin-arm fable + --lane-deliverable 'report:<path>'
#   -> architect_prepass must SKIP the architect subprocess
#   entirely (status=skipped reason=report_only_deliverable), the fake architect
#   binary must never be invoked (sentinel file absent), and the lane must still
#   reach worker_spawned.
#
# Case B (negative control): the SAME --kind audit product classification, but
# an ordinary code lane (no --lane-deliverable, a real multi-file --writes) whose
# architect binary always fails -- must still pay the full retry-then-park path
# and park with reason=no_design_after_<N>_attempts, worker_launched=0. A fix
# that also skips this case has removed the gate, not made it apply correctly.
# run-all-triggers: leadv2-dispatch-code

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-code.sh"

setup_repo() { # <root> -> repo path on stdout
  local root="$1" repo="$1/repo"
  mkdir -p "${repo}/.claude/ref" "${repo}/docs/leadv2/.bus-offsets"
  ( cd "${repo}" && git init -q && git config user.email test@example.com \
      && git config user.name test && : > seed && git add seed \
      && git commit -qm seed ) >/dev/null 2>&1
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: [safety_gate_publish_payments]\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${repo}/.claude/ref/leadv2-routing.yaml"
  # Keep classification hermetic: the real judge may call a provider, which
  # would turn this dispatcher regression into a network-dependent test.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" '\''{"complexity":"trivial","subsystems_touched":1,"risk_class":"none","work_kind":"build","duration_class":"short","estimate_source":"judge"}'\''\n' \
    > "${root}/judge"
  chmod +x "${root}/judge"
  printf '%s' "${repo}"
}

stop_fixture_worker() { # <root>
  local root="$1" pid=""
  [[ -f "${root}/worker.pid" ]] && pid="$(cat "${root}/worker.pid" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
  rm -rf "${root}"
}

# --- Case A: report-only lane must SKIP the architect entirely -------------
run_case_a() {
  local ROOT REPO WORKER ARCH
  ROOT="$(mktemp -d "${LEADV2_TEST_TMPDIR:-/tmp}/leadv2-report-only-prepass.XXXXXX")"
  REPO="$(setup_repo "${ROOT}")"
  WORKER="${ROOT}/worker"; ARCH="${ROOT}/architect"
  printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "%%s" "$!" > "'"${ROOT}"'/worker.pid"\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${WORKER}"
  # A fake architect that PROVES it was invoked (sentinel file) -- if the skip
  # regresses, this file appears and case A fails on it, not on a log-grep miss.
  cat > "${ARCH}" <<EOF
#!/usr/bin/env bash
: > "${ROOT}/architect-invoked"
exit 1
EOF
  chmod +x "${WORKER}" "${ARCH}"

  ( cd "${REPO}" && \
    LEADV2_DISPATCH_ARCHITECT_GATE=1 \
    CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_STATE_ROOT="${ROOT}/state" LEADV2_DISPATCH_CACHE_DIR="${ROOT}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${WORKER}" LEADV2_DISPATCH_ARCHITECT_BIN="${ARCH}" \
    LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=10 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off LEADV2_REQUIRE_PHASES=0 \
    LEADV2_DISPATCH_COST_ESTIMATE=0 LEADV2_PULSE_MODE=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_TASK_JUDGE_BIN="${ROOT}/judge" \
      bash "${DISPATCH}" 'FABLE-CANNOT-TAKE-ANY-NON-PRODUCT-LANE-01 case A: audit lane with a declared report deliverable' \
      --kind audit --pin-arm fable --protected --no-probe-yet --lane-deliverable 'report:docs/handoff/case-a/report.md' \
      >"${ROOT}/out.log" 2>&1 )

  if grep -q 'architect_prepass task=.* status=skipped reason=report_only_deliverable' "${ROOT}/out.log"; then
    ok "case A: architect_prepass emits status=skipped reason=report_only_deliverable for a declared report lane"
  else
    bad "case A: expected architect_prepass status=skipped reason=report_only_deliverable, got:"
    cat "${ROOT}/out.log"
  fi

  if [[ -f "${ROOT}/architect-invoked" ]]; then
    bad "case A: the architect binary WAS invoked -- the skip did not prevent the spawn it exists to avoid"
  else
    ok "case A: the architect binary was never invoked (no sentinel file)"
  fi

  if grep -qE 'architect_prepass task=.* status=(parked|retrying)' "${ROOT}/out.log"; then
    bad "case A: architect_prepass still retried/parked instead of skipping:"
    cat "${ROOT}/out.log"
  else
    ok "case A: no retry/park decision was emitted"
  fi

  if grep -q 'worker_spawned' "${ROOT}/out.log"; then
    ok "case A: dispatch still reached worker_spawned despite no architect design"
  else
    bad "case A: dispatch never reached worker_spawned:"
    cat "${ROOT}/out.log"
  fi

  stop_fixture_worker "${ROOT}"
}

# --- Case B (negative control): an ordinary code lane must still pay the
# full prepass gate and can still park with no design. -----------------------
run_case_b() {
  local ROOT REPO WORKER ARCH
  ROOT="$(mktemp -d "${LEADV2_TEST_TMPDIR:-/tmp}/leadv2-report-only-prepass.XXXXXX")"
  REPO="$(setup_repo "${ROOT}")"
  WORKER="${ROOT}/worker"; ARCH="${ROOT}/architect"
  printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "%%s" "$!" > "'"${ROOT}"'/worker.pid"\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${WORKER}"
  # Always fails, produces no design artifact, generic rc=1 (classifies as
  # failed_rc_1 -- not one of the auth/rate/quota classes that would trigger a
  # cross-provider fallback attempt, keeping this a clean retry-then-park case).
  printf '#!/usr/bin/env bash\nprintf "generic architect failure\\n" >&2\nexit 1\n' > "${ARCH}"
  chmod +x "${WORKER}" "${ARCH}"

  ( cd "${REPO}" && \
    LEADV2_DISPATCH_ARCHITECT_GATE=1 LEADV2_DISPATCH_ARCHITECT_ATTEMPTS=2 \
    CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_STATE_ROOT="${ROOT}/state" LEADV2_DISPATCH_CACHE_DIR="${ROOT}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${WORKER}" LEADV2_DISPATCH_ARCHITECT_BIN="${ARCH}" \
    LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=10 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off LEADV2_REQUIRE_PHASES=0 \
    LEADV2_DISPATCH_COST_ESTIMATE=0 LEADV2_PULSE_MODE=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_TASK_JUDGE_BIN="${ROOT}/judge" \
      bash "${DISPATCH}" 'FABLE-CANNOT-TAKE-ANY-NON-PRODUCT-LANE-01 case B: ordinary audit-classified code lane, no report deliverable' \
      --kind audit --pin-arm fable --protected --no-probe-yet --writes "a.txt,b.txt" \
      >"${ROOT}/out.log" 2>&1 )

  if grep -q 'architect_prepass task=.* status=skipped reason=report_only_deliverable' "${ROOT}/out.log"; then
    bad "case B: an UNDECLARED code lane was skipped as report-only -- the gate no longer applies to real work:"
    cat "${ROOT}/out.log"
  else
    ok "case B: no report_only_deliverable skip fired for an undeclared code lane"
  fi

  if grep -q "architect_prepass task=.* status=parked reason=no_design_after_2_attempts" "${ROOT}/out.log"; then
    ok "case B: the code lane still parked with reason=no_design_after_2_attempts (gate still applies)"
  else
    bad "case B: expected the code lane to park with no_design_after_2_attempts, got:"
    cat "${ROOT}/out.log"
  fi

  if grep -q 'worker_spawned' "${ROOT}/out.log"; then
    bad "case B: a parked lane with no design reached worker_spawned -- PREPASS-RETRY-THEN-PARK-01 is broken"
  else
    ok "case B: the parked lane never reached worker_spawned"
  fi

  stop_fixture_worker "${ROOT}"
}

run_case_a
run_case_b

printf '\n[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
