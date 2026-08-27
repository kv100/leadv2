#!/usr/bin/env bash
# tests/test-continuation-guard.sh — CONTINUATION-GUARD-01 hermetic test suite.
#
# Fully isolated: all state under mktemp sandbox. No reads of ~/.claude or
# real repo state. Creates synthetic active.yaml, transcript JSONL, and flag
# files inside a temp dir, then pipes JSON payloads to the hook.
#
# Run: bash plugins/leadv2/scripts/tests/test-continuation-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-continuation-guard.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMPROOT=""
cleanup() {
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] && rm -rf "$TMPROOT"
  return 0
}
trap cleanup EXIT

# ── fixture builder ──────────────────────────────────────────────────────────
# Creates a temp project dir with configurable state.
# Args:
#   $1 = active.yaml content (empty string = no active.yaml)
#   $2 = "closed" or "open" — whether phase8-passed.flag exists
# Globals set: FIXTURE_ROOT, FIXTURE_TRANSCRIPT, FIXTURE_SENTINEL_DIR
setup_fixture() {
  local active_yaml_content="$1"
  local closed_state="$2"

  TMPROOT="$(mktemp -d)"
  FIXTURE_ROOT="$TMPROOT/project"
  FIXTURE_SENTINEL_DIR="$TMPROOT/sentinels"

  mkdir -p "$FIXTURE_ROOT/docs/leadv2" "$FIXTURE_ROOT/docs/handoff/TEST-TASK-01" \
           "$FIXTURE_SENTINEL_DIR"

  if [[ -n "$active_yaml_content" ]]; then
    printf '%s\n' "$active_yaml_content" > "$FIXTURE_ROOT/docs/leadv2/active.yaml"
  fi

  if [[ "$closed_state" == "closed" ]]; then
    touch "$FIXTURE_ROOT/docs/handoff/TEST-TASK-01/phase8-passed.flag"
  fi

  FIXTURE_TRANSCRIPT="$FIXTURE_ROOT/transcript.jsonl"
}

# Build a transcript JSONL with given assistant tool_use blocks and final text.
# Args:
#   $1 = JSON array of tool_use blocks (or "[]" for none)
#   $2 = final assistant text (or "")
write_transcript() {
  local tool_blocks="$1"
  local final_text="$2"

  # User message (boundary)
  printf '{"type":"user","message":{"role":"user","content":"go"}}\n' > "$FIXTURE_TRANSCRIPT"

  # Assistant record with tool_use blocks (if any)
  if [[ "$tool_blocks" != "[]" ]]; then
    printf '{"type":"assistant","message":{"role":"assistant","content":%s}}\n' \
      "$tool_blocks" >> "$FIXTURE_TRANSCRIPT"
  fi

  # Final assistant record with text
  local escaped_text
  escaped_text="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$final_text" 2>/dev/null || echo '""')"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' \
    "$escaped_text" >> "$FIXTURE_TRANSCRIPT"
}

# ── hook runner ──────────────────────────────────────────────────────────────
# Pipes a JSON payload to the hook, captures stdout, rc.
# Uses globals: HOOK_OUT, HOOK_RC
# Args:
#   $1 = extra env (e.g. "LEADV2_TASK_ID=foo")
#   $2 = stop_hook_active (true/false)
run_hook() {
  local extra_env="$1"
  local stop_active="$2"

  local payload
  payload="$(python3 -c '
import json, sys
print(json.dumps({
    "session_id": "test-sess-cg01",
    "stop_hook_active": sys.argv[1] == "true",
    "cwd": sys.argv[2],
    "transcript_path": sys.argv[3]
}))
' "$stop_active" "$FIXTURE_ROOT" "$FIXTURE_TRANSCRIPT" 2>/dev/null)"

  HOOK_OUT="$(eval "$extra_env LEADV2_CONTINUATION_GUARD_SENTINEL_DIR='$FIXTURE_SENTINEL_DIR'" \
    "$HOOK_SH" 2>/dev/null <<<"$payload" || true)"
  HOOK_RC=$?
}

# ── helpers ──────────────────────────────────────────────────────────────────

# Check that hook output is a block decision.
is_block() {
  [[ -z "$1" ]] && return 1
  echo "$1" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); exit(0 if d.get("decision")=="block" else 1)' 2>/dev/null
}

# Check that hook output is NOT a block decision (empty output = allow).
is_allow() {
  [[ -z "$1" ]] && return 0
  echo "$1" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); exit(0 if d.get("decision")!="block" else 1)' 2>/dev/null
}

ACTIVE_YAML_OPEN='sessions:
  - task_id: TEST-TASK-01
    phase: build'

ACTIVE_YAML_CLOSED='sessions:
  - task_id: TEST-TASK-01
    phase: close'

# ════════════════════════════════════════════════════════════════════════════
# Case 1: active task + silent stop (no tools, no continuation) → BLOCK
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Ответ на вопрос основателя."
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 1: blocks on silent-stop with active task"
  else
    fail "Case 1: should block on silent-stop with active task (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 2: active task + Edit tool used → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/x.txt"}}]' "Готово."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 2: allows when Edit tool used"
  else
    fail "Case 2: should allow when Edit used (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 3: active task + state-changing Bash (git commit) → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m fix"}}]' "Done."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 3: allows when git commit Bash used"
  else
    fail "Case 3: should allow when git commit used (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4: active task + Agent dispatched → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Agent","input":{}}]' "Dispatched."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 4: allows when Agent dispatched"
  else
    fail "Case 4: should allow when Agent dispatched (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5: active task + Monitor armed → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Monitor","input":{}}]' "Watching."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 5: allows when Monitor armed"
  else
    fail "Case 5: should allow when Monitor armed (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 6: active task + continuation phrase in final text → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Работа продолжается: ждём сборку на CI."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 6: allows with continuation phrase"
  else
    fail "Case 6: should allow with continuation phrase (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 7: active task + close phrase in final text → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Задача закрыта: DELIVERABLE_COMPLETE"
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 7: allows with close phrase"
  else
    fail "Case 7: should allow with close phrase (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 8: task closed (phase8-passed.flag) + silent stop → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_CLOSED" "closed"
  write_transcript '[]' "Всё готово."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 8: allows when task is closed"
  else
    fail "Case 8: should allow when task closed (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 9: no active.yaml + silent stop → ALLOW (no active task)
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "" "open"
  write_transcript '[]' "Просто ответ."
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 9: allows when no active task"
  else
    fail "Case 9: should allow when no active task (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 10: kill switch LEADV2_CONTINUATION_GUARD=0 → ALLOW
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  run_hook "LEADV2_CONTINUATION_GUARD=0" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 10: kill switch disables guard"
  else
    fail "Case 10: kill switch should disable guard (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 11: stop_hook_active=true → ALLOW (anti-loop canonical field)
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  run_hook "" "true"

  if is_allow "$HOOK_OUT"; then
    pass "Case 11: stop_hook_active prevents block"
  else
    fail "Case 11: stop_hook_active should prevent block (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 12: never double-blocks (sentinel prevents second block)
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  # First run — should block
  run_hook "" "false"
  FIRST_BLOCKED="no"
  if is_block "$HOOK_OUT"; then FIRST_BLOCKED="yes"; fi

  # Sentinel now exists (written by the hook). Second run — sentinel should
  # catch it and pass through.
  run_hook "" "false"
  SECOND_BLOCKED="no"
  if is_block "$HOOK_OUT"; then SECOND_BLOCKED="yes"; fi

  if [[ "$FIRST_BLOCKED" == "yes" && "$SECOND_BLOCKED" == "no" ]]; then
    pass "Case 12: never double-blocks same turn"
  else
    fail "Case 12: first=$FIRST_BLOCKED second=$SECOND_BLOCKED (expected yes/no)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 13: LEADV2_TASK_ID env with no phase8-passed.flag → active → BLOCK
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "" "open"
  write_transcript '[]' "Ответ."
  run_hook "LEADV2_TASK_ID=ENV-TASK-01" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 13: LEADV2_TASK_ID env without close flag blocks"
  else
    fail "Case 13: should block on LEADV2_TASK_ID without close flag (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 14 (T16 §6): tail-window fast path — a transcript padded with >256KB
# of pre-turn records must yield the SAME verdict as the unpadded one. The
# last user turn + silent stop sit at the very end of the file, inside the
# window: still BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  # Prepend ~300KB of old assistant chatter so the loader takes the
  # tail-window path (file size > TAIL_WINDOW_BYTES=262144).
  python3 - "$FIXTURE_TRANSCRIPT" <<'PYEOF'
import sys
path = sys.argv[1]
pad = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"old chatter %08d"}]}}\n'
with open(path, encoding="utf-8") as f:
    body = f.read()
with open(path, "w", encoding="utf-8") as f:
    for i in range(3200):  # ~95 bytes/line -> ~300KB
        f.write(pad % i)
    f.write(body)
PYEOF
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 14: tail-window fast path still blocks silent stop"
  else
    fail "Case 14: tail-window fast path should still block (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 15 (T16 §6): fast path with an action inside the window — padded
# transcript + an Edit tool_use in the final turn → ALLOW (window sees the
# action; no full parse needed).
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}]' "Готово."
  python3 - "$FIXTURE_TRANSCRIPT" <<'PYEOF'
import sys
path = sys.argv[1]
pad = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"old chatter %08d"}]}}\n'
with open(path, encoding="utf-8") as f:
    body = f.read()
with open(path, "w", encoding="utf-8") as f:
    for i in range(3200):
        f.write(pad % i)
    f.write(body)
PYEOF
  run_hook "" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 15: tail-window fast path allows turn with in-window action"
  else
    fail "Case 15: tail-window fast path should allow in-window action (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════
log ""
log "═══ Results: $PASS passed, $FAIL failed ═══"
if [[ "$FAIL" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
