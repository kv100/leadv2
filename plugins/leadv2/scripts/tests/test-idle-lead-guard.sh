#!/usr/bin/env bash
# tests/test-idle-lead-guard.sh — IDLE-LEAD-GUARD-01 fixture test.
#
# Fully isolated: all four test-only env overrides
# (LEADV2_IDLE_GUARD_TASKS_FILE, LEADV2_IDLE_GUARD_LIVENESS_SH,
#  LEADV2_IDLE_GUARD_QUESTIONS_DIR, LEADV2_IDLE_GUARD_STATE_DIR)
# point at throwaway tmp dirs / stub scripts so no real git worktree,
# real lane, or real question store is needed.
#
# Run: bash plugins/leadv2/scripts/tests/test-idle-lead-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-idle-lead-guard.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMPROOT=""
cleanup() {
  # Case 11 chmod's FIXTURE_STATE to 555; restore write perms before rm -rf,
  # else the removal silently fails and the temp dir leaks.
  [[ -n "${FIXTURE_STATE:-}" && -d "$FIXTURE_STATE" ]] && chmod 755 "$FIXTURE_STATE" 2>/dev/null
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] && chmod -R u+w "$TMPROOT" 2>/dev/null
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] && rm -rf "$TMPROOT"
  return 0
}
trap cleanup EXIT

# ── fixture builder ──────────────────────────────────────────────────────────
# Creates a temp project dir with:
#   - docs/leadv2/  (R6 gate)
#   - docs/tasks.yaml (populated per args)
#   - questions/ dir (empty or with a pending question)
#   - stub-liveness.sh (echoes canned JSON)
# Returns paths via globals: FIXTURE_ROOT, FIXTURE_TASKS, FIXTURE_QDIR,
#   FIXTURE_STATE, FIXTURE_LIVENESS
setup_fixture() {
  local tasks_yaml="$1"
  local liveness_json="$2"
  local pending_question="${3:-no}"

  TMPROOT="$(mktemp -d)"
  FIXTURE_ROOT="$TMPROOT/project"
  FIXTURE_TASKS="$FIXTURE_ROOT/docs/tasks.yaml"
  FIXTURE_QDIR="$TMPROOT/questions"
  FIXTURE_STATE="$TMPROOT/state"
  FIXTURE_LIVENESS="$TMPROOT/stub-liveness.sh"

  mkdir -p "$FIXTURE_ROOT/docs/leadv2" "$FIXTURE_QDIR" "$FIXTURE_STATE"

  printf '%s\n' "$tasks_yaml" > "$FIXTURE_TASKS"

  if [[ "$pending_question" == "yes" ]]; then
    printf 'status: pending\nquestion: "Should we proceed?"\n' > "$FIXTURE_QDIR/q001.yaml"
  fi

  # Stub liveness script that echoes the canned JSON
  # The single quotes around the JSON prevent bash brace expansion
  printf '#!/usr/bin/env bash\nprintf %%s '\''%s'\''\n' "$liveness_json" > "$FIXTURE_LIVENESS"
  chmod +x "$FIXTURE_LIVENESS"
}

# Builds an isolated copy of the hook under $TMPROOT/isolated/hooks/, whose
# sibling scripts/ dir has NO leadv2-state-path.sh — simulates a broken
# plugin install for case 12. Sets FIXTURE_HOOK_SH.
setup_hook_copy_without_statepath() {
  mkdir -p "$TMPROOT/isolated/hooks" "$TMPROOT/isolated/scripts"
  cp "$HOOK_SH" "$TMPROOT/isolated/hooks/leadv2-idle-lead-guard.sh"
  chmod +x "$TMPROOT/isolated/hooks/leadv2-idle-lead-guard.sh"
  FIXTURE_HOOK_SH="$TMPROOT/isolated/hooks/leadv2-idle-lead-guard.sh"
}

# ── hook runner ──────────────────────────────────────────────────────────────
# Pipes a JSON payload to the hook, captures stdout, stderr, rc.
# Uses globals: HOOK_OUT, HOOK_ERR, HOOK_RC
# Optional 3rd arg overrides the hook path (default $HOOK_SH).
run_hook() {
  local payload="$1"
  local extra_env="$2"
  local hook_path="${3:-$HOOK_SH}"

  HOOK_OUT="$(eval "$extra_env" "$hook_path" 2>"$TMPROOT/err.txt" <<<"$payload" || true)"
  HOOK_RC=$?
  HOOK_ERR="$(cat "$TMPROOT/err.txt" 2>/dev/null || true)"
}

PAYLOAD='{"session_id":"test-sess-idle","cwd":"PLACEHOLDER","stop_hook_active":false}'

# ════════════════════════════════════════════════════════════════════════════
# Case 1: 2 queued rows, count_live=0, no pending question → BLOCK
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
- id: task-bbb
  status: queued
  lane: side
  title: "Fix bug B"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if printf '%s' "$HOOK_OUT" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["decision"] == "block", "decision is not block"
assert "task-aaa" in d["reason"], "reason missing task-aaa"
' 2>/dev/null; then
    pass "case 1: queued+0live blocks with reason naming task id"
  else
    fail "case 1: expected block with task-aaa, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 2: 2 queued rows, count_live=1 → allow (empty stdout)
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
- id: task-bbb
  status: queued
  lane: side
  title: "Fix bug B"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":1}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 2: queued+1live allows stop (empty stdout)"
  else
    fail "case 2: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 3: only done rows → allow
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-done
  status: done
  lane: main
  title: "Completed task"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 3: no queued work allows stop"
  else
    fail "case 3: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4: queued+0live but pending question → allow
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}' yes
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 4: pending question allows stop"
  else
    fail "case 4: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5: loop block 9×, 1-8 block, 9th allows + warns
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  # We need the counter to persist across invocations within this case.
  # Each run_hook call creates fresh TMPROOT, so we use a fixed state dir.
  SHARED_STATE="$TMPROOT/shared-state"
  mkdir -p "$SHARED_STATE"

  # Default cap is 8, so 8 blocks then 9th allows
  LEADV2_ENV="LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$SHARED_STATE"

  blocked_count=0
  for i in $(seq 1 8); do
    run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
    if printf '%s' "$HOOK_OUT" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["decision"] == "block"
' 2>/dev/null; then
      blocked_count=$((blocked_count + 1))
    fi
  done

  # 9th call: should allow (cap reached), stderr warning, empty stdout
  run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"

  if [[ $blocked_count -eq 8 && -z "$HOOK_OUT" && "$HOOK_ERR" == *"IDLE-LEAD-GUARD"* && "$HOOK_ERR" == *"cap"* ]]; then
    pass "case 5: 8 blocks then 9th allows with cap warning"
  else
    fail "case 5: blocked=$blocked_count, 9th out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 6: LEADV2_IDLE_GUARD=0 → allow (kill switch)
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=0 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" && -z "$HOOK_ERR" ]]; then
    pass "case 6: kill switch allows stop silently"
  else
    fail "case 6: expected empty stdout+stderr, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 7a: malformed stdin → allow
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture '- id: x
  status: queued
  lane: main
  title: "X"' '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  HOOK_OUT="$(LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS \
    LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS \
    LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR \
    LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE \
    "$HOOK_SH" 2>/dev/null <<<'not json at all' || true)"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 7a: malformed stdin allows stop"
  else
    fail "case 7a: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 7b: tasks.yaml deleted → allow
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture '- id: x
  status: queued
  lane: main
  title: "X"' '{"availability":"authoritative","count_live":0}'
  rm -f "$FIXTURE_TASKS"
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 7b: deleted tasks.yaml allows stop"
  else
    fail "case 7b: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 7c: liveness script absent → allow
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture '- id: x
  status: queued
  lane: main
  title: "X"' '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$TMPROOT/nonexistent.sh LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 7c: absent liveness probe allows stop"
  else
    fail "case 7c: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 7d: liveness unavailable → allow
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture '- id: x
  status: queued
  lane: main
  title: "X"' '{"availability":"unavailable"}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 7d: unavailable liveness allows stop"
  else
    fail "case 7d: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 8: no docs/leadv2/ → allow
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture '- id: x
  status: queued
  lane: main
  title: "X"' '{"availability":"authoritative","count_live":0}'
  rm -rf "$FIXTURE_ROOT/docs/leadv2"
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]]; then
    pass "case 8: no docs/leadv2/ allows stop"
  else
    fail "case 8: expected empty stdout, got: $HOOK_OUT"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 9: counter reset after an allowing stop
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  SHARED_STATE="$TMPROOT/shared-state-9"
  mkdir -p "$SHARED_STATE"
  LEADV2_ENV="LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$SHARED_STATE"

  # 1st: block (counter → 1)
  run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
  local_block_1="$HOOK_OUT"

  # 2nd: change to allow condition (1 live lane) — counter resets to 0
  printf '#!/usr/bin/env bash\nprintf %%s '\''%s'\''\n' '{"availability":"authoritative","count_live":1}' > "$FIXTURE_LIVENESS"
  run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
  local_allow="$HOOK_OUT"

  # 3rd: back to block condition — counter should be 1 again (was reset)
  printf '#!/usr/bin/env bash\nprintf %%s '\''%s'\''\n' '{"availability":"authoritative","count_live":0}' > "$FIXTURE_LIVENESS"
  run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
  local_block_2="$HOOK_OUT"

  # Verify counter file contains "1" after the third call
  counter_val="$(cat "$SHARED_STATE/leadv2-idle-guard-test-sess-idle.count" 2>/dev/null || printf '?')"

  if printf '%s' "$local_block_1" | python3 -c 'import sys,json; assert json.loads(sys.stdin.read())["decision"]=="block"' 2>/dev/null \
    && [[ -z "$local_allow" ]] \
    && printf '%s' "$local_block_2" | python3 -c 'import sys,json; assert json.loads(sys.stdin.read())["decision"]=="block"' 2>/dev/null \
    && [[ "$counter_val" == "1" ]]; then
    pass "case 9: counter resets on allow, re-blocks from 1"
  else
    fail "case 9: counter=$counter_val block1=$local_block_1 allow=$local_allow block2=$local_block_2"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 10: hooks.json registration assertion
# ════════════════════════════════════════════════════════════════════════════
{
  HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
  if python3 -c '
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
stop_hooks = d["hooks"]["Stop"][0]["hooks"]
ids = [h["command"] for h in stop_hooks]
# Must contain idle-lead-guard
assert any("leadv2-idle-lead-guard.sh" in c for c in ids), f"idle-lead-guard not found in {ids}"
# Must be after promise-guard
pg_idx = next(i for i, c in enumerate(ids) if "leadv2-promise-guard.sh" in c)
ig_idx = next(i for i, c in enumerate(ids) if "leadv2-idle-lead-guard.sh" in c)
assert ig_idx > pg_idx, f"idle-guard (idx {ig_idx}) must be after promise-guard (idx {pg_idx})"
# Must be the last entry
assert ig_idx == len(ids) - 1, f"idle-guard is not last (idx {ig_idx}, last {len(ids)-1})"
' "$HOOKS_JSON" 2>/dev/null; then
    pass "case 10: hooks.json has idle-lead-guard last after promise-guard"
  else
    fail "case 10: registration assertion failed"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 11: unwritable state dir (chmod 555) + queued + 0 live → ALLOWS every
# call, no {"decision":"block"} on any of 10 consecutive calls (F1).
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"
  LEADV2_ENV="LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  chmod 555 "$FIXTURE_STATE"

  all_empty=1
  check_calls=""
  for i in $(seq 1 10); do
    run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
    if [[ -n "$HOOK_OUT" ]]; then
      all_empty=0
    fi
    if [[ "$i" == 2 || "$i" == 5 || "$i" == 10 ]]; then
      if [[ -n "$HOOK_OUT" ]]; then
        check_calls="${check_calls}call${i}=NONEMPTY(${HOOK_OUT}) "
      else
        check_calls="${check_calls}call${i}=empty "
      fi
    fi
  done

  chmod 755 "$FIXTURE_STATE"

  if [[ "$all_empty" == 1 ]]; then
    pass "case 11: unwritable state dir allows stop on all 10 calls (${check_calls})"
  else
    fail "case 11: expected empty stdout on every call, got: ${check_calls}"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 12: leadv2-state-path.sh unresolvable (absent sibling script), a real
# pending question exists, QUESTIONS_DIR override unset → ALLOWS, stderr
# names the resolution failure (F2).
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}' yes
  setup_hook_copy_without_statepath
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  # LEADV2_IDLE_GUARD_QUESTIONS_DIR deliberately unset — forces the
  # leadv2-state-path.sh resolution path, which is absent in the isolated copy.
  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE" \
    "$FIXTURE_HOOK_SH"

  if [[ -z "$HOOK_OUT" ]] && [[ "$HOOK_ERR" == *"questions dir unresolvable"* ]]; then
    pass "case 12: unresolvable questions dir allows stop, stderr names it"
  else
    fail "case 12: expected empty stdout + 'questions dir unresolvable' stderr, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 13: QDIR resolvable and contains a pending question → ALLOWS, stderr
# names "question pending" and the question id.
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}' yes
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE"

  if [[ -z "$HOOK_OUT" ]] && [[ "$HOOK_ERR" == *"question pending"* ]] && [[ "$HOOK_ERR" == *"q001"* ]]; then
    pass "case 13: pending question allows stop, stderr names id"
  else
    fail "case 13: expected empty stdout + 'question pending (q001)' stderr, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 14: writable state dir, regression guard — still reaches the cap at 8
# (proves F1's fix did not disable the cap).
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  SHARED_STATE="$TMPROOT/shared-state-14"
  mkdir -p "$SHARED_STATE"
  LEADV2_ENV="LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$SHARED_STATE"

  blocked_count=0
  for i in $(seq 1 8); do
    run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"
    if printf '%s' "$HOOK_OUT" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["decision"] == "block"
' 2>/dev/null; then
      blocked_count=$((blocked_count + 1))
    fi
  done

  run_hook "$PAYLOAD_CWD" "$LEADV2_ENV"

  if [[ $blocked_count -eq 8 && -z "$HOOK_OUT" && "$HOOK_ERR" == *"cap reached (8/8)"* ]]; then
    pass "case 14: writable state dir still reaches cap at 8/8"
  else
    fail "case 14: blocked=$blocked_count, 9th out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 15: session-goal.yaml present but unsatisfiable → behaves like case 1
# (still blocks). Proves the goal file cannot accidentally suppress a
# legitimate block (F5.1).
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  # NOTE: the design's fixture used {task-aaa: queued} as the "unsatisfiable"
  # goal, but task-aaa's actual status IS "queued" — under the exact-match
  # tasks_status semantics defined in §5.1 that is trivially SATISFIED, the
  # opposite of what the case intends to prove. Using {task-aaa: done}
  # instead: genuinely unsatisfied (the task is still queued, not done),
  # which is what "goal present, not reached, still blocks" requires.
  GOAL_FILE="$TMPROOT/session-goal-15.yaml"
  printf 'goal: "close IDLE-LEAD-GUARD-01"\ndone_when:\n  tasks_status: {task-aaa: done}\n' > "$GOAL_FILE"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE LEADV2_IDLE_GUARD_GOAL_FILE=$GOAL_FILE"

  if printf '%s' "$HOOK_OUT" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["decision"] == "block", "decision is not block"
' 2>/dev/null; then
    pass "case 15: unsatisfied goal does not suppress a legitimate block"
  else
    fail "case 15: expected block, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 16: session-goal.yaml with file_exists pointing at a file that exists,
# plus a queued row and 0 live lanes → ALLOWS, stderr names "goal reached".
# ════════════════════════════════════════════════════════════════════════════
{
  TASKS_YAML='- id: task-aaa
  status: queued
  lane: main
  title: "Implement feature A"
'
  setup_fixture "$TASKS_YAML" '{"availability":"authoritative","count_live":0}'
  PAYLOAD_CWD="${PAYLOAD/PLACEHOLDER/$FIXTURE_ROOT}"

  RESULT_FILE="$FIXTURE_ROOT/docs/handoff/x/result.md"
  mkdir -p "$(dirname "$RESULT_FILE")"
  printf 'done\n' > "$RESULT_FILE"

  GOAL_FILE="$TMPROOT/session-goal-16.yaml"
  printf 'goal: "close IDLE-LEAD-GUARD-01"\ndone_when:\n  file_exists: docs/handoff/x/result.md\n' > "$GOAL_FILE"

  run_hook "$PAYLOAD_CWD" \
    "LEADV2_IDLE_GUARD=1 LEADV2_IDLE_GUARD_TASKS_FILE=$FIXTURE_TASKS LEADV2_IDLE_GUARD_LIVENESS_SH=$FIXTURE_LIVENESS LEADV2_IDLE_GUARD_QUESTIONS_DIR=$FIXTURE_QDIR LEADV2_IDLE_GUARD_STATE_DIR=$FIXTURE_STATE LEADV2_IDLE_GUARD_GOAL_FILE=$GOAL_FILE"

  if [[ -z "$HOOK_OUT" ]] && [[ "$HOOK_ERR" == *"goal reached"* ]]; then
    pass "case 16: satisfied file_exists goal allows stop"
  else
    fail "case 16: expected empty stdout + 'goal reached' stderr, got: out=$HOOK_OUT err=$HOOK_ERR"
  fi
}

# ── summary ──────────────────────────────────────────────────────────────────
printf -- '\n[TEST] idle-lead-guard: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
for e in "${ERRORS[@]:-}"; do printf -- '[TEST] %s\n' "$e"; done
(( FAIL == 0 ))
