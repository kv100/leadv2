#!/usr/bin/env bash
# Isolated subprocess integration coverage for PREPASS-PROVIDER-FALLBACK-01-R9.
# Every case runs a copy of the dispatcher against a temporary Git repository;
# Codex, GLM, and registry behavior are local stubs.  No provider or canonical
# active.yaml registry is contacted.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prepass-fixtures.XXXXXX")"
PASS=0 FAIL=0
cleanup() { rm -rf "${ROOT}"; }
trap cleanup EXIT
ok() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

make_fixture() { # prints fixture root
  local d="$1"
  mkdir -p "${d}/tmp"
  cp -R "${SCRIPTS_DIR}" "${d}/scripts"
  # Load the real definitions without dispatching its CLI footer.
  awk '/^# ── dispatch / { exit } { print }' \
    "${d}/scripts/leadv2-dispatch-code.sh" > "${d}/scripts/dispatch-lib.sh"
  local repo="${d}/repo"
  mkdir -p "${repo}"
  git -C "${repo}" init -q -b main
  git -C "${repo}" config user.email fixture@example.invalid
  git -C "${repo}" config user.name fixture
  printf 'seed\n' > "${repo}/seed.txt"
  git -C "${repo}" add seed.txt
  git -C "${repo}" commit -qm seed
  printf '%s' "${repo}"
}

make_provider_stub() { # <path>
  local path="$1"
  cat > "${path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${STUB_ARGS_FILE}"
case "${STUB_MODE}" in
  success) printf 'acceptance:\n  surface: file_artifact\nLANE_WRITES: seed.txt\n' ;;
  glm-success)
    out=""; while [[ $# -gt 0 ]]; do [[ "$1" == --out ]] && { out="$2"; shift 2; continue; }; shift; done
    printf 'acceptance:\n  surface: file_artifact\nLANE_WRITES: seed.txt\n' > "${out}"
    ;;
  fail) exit 23 ;;
  sleep) printf '%s' "$$" > "${STUB_PROVIDER_PID_FILE}"; sleep 30 ;;
  *) exit 64 ;;
esac
EOF
  chmod +x "${path}"
}

make_runner() { # <fixture-dir> <repo> <mode> <provider> <stub-mode>
  local d="$1" repo="$2" mode="$3" provider="$4" stub_mode="$5"
  cat > "${d}/runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${FIXTURE_DIR}/scripts/dispatch-lib.sh"
PROJECT_ROOT="${FIXTURE_REPO}"
ARCHITECT_PREPASS_TIMEOUT_SEC="${FIXTURE_TIMEOUT:-1}"
emit() { printf '%s\n' "$*" >> "${FIXTURE_DIR}/events.log"; }
_provider_available() { return 0; }
_load_dispatch_ladder() {
  if [[ "${FIXTURE_PROVIDER}" == codex ]]; then
    _LADDER_IDS=(codex); _LADDER_PROVIDERS=(openai)
  else
    _LADDER_IDS=(glm); _LADDER_PROVIDERS=(zai)
  fi
}
CODEX_BIN="${FIXTURE_DIR}/provider.sh"
GLM_BIN="${FIXTURE_DIR}/provider.sh"
printf 'architect prompt\n' > "${FIXTURE_DIR}/mission.md"
if [[ "${FIXTURE_MODE}" == registry-foreign || "${FIXTURE_MODE}" == registry-worker || "${FIXTURE_MODE}" == registry-owned || "${FIXTURE_MODE}" == registry-signal-window ]]; then
  session=foreign-session; pid=999999; role=lead_durable
  [[ "${FIXTURE_MODE}" == registry-worker ]] && { session=ours-session; pid=12345; role=worker; }
  [[ "${FIXTURE_MODE}" == registry-owned ]] && { session=ours-session; pid=12345; }
  [[ "${FIXTURE_MODE}" == registry-signal-window ]] && { session=ours-session; pid=12345; }
  cat > "${FIXTURE_DIR}/registry.yaml" <<YAML
sessions:
  - task_id: fixture-lane
    session_id: ${session}
    pid: ${pid}
    pid_role: ${role}
YAML
  _leadv2_yaml_file() { printf '%s\n' "${FIXTURE_DIR}/registry.yaml"; }
  _leadv2_yaml_lockfile() { printf '%s\n' "${FIXTURE_DIR}/registry.lock"; }
  DISPATCH_SLOT_REG_ID=fixture-lane
  DISPATCH_SLOT_SESSION=ours-session
  DISPATCH_SLOT_PID=12345
  if [[ "${FIXTURE_MODE}" == registry-signal-window ]]; then
    # The runner itself is the live-worker stand-in.  Exercise the exact
    # release entry point while the pre-spawn disarm is active; its row must
    # survive even though the process is still live.
    kill -0 "$$"
    _dispatch_disarm_slot_before_spawn
    _release_registered_lane fixture-lane fixture-sig signal-window
  else
  _release_registered_lane fixture-lane fixture-sig fixture-test
  fi
  python3 - "${FIXTURE_DIR}/registry.yaml" "${FIXTURE_MODE}" <<'PY'
import sys, yaml
data, mode = yaml.safe_load(open(sys.argv[1])), sys.argv[2]
if mode == 'registry-owned':
    assert data['sessions'] == []
else:
    row = data['sessions'][0]
    assert row['session_id'] == ('foreign-session' if mode == 'registry-foreign' else 'ours-session')
PY
  exit 0
fi
_architect_fallback_design "${FIXTURE_DIR}/mission.md" fixture-sig authentication_failed "${FIXTURE_DIR}/design.md" anthropic
EOF
  chmod +x "${d}/runner.sh"
  make_provider_stub "${d}/provider.sh"
  FIXTURE_DIR="${d}" FIXTURE_REPO="${repo}" FIXTURE_MODE="${mode}" \
    FIXTURE_PROVIDER="${provider}" STUB_MODE="${stub_mode}" \
    STUB_ARGS_FILE="${d}/provider.args" STUB_PROVIDER_PID_FILE="${d}/provider.pid" TMPDIR="${d}/tmp" bash "${d}/runner.sh"
}

case_success_codex() {
  local d="${ROOT}/success-codex" repo out
  repo="$(make_fixture "${d}")"
  if out="$(make_runner "${d}" "${repo}" fallback codex success 2>&1)" \
      && python3 - "${d}" "${repo}" <<'PY'
import os, sys
d, repo = sys.argv[1:]
assert os.path.getsize(os.path.join(d, 'design.md')) > 0
args = open(os.path.join(d, 'provider.args')).read()
assert '--cwd ' in args and repo not in args.split('--cwd ', 1)[1].split()[0:1]
assert not any(name.startswith('leadv2-afb.') for name in os.listdir(os.path.join(d, 'tmp')))
PY
  then ok 'Codex success writes a design from an isolated disposable worktree'; else printf '%s\n' "${out}"; bad 'Codex success fixture'; fi
}

workspace_absent() { # <fixture-dir>
  python3 - "$1" <<'PY'
import os, sys
assert not any(name.startswith('leadv2-afb.') for name in os.listdir(os.path.join(sys.argv[1], 'tmp')))
PY
}

provider_not_running() { # <pid> -- a zombie has been killed and awaits reap
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  [[ -z "${state}" || "${state}" == Z* ]]
}

case_success_glm() {
  local d="${ROOT}/success-glm" repo
  repo="$(make_fixture "${d}")"
  if make_runner "${d}" "${repo}" fallback glm glm-success >/dev/null 2>&1 \
      && [[ -s "${d}/design.md" ]]; then ok 'GLM --out success is accepted and disposed'; else bad 'GLM success fixture'; fi
}

case_nonzero_cleanup() {
  local d="${ROOT}/nonzero" repo rc=0
  repo="$(make_fixture "${d}")"
  make_runner "${d}" "${repo}" fallback codex fail >/dev/null 2>&1 || rc=$?
  if [[ ${rc} -ne 0 ]] && workspace_absent "${d}"; then
    ok 'nonzero provider result fails and removes the fallback workspace'
  else bad 'nonzero provider fixture'; fi
}

case_timeout_cleanup() {
  local d="${ROOT}/timeout" repo rc=0
  repo="$(make_fixture "${d}")"
  make_runner "${d}" "${repo}" fallback codex sleep >/dev/null 2>&1 || rc=$?
  if [[ ${rc} -ne 0 ]] && workspace_absent "${d}"; then
    ok 'timeout kills the stubbed provider and removes the fallback workspace'
  else bad 'timeout fixture'; fi
}

case_signal_cleanup() {
  local d="${ROOT}/signal" repo pid rc=0 i elapsed
  repo="$(make_fixture "${d}")"
  # Build the same isolated runner/provider seam used by the other subprocess
  # cases, then start a fresh long-running fallback through that seam.
  make_runner "${d}" "${repo}" fallback codex success >/dev/null 2>&1
  SECONDS=0
  FIXTURE_DIR="${d}" FIXTURE_REPO="${repo}" FIXTURE_MODE=fallback FIXTURE_PROVIDER=codex \
    FIXTURE_TIMEOUT=30 STUB_MODE=sleep STUB_ARGS_FILE="${d}/provider.args" STUB_PROVIDER_PID_FILE="${d}/provider.pid" TMPDIR="${d}/tmp" bash "${d}/runner.sh" >"${d}/runner.log" 2>&1 &
  pid=$!
  for i in $(seq 1 40); do
    [[ -s "${d}/provider.args" && -s "${d}/provider.pid" ]] && break
    sleep 0.05
  done
  kill -TERM "${pid}" 2>/dev/null || true
  wait "${pid}" || rc=$?
  elapsed=${SECONDS}
  if [[ -s "${d}/provider.pid" && ${rc} -ne 0 && ${elapsed} -lt 3 ]] && workspace_absent "${d}" \
      && provider_not_running "$(cat "${d}/provider.pid")"; then
    ok 'SIGTERM interrupts a 30-second fallback promptly and removes its workspace'
  else
    bad 'signal cleanup fixture'
  fi
}

case_signal_window_registry_survives() {
  local arm="$1" d="${ROOT}/signal-window-${1}" repo
  repo="$(make_fixture "${d}")"
  if make_runner "${d}" "${repo}" registry-signal-window "${arm}" success >/dev/null 2>&1; then
    ok "${arm} live-row signal window is disarmed before EXIT cleanup"
  else bad "${arm} signal-window fixture"; fi
}

case_foreign_owner_refusal() {
  local d="${ROOT}/foreign-owner" repo
  repo="$(make_fixture "${d}")"
  if make_runner "${d}" "${repo}" registry-foreign codex success >/dev/null 2>&1; then
    ok 'registry compare-and-delete refuses a foreign owner row'
  else bad 'foreign owner fixture'; fi
}

case_worker_owner_refusal() {
  local d="${ROOT}/worker-owner" repo
  repo="$(make_fixture "${d}")"
  if make_runner "${d}" "${repo}" registry-worker codex success >/dev/null 2>&1; then
    ok 'registry compare-and-delete refuses a worker-owned row'
  else bad 'worker owner fixture'; fi
}

case_owned_compare_delete() {
  local d="${ROOT}/owned-row" repo
  repo="$(make_fixture "${d}")"
  if make_runner "${d}" "${repo}" registry-owned codex success >/dev/null 2>&1; then
    ok 'registry compare-and-delete removes only the captured owner row'
  else bad 'owned compare-delete fixture'; fi
}

case_success_codex
case_success_glm
case_nonzero_cleanup
case_timeout_cleanup
case_signal_cleanup
case_signal_window_registry_survives codex
case_signal_window_registry_survives glm
case_foreign_owner_refusal
case_worker_owner_refusal
case_owned_compare_delete
printf '\n[SUITE] %s: %d passed, %d failed\n' "$([[ ${FAIL} -eq 0 ]] && printf PASS || printf FAIL)" "${PASS}" "${FAIL}"
exit "${FAIL}"
