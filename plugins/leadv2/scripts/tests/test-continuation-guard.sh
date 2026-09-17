#!/usr/bin/env bash
# tests/test-continuation-guard.sh — CONTINUATION-GUARD-01 hermetic test suite.
#
# Fully isolated: all state under mktemp sandbox. No reads of ~/.claude or
# real repo state. Creates synthetic active.yaml, transcript JSONL, and flag
# files inside a temp dir, then pipes JSON payloads to the hook. The waker
# probes (LEADV2_GUARD_REGISTRIES / LEADV2_GUARD_WATCH_DIR /
# LEADV2_GUARD_TASKS_DIR) are pinned to fixture paths on EVERY run_hook call
# — without that pin, a live lane on this machine would flip case outcomes
# (the core-offline-under-concurrent-runners hermeticity class).
#
# Run: bash plugins/leadv2/scripts/tests/test-continuation-guard.sh
# run-all-triggers: leadv2-continuation-guard
#
# SUPERSEDED REQUIREMENT (recorded per lane-rules.md): cases 2/3/3b/4/5 of
# the previous suite encoded "a turn with a tool call passes the guard"
# (original CONTINUATION-GUARD-01 contract, 2026-08). Superseded 2026-09-17
# by the founder decision delivered in mission
# CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01:
#   "A tool call proves the turn did work. It does not prove the session
#    will ever wake again." — the lead ran a full turn of tool calls, passed
#    the guard, and three finished lanes sat dead for six hours.
# The new predicate: a Stop is safe iff no active task, OR a waker exists
# (w1 live lane/worker process, w2 live background command, w3 fresh
# armed-watcher sentinel), OR the turn ended with the explicit
# continuation/close line. These cases assert the NEW behaviour, so the
# decision itself is guarded here.
#
# DECLARED NEGATIVE CONTROLS (lane-rules.md: one control per independent
# claim), applied with plugins/leadv2/scripts/leadv2-mutation-control.sh
# --live inside the hook's Python body only. Each must make this suite red:
#   M1 waker-aggregation:
#      s|waker_any = w1 or w2 or w3  # cg-mut-M1: waker aggregation|waker_any = True  # cg-mut-M1|
#      -> cases 2/3/3b/4/5 allow: a no-waker stop passes (the original bug).
#   M2 sentinel-freshness:
#      s|_fresh = (_exp > _now_dt).*cg-mut-M2|_fresh = True  # cg-mut-M2|
#      -> cases 5c/5d allow: an expired / over-horizon sentinel counts fresh.
#   M3 reused-pid ghost gate:
#      s|if _birth and _birth != _lstart:  # cg-mut-M3: reused-pid ghost gate|if False:  # cg-mut-M3|
#      -> case 4c allows: a registry row whose pid_birth contradicts
#         `ps -o lstart=` counts as a live lane.
#   M4 write-holder gate:
#      s|_is_write = .*cg-mut-M4|_is_write = False  # cg-mut-M4|
#      -> case 5e blocks: a live background task's write-held *.output stops
#         counting as a waker.
#   M5 ancestry/garbage-pid gate:
#      s|if _pid <= 1 or _pid in _ancestry:|if False:  # cg-mut-M5|
#      -> case 4e allows: a registry row naming this hook's own harness
#         process counts as a lane worker.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-continuation-guard.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMPROOT=""
SPAWNED_PIDS=()
cleanup() {
  for p in "${SPAWNED_PIDS[@]:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null
  done
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] && rm -rf "$TMPROOT"
  return 0
}
trap cleanup EXIT

# ── fixture builder ──────────────────────────────────────────────────────────
# Creates a temp project dir with configurable state.
# Args:
#   $1 = active.yaml content (empty string = no active.yaml)
#   $2 = "closed" or "open" — whether phase8-passed.flag exists
# Globals set: FIXTURE_ROOT, FIXTURE_TRANSCRIPT, FIXTURE_SENTINEL_DIR,
#              EMPTY_REGS, EMPTY_WATCH, EMPTY_TASKS
setup_fixture() {
  local active_yaml_content="$1"
  local closed_state="$2"
  local tmp_base="${LEADV2_TEST_TMPDIR:-${TMPDIR:-/tmp}}"

  TMPROOT="$(mktemp -d "${tmp_base%/}/leadv2-continuation-guard.XXXXXX")"
  FIXTURE_ROOT="$TMPROOT/project"
  FIXTURE_SENTINEL_DIR="$TMPROOT/sentinels"
  EMPTY_REGS="$TMPROOT/empty-registries.yaml"   # nonexistent -> w1 = no
  EMPTY_WATCH="$TMPROOT/empty-watch"            # empty dir    -> w3 = no
  EMPTY_TASKS="$TMPROOT/empty-tasks"            # empty dir    -> w2 = no

  mkdir -p "$FIXTURE_ROOT/docs/leadv2" "$FIXTURE_ROOT/docs/handoff/TEST-TASK-01" \
           "$FIXTURE_SENTINEL_DIR" "$EMPTY_WATCH" "$EMPTY_TASKS"

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

# Write a fixture lane registry (w1 source).
# Args:
#   $1 = registry path to write
#   $2 = task_id   $3 = pid ("0"/empty = omit)   $4 = pid_birth ("" = omit)
#   $5 = worktree
write_registry_row() {
  local path="$1" tid="$2" pid="$3" birth="$4" wt="$5"
  {
    printf 'sessions:\n'
    printf '  - task_id: %s\n' "$tid"
    printf '    phase: build\n'
    [[ -n "$pid"   ]] && printf '    pid: %s\n' "$pid"
    [[ -n "$birth" ]] && printf "    pid_birth: '%s'\n" "$birth"
    [[ -n "$wt"    ]] && printf '    worktree: %s\n' "$wt"
  } > "$path"
}

# Write an armed-watcher sentinel (w3 source) relative to now.
# Args:
#   $1 = watch dir   $2 = session id
#   $3 = armed offset seconds (may be negative)   $4 = expires offset seconds
write_sentinel() {
  local wdir="$1" sid="$2" armed_off="$3" exp_off="$4"
  mkdir -p "$wdir"
  python3 - "$wdir" "$sid" "$armed_off" "$exp_off" <<'PYEOF'
import json, sys, datetime as dt
wdir, sid, aoff, eoff = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
now = dt.datetime.now(dt.timezone.utc)
doc = {"kind": "monitor", "watching": "suite fixture",
       "armed_at": (now + dt.timedelta(seconds=aoff)).isoformat(),
       "expires_at": (now + dt.timedelta(seconds=eoff)).isoformat()}
open("%s/%s.watch.json" % (wdir, sid), "w", encoding="utf-8").write(json.dumps(doc))
PYEOF
}

# Spawn a long-lived process with cwd = $1 (w1 attribution target) and,
# optionally, stdout redirected into a file named $2 under $1 (w2 target).
# Globals set: LIVE_PID, LIVE_LSTART. Aliveness is asserted — a reaped
# fixture must fail loudly, never silently flip the case.
spawn_live_proc() {
  local dir="$1" outfile="${2:-}"
  if [[ -n "$outfile" ]]; then
    ( cd "$dir" && exec sleep 90 > "$outfile" 2>&1 ) & LIVE_PID=$!
  else
    ( cd "$dir" && exec sleep 90 >/dev/null 2>&1 ) & LIVE_PID=$!
  fi
  SPAWNED_PIDS+=("$LIVE_PID")
  sleep 0.4
  if ! kill -0 "$LIVE_PID" 2>/dev/null; then
    fail "spawn_live_proc: fixture died immediately (pid $LIVE_PID)"
    return 1
  fi
  LIVE_LSTART="$(ps -o lstart= -p "$LIVE_PID" 2>/dev/null | xargs)"
  [[ -n "$LIVE_LSTART" ]] || { fail "spawn_live_proc: no lstart for $LIVE_PID"; return 1; }
  return 0
}

# ── hook runner ──────────────────────────────────────────────────────────────
# Pipes a JSON payload to the hook, captures stdout, rc.
# Uses globals: HOOK_OUT, HOOK_RC
# Args:
#   $1 = extra env (e.g. "LEADV2_TASK_ID=foo") — placed AFTER the pinned
#        defaults so it wins (env operand order: last wins)
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

  HOOK_OUT="$(eval "LEADV2_CONTINUATION_GUARD_SENTINEL_DIR='$FIXTURE_SENTINEL_DIR' \
    LEADV2_GUARD_REGISTRIES='$EMPTY_REGS' \
    LEADV2_GUARD_WATCH_DIR='$EMPTY_WATCH' \
    LEADV2_GUARD_TASKS_DIR='$EMPTY_TASKS' \
    ${extra_env}" \
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

block_reason_contains() {
  [[ -n "$1" ]] || return 1
  printf '%s' "$1" | python3 -c 'import json, sys; exit(0 if sys.argv[1] in json.loads(sys.stdin.read()).get("reason", "") else 1)' \
    "$2" 2>/dev/null
}

ACTIVE_YAML_OPEN='sessions:
  - task_id: TEST-TASK-01
    phase: build'

ACTIVE_YAML_CLOSED='sessions:
  - task_id: TEST-TASK-01
    phase: close'

# ════════════════════════════════════════════════════════════════════════════
# Case 1: active task + silent stop (no tools, no waker, no continuation) → BLOCK
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Ответ на вопрос основателя."
  run_hook "" "false"

  if is_block "$HOOK_OUT" && block_reason_contains "$HOOK_OUT" "emit only the missing line; do not restate anything already said"; then
    pass "Case 1: blocks on silent-stop with non-repeating recovery instruction"
  else
    fail "Case 1: should block on silent-stop with non-repeating recovery instruction (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 2 (SUPERSEDES old "Edit → ALLOW"): active task + Edit tool + NO waker
# → BLOCK. Mission control 1: the tool call proves the turn acted, not that
# anything will wake the session (founder decision, 2026-09-17).
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/x.txt"}}]' "Готово."
  run_hook "" "false"

  if is_block "$HOOK_OUT" && block_reason_contains "$HOOK_OUT" "w2"; then
    pass "Case 2: tool-call turn with no waker now BLOCKS (superseded requirement asserted new)"
  else
    fail "Case 2: tool-call turn without waker should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 3 (SUPERSEDES old "state-changing Bash → ALLOW"): git commit this turn,
# nothing armed → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m fix"}}]' "Done."
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 3: git-commit turn with no waker BLOCKS"
  else
    fail "Case 3: git-commit turn without waker should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 3b (SUPERSEDES E2E-KILLRATE-01 pass direction): measured turn + read-only
# Bash probe, nothing armed → BLOCK. A completed probe is still not a waker.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Bash","input":{"command":"git status --short && git log -1 --oneline"}}]' "Проверил состояние лейна: изменений нет."
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 3b: measured read-only probe with no waker BLOCKS"
  else
    fail "Case 3b: measured read-only probe without waker should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4 (SUPERSEDES old "Agent dispatched → ALLOW"): the transcript MENTIONS
# an Agent dispatch, but no live waker is detectable → BLOCK. A transcript
# mention is not an armed process.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Agent","input":{}}]' "Dispatched."
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 4: transcript Agent mention without live waker BLOCKS"
  else
    fail "Case 4: transcript Agent mention without live waker should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4b (w1 live): registry row with a REAL live process whose cwd sits in
# the row's worktree and whose pid_birth matches ps → ALLOW.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Agent","input":{}}]' "Dispatched."
  WT="$TMPROOT/lane-wt"; mkdir -p "$WT"
  if spawn_live_proc "$WT"; then
    REG="$TMPROOT/regs-live.yaml"
    write_registry_row "$REG" "LANE-W1-LIVE" "$LIVE_PID" "$LIVE_LSTART" "$WT"
    run_hook "LEADV2_GUARD_REGISTRIES='$REG'" "false"

    if is_allow "$HOOK_OUT"; then
      pass "Case 4b: w1 live lane process (pid $LIVE_PID, cwd-attributed) ALLOWS"
    else
      fail "Case 4b: w1 live lane process should ALLOW (got: $HOOK_OUT)"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4c (w1 anti-reuse): pid alive but registry pid_birth contradicts
# `ps -o lstart=` → the row is a ghost → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  WT="$TMPROOT/lane-wt-ghost"; mkdir -p "$WT"
  if spawn_live_proc "$WT"; then
    REG="$TMPROOT/regs-ghost.yaml"
    write_registry_row "$REG" "LANE-W1-GHOST" "$LIVE_PID" "Mon Jan 1 00:00:00 2001" "$WT"
    run_hook "LEADV2_GUARD_REGISTRIES='$REG'" "false"

    if is_block "$HOOK_OUT"; then
      pass "Case 4c: reused-pid ghost (pid_birth mismatch) BLOCKS"
    else
      fail "Case 4c: reused-pid ghost should BLOCK (got: $HOOK_OUT)"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4d (w1 garbage pid): registry row with pid=1 (real-world garbage row
# observed 2026-09-17 in the live control-plane registry) → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  WT="$TMPROOT/lane-wt-garbage"; mkdir -p "$WT"
  REG="$TMPROOT/regs-garbage.yaml"
  write_registry_row "$REG" "LANE-W1-GARBAGE" "1" "" "$WT"
  run_hook "LEADV2_GUARD_REGISTRIES='$REG'" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 4d: garbage pid=1 registry row BLOCKS"
  else
    fail "Case 4d: garbage pid=1 registry row should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 4e (w1 self-attribution): registry row naming the SUITE's own shell
# (alive, correct birth, cwd = invocation dir) — the hook's own harness must
# never count as a lane worker → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  SELF_LSTART="$(ps -o lstart= -p $$ | xargs)"
  REG="$TMPROOT/regs-self.yaml"
  write_registry_row "$REG" "LANE-W1-SELF" "$$" "$SELF_LSTART" "$(pwd)"
  run_hook "LEADV2_GUARD_REGISTRIES='$REG'" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 4e: registry row naming the hook's own harness BLOCKS"
  else
    fail "Case 4e: self-referencing registry row should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5 (SUPERSEDES old "Monitor armed → ALLOW"): the transcript MENTIONS a
# Monitor, but no sentinel attests it and nothing else is live → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Monitor","input":{}}]' "Watching."
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 5: transcript Monitor mention without sentinel BLOCKS"
  else
    fail "Case 5: transcript Monitor mention without sentinel should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5b (w3 fresh): fresh armed-watcher sentinel → ALLOW.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Monitor","input":{}}]' "Watching."
  write_sentinel "$TMPROOT/watch" "test-sess-cg01" 0 600
  run_hook "LEADV2_GUARD_WATCH_DIR='$TMPROOT/watch'" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 5b: fresh armed-watcher sentinel ALLOWS"
  else
    fail "Case 5b: fresh sentinel should ALLOW (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5c (w3 expired): expired sentinel is stale → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  write_sentinel "$TMPROOT/watch" "test-sess-cg01" -1200 -600
  run_hook "LEADV2_GUARD_WATCH_DIR='$TMPROOT/watch'" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 5c: expired sentinel BLOCKS"
  else
    fail "Case 5c: expired sentinel should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5d (w3 horizon clamp): sentinel armed 2h ago claiming a future expiry
# beyond armed_at + 3600s → the attestation is capped → BLOCK. A sentinel
# that never expires would re-create this bug in a new place.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  write_sentinel "$TMPROOT/watch" "test-sess-cg01" -7200 86400
  run_hook "LEADV2_GUARD_WATCH_DIR='$TMPROOT/watch'" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 5d: over-horizon sentinel attestation BLOCKS"
  else
    fail "Case 5d: over-horizon sentinel should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5e (w2 live): a live background task holds live.output open for WRITE
# under the session's tasks dir → its completion will notify → ALLOW.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  TD="$TMPROOT/tasks-live"; mkdir -p "$TD"
  if spawn_live_proc "$TD" "live.output"; then
    run_hook "LEADV2_GUARD_TASKS_DIR='$TD'" "false"

    if is_allow "$HOOK_OUT"; then
      pass "Case 5e: live background task (write-held *.output) ALLOWS"
    else
      fail "Case 5e: live background task should ALLOW (got: $HOOK_OUT)"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 5f (w2 dead): tasks dir exists but nothing holds any *.output for
# write → BLOCK.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  TD="$TMPROOT/tasks-dead"; mkdir -p "$TD"
  printf 'x' > "$TD/finished.output"
  run_hook "LEADV2_GUARD_TASKS_DIR='$TD'" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 5f: finished task output (no write holder) BLOCKS"
  else
    fail "Case 5f: finished task output should BLOCK (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 6: active task + continuation phrase in final text → ALLOW
# (contract (b): the explicit line is an honest declaration; kept).
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
# (silent, no waker)
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
# between the user turn and its final assistant record must yield the SAME
# verdict as the unpadded one. The tail misses the user turn, so the full-file
# fallback is required: still BLOCK.
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
    lines = f.readlines()
with open(path, "w", encoding="utf-8") as f:
    f.write(lines[0])
    for i in range(3200):  # ~95 bytes/line -> ~300KB
        f.write(pad % i)
    f.writelines(lines[1:])
PYEOF
  run_hook "" "false"

  if is_block "$HOOK_OUT"; then
    pass "Case 14: tail-window fast path still blocks silent stop"
  else
    fail "Case 14: tail-window fast path should still block (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 15 (T16 §6, waker edition): same fallback shape, an Edit in the final
# turn AND a fresh sentinel → ALLOW. (The Edit alone no longer passes — the
# sentinel is what makes this safe; the case still proves the tail-window
# fallback reaches the waker evaluation.)
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}]' "Готово."
  write_sentinel "$TMPROOT/watch" "test-sess-cg01" 0 600
  python3 - "$FIXTURE_TRANSCRIPT" <<'PYEOF'
import sys
path = sys.argv[1]
pad = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"old chatter %08d"}]}}\n'
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
with open(path, "w", encoding="utf-8") as f:
    f.write(lines[0])
    for i in range(3200):
        f.write(pad % i)
    f.writelines(lines[1:])
PYEOF
  run_hook "LEADV2_GUARD_WATCH_DIR='$TMPROOT/watch'" "false"

  if is_allow "$HOOK_OUT"; then
    pass "Case 15: tail-window fast path allows in-window action with fresh sentinel"
  else
    fail "Case 15: tail-window fast path should allow with sentinel (got: $HOOK_OUT)"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Case 16: the block message NAMES what to arm — all three waker classes and
# the exact sentinel path for this session id.
# ════════════════════════════════════════════════════════════════════════════
{
  setup_fixture "$ACTIVE_YAML_OPEN" "open"
  write_transcript '[]' "Тишина."
  run_hook "" "false"

  if is_block "$HOOK_OUT" \
     && block_reason_contains "$HOOK_OUT" "w1" \
     && block_reason_contains "$HOOK_OUT" "w2" \
     && block_reason_contains "$HOOK_OUT" "w3" \
     && block_reason_contains "$HOOK_OUT" "test-sess-cg01.watch.json"; then
    pass "Case 16: block message names the wakers and the sentinel path"
  else
    fail "Case 16: block message should name wakers + sentinel path (got: $HOOK_OUT)"
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
