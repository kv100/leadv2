#!/usr/bin/env bash
# Offline regression coverage for FIX-SESSION-RUNNER-TURNCAP-01.
# run-all-triggers: leadv2-session-runner
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPTS_ROOT/leadv2-session-runner.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-turncap.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

CLAUDE_STUB="$ROOT/claude"
cat > "$CLAUDE_STUB" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_TRACE"
printf '%s\n' '{"is_error":true,"num_turns":31,"stop_reason":"tool_use"}'
exit 1
STUB
chmod +x "$CLAUDE_STUB"

# SD-DISPATCH-WRITESET-TWO-ROW-FIX-01: seed the registry row the dispatcher
# would have created -- the runner refuses adoption without one.
seed_lane_row() { # <project-root> <task-id>
  local reg_sh
  reg_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-active-registry.sh"
  mkdir -p "$1/docs/leadv2"
  LEADV2_PROJECT_ROOT="$1" LEADV2_BURN_GOVERNOR=0 \
    bash -c 'source "$3"; leadv2_active_register "$2" Standard "$1" "$1" false "" "" "" "prepass_pending" >/dev/null 2>&1' \
    _ "$1" "$2" "$reg_sh" || true
}

run_runner() {
  local project="$1" task_id="$2" trace="$3"
  seed_lane_row "$project" "$task_id"
  STUB_TRACE="$trace" LEADV2_PROJECT_ROOT="$project" LEADV2_TASK_ID="$task_id" \
  LEADV2_FANOUT_CLAUDE_BIN="$CLAUDE_STUB" LEADV2_CLAUDE_MAX_TURNS=30 \
  LEADV2_RUNNER_MAX_ATTEMPTS=2 LEADV2_RUNNER_RETRY_SLEEP_S=0 \
  LEADV2_RUNNER_NOOP_MAX=99 LEADV2_RUNNER_STALL_MAX=99 "$RUNNER"
}

if bash -n "$RUNNER"; then pass "runner syntax"; else fail "runner syntax"; fi

task_id="TURNCAP-EXHAUSTION"
project="$ROOT/turncap-project"
mkdir -p "$project/docs/handoff/$task_id"
set +e
turncap_out="$(run_runner "$project" "$task_id" "$project/claude.args" 2>&1)"
turncap_rc=$?
set -e
calls="$(wc -l < "$project/claude.args")"
if [[ "$turncap_rc" -eq 3 && "$calls" -eq 2 \
  && "$turncap_out" == *"exhausted max_turns (31/30) — NOT a crash"* \
  && "$(sed -n '2p' "$project/claude.args")" == *"--resume"* \
  && "$(sed -n '2p' "$project/claude.args")" == *"--max-turns 30"* ]]; then
  pass "terminal num_turns at cap is resumed as turn-cap exhaustion with a fresh budget"
else
  fail "turn-cap rc=$turncap_rc calls=$calls out=$turncap_out"
fi

task_id="TURNCAP-E2E-COMPLETE"
project="$ROOT/e2e-project"
mkdir -p "$project/docs/handoff/$task_id"
: > "$project/docs/handoff/$task_id/e2e-gate-passed.flag"
set +e
e2e_out="$(run_runner "$project" "$task_id" "$project/claude.args" 2>&1)"
e2e_rc=$?
set -e
if [[ "$e2e_rc" -eq 0 && ! -e "$project/claude.args" \
  && "$e2e_out" == *"E2E gate completion flag already present"* ]]; then
  pass "E2E completion flag prevents a relaunch"
else
  fail "e2e rc=$e2e_rc out=$e2e_out"
fi

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
