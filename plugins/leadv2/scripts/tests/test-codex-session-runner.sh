#!/usr/bin/env bash
# Fake-Codex integration smoke test for the provider-neutral full-cycle runner.
# No network/model call is made. The stub emits real Codex JSONL event shapes.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPTS_ROOT/leadv2-session-runner.sh"
REGISTRY="$SCRIPTS_ROOT/leadv2-active-registry.sh"
PASS=0
FAIL=0
ERRORS=()
ROOT="$(lv2_mktemp_dir "leadv2-codex-runner-test")"
trap 'rm -rf "$ROOT"' EXIT

pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf -- '[TEST] FAIL: %s\n' "$1"; }

CODEX_STUB="$ROOT/codex"
cat > "$CODEX_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf -- '%s\n' "$*" >> "$STUB_TRACE"
if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  exit 0
fi
if [[ "${STUB_MODE:-complete}" != "no-thread" && "${1:-}" == "exec" && "${2:-}" != "resume" ]]; then
  printf -- '{"type":"thread.started","thread_id":"codex-thread-test"}\n'
fi
printf -- '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":2}}\n'
if [[ "${STUB_MODE:-complete}" == "recursion" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"env LEADV2_TASK_ID=CODEX-SMOKE-RECURSION bash .claude/scripts/leadv2-supervise.sh\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-exec" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"exec .claude/scripts/leadv2-supervise.sh\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-env" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-if" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"if .claude/scripts/leadv2-supervise.sh; then :; fi\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-bash" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"bash .claude/scripts/leadv2-supervise.sh\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-env-split" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -S '\''bash .claude/scripts/leadv2-supervise.sh'\''"}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-env-split-long" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env --split-string='\''bash .claude/scripts/leadv2-supervise.sh'\''"}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-time" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"time -p .claude/scripts/leadv2-supervise.sh\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-coproc" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"coproc worker { .claude/scripts/leadv2-supervise.sh; }\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-coproc-direct" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"coproc .claude/scripts/leadv2-supervise.sh --flag\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "recursion-coproc-unnamed-group" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"coproc { .claude/scripts/leadv2-supervise.sh; }\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "negative-coproc-direct" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"coproc grep .claude/scripts/leadv2-supervise.sh somefile.txt\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "negative-coproc-named-group" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/zsh -lc \\"coproc worker { grep .claude/scripts/leadv2-supervise.sh f; }\\""}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "negative" ]]; then
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"grep -n leadv2-supervise.sh docs/x.md"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"sed -n 1,5p .claude/scripts/leadv2-codex-session-runner.sh"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"echo see .claude/scripts/leadv2-fanout.sh for details"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -i FOO=bar grep leadv2-supervise.sh x.md"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"cat .claude/scripts/leadv2-fanout.sh"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -u PATH grep leadv2-supervise.sh f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"exec -a name grep leadv2-supervise.sh f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"time cat leadv2-supervise.sh"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"{ echo leadv2-supervise.sh; }"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -S \\"grep leadv2-supervise.sh f\\""}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"if grep -q leadv2-supervise.sh f; then :; fi"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -- grep leadv2-supervise.sh f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"exec -- grep leadv2-supervise.sh f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"time -- cat leadv2-supervise.sh"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"timeout -- 1 cat leadv2-supervise.sh"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"xargs -- grep leadv2-supervise.sh f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env -a leadv2-supervise.sh grep pattern f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env --argv0 leadv2-supervise.sh grep pattern f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"env --argv0=leadv2-supervise.sh grep pattern f"}}\n'
  printf -- '{"type":"item.completed","item":{"type":"command_execution","command":"if true; then :; fi leadv2-supervise.sh"}}\n'
fi
if [[ "${STUB_MODE:-complete}" == "complete" && "${1:-}" == "exec" && "${2:-}" == "resume" ]]; then
  mkdir -p "$STUB_PROJECT_ROOT/docs/handoff/$STUB_TASK_ID"
  : > "$STUB_PROJECT_ROOT/docs/handoff/$STUB_TASK_ID/phase8-passed.flag"
fi
exit 0
STUB
chmod +x "$CODEX_STUB"

new_case() {
  local name="$1" task_id="$2" project
  project="$ROOT/$name"
  mkdir -p "$project/docs/leadv2" "$project/docs/handoff/$task_id"
  LEADV2_PROJECT_ROOT="$project" bash -c '
    set -euo pipefail
    source "'"$REGISTRY"'"
    leadv2_active_register "'"$task_id"'" Standard "$LEADV2_PROJECT_ROOT" test-branch true >/dev/null
  '
  printf -- '%s' "$project"
}

run_case() {
  local project="$1" task_id="$2" mode="$3" max_attempts="$4" trace
  trace="$project/codex.args"
  STUB_TRACE="$trace" STUB_MODE="$mode" STUB_PROJECT_ROOT="$project" STUB_TASK_ID="$task_id" \
  LEADV2_PROJECT_ROOT="$project" LEADV2_TASK_ID="$task_id" \
  LEADV2_SESSION_PROVIDER=codex LEADV2_CODEX_BIN="$CODEX_STUB" \
  LEADV2_LEAD_MODEL=gpt-5.6-terra LEADV2_LEAD_EFFORT=medium \
  LEADV2_RUNNER_MAX_ATTEMPTS="$max_attempts" LEADV2_RUNNER_RETRY_SLEEP_S=0 \
  LEADV2_CODEX_BYPASS_APPROVALS=0 \
    "$RUNNER"
}

receipt_statuses() {
  local yaml_file="$1" task_id="$2"
  python3 - "$yaml_file" "$task_id" <<'PYEOF'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
row = next(s for s in data.get("sessions", []) if s.get("task_id") == sys.argv[2])
print(",".join(str(r.get("status")) for r in row.get("provider_receipts", [])))
PYEOF
}

if bash -n "$RUNNER" && bash -n "$SCRIPTS_ROOT/leadv2-codex-session-runner.sh"; then
  pass "runner syntax"
else
  fail "runner syntax"
fi

# dispatch-reliability work of 2026-07-24 raised STALL_MAX 2 -> 6; read the runner's live
# default straight from source instead of re-hardcoding it, so the next tuning pass can't
# silently re-break this assertion the way it broke it before.
runner_stall_max="$(sed -n 's/^STALL_MAX="\${LEADV2_RUNNER_STALL_MAX:-\([0-9][0-9]*\)}".*/\1/p' "$RUNNER" | head -1)"
if [[ -z "$runner_stall_max" ]]; then
  fail "could not read STALL_MAX default from $RUNNER"
  runner_stall_max=6
fi

task_id="CODEX-SMOKE-COMPLETE"
project="$(new_case complete "$task_id")"
set +e
complete_out="$(run_case "$project" "$task_id" complete 3 2>&1)"
complete_rc=$?
set -e
statuses="$(receipt_statuses "$project/docs/leadv2/active.yaml" "$task_id")"
if [[ "$complete_rc" -eq 0 \
   && -f "$project/docs/handoff/$task_id/phase8-passed.flag" \
   && "$(<"$project/docs/handoff/$task_id/.session-runner.codex-thread-id")" == "codex-thread-test" \
   && "$(<"$project/codex.args")" == *"exec resume"* \
   && "$statuses" == *"turn_completed"* \
   && "$statuses" == *"complete"* ]]; then
  pass "fresh Codex thread resumes to the common Phase-8 sentinel with receipts"
else
  fail "complete case rc=$complete_rc statuses=$statuses out=$complete_out"
fi

task_id="CODEX-SMOKE-INCOMPLETE"
project="$(new_case incomplete "$task_id")"
set +e
incomplete_out="$(run_case "$project" "$task_id" incomplete 1 2>&1)"
incomplete_rc=$?
set -e
if [[ "$incomplete_rc" -eq 4 \
   && ! -f "$project/docs/handoff/$task_id/phase8-passed.flag" \
   && "$incomplete_out" == *"INCOMPLETE"* ]]; then
  pass "successful model turn without Phase-8 sentinel returns INCOMPLETE"
else
  fail "incomplete case rc=$incomplete_rc out=$incomplete_out"
fi

task_id="CODEX-SMOKE-NO-THREAD"
project="$(new_case no-thread "$task_id")"
set +e
no_thread_out="$(run_case "$project" "$task_id" no-thread 3 2>&1)"
no_thread_rc=$?
set -e
exec_count="$(grep -c '^exec ' "$project/codex.args" || true)"
if [[ "$no_thread_rc" -eq 3 && "$exec_count" -eq 1 \
   && "$no_thread_out" == *"refusing a blind fresh restart"* ]]; then
  pass "missing thread receipt fails closed without a blind restart"
else
  fail "no-thread case rc=$no_thread_rc exec_count=$exec_count out=$no_thread_out"
fi

task_id="CODEX-SMOKE-SHARED-RECEIPT"
project="$(new_case shared-receipt "$task_id")"
mkdir -p "$project/docs/leadv2/completions"
cat > "$project/docs/leadv2/completions/$task_id.json" <<EOF
{"schema_version":1,"task_id":"$task_id","status":"phase8_passed","assertions":"7/7"}
EOF
set +e
shared_out="$(run_case "$project" "$task_id" incomplete 1 2>&1)"
shared_rc=$?
set -e
if [[ "$shared_rc" -eq 0 && ! -f "$project/codex.args" \
   && "$shared_out" == *"Phase-8 completion proof already present"* ]]; then
  pass "validated shared receipt closes a main-checkout runner without a model call"
else
  fail "shared receipt case rc=$shared_rc out=$shared_out"
fi

task_id="CODEX-SMOKE-STALL-CAP"
project="$(new_case stall-cap "$task_id")"
set +e
stall_out="$(run_case "$project" "$task_id" incomplete 6 2>&1)"
stall_rc=$?
set -e
stall_calls="$(grep -c '^exec' "$project/codex.args" || true)"
if [[ "$stall_rc" -eq 4 && "$stall_calls" -eq "$runner_stall_max" \
   && "$stall_out" == *"CODEX-LEAD RECURSION suspected"* \
   && "$stall_out" == *"stopping early to prevent token-burning resumes"* ]]; then
  pass "stall_max turns without phase/git/handoff progress stop the runner (STALL_MAX=$runner_stall_max)"
else
  fail "stall cap case rc=$stall_rc calls=$stall_calls (expected $runner_stall_max) out=$stall_out"
fi

task_id="CODEX-SMOKE-RECURSION"
project="$(new_case recursion "$task_id")"
set +e
recursion_out="$(run_case "$project" "$task_id" recursion 6 2>&1)"
recursion_rc=$?
set -e
recursion_calls="$(grep -c '^exec' "$project/codex.args" || true)"
if [[ "$recursion_rc" -eq 5 && "$recursion_calls" -eq 1 \
   && "$recursion_out" == *"CODEX-LEAD RECURSION"* ]]; then
  pass "launcher self-invocation fails immediately before retrying"
else
  fail "recursion case rc=$recursion_rc calls=$recursion_calls out=$recursion_out"
fi

# --- CODEX-LEAD-RECURSION-01: round-1 positive shapes + regression (bash)

for shape in exec env if bash; do
  task_id="CODEX-SMOKE-RECURSION-${shape^^}"
  project="$(new_case "recursion-${shape}" "$task_id")"
  set +e
  shape_out="$(run_case "$project" "$task_id" "recursion-${shape}" 6 2>&1)"
  shape_rc=$?
  set -e
  shape_calls="$(grep -c '^exec' "$project/codex.args" || true)"
  if [[ "$shape_rc" -eq 5 && "$shape_calls" -eq 1 \
     && "$shape_out" == *"CODEX-LEAD RECURSION"* ]]; then
    pass "recursion via ${shape} wrapper is caught"
  else
    fail "recursion-${shape} case rc=$shape_rc calls=$shape_calls out=$shape_out"
  fi
done

# --- CORE-OFFLINE-CODEX-RECURSION-01: round-2 parser paths

for shape in env-split env-split-long time coproc coproc-direct coproc-unnamed-group; do
  task_id="CODEX-SMOKE-RECURSION-${shape^^}"
  project="$(new_case "recursion-${shape}" "$task_id")"
  set +e
  shape_out="$(run_case "$project" "$task_id" "recursion-${shape}" 6 2>&1)"
  shape_rc=$?
  set -e
  shape_calls="$(grep -c '^exec' "$project/codex.args" || true)"
  if [[ "$shape_rc" -eq 5 && "$shape_calls" -eq 1 \
     && "$shape_out" == *"CODEX-LEAD RECURSION"* ]]; then
    pass "round-2 recursion via ${shape} is caught"
  else
    fail "recursion-${shape} case rc=$shape_rc calls=$shape_calls out=$shape_out"
  fi
done

# `coproc CMD args...` has no NAME: CMD remains the program. A NAME is valid
# only before a compound group, whose inner grep operand must also remain safe.
for shape in coproc-direct coproc-named-group; do
  task_id="CODEX-SMOKE-FALSEKILL-${shape^^}"
  project="$(new_case "falsekill-${shape}" "$task_id")"
  set +e
  shape_out="$(run_case "$project" "$task_id" "negative-${shape}" 6 2>&1)"
  shape_rc=$?
  set -e
  shape_calls="$(grep -c '^exec' "$project/codex.args" || true)"
  if [[ "$shape_rc" -eq 4 && "$shape_calls" -eq "$runner_stall_max" \
     && "$shape_out" != *"CODEX-LEAD RECURSION:"* ]]; then
    pass "coproc ${shape} launcher mention does not trip falsekill"
  else
    fail "negative-${shape} case rc=$shape_rc calls=$shape_calls out=$shape_out"
  fi
done

# --- CODEX-LEAD-RECURSION-FALSEKILL-01: all known non-executing mentions

task_id="CODEX-SMOKE-FALSEKILL"
project="$(new_case falsekill "$task_id")"
set +e
falsekill_out="$(run_case "$project" "$task_id" negative 6 2>&1)"
falsekill_rc=$?
set -e
falsekill_calls="$(grep -c '^exec' "$project/codex.args" || true)"
if [[ "$falsekill_rc" -eq 4 && "$falsekill_calls" -eq "$runner_stall_max" \
   && "$falsekill_out" != *"CODEX-LEAD RECURSION:"* ]]; then
  pass "all launcher-mention, option-operand, closing-word, and sentinel shapes do not trip falsekill"
else
  fail "falsekill case rc=$falsekill_rc calls=$falsekill_calls out=$falsekill_out"
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf -- '[TEST] %s\n' "${ERRORS[@]}"
  exit 1
fi
