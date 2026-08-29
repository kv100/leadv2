#!/usr/bin/env bash
# tests/test-board-blind-detached-workers-01.sh — BOARD-BLIND-TO-DETACHED-WORKERS-01.
#
# Root cause (verified live 2026-08-29, persona-engine): dispatch-code.sh's
# glm/glm-flash/kimi/freepool/codex arms spawn DETACHED workers — no local PID,
# only a handle — and never stamp a worker identity onto the active.yaml row
# (only the sonnet arm calls leadv2_active_set_worker_pid). The row keeps
# pid_role=lead_durable with the DISPATCHER's pid. leadv2-lane-liveness.sh
# correctly refuses to read a lead_durable pid as worker evidence
# (LANE-REGISTRY-SELF-DEADLOCK-01) — but nothing replaced the missing worker
# leg, so a running detached worker (whose artifacts live in its run dir /
# worktree, NOT in docs/handoff/<tid>/) resolved dead:no_log_artifact /
# dead:silent_no_process. leadv2-lanes-snapshot.sh then rendered the board
# empty (ДОСКА ПУСТА) and — worse — its corroborated prune ("pid dead" on the
# exited dispatcher's pid) tombstoned+deleted genuinely running rows.
#
# The observed release at 00:10:20Z (`active_lane_released where=exit_trap`)
# belonged to an attempt that exited phase_precondition_refused BEFORE any
# spawn — a correct release. On a CONFIRMED spawn the exit trap is disarmed
# (dispatch-code.sh R5 §4), so the trap was never the deleter; the snapshot
# prune was. Test 4 pins the trap-side contract anyway: a handed-over row
# survives the exit-trap release path, and a worker-role row is never released
# by a foreign owner.
#
# Fix under test, both directions:
#   1. lane-liveness consults the WORKER's own channel (arm-registered handle
#      -> glm/kimi/freepool run-dir pgid group, codex job registry) before any
#      dead verdict that only lead_durable/pid evidence produced.
#   2. lanes-snapshot's prune veto honors an authoritative `alive` verdict.
#
# All tests drive the REAL leadv2-lane-liveness.sh / leadv2-lanes-snapshot.sh /
# (awk-stripped) leadv2-dispatch-code.sh against scratch fixtures — the live
# control-plane registry is never touched.
#
# Run: bash scripts/tests/test-board-blind-detached-workers-01.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIVENESS_SH="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
SNAPSHOT_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
DISPATCH_SH="${PLUGIN_DIR}/scripts/leadv2-dispatch-code.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()
_PGROUP_PIDS=()
cleanup() {
  for p in "${_PGROUP_PIDS[@]:-}"; do kill -9 -"$p" 2>/dev/null || true; done
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

json_get() { python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print($1)
"; }

_new_fixture() {
  local repo state
  repo="$(lv2_mktemp_dir "bbdw-repo")"
  state="$(lv2_mktemp_dir "bbdw-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  (cd "$repo" && git init -q)
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
  # inert codex registry stub: lane-liveness's codex shell-out must never
  # reach a real app-server from a test (CODEX_TASK_SH is its env seam)
  printf -- '{"running":[],"recent":[]}' > "$repo/codex-none.json"
  printf -- '#!/usr/bin/env bash\ncat "%s/codex-none.json"\n' "$repo" > "$repo/codex-stub.sh"
  chmod +x "$repo/codex-stub.sh"
  printf -- '%s %s\n' "$repo" "$state"
}

_state_file() { # <repo> <state> <name>
  LEADV2_PROJECT_ROOT="$1" CLAUDE_PROJECT_DIR="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" "$3"
}

# A genuinely live process group this test controls: start_new_session makes
# the child its own pgid, exactly like setsid_wrapper detaches a glm/kimi/
# freepool worker. Prints the pgid.
_start_live_group() {
  python3 -c '
import subprocess
p = subprocess.Popen(["sleep", "300"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid)
'
}

# Fixture: registry row for a DETACHED lane. The dispatcher's pid is dead (it
# exited right after handing the worker off — no surviving local pid, handle
# only), pid_role stays lead_durable, and the registered stream does not exist
# in the main checkout (the detached worker writes into its run dir / the lane
# worktree instead). This is byte-for-byte the dispatch-ab0ec014 shape.
_make_detached_row() { # <active_path> <task_id> <dead_pid> <handle>
  python3 - "$1" "$2" "$3" <<'PY'
import sys, yaml
path, tid, dead_pid = sys.argv[1], sys.argv[2], int(sys.argv[3])
doc = {"sessions": [{
    "task_id": tid,
    "session_id": "s-20260829T000000Z-1-1",
    "worktree": "/tmp/fixture-worktree",
    "branch": "main",
    "started_at": "2020-01-01T00:00:00+00:00",   # past SPAWN_GRACE_MIN/STARTING_MAX
    "phase": "build",
    "class": "Heavy",
    "pid": dead_pid,
    "pid_birth": None,
    "pid_role": "lead_durable",
    "log_path": f"docs/handoff/{tid}/developer.stream.jsonl",  # never written
    "protocol_version": 2,
    "backend": "terminal",
    "last_pulse_at": "2020-01-01T00:00:00+00:00",
    "stale": False,
}]}
with open(path, "w") as fh:
    yaml.safe_dump(doc, fh)
PY
}

# ── Test 1: live detached glm worker -> lane-liveness verdict ALIVE ─────────

test_1_detached_glm_live() {
  log "Test 1: live detached glm worker (dead lead pid, handle only) -> verdict alive"
  local repo state active pgid handle out verdict
  read -r repo state < <(_new_fixture)
  active="$(_state_file "$repo" "$state" active.yaml)"
  mkdir -p "$(dirname "$active")"

  local dead_pid
  ( sleep 0 ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  local tid="dispatch-cafe0001"
  _make_detached_row "$active" "$tid" "$dead_pid"
  mkdir -p "$repo/docs/handoff/$tid"

  # the detached worker: live process group + its run dir (pgid/journal), and
  # the spawn-time handle record dispatch-code.sh writes via _dispatch_register_arm
  pgid="$(_start_live_group)"; _PGROUP_PIDS+=("$pgid")
  handle="260829-034420-cafe0001-aaaa"
  mkdir -p "$repo/glm-runs/$handle"
  printf -- '%s\n' "$pgid" > "$repo/glm-runs/$handle/pgid"
  printf -- '%s\n' '{"n":1}' > "$repo/glm-runs/$handle/journal.jsonl"
  printf -- 'arm=glm handle=%s epoch=1787964261 LEAD_SESSION=test\n' "$handle" \
    > "$repo/docs/handoff/$tid/arm-registered"

  out="$(GLM_RUNS_DIR="$repo/glm-runs" CODEX_TASK_SH="$repo/codex-stub.sh" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$LIVENESS_SH" --project-root "$repo" --lane "$tid" --no-codex --json 2>/dev/null)" \
    || { fail "Test 1: lane-liveness exited nonzero"; return; }
  verdict="$(printf -- '%s' "$out" | json_get "d['verdict']")"
  if [[ "$verdict" == "alive" ]]; then
    pass "Test 1: detached glm worker live -> verdict=alive (was dead:no_log_artifact)"
  else
    fail "Test 1: verdict=$verdict, expected alive (live pgid=$pgid handle=$handle)"
  fi
}

# ── Test 2: the row survives the snapshot prune AND renders as live ─────────

test_2_row_survives_prune_and_renders_live() {
  log "Test 2: 2-poll snapshot prune keeps the live detached row; table renders it active"
  local repo state active snap pgid handle out1 out2 still status_now
  read -r repo state < <(_new_fixture)
  active="$(_state_file "$repo" "$state" active.yaml)"
  snap="$(_state_file "$repo" "$state" .supervise-last.json)"
  mkdir -p "$(dirname "$active")" "$(dirname "$snap")"

  local dead_pid
  ( sleep 0 ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  local tid="dispatch-cafe0002"
  _make_detached_row "$active" "$tid" "$dead_pid"
  mkdir -p "$repo/docs/handoff/$tid"

  pgid="$(_start_live_group)"; _PGROUP_PIDS+=("$pgid")
  handle="260829-034420-cafe0002-bbbb"
  mkdir -p "$repo/glm-runs/$handle"
  printf -- '%s\n' "$pgid" > "$repo/glm-runs/$handle/pgid"
  printf -- '%s\n' '{"n":1}' > "$repo/glm-runs/$handle/journal.jsonl"
  printf -- 'arm=glm handle=%s epoch=1787964261 LEAD_SESSION=test\n' "$handle" \
    > "$repo/docs/handoff/$tid/arm-registered"

  # Past the 2-cycle observe-only reconciliation grace so prunes actually apply
  # (same preseed trick as test-lane-liveness-lies.sh).
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  local env=(GLM_RUNS_DIR="$repo/glm-runs" CODEX_TASK_SH="$repo/codex-stub.sh" LEADV2_PROJECT_ROOT="$repo"
             CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state")
  out1="$(env "${env[@]}" bash "$SNAPSHOT_SH" --no-all-repos --json 2>/dev/null)" \
    || { fail "Test 2: poll 1 exited nonzero"; return; }
  out2="$(env "${env[@]}" bash "$SNAPSHOT_SH" --no-all-repos --json 2>/dev/null)" \
    || { fail "Test 2: poll 2 exited nonzero"; return; }

  still="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active')) or {}
print(any(s.get('task_id') == '$tid' for s in d.get('sessions', [])))")"
  status_now="$(printf -- '%s' "$out2" | json_get "next((x['status'] for x in d.get('table', []) if x['task_id'] == '$tid'), 'absent')")"
  if [[ "$still" == "True" && "$status_now" == "active" ]]; then
    pass "Test 2: row still in active.yaml after 2 polls; table status=active"
  else
    fail "Test 2: still_present=$still table_status=$status_now (expected True/active)"
  fi
}

# ── Test 3: opposite direction — a finished detached worker is releasable ───

test_3_finished_worker_still_releasable() {
  log "Test 3: dead detached worker (group gone) -> verdict dead, row pruned — no leak"
  local repo state active snap pgid handle tid="dispatch-cafe0003" out verdict still status_now
  read -r repo state < <(_new_fixture)
  active="$(_state_file "$repo" "$state" active.yaml)"
  snap="$(_state_file "$repo" "$state" .supervise-last.json)"
  mkdir -p "$(dirname "$active")" "$(dirname "$snap")"

  local dead_pid
  ( sleep 0 ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  _make_detached_row "$active" "$tid" "$dead_pid"
  mkdir -p "$repo/docs/handoff/$tid"

  # a worker that has genuinely FINISHED: its process group is gone (glm
  # reaps the group on completion) — only the inert run dir remains
  pgid="$(_start_live_group)"
  kill -9 -"$pgid" 2>/dev/null || true
  handle="260829-034420-cafe0003-cccc"
  mkdir -p "$repo/glm-runs/$handle"
  printf -- '%s\n' "$pgid" > "$repo/glm-runs/$handle/pgid"
  printf -- 'arm=glm handle=%s epoch=1787964261 LEAD_SESSION=test\n' "$handle" \
    > "$repo/docs/handoff/$tid/arm-registered"
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  out="$(GLM_RUNS_DIR="$repo/glm-runs" CODEX_TASK_SH="$repo/codex-stub.sh" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$LIVENESS_SH" --project-root "$repo" --lane "$tid" --no-codex --json 2>/dev/null)" \
    || { fail "Test 3: lane-liveness exited nonzero"; return; }
  verdict="$(printf -- '%s' "$out" | json_get "d['verdict']")"
  if [[ "$verdict" != dead:* ]]; then
    fail "Test 3: verdict=$verdict for a finished worker, expected dead:*"
    return
  fi

  local env=(GLM_RUNS_DIR="$repo/glm-runs" CODEX_TASK_SH="$repo/codex-stub.sh" LEADV2_PROJECT_ROOT="$repo"
             CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state")
  out1="$(env "${env[@]}" bash "$SNAPSHOT_SH" --no-all-repos --json 2>/dev/null)" \
    || { fail "Test 3: poll 1 exited nonzero"; return; }
  out2="$(env "${env[@]}" bash "$SNAPSHOT_SH" --no-all-repos --json 2>/dev/null)" \
    || { fail "Test 3: poll 2 exited nonzero"; return; }
  still="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active')) or {}
print(any(s.get('task_id') == '$tid' for s in d.get('sessions', [])))")"
  if [[ "$still" == "False" ]]; then
    pass "Test 3: finished worker -> dead verdict, row pruned from active.yaml"
  else
    fail "Test 3: row still present after 2 polls (dead detached rows must not leak)"
  fi
}

# ── Test 4: the exit-trap release path never eats a handed-over row ─────────

test_4_exit_trap_release_path() {
  log "Test 4: exit-trap release path — disarmed-after-spawn row survives; worker-role row never released"
  local d repo
  d="$(lv2_mktemp_dir "bbdw-dispatch")"; CLEANUP_DIRS+=("$d")
  repo="$(lv2_mktemp_dir "bbdw-dispatch-repo")"; CLEANUP_DIRS+=("$repo")
  (cd "$repo" && git init -q)
  mkdir -p "$d/tmp" "$repo/docs/handoff"
  cp -R "${PLUGIN_DIR}/scripts" "$d/scripts"
  # Load the real definitions without dispatching its CLI footer (same awk
  # seam test-dispatch-prepass-provider-fallback.sh uses).
  awk '/^# ── dispatch / { exit } { print }' \
    "${d}/scripts/leadv2-dispatch-code.sh" > "${d}/scripts/dispatch-lib.sh"

  cat > "$d/runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${FIXTURE_DIR}/scripts/dispatch-lib.sh"
PROJECT_ROOT="${FIXTURE_REPO}"
emit() { printf -- '%s\n' "$*" >> "${FIXTURE_DIR}/events.log"; }
_leadv2_yaml_file() { printf -- '%s\n' "${FIXTURE_DIR}/registry.yaml"; }
_leadv2_yaml_lockfile() { printf -- '%s\n' "${FIXTURE_DIR}/registry.lock"; }

mkdir -p "${FIXTURE_DIR}"
# Row A — the DETACHED-spawn handoff: cmd_resolve disarms the slot at the
# confirmed spawn (R5 §4), so the EXIT trap must leave the row alone even
# though the dispatcher process is about to exit and its pid will die.
cat > "${FIXTURE_DIR}/registry.yaml" <<YAML
sessions:
  - task_id: detached-live-lane
    session_id: ours-session
    pid: 12345
    pid_role: lead_durable
YAML
DISPATCH_SLOT_REG_ID=""
DISPATCH_SLOT_SESSION="ours-session"
DISPATCH_SLOT_PID=12345
DISPATCH_SLOT_SIG8="cafe0004"
cleanup_pending_dispatch || true
cp "${FIXTURE_DIR}/registry.yaml" "${FIXTURE_DIR}/registry-after-a.yaml"

# Row B — a worker-owned row (sonnet-arm promotion) with the slot still armed:
# the owner-verified release must refuse it even for the registering owner.
cat > "${FIXTURE_DIR}/registry.yaml" <<YAML
sessions:
  - task_id: worker-owned-lane
    session_id: ours-session
    pid: 12345
    pid_role: worker
YAML
DISPATCH_SLOT_REG_ID="worker-owned-lane"
DISPATCH_SLOT_SESSION="ours-session"
DISPATCH_SLOT_PID=12345
DISPATCH_SLOT_SIG8="cafe0005"
_release_registered_lane "worker-owned-lane" "cafe0005" "exit_trap" || true
EOF
  chmod +x "$d/runner.sh"
  FIXTURE_DIR="$d" FIXTURE_REPO="$repo" TMPDIR="$d/tmp" LEADV2_FOREIGN_ROOT_GUARD=0 \
    bash "$d/runner.sh" || { fail "Test 4: runner exited nonzero"; return; }

  python3 - "$d/registry-after-a.yaml" "$d/registry.yaml" "$d/events.log" <<'PY' || { fail "Test 4: assertion failed"; return; }
import sys, yaml
rows_a = {s["task_id"] for s in yaml.safe_load(open(sys.argv[1]))["sessions"]}
rows_b = {s["task_id"] for s in yaml.safe_load(open(sys.argv[2]))["sessions"]}
assert "detached-live-lane" in rows_a, "disarmed exit trap must not touch the handed-over row"
assert "worker-owned-lane" in rows_b, "worker-role row must never be released by the trap"
events = open(sys.argv[3]).read()
assert "worker-owned-lane" in events and "reason=not_owner_row_intact" in events, events
PY
  pass "Test 4: disarmed trap keeps the detached row; worker-role row refused (not_owner_row_intact)"
}

# ── Test 5: the codex leg — a queued/running job record keeps the lane alive ─

test_5_detached_codex_live() {
  log "Test 5: live detached codex job (handle only, job registry says running) -> verdict alive"
  local repo state active tid="dispatch-cafe0006" stub out verdict
  read -r repo state < <(_new_fixture)
  active="$(_state_file "$repo" "$state" active.yaml)"
  mkdir -p "$(dirname "$active")"

  local dead_pid
  ( sleep 0 ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  _make_detached_row "$active" "$tid" "$dead_pid"
  mkdir -p "$repo/docs/handoff/$tid"
  # codex handle shape: task-<base36>-<rand>, matching the incident's
  # task-mtdmkbgy-xtd2rd; job registry (codex-task.sh status --all) says running
  printf -- 'arm=codex handle=task-mtdmkbgy-xyz123 epoch=1787962258 LEAD_SESSION=test\n' \
    > "$repo/docs/handoff/$tid/arm-registered"
  stub="$repo/codex-stub.sh"
  cat > "$stub" <<'EOF'
#!/usr/bin/env bash
printf -- '{"running":[{"id":"task-mtdmkbgy-xyz123","status":"running","phase":"build"}],"recent":[]}'
EOF
  chmod +x "$stub"

  out="$(CODEX_TASK_SH="$stub" LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$LIVENESS_SH" --project-root "$repo" --lane "$tid" --json 2>/dev/null)" \
    || { fail "Test 5: lane-liveness exited nonzero"; return; }
  verdict="$(printf -- '%s' "$out" | json_get "d['verdict']")"
  if [[ "$verdict" == "alive" ]]; then
    pass "Test 5: detached codex job running -> verdict=alive"
  else
    fail "Test 5: verdict=$verdict, expected alive"
  fi
}

test_1_detached_glm_live
test_2_row_survives_prune_and_renders_live
test_3_finished_worker_still_releasable
test_4_exit_trap_release_path
test_5_detached_codex_live

printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
