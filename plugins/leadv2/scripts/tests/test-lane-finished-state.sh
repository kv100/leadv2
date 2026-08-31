#!/usr/bin/env bash
# tests/test-lane-finished-state.sh — LANE-LIVENESS-THREE-STATES-02.
#
# A lane can be alive, dead, or FINISHED. Before this fix the code only knew
# alive/dead, so a worker that finished a round normally (process exited,
# work committed) was misread in BOTH directions from the same underlying
# fact:
#   Direction 1 (leadv2-lanes-snapshot.sh escalation): "pid dead" alone was
#     treated as death evidence -> three founder-facing "corroborated dead"
#     questions fired for three successful, already-committed rounds.
#   Direction 2 (leadv2-lane-liveness.sh verdict, consumed by
#     leadv2-dispatch-code.sh's placement gate): a still-fresh stream mtime
#     alone marked the lane "alive" even with a confirmed-dead pid, refusing
#     re-dispatch (`lane_placement_refused reason=lane_is_live`) until the
#     stream aged out on its own.
#
# The fix introduces a third, externally-checkable state: no live pid + a
# commit in the lane's OWN worktree within LEADV2_LANE_FINISHED_WINDOW_S
# (default 1800s -- see the rationale comment beside `finished_window` in
# leadv2-lane-liveness.sh) is FINISHED, not dead, and must never be shadowed
# by log/stream freshness. Both probes read the SAME env var and default so
# they can never disagree about the same lane (acceptance item 5).
#
# All fixture tests below drive the REAL leadv2-lane-liveness.sh and
# leadv2-lanes-snapshot.sh binaries against scratch active.yaml/worktree
# fixtures -- never a real lane, never a real state root, never a helper
# function tested in isolation. Tests 5a/5b additionally mutate the two
# PRODUCTION scripts themselves IN PLACE (no scratch-copy mutation) to prove
# a RED control: collapsing the finished-check must turn the corresponding
# assertion red, and reverting must restore green. The cleanup trap
# unconditionally restores both scripts from their own pre-mutation backup on
# every exit path, including a failure mid-mutation.
#
# Run: bash scripts/tests/test-lane-finished-state.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SNAPSHOT_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
LIVENESS_SH="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()
_SLEEPER_PID=""

cleanup() {
  [[ -n "${_SLEEPER_PID}" ]] && kill "${_SLEEPER_PID}" 2>/dev/null || true
  wait "${_SLEEPER_PID}" 2>/dev/null || true
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  # Unconditional restore safety net: even on an abnormal exit mid-mutation,
  # the two production scripts must end byte-identical to how this suite
  # found them, on the failure path too.
  if [[ -f "${LIVENESS_SH}.finstate-orig" ]]; then
    cp "${LIVENESS_SH}.finstate-orig" "${LIVENESS_SH}"
    rm -f "${LIVENESS_SH}.finstate-orig"
  fi
  if [[ -f "${SNAPSHOT_SH}.finstate-orig" ]]; then
    cp "${SNAPSHOT_SH}.finstate-orig" "${SNAPSHOT_SH}"
    rm -f "${SNAPSHOT_SH}.finstate-orig"
  fi
  return 0
}
trap cleanup EXIT

_new_fixture() {
  # Deliberately NO seed commit here -- some fixtures (the dead/no-commit
  # control) need a worktree with an UNBORN HEAD (git log -1 fails -> None,
  # never a fabricated age). Callers that need a commit make it themselves.
  local repo state
  repo="$(lv2_mktemp_dir "lfs-repo")"
  state="$(lv2_mktemp_dir "lfs-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  ( cd "$repo" && git init -q -b main \
      && git config user.email test@example.com && git config user.name test )
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
  printf -- '%s %s\n' "$repo" "$state"
}

_commit_now() { # <repo> <message>
  ( cd "$1" && git commit --allow-empty -q -m "$2" )
}

_commit_aged() { # <repo> <message> <age_s>
  # Backdate the commit so commit_age_s() reports ~<age_s> seconds old --
  # needed to place a fixture strictly between LEADV2_LANE_FRESH_S (120s,
  # the pre-existing LANE-LIVENESS-LIES-01 freshness veto) and
  # LEADV2_LANE_FINISHED_WINDOW_S (1800s, this lane's finished veto), so a
  # mutation-gate test can isolate the new veto instead of both firing.
  local repo="$1" msg="$2" age="$3" ts
  ts="$(( $(date +%s) - age ))"
  ( cd "$repo" && GIT_AUTHOR_DATE="@${ts}" GIT_COMMITTER_DATE="@${ts}" \
    git commit --allow-empty -q -m "$msg" )
}

_active_yaml() {
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml
}

_bypass_reconcile_grace() {
  # The first 2 FULL reconciliation cycles after rollout are ALWAYS
  # observe-only for legacy rows (leadv2-lanes-snapshot.sh "D-e") -- pre-seed
  # .supervise-last.json with reconcile_cycle_count=5 so polls in this suite
  # are past that grace window and prunes actually apply.
  local repo="$1" state="$2" snap
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"
}

_row_present() {
  python3 -c "
import yaml
d = yaml.safe_load(open('$1')) or {}
print(any(s.get('task_id')=='$2' for s in d.get('sessions', [])))
"
}

json_get() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print($1)
"
}

_start_sleeper() { sleep 300 & _SLEEPER_PID=$!; }
_stop_sleeper() {
  [[ -n "${_SLEEPER_PID}" ]] && kill "${_SLEEPER_PID}" 2>/dev/null || true
  wait "${_SLEEPER_PID}" 2>/dev/null || true
  _SLEEPER_PID=""
}
_dead_pid() {
  # A pid that has already exited by the time the caller reads it -- os.kill
  # will raise ProcessLookupError regardless of reuse.
  local p
  ( sleep 0 ) & p=$!
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

# The EXACT liveness call leadv2-dispatch-code.sh's placement gate (Step 5)
# makes -- prints the raw verdict so a fixture can assert both the verdict
# string AND (via _is_live_verdict) the same live/not-live boolean the
# placement gate derives from it.
_placement_probe() { # <repo> <tid> <state>
  local repo="$1" tid="$2" state="${3:-}" row
  row="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$LIVENESS_SH" --project-root "$repo" --lane "$tid" --no-codex --json 2>/dev/null || true)"
  printf '%s' "$row" | json_get "d.get('verdict')"
}

_is_live_verdict() {
  case "$1" in
    alive|starting:*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Test 1: live pid -> alive; re-dispatch refused as today ─────────────────

test_1_live_pid_alive_not_escalated() {
  log "Test 1: live pid + fresh stream -> alive; not an escalation candidate"
  _start_sleeper
  local repo state active_path log_rel log_abs tid verdict
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  tid="LIVE-PID-ALIVE"
  mkdir -p "$repo/docs/handoff/${tid}"
  log_rel="docs/handoff/${tid}/developer.stream.jsonl"
  log_abs="$repo/$log_rel"
  printf '{"type":"assistant","text":"working"}\n' > "$log_abs"
  _bypass_reconcile_grace "$repo" "$state"

  python3 - "$active_path" "$_SLEEPER_PID" "$tid" "$log_rel" "$repo" <<'PY'
import sys, yaml
path, pid, tid, log_path, worktree = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
doc = {"sessions": [{
    "task_id": tid, "session_id": "s1", "started_at": "2020-01-01T00:00:00+00:00",
    "phase": "build", "pid": pid, "pid_birth": None, "worktree": worktree,
    "protocol_version": 2, "backend": "terminal", "log_path": log_path,
    "last_pulse_at": "2020-01-01T00:00:00+00:00", "stale": False,
}]}
with open(path, "w") as fh:
    yaml.safe_dump(doc, fh)
PY

  verdict="$(_placement_probe "$repo" "$tid" "$state")"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 1: poll 1 exited nonzero"; _stop_sleeper; return; }
  local out2 escalated still
  out2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json 2>/dev/null)" || { fail "Test 1: poll 2 exited nonzero"; _stop_sleeper; return; }
  escalated="$(printf -- '%s' "$out2" | json_get "any(x['task_id']=='$tid' for x in d.get('dead', []))")"
  still="$(_row_present "$active_path" "$tid")"

  if [[ "$verdict" == "alive" ]] && _is_live_verdict "$verdict" && [[ "$escalated" == False && "$still" == True ]]; then
    pass "Test 1: live pid -> verdict=alive, placement would refuse (live), escalation path agrees (not dead)"
  else
    fail "Test 1: verdict=$verdict escalated=$escalated still_present=$still"
  fi
  _stop_sleeper
}

# ── Test 2: no pid + commit inside window -> finished, no escalation ────────

test_2_finished_no_escalation_redispatch_admitted() {
  log "Test 2: dead pid + recent commit -> finished, no escalation, placement not refused"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  dead_pid="$(_dead_pid)"
  _commit_now "$repo" "finished work"
  tid="FINISHED-COMMITTED"
  _bypass_reconcile_grace "$repo" "$state"

  cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: s2
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${dead_pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML

  verdict="$(_placement_probe "$repo" "$tid" "$state")"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 2: poll 1 exited nonzero"; return; }
  local out2 escalated still
  out2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json 2>/dev/null)" || { fail "Test 2: poll 2 exited nonzero"; return; }
  escalated="$(printf -- '%s' "$out2" | json_get "any(x['task_id']=='$tid' for x in d.get('dead', []))")"
  still="$(_row_present "$active_path" "$tid")"

  if [[ "$verdict" == finished:* ]] && ! _is_live_verdict "$verdict" && [[ "$escalated" == False && "$still" == True ]]; then
    pass "Test 2: dead pid + recent commit -> verdict=$verdict (finished, not live), no escalation, row kept"
  else
    fail "Test 2: verdict=$verdict escalated=$escalated still_present=$still"
  fi
}

# ── Test 3: no pid + no commit + no deliverable -> dead, escalates as today ─

test_3_dead_no_commit_escalates() {
  log "Test 3: dead pid, unborn-HEAD worktree, no deliverable -> dead, escalation raised"
  local repo state active_path tid dead_pid verdict
  read -r repo state < <(_new_fixture)   # no commit made -- unborn HEAD
  active_path="$(_active_yaml "$repo" "$state")"
  dead_pid="$(_dead_pid)"
  tid="GENUINELY-DEAD-NO-COMMIT"
  _bypass_reconcile_grace "$repo" "$state"

  cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: s3
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${dead_pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML

  verdict="$(_placement_probe "$repo" "$tid" "$state")"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 3: poll 1 exited nonzero"; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 3: poll 2 exited nonzero"; return; }
  local removed
  removed="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='$tid' for s in d.get('sessions', [])))
")"

  if [[ "$verdict" == dead:* ]] && ! _is_live_verdict "$verdict" && [[ "$removed" == True ]]; then
    pass "Test 3: dead pid + no commit -> verdict=$verdict (dead), corroborated dead, pruned as today"
  else
    fail "Test 3: verdict=$verdict removed=$removed (real death detection must not be disabled by this fix)"
  fi
}

# ── Test 4: no pid + commit + FRESH stream -> still finished (mtime must not override) ─

test_4_fresh_stream_does_not_override_finished() {
  log "Test 4: dead pid + recent commit + fresh stream mtime -> still finished, never alive"
  local repo state active_path tid dead_pid log_rel log_abs verdict
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  dead_pid="$(_dead_pid)"
  _commit_now "$repo" "finished work"
  tid="FINISHED-FRESH-STREAM"
  mkdir -p "$repo/docs/handoff/${tid}"
  log_rel="docs/handoff/${tid}/developer.stream.jsonl"
  log_abs="$repo/$log_rel"
  printf '{"type":"assistant","text":"still working"}\n' > "$log_abs"   # mtime = now
  _bypass_reconcile_grace "$repo" "$state"

  cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: s4
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${dead_pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    log_path: "${log_rel}"
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML

  verdict="$(_placement_probe "$repo" "$tid" "$state")"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 4: poll 1 exited nonzero"; return; }
  local out2 escalated still
  out2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json 2>/dev/null)" || { fail "Test 4: poll 2 exited nonzero"; return; }
  escalated="$(printf -- '%s' "$out2" | json_get "any(x['task_id']=='$tid' for x in d.get('dead', []))")"
  still="$(_row_present "$active_path" "$tid")"

  if [[ "$verdict" == finished:* ]] && [[ "$verdict" != "alive" ]] && [[ "$escalated" == False && "$still" == True ]]; then
    pass "Test 4: fresh stream mtime did NOT override the pid+commit evidence -> verdict=$verdict, no escalation"
  else
    fail "Test 4: verdict=$verdict (must be finished:*, never alive) escalated=$escalated still_present=$still"
  fi
}

# ── Test 5a: mutation gate -- leadv2-lane-liveness.sh finished-check ────────

test_5a_mutation_gate_liveness() {
  log "Test 5a: mutating leadv2-lane-liveness.sh's finished-check must turn verdict non-finished (RED), revert restores it (GREEN)"
  local repo state active_path tid dead_pid green1 red green2
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  dead_pid="$(_dead_pid)"
  _commit_now "$repo" "finished work"
  tid="MUTGATE-LIVENESS"

  cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: mg1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${dead_pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML

  green1="$(_placement_probe "$repo" "$tid" "$state")"
  if [[ "$green1" != finished:* ]]; then
    fail "Test 5a: pre-mutation baseline must be finished:* (got $green1) -- fixture broken, mutation gate aborted"
    return
  fi

  cp "$LIVENESS_SH" "${LIVENESS_SH}.finstate-orig"
  sed -i.bak 's/if _commit_age is not None and _commit_age <= finished_window:/if False:  # LANE-LIVENESS-THREE-STATES-02 mutation gate/' "$LIVENESS_SH"
  rm -f "${LIVENESS_SH}.bak"

  red="$(_placement_probe "$repo" "$tid" "$state")"

  cp "${LIVENESS_SH}.finstate-orig" "$LIVENESS_SH"
  rm -f "${LIVENESS_SH}.finstate-orig"

  green2="$(_placement_probe "$repo" "$tid" "$state")"

  if [[ "$red" != finished:* && "$green2" == finished:* ]]; then
    pass "Test 5a: mutation collapsed finished-check -> verdict=$red (RED); revert -> verdict=$green2 (GREEN)"
  else
    fail "Test 5a: RED/GREEN control failed -- baseline=$green1 red=$red after_revert=$green2"
  fi
}

# ── Test 5b: mutation gate -- leadv2-lanes-snapshot.sh finished-veto ────────

test_5b_mutation_gate_snapshot() {
  log "Test 5b: mutating leadv2-lanes-snapshot.sh's finished-veto must let escalation fire again (RED), revert restores no-escalation (GREEN)"
  local repo state active_path tid dead_pid
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  dead_pid="$(_dead_pid)"
  # 600s: strictly between LEADV2_LANE_FRESH_S (120s, the pre-existing
  # LIES-01 freshness veto) and LEADV2_LANE_FINISHED_WINDOW_S (1800s) -- a
  # fresh (age=0) commit would satisfy BOTH vetoes, so mutating only the
  # new finished-veto would not isolate its effect (the old veto would
  # still clear reasons via the authoritative liveness row's age_s, which
  # equals commit_age for a finished verdict). This age makes the old veto
  # NOT fire, so the mutation gate below actually tests the new code.
  _commit_aged "$repo" "finished work" 600
  tid="MUTGATE-SNAPSHOT"

  _fixture_row() {
    cat > "$active_path" <<YAML
sessions:
  - task_id: ${tid}
    session_id: mg2
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: ${dead_pid}
    pid_birth: null
    worktree: "${repo}"
    protocol_version: 2
    backend: terminal
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  }

  # GREEN baseline: unmutated snapshot script must not escalate this lane.
  _fixture_row
  _bypass_reconcile_grace "$repo" "$state"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 5b: baseline poll 1 exited nonzero"; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 5b: baseline poll 2 exited nonzero"; return; }
  local green1
  green1="$(_row_present "$active_path" "$tid")"
  if [[ "$green1" != True ]]; then
    fail "Test 5b: pre-mutation baseline must keep the row present (got present=$green1) -- fixture broken, mutation gate aborted"
    return
  fi

  # RED: mutate, reset the poll state, re-run the exact same 2-poll cycle.
  cp "$SNAPSHOT_SH" "${SNAPSHOT_SH}.finstate-orig"
  sed -i.bak 's/if _commit_age is not None and _commit_age <= _LANE_FINISHED_WINDOW_S:/if False:  # LANE-LIVENESS-THREE-STATES-02 mutation gate/' "$SNAPSHOT_SH"
  rm -f "${SNAPSHOT_SH}.bak"

  _fixture_row
  _bypass_reconcile_grace "$repo" "$state"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || true
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || true
  local red
  red="$(_row_present "$active_path" "$tid")"

  cp "${SNAPSHOT_SH}.finstate-orig" "$SNAPSHOT_SH"
  rm -f "${SNAPSHOT_SH}.finstate-orig"

  # GREEN after revert: same 2-poll cycle, fresh state, must keep the row again.
  _fixture_row
  _bypass_reconcile_grace "$repo" "$state"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 5b: post-revert poll 1 exited nonzero"; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SNAPSHOT_SH" --json >/dev/null 2>&1 || { fail "Test 5b: post-revert poll 2 exited nonzero"; return; }
  local green2
  green2="$(_row_present "$active_path" "$tid")"

  if [[ "$red" == False && "$green2" == True ]]; then
    pass "Test 5b: mutation re-enabled escalation on a finished lane (row pruned, RED); revert restores no-escalation (row kept, GREEN)"
  else
    fail "Test 5b: RED/GREEN control failed -- baseline_present=$green1 red_present=$red after_revert_present=$green2"
  fi
}

test_1_live_pid_alive_not_escalated
test_2_finished_no_escalation_redispatch_admitted
test_3_dead_no_commit_escalates
test_4_fresh_stream_does_not_override_finished
test_5a_mutation_gate_liveness
test_5b_mutation_gate_snapshot

echo
log "==================================================================="
log "RESULTS: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
