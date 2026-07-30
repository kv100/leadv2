#!/usr/bin/env bash
# test-codex-task-spawn-failure.sh — wave2 round3 finding 5: `codex-task.sh <task|review>
# --background` must reach `_record_spawn_failure` (and propagate the launcher's real exit
# code) even when the background launcher itself fails and emits no parseable jobId.
#
# codex-task.sh runs under `set -e`. Before this fix,
#   _BG_OUT="$(_run_with_fallback "$@")"
#   _BG_RC=$?
# was a bare simple-command assignment -- NOT exempt from errexit -- so a genuinely
# failing launcher aborted the WHOLE script at that line: `_BG_RC` was never captured,
# the no-jobId branch never ran, and `_record_spawn_failure` never fired. This test drives
# the REAL codex-task.sh against a fake, fast-failing "codex-companion.mjs" (a real
# subprocess that exits nonzero and prints nothing matching the jobId regex -- not a
# hand-mocked shell function), so it fails against the pre-fix file and passes against the
# fix.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_TASK_SH="${HERE}/codex-task.sh"

REAL_COMPANION="$(find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs -path '*/scripts/*' 2>/dev/null | sort -V | tail -1)"
if [[ -z "${REAL_COMPANION}" ]]; then
  echo "SKIP: codex-companion.mjs not found (openai-codex plugin not installed) -- cannot run this test"
  exit 0
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT
export CLAUDE_PLUGIN_DATA="${SANDBOX}/plugin-data"
export CODEX_GUARD_STATE_ROOT="${SANDBOX}/plugin-data/state"
CWD="${SANDBOX}/project"
mkdir -p "${CWD}"

FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=1; }

# Real companion dir, cloned so `lib/` (state.mjs et al, used by
# _record_spawn_failure/_sync_state_index) stays 100% real and untouched -- only the
# entrypoint itself is replaced with a fake that always fails fast, emitting nothing that
# matches the (task|review)-<id>-<rand> jobId pattern.
cp -R "$(dirname "${REAL_COMPANION}")" "${SANDBOX}/companion-copy"
FAKE_COMPANION="${SANDBOX}/companion-copy/codex-companion.mjs"
cat > "${FAKE_COMPANION}" <<'EOF'
#!/usr/bin/env node
console.error("[fake-companion] simulated spawn failure -- no job id will ever be emitted");
process.exit(7);
EOF

STUB_BIN_DIR="${SANDBOX}/stubbin"
mkdir -p "${STUB_BIN_DIR}"
cat > "${STUB_BIN_DIR}/find" <<EOF
#!/usr/bin/env bash
echo "${FAKE_COMPANION}"
EOF
chmod +x "${STUB_BIN_DIR}/find"

_RC=0
OUT="$(PATH="${STUB_BIN_DIR}:${PATH}" bash "${CODEX_TASK_SH}" task "spawn-failure regression probe" --background --cwd "${CWD}" \
  2>"${SANDBOX}/spawn.err")" || _RC=$?

# --- 1: the launcher's real exit code (7) must propagate, not be swallowed/aborted early ---
if [[ "${_RC}" -eq 7 ]]; then
  pass "launcher's real exit code (7) propagated as codex-task.sh's own exit code"
else
  fail "expected exit code 7 from the failing launcher, got ${_RC} (stderr: $(cat "${SANDBOX}/spawn.err" 2>/dev/null))"
fi

# --- 2: the no-jobId WARN branch must actually run (proves the script did not die at the
#         command-substitution assignment before ever reaching it) ---
if grep -q "could not parse jobId" "${SANDBOX}/spawn.err"; then
  pass "no-jobId WARN branch was reached"
else
  fail "no-jobId WARN branch never ran (stderr: $(cat "${SANDBOX}/spawn.err" 2>/dev/null))"
fi

# --- 3: _record_spawn_failure must actually have run and recorded a job ---
if grep -q "recorded spawn failure as" "${SANDBOX}/spawn.err"; then
  pass "_record_spawn_failure ran and reported recording a job"
else
  fail "_record_spawn_failure never ran (stderr: $(cat "${SANDBOX}/spawn.err" 2>/dev/null))"
fi

# --- 4: a real job record with kind=spawn-failure must exist in the state index (not just
#         a log line) -- read through the REAL (untouched) lib/state.mjs, same discipline
#         as test-codex-task-reap.sh's read_index_status helper ---
LIB_DIR="$(dirname "${REAL_COMPANION}")/lib"
SPAWN_FAIL_COUNT="$(node -e '
(async () => {
  const [libDir, cwd] = process.argv.slice(1);
  const { listJobs } = await import(libDir + "/state.mjs");
  const jobs = listJobs(cwd).filter((j) => j.kind === "spawn-failure" && j.status === "failed");
  console.log(jobs.length);
})();
' "${LIB_DIR}" "${CWD}" 2>/dev/null)"
if [[ "${SPAWN_FAIL_COUNT:-0}" -ge 1 ]]; then
  pass "a real kind=spawn-failure, status=failed job exists in the state index"
else
  fail "no kind=spawn-failure job found in the state index (count=${SPAWN_FAIL_COUNT:-0})"
fi

# --- 5: no codex-guard.sh was armed for a failure that produced no job id (nothing to
#         babysit) ---
if grep -q "armed codex-guard.sh" "${SANDBOX}/spawn.err"; then
  fail "codex-guard.sh was armed despite no jobId ever being parsed"
else
  pass "codex-guard.sh was correctly NOT armed (no jobId to watch)"
fi

if [[ ${FAIL} -eq 0 ]]; then
  echo 'PASS: codex-task.sh --background spawn-failure recording (round3 finding 5)'
  exit 0
fi
exit 1
