#!/usr/bin/env bash
# Offline intake tests for /leadv2 codex [task-id|next]. No provider/network.

set -euo pipefail
# shellcheck disable=SC1091  # path is resolved relative to this suite at runtime
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$TEST_DIR/../leadv2-codex-lead.sh"
PASS=0
FAIL=0
ERRORS=()
SUITE_ROOT="$(lv2_mktemp_dir "codex-lead-intake")"
trap 'rm -rf "$SUITE_ROOT"' EXIT

pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf -- '[TEST] FAIL: %s\n' "$1"; }

RUNNER_STUB="$SUITE_ROOT/runner-stub.sh"
cat > "$RUNNER_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
{
  printf -- 'argc=%s\n' "$#"
  for arg in "$@"; do printf -- 'arg=%s\n' "$arg"; done
  printf -- 'task=%s\n' "${LEADV2_TASK_ID:-}"
  printf -- 'root=%s\n' "${LEADV2_PROJECT_ROOT:-}"
  printf -- 'claude_root=%s\n' "${CLAUDE_PROJECT_DIR:-}"
  printf -- 'project_root=%s\n' "${PROJECT_ROOT:-}"
  printf -- 'cwd=%s\n' "$(pwd -P)"
} > "${STUB_TRACE:?STUB_TRACE is required}"
STUB
chmod +x "$RUNNER_STUB"

seed_project() {
  local name="$1" root
  root="$SUITE_ROOT/$name"
  mkdir -p "$root/docs" "$root/state" "$root/job-registry"
  root="$(cd "$root" && pwd -P)"
  git -C "$root" init -q
  git -C "$root" checkout -q -b main
  git -C "$root" config user.email codex-lead-test@example.invalid
  git -C "$root" config user.name codex-lead-test
  cat > "$root/docs/tasks.yaml" <<'YAML'
- id: TASK-BLOCKED
  lane: action
  priority: critical
  status: queued
  title: Blocked critical
  created_at: '2026-01-01T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: [DEP-PENDING]}
- id: TASK-HIGH
  lane: action
  priority: high
  status: queued
  title: Top eligible
  created_at: '2026-01-02T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
- id: TASK-EXPLICIT
  lane: action
  priority: medium
  status: queued
  title: Explicit eligible
  created_at: '2026-01-03T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
- id: DEP-PENDING
  lane: human-needed
  priority: low
  status: queued
  title: Pending dependency
  created_at: '2026-01-04T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
YAML
  printf -- 'seed\n' > "$root/README.md"
  git -C "$root" add README.md docs/tasks.yaml
  git -C "$root" commit -qm seed
  printf '%s' "$root"
}

task_sig() {
  printf '%s' "$1" | tr -d '\r' | tr -s '[:space:]' ' ' | \
    sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}'
}

task_state() {
  python3 - "$1/docs/tasks.yaml" "$2" <<'PYEOF'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or []
row = next(row for row in rows if str(row.get("id")) == sys.argv[2])
claim = row.get("claim") or {}
print(f"{row.get('status', '')}|{claim.get('by') or ''}")
PYEOF
}

wait_for_file() {
  local path="$1" i
  for ((i = 0; i < 100; i++)); do
    [[ -f "$path" ]] && return 0
    sleep 0.02
  done
  return 1
}

run_wrapper() {
  local root="$1" request="$2" job_root="${3:-$1/job-registry}"
  env -u LEADV2_DISPATCH_TERMINAL_LEDGER_FILE \
    -u LEADV2_CODEX_LEAD_TERMINAL_LEDGER_FILE \
    STUB_TRACE="$root/runner.args" \
    LEADV2_PROJECT_ROOT="$root" \
    LEADV2_STATE_ROOT="$root/state" \
    LEADV2_LANE_WORKTREE_ERRF="$root/state/lane-worktree.err" \
    LEADV2_CODEX_LEAD_DISPATCH_LEDGER_FILE="$root/dispatch-ledger.jsonl" \
    LEADV2_JOB_REGISTRY_ROOT="$job_root" \
    LEADV2_CODEX_LEAD_RUNNER_BIN="$RUNNER_STUB" \
    bash "$WRAPPER" "$request"
}

test_next_and_exact_runner_contract() {
  local root out rc sig sig8 trace lane
  root="$(seed_project next)"
  set +e
  out="$(run_wrapper "$root" next 2>&1)"
  rc=$?
  set -e
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"
  lane="$root/.claude/worktrees/TASK-HIGH"
  wait_for_file "$root/runner.args" || true
  trace="$(cat "$root/runner.args" 2>/dev/null || true)"

  if [[ $rc -eq 0 \
     && "$out" == *"chosen task: TASK-HIGH (signature=$sig8)"* \
     && "$out" == *"worktree: $lane"* \
     && "$out" == *"relay sentinel (shared root): $root/docs/handoff/TASK-HIGH/phase8-passed.flag"* \
     && "$out" == *"relay sentinel (worktree mirror): $lane/docs/handoff/TASK-HIGH/phase8-passed.flag"* \
     && "$trace" == *$'argc=0\ntask=TASK-HIGH'* \
     && "$trace" == *"root=$root"* \
     && "$trace" == *"claude_root=$root"* \
     && "$trace" == *"project_root=$root"* \
     && "$trace" == *"cwd=$lane"* \
     && -d "$lane" \
     && ! -L "$lane" \
     && ! -e "$root/.claude/worktrees/$sig8" \
     && "$(git -C "$lane" branch --show-current)" == "worktree-TASK-HIGH" ]]; then
    pass 'next uses shared root envs, lane cwd, zero args, and names both sentinel paths'
  else
    fail "next/runner contract rc=$rc out=$out trace=$trace"
  fi
}

test_next_skips_poisoned_rows() {
  local root out rc poison_state marker_state safe_state
  root="$(seed_project poisoned-next)"
  cat > "$root/docs/tasks.yaml" <<'YAML'
- id: POISON-TOP
  lane: recovery
  priority: 999
  status: queued
  title: Poisoned numeric row
  intent: DUPLICATE - DO NOT DISPATCH. Replaced by TASK-SAFE.
  created_at: '2026-01-01T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
- id: POISON-MARKER
  lane: recovery
  priority: critical
  status: queued
  title: Poisoned intent row
  intent: Hold this row - DO NOT DISPATCH automatically
  created_at: '2026-01-02T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
- id: TASK-SAFE
  lane: action
  priority: high
  status: queued
  title: Safe eligible
  intent: Implement the safe task
  created_at: '2026-01-03T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
YAML
  git -C "$root" add docs/tasks.yaml
  git -C "$root" commit -qm poisoned-next

  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  wait_for_file "$root/runner.args" || true
  poison_state="$(task_state "$root" POISON-TOP)"
  marker_state="$(task_state "$root" POISON-MARKER)"
  safe_state="$(task_state "$root" TASK-SAFE)"
  if [[ $rc -eq 0 && "$out" == *'chosen task: TASK-SAFE'* \
     && "$poison_state" == 'queued|' && "$marker_state" == 'queued|' \
     && "$safe_state" == in_progress\|codex-lead:* \
     && ! -e "$root/.claude/worktrees/POISON-TOP" \
     && ! -e "$root/.claude/worktrees/POISON-MARKER" \
     && -d "$root/.claude/worktrees/TASK-SAFE" ]]; then
    pass 'next skips reserved priority and duplicate-marker rows before claiming the next eligible task'
  else
    fail "poisoned next rc=$rc out=$out poison=$poison_state marker=$marker_state safe=$safe_state"
  fi
}

test_next_refuses_all_poisoned_queue() {
  local root out rc poison_state marker_state
  root="$(seed_project all-poisoned)"
  cat > "$root/docs/tasks.yaml" <<'YAML'
- id: POISON-ONLY
  lane: recovery
  priority: 999
  status: queued
  title: Poisoned numeric row
  intent: DUPLICATE - DO NOT DISPATCH
  created_at: '2026-01-01T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
- id: POISON-MARKER
  lane: action
  priority: high
  status: queued
  title: Poisoned intent row
  intent: DO NOT DISPATCH without re-planning
  created_at: '2026-01-02T00:00:00Z'
  claim: {by: null, lease_expires: null}
  context: {depends_on: []}
YAML
  git -C "$root" add docs/tasks.yaml
  git -C "$root" commit -qm all-poisoned

  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  poison_state="$(task_state "$root" POISON-ONLY)"
  marker_state="$(task_state "$root" POISON-MARKER)"
  if [[ $rc -ne 0 \
     && "$out" == *'no eligible task remains after poisoned-row filtering'* \
     && "$out" == *'POISON-ONLY:reserved-priority=999'* \
     && "$out" == *'POISON-MARKER:duplicate-marker'* \
     && "$poison_state" == 'queued|' && "$marker_state" == 'queued|' \
     && ! -e "$root/.claude/worktrees/POISON-ONLY" \
     && ! -e "$root/.claude/worktrees/POISON-MARKER" \
     && ! -e "$root/runner.args" ]]; then
    pass 'an all-poisoned queue refuses clearly without claiming or creating a lane'
  else
    fail "all-poisoned rc=$rc out=$out poison=$poison_state marker=$marker_state"
  fi
}

test_explicit_task_id() {
  local root out rc trace
  root="$(seed_project explicit)"
  set +e
  out="$(run_wrapper "$root" TASK-EXPLICIT 2>&1)"
  rc=$?
  set -e
  wait_for_file "$root/runner.args" || true
  trace="$(cat "$root/runner.args" 2>/dev/null || true)"
  if [[ $rc -eq 0 && "$out" == *'chosen task: TASK-EXPLICIT'* \
     && "$trace" == *$'argc=0\ntask=TASK-EXPLICIT'* ]]; then
    pass 'explicit task id resolves independently of queue priority'
  else
    fail "explicit resolution rc=$rc out=$out trace=$trace"
  fi
}

test_duplicate_ledger_and_live_handle_refusal() {
  local root sig sig8 out rc state ledger_ok=0 handle_ok=0 claim_ok=0 now

  root="$(seed_project duplicate-ledger)"
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"; now="$(date +%s)"
  printf -- '{"task_sig":"%s","state":"pending","created_epoch":%s,"token":"existing"}\n' \
    "$sig" "$now" > "$root/dispatch-ledger.jsonl"
  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  state="$(task_state "$root" TASK-HIGH)"
  if [[ $rc -ne 0 && "$out" == *'dispatch ledger has an open pending row'* \
     && "$state" == 'queued|' && ! -e "$root/.claude/worktrees/$sig8" \
     && ! -e "$root/.claude/worktrees/TASK-HIGH" \
     && ! -e "$root/runner.args" ]]; then
    ledger_ok=1
  fi

  root="$(seed_project duplicate-handle)"
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"
  mkdir -p "$root/job-registry/existing"
  printf -- '%s\t2026-08-03T00:00:00Z\tcodex-lead\tTASK-HIGH\n' \
    "$root/.claude/worktrees/TASK-HIGH" > "$root/job-registry/existing/codex-lead-$sig8"
  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  state="$(task_state "$root" TASK-HIGH)"
  if [[ $rc -ne 0 && "$out" == *'job registry has live handle'* \
     && "$state" == 'queued|' && ! -e "$root/.claude/worktrees/$sig8" \
     && ! -e "$root/.claude/worktrees/TASK-HIGH" \
     && ! -e "$root/runner.args" ]]; then
    handle_ok=1
  fi

  root="$(seed_project duplicate-active-claim)"
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"
  cat > "$root/state/active.yaml" <<YAML
meta: {}
sessions:
  - task_id: TASK-HIGH
    status: claimed
    phase: intake
    pid: $$
YAML
  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  state="$(task_state "$root" TASK-HIGH)"
  if [[ $rc -ne 0 && "$out" == *'active registry has a live claim'* \
     && "$state" == 'queued|' && ! -e "$root/.claude/worktrees/$sig8" \
     && ! -e "$root/.claude/worktrees/TASK-HIGH" \
     && ! -e "$root/runner.args" ]]; then
    claim_ok=1
  fi

  if [[ $ledger_ok -eq 1 && $handle_ok -eq 1 && $claim_ok -eq 1 ]]; then
    pass 'open ledger rows, live job handles, and active claims refuse without queue claim or launch'
  else
    fail "duplicate guards ledger_ok=$ledger_ok handle_ok=$handle_ok claim_ok=$claim_ok out=$out state=$state"
  fi
}

test_terminal_ledger_refuses_landed_and_dead() {
  local terminal root sig sig8 out rc state ok_count=0
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"
  for terminal in landed dead; do
    root="$(seed_project "terminal-$terminal")"
    printf -- '{"task_sig":"%s","terminal":"%s","task_id":"TASK-HIGH"}\n' \
      "$sig8" "$terminal" > "$root/state/dispatch-ledger.jsonl"
    set +e
    out="$(run_wrapper "$root" next 2>&1)"; rc=$?
    set -e
    state="$(task_state "$root" TASK-HIGH)"
    if [[ $rc -ne 0 && "$out" == *"terminal ledger records $terminal for signature $sig8"* \
       && "$state" == 'queued|' \
       && ! -e "$root/.claude/worktrees/TASK-HIGH" \
       && ! -e "$root/runner.args" ]]; then
      ok_count=$((ok_count + 1))
    fi
  done
  if [[ $ok_count -eq 2 ]]; then
    pass 'terminal ledger landed and dead outcomes both refuse before claim or launch'
  else
    fail "terminal refusals ok_count=$ok_count terminal=$terminal rc=$rc out=$out state=$state"
  fi
}

test_retryable_terminal_warns_and_allows() {
  local terminal root sig sig8 out rc trace ok_count=0
  sig="$(task_sig 'Explicit eligible')"; sig8="${sig:0:8}"
  for terminal in parked refused no_work; do
    root="$(seed_project "terminal-retry-$terminal")"
    printf -- '{"task_sig":"%s","terminal":"%s","task_id":"TASK-EXPLICIT"}\n' \
      "$sig8" "$terminal" > "$root/state/dispatch-ledger.jsonl"
    set +e
    out="$(run_wrapper "$root" TASK-EXPLICIT 2>&1)"; rc=$?
    set -e
    wait_for_file "$root/runner.args" || true
    trace="$(cat "$root/runner.args" 2>/dev/null || true)"
    if [[ $rc -eq 0 \
       && "$out" == *"warning: prior terminal $terminal for signature $sig8; retry remains allowed"* \
       && "$out" == *'chosen task: TASK-EXPLICIT'* \
       && "$trace" == *$'argc=0\ntask=TASK-EXPLICIT'* ]]; then
      ok_count=$((ok_count + 1))
    fi
  done
  if [[ $ok_count -eq 3 ]]; then
    pass 'parked, refused, and no_work terminals warn while allowing a retry'
  else
    fail "retryable terminals ok_count=$ok_count terminal=$terminal rc=$rc out=$out trace=$trace"
  fi
}

test_failure_rolls_back_claim_and_worktree() {
  local root sig sig8 out rc state blocked_job_root
  root="$(seed_project rollback)"
  sig="$(task_sig 'Top eligible')"; sig8="${sig:0:8}"
  blocked_job_root="$root/job-registry-blocker"
  printf -- 'not a directory\n' > "$blocked_job_root"

  set +e
  out="$(run_wrapper "$root" next "$blocked_job_root" 2>&1)"; rc=$?
  set -e
  state="$(task_state "$root" TASK-HIGH)"
  if [[ $rc -ne 0 && "$out" == *'could not create job registry entry'* \
     && "$state" == 'pending|' \
     && ! -e "$root/.claude/worktrees/TASK-HIGH" \
     && ! -e "$root/docs/handoff/TASK-HIGH" \
     && ! -e "$root/runner.args" ]] \
     && ! git -C "$root" show-ref --verify --quiet refs/heads/worktree-TASK-HIGH; then
    pass 'post-guard launch failure removes claim, canonical lane, branch, and handoff residue'
  else
    fail "rollback rc=$rc out=$out state=$state"
  fi
}

test_advisory_is_first_line() {
  local root out rc first
  root="$(seed_project advisory)"
  printf -- '[]\n' > "$root/docs/tasks.yaml"
  set +e
  out="$(run_wrapper "$root" next 2>&1)"; rc=$?
  set -e
  first="${out%%$'\n'*}"
  if [[ $rc -ne 0 && "$first" == *'use /model sonnet'* && "$first" == *'thinking runs on Codex'* ]]; then
    pass 'the /model sonnet advisory is emitted first, including on refusal'
  else
    fail "advisory rc=$rc first=$first"
  fi
}

main() {
  if bash -n "$WRAPPER" && bash -n "$RUNNER_STUB"; then
    pass 'wrapper and test runner stub syntax'
  else
    fail 'wrapper or test runner stub syntax'
  fi
  test_next_and_exact_runner_contract
  test_next_skips_poisoned_rows
  test_next_refuses_all_poisoned_queue
  test_explicit_task_id
  test_duplicate_ledger_and_live_handle_refusal
  test_terminal_ledger_refuses_landed_and_dead
  test_retryable_terminal_warns_and_allows
  test_failure_rolls_back_claim_and_worktree
  test_advisory_is_first_line

  printf -- '[TEST] Results: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf -- '[TEST] Failures:\n'
    printf -- '  %s\n' "${ERRORS[@]}"
    exit 1
  fi
}

main "$@"
