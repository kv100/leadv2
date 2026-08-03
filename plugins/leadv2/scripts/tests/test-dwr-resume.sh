#!/usr/bin/env bash
# GLM-DIED-WITH-WORK-RESUME-01 harness.
# Proves product-close resumes a died-with-work lane exactly once via the
# provider's `bg` entrypoint before gating its partial diff.  Uses the same
# ok/bad/assert_eq helpers and GLM_RUNS_DIR / KIMI_RUNS_DIR / LEADV2_PC_RUNS_ROOT
# / LEADV2_JOB_REGISTRY_ROOT / LEADV2_JOURNAL_BIN / LEADV2_DISPATCH_LEDGER_BIN
# seams as test-no-work-terminal.sh.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
PASS=0; FAIL=0
ok()   { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_eq() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

make_stubs() { # <dir>
  local d="$1"
  cat > "${d}/resolver.py" <<'PY'
print("reviewer=codex"); print("pool=codex"); print("refusal=")
PY
  cat > "${d}/codex.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$2"; printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$1"
SH
  chmod +x "${d}/codex.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal.log"\n' "${d}" > "${d}/journal.sh"
  chmod +x "${d}/journal.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/ledger.log"\n' "${d}" > "${d}/ledger.sh"
  chmod +x "${d}/ledger.sh"
}

new_repo() {
  local root="$1"
  mkdir -p "${root}/agent"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
}

# Build a stub launcher that records argv, seeds a new completed run dir, and
# exits with a configurable rc.  Reads at runtime:
#   LEADV2_TEST_NEW_RUN_ID  — the run-id to print (must match ^[0-9]{6}-[0-9]{6}-)
#   LEADV2_TEST_LAUNCHER_RC — exit code (0=success, 1|2=gate refuse, other=fail)
#   LEADV2_TEST_RUNS_DIR    — root for the new run dir
#   LEADV2_TEST_CALLS_LOG   — file to append argv to
make_stub_launcher() { # <dir>
  local d="$1"
  cat > "${d}/stub-launcher.sh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
# Record argv.
[[ -n "${LEADV2_TEST_CALLS_LOG:-}" ]] && printf '%s\n' "$*" >> "${LEADV2_TEST_CALLS_LOG}"
# Seed a new run dir with status: complete so the second pc_await_worker_exit
# returns 0 immediately.
new_run="${LEADV2_TEST_NEW_RUN_ID:-260803-180000-resume00}"
runs_dir="${LEADV2_TEST_RUNS_DIR:-${GLM_RUNS_DIR:-${KIMI_RUNS_DIR:-${LEADV2_PC_RUNS_ROOT:-/tmp}/glm-runs}}}"
run_dir="${runs_dir}/${new_run}"
mkdir -p "${run_dir}"
# Parse --cwd from argv for a faithful meta.
cwd_val="${PWD}"
i=1
while [[ ${i} -le $# ]]; do
  if [[ "${!i}" == "--cwd" ]]; then
    next=$((i + 1))
    cwd_val="${!next}"
    break
  fi
  i=$((i + 1))
done
printf 'run_id: %s\nstatus: complete\noutcome: completed\ncwd: %s\nmax_turns: 50\ntimeout: 3600\n' \
  "${new_run}" "${cwd_val}" > "${run_dir}/meta.yaml"
: > "${run_dir}/prompt.txt"
echo "${new_run}"
exit "${LEADV2_TEST_LAUNCHER_RC:-0}"
STUB
  chmod +x "${d}/stub-launcher.sh"
}

# Create a fake run dir with a given outcome.
# Args: <runs_dir> <handle> <root> <outcome> <extra_meta...>
make_dead_run() { # <runs_dir> <handle> <root> <outcome>
  local runs_dir="$1" handle="$2" root="$3" outcome="$4"
  local run_dir="${runs_dir}/${handle}"
  mkdir -p "${run_dir}"
  printf 'run_id: %s\nstatus: complete\ncwd: %s\nmax_turns: 50\ntimeout: 3600\noutcome: %s\n' \
    "${handle}" "${root}" "${outcome}" > "${run_dir}/meta.yaml"
  printf 'Write the deliverable described in the lane brief.\n' > "${run_dir}/prompt.txt"
}

# ---- Case (a): resume once on died-with-work -------------------------------
case_resume_once() {
  local d root handle runs launcher calls handoff rc new_run
  d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-deadrun1"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
  runs="${d}/glm-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
  new_run="260803-180000-resume01"
  make_dead_run "${runs}" "${handle}" "${root}" "died-with-work"
  : > "${calls}"
  LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
    LEADV2_TEST_NEW_RUN_ID="${new_run}" LEADV2_TEST_LAUNCHER_RC=0 \
    LEADV2_TEST_RUNS_DIR="${runs}" LEADV2_TEST_CALLS_LOG="${calls}" \
    GLM_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_PC_RESUME_MAX_WAIT_S=5 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" dwra0001 glm "${handle}" 0 0 "founder-dwr-a" >"${d}/close.log" 2>&1
  rc=$?
  handoff="${root}/docs/handoff/dispatch-dwra0001"
  local n_calls
  n_calls="$(wc -l < "${calls}" 2>/dev/null || echo 0)"
  assert_eq "$(printf '%s' "${n_calls}" | tr -d ' ')" "1" "stub launcher invoked exactly once"
  if grep -q -- '--cwd' "${calls}" 2>/dev/null && grep -q 'bg' "${calls}" 2>/dev/null; then
    ok "stub argv contains bg and --cwd"
  else bad "stub argv missing bg or --cwd (got: $(cat "${calls}" 2>/dev/null))"
  fi
  if [[ -f "${handoff}/.dwr-resume-attempted" ]]; then
    ok ".dwr-resume-attempted exists"
  else bad ".dwr-resume-attempted missing"
  fi
  if grep -q "dwr_resume task=dwra0001 from_run=${handle} new_run=${new_run}" "${d}/journal.log" 2>/dev/null; then
    ok "journal has dwr_resume new_run=${new_run}"
  else bad "journal dwr_resume line missing (got: $(grep dwr_resume "${d}/journal.log" 2>/dev/null || echo '<none>'))"
  fi
  if [[ -f "${handoff}/review.diff" ]]; then ok "gating ran (review.diff created)"; else bad "gating did not run"; fi
  rm -rf "${d}"
}

# ---- Case (b): marker present -> no second resume --------------------------
case_marker_present() {
  local d root handle runs launcher calls handoff rc
  d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-deadrun2"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
  runs="${d}/glm-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
  make_dead_run "${runs}" "${handle}" "${root}" "died-with-work"
  handoff="${root}/docs/handoff/dispatch-dwrb0002"
  mkdir -p "${handoff}"
  printf 'from_run=%s\nat=2026-08-03T17:00:00Z\nby=99999\n' "${handle}" > "${handoff}/.dwr-resume-attempted"
  : > "${calls}"
  LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
    LEADV2_TEST_NEW_RUN_ID="260803-180000-resume02" LEADV2_TEST_LAUNCHER_RC=0 \
    LEADV2_TEST_RUNS_DIR="${runs}" LEADV2_TEST_CALLS_LOG="${calls}" \
    GLM_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" dwrb0002 glm "${handle}" 0 0 "founder-dwr-b" >"${d}/close.log" 2>&1
  rc=$?
  local n_calls
  n_calls="$(wc -l < "${calls}" 2>/dev/null || echo 0)"
  assert_eq "$(printf '%s' "${n_calls}" | tr -d ' ')" "0" "stub launcher NOT invoked when marker present"
  if grep -q "dwr_resume task=dwrb0002 from_run=${handle} new_run=skipped reason=already_attempted" "${d}/journal.log" 2>/dev/null; then
    ok "journal has new_run=skipped reason=already_attempted"
  else bad "journal missing skipped line (got: $(grep dwr_resume "${d}/journal.log" 2>/dev/null || echo '<none>'))"
  fi
  if [[ -f "${handoff}/review.diff" ]]; then ok "gating still ran with marker present"; else bad "gating did not run"; fi
  rm -rf "${d}"
}

# ---- Case (c): not eligible (completed / died-clean) -----------------------
case_not_eligible() {
  local outcome
  for outcome in completed died-clean; do
    local d root handle runs launcher calls rc
    d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-${outcome}"
    mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
    runs="${d}/glm-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
    make_dead_run "${runs}" "${handle}" "${root}" "${outcome}"
    : > "${calls}"
    LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
      GLM_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
      LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
      LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
      LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
      LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
      LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
      LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
      bash "${PC}" "${root}" "dwrc$(printf '%s' "${outcome}" | cut -c1-3)" glm "${handle}" 0 0 "founder-dwr-c" >"${d}/close.log" 2>&1
    rc=$?
    local n_calls
    n_calls="$(wc -l < "${calls}" 2>/dev/null || echo 0)"
    assert_eq "$(printf '%s' "${n_calls}" | tr -d ' ')" "0" "stub NOT invoked for outcome=${outcome}"
    if grep -q 'dwr_resume' "${d}/journal.log" 2>/dev/null; then
      bad "outcome=${outcome} emitted a dwr_resume line (should be silent)"
    else ok "outcome=${outcome} has no dwr_resume journal line"
    fi
    rm -rf "${d}"
  done
}

# ---- Case (d): gate refuses (rc 2) -> blocked_by_gate, gating proceeds -----
case_gate_refuses() {
  local d root handle runs launcher calls handoff rc
  d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-deadrun4"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
  runs="${d}/glm-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
  make_dead_run "${runs}" "${handle}" "${root}" "died-with-work"
  : > "${calls}"
  LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
    LEADV2_TEST_LAUNCHER_RC=2 \
    LEADV2_TEST_RUNS_DIR="${runs}" LEADV2_TEST_CALLS_LOG="${calls}" \
    GLM_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" dwrd0004 glm "${handle}" 0 0 "founder-dwr-d" >"${d}/close.log" 2>&1
  rc=$?
  handoff="${root}/docs/handoff/dispatch-dwrd0004"
  if grep -q "dwr_resume task=dwrd0004 from_run=${handle} new_run=blocked_by_gate rc=2" "${d}/journal.log" 2>/dev/null; then
    ok "journal has blocked_by_gate rc=2"
  else bad "journal missing blocked_by_gate (got: $(grep dwr_resume "${d}/journal.log" 2>/dev/null || echo '<none>'))"
  fi
  if [[ -f "${handoff}/review.diff" ]]; then ok "gating still ran after gate refusal"; else bad "gating did not run"; fi
  if [[ -f "${handoff}/.dwr-resume-attempted" ]]; then ok "marker written despite gate refusal"; else bad "marker missing after gate refusal"; fi
  rm -rf "${d}"
}

# ---- Case (e): kimi parity — same treatment keyed off outcome: --------------
case_kimi_parity() {
  local d root handle runs launcher calls handoff rc new_run
  d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-kimidead"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
  runs="${d}/kimi-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
  new_run="260803-180000-kimires"
  make_dead_run "${runs}" "${handle}" "${root}" "died-with-work"
  : > "${calls}"
  LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
    LEADV2_TEST_NEW_RUN_ID="${new_run}" LEADV2_TEST_LAUNCHER_RC=0 \
    LEADV2_TEST_RUNS_DIR="${runs}" LEADV2_TEST_CALLS_LOG="${calls}" \
    KIMI_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_PC_RESUME_MAX_WAIT_S=5 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" dwre0005 kimi "${handle}" 0 0 "founder-dwr-e" >"${d}/close.log" 2>&1
  rc=$?
  handoff="${root}/docs/handoff/dispatch-dwre0005"
  local n_calls
  n_calls="$(wc -l < "${calls}" 2>/dev/null || echo 0)"
  assert_eq "$(printf '%s' "${n_calls}" | tr -d ' ')" "1" "kimi: stub launcher invoked once"
  if grep -q "dwr_resume task=dwre0005 from_run=${handle} new_run=${new_run}" "${d}/journal.log" 2>/dev/null; then
    ok "kimi: journal has dwr_resume new_run=${new_run}"
  else bad "kimi: journal dwr_resume missing (got: $(grep dwr_resume "${d}/journal.log" 2>/dev/null || echo '<none>'))"
  fi
  if [[ -f "${handoff}/review.diff" ]]; then ok "kimi: gating ran"; else bad "kimi: gating did not run"; fi
  rm -rf "${d}"
}

# ---- Case (f): kill switch off (LEADV2_PC_DWR_RESUME=0) --------------------
case_kill_switch() {
  local d root handle runs launcher calls rc
  d="$(mktemp -d)"; root="${d}/repo"; handle="260803-173809-ksdead"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"; make_stub_launcher "${d}"
  runs="${d}/glm-runs"; launcher="${d}/stub-launcher.sh"; calls="${d}/launcher-calls.log"
  make_dead_run "${runs}" "${handle}" "${root}" "died-with-work"
  : > "${calls}"
  LEADV2_PC_DWR_RESUME=0 \
    LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}" \
    LEADV2_TEST_RUNS_DIR="${runs}" LEADV2_TEST_CALLS_LOG="${calls}" \
    GLM_RUNS_DIR="${runs}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" dwrf0006 glm "${handle}" 0 0 "founder-dwr-f" >"${d}/close.log" 2>&1
  rc=$?
  local n_calls
  n_calls="$(wc -l < "${calls}" 2>/dev/null || echo 0)"
  assert_eq "$(printf '%s' "${n_calls}" | tr -d ' ')" "0" "kill switch: stub NOT invoked"
  if grep -q 'dwr_resume' "${d}/journal.log" 2>/dev/null; then
    bad "kill switch: emitted dwr_resume line (should be silent)"
  else ok "kill switch: no dwr_resume journal line"
  fi
  rm -rf "${d}"
}

case_resume_once
case_marker_present
case_not_eligible
case_gate_refuses
case_kimi_parity
case_kill_switch

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
