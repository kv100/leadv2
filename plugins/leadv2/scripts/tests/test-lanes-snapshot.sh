#!/usr/bin/env bash
# tests/test-lanes-snapshot.sh — SUPERVISOR-DELETE-01 (2026-08-19): retargeted
# from tests/test-supervise-v2.sh onto leadv2-lanes-snapshot.sh (the renamed
# leadv2-supervise.sh, kept as a live founder-status lanes-table dependency)
# after the supervisor loop/pick/watchdog machinery was deleted outright.
# Carries forward exactly the coverage that survives the rename — pure
# reconciliation logic with no loop/pick dependency:
#
#   3. adoption triple-proof matrix — name-only tmux window -> orphan
#      (never adopted); full proof (name+task-id+live claude PID) -> adopted.
#   4. tombstone-before-prune — a corroborated-dead row is tombstoned AND
#      removed from active.yaml; the observe_only visibility fix (would_prune
#      always reports a gated-but-eligible prune) is asserted directly.
#   5. truth-probe timeout -> unavailable (fail-open-to-EMPTY, never -clear).
#   7. R2-3 AND-condition death matrix (window+PID BOTH required).
#   8. R2-4 tombstone-write-failure keeps the row (never a silent prune).
#   9. R2-5 DEAD event dedup through new_events (once, not every poll).
#  12. SUPERVISOR-AUDIT-01 fix — pid:null funnel row survives prune.
#
# Dropped (loop/pick-only, subject deleted with the loop):
#   test_1 loop cadence/ceiling, test_2 pick-script ranking, test_10 --ensure
#   atomic attach, test_11 global legacy question scan.
#
# Fully isolated: LEADV2_STATE_ROOT points every control-plane read/write at
# a throwaway tmp dir (never ~/.claude/leadv2-state/<real-repo>), and tmux
# tests use an isolated `tmux -L` socket (never the real "leadv2" session).
# No GNU-only utilities. Run: bash scripts/tests/test-lanes-snapshot.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LANES_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
LANES_RESUME_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-resume.sh"
ACTIVE_REGISTRY_SH="${PLUGIN_DIR}/scripts/leadv2-active-registry.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# Keep every suite-lifetime fallback surface private. Individual cases retain
# their explicit fixture roots and tmux sockets; these exports cover subject
# paths that use the defaults before a case-specific override is supplied.
LEADV2_SUPERVISE_TMP_ROOT="$(lv2_mktemp_dir "lns-root")"
# This host provides PyYAML from its Python user-site. Capture that immutable
# dependency before changing HOME, so fixture isolation does not make the
# subject fail to parse its YAML registry.
LEADV2_SUPERVISE_PYTHON_USER_SITE="$(python3 -c 'import site; print(site.getusersitepackages())')"
export HOME="$LEADV2_SUPERVISE_TMP_ROOT/home"
export XDG_CACHE_HOME="$LEADV2_SUPERVISE_TMP_ROOT/cache"
export LEADV2_STATE_ROOT="$LEADV2_SUPERVISE_TMP_ROOT/state"
export LEADV2_SUPERVISE_TMUX_SOCKET="$LEADV2_SUPERVISE_TMP_ROOT/tmux"
export PYTHONPATH="$LEADV2_SUPERVISE_PYTHON_USER_SITE${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$HOME/.claude/cache" "$XDG_CACHE_HOME" "$LEADV2_STATE_ROOT"

CLEANUP_DIRS=()
TMUX_SOCKETS=()
cleanup() {
  tmux -L "$LEADV2_SUPERVISE_TMUX_SOCKET" kill-server 2>/dev/null || true
  for s in "${TMUX_SOCKETS[@]:-}"; do
    [[ -n "$s" ]] && tmux -L "$s" kill-server 2>/dev/null || true
  done
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

_new_fixture() {
  # Creates one isolated repo+state root pair. Prints "<repo> <state>".
  local repo state
  repo="$(lv2_mktemp_dir "lns-repo")"
  state="$(lv2_mktemp_dir "lns-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  (cd "$repo" && git init -q)
  # TEST SAFETY (B1 root cause, fix-round-2): hard-abort unless this is
  # provably a throwaway fixture — see lv2_assert_scratch_repo in
  # leadv2-temp.sh. Every fixture in this suite is created here; this is the
  # single choke point.
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$repo/.claude/cache"
  # Trailing newline is REQUIRED: `read` (in `read -r a b < <(_new_fixture)`)
  # returns 1 on EOF-without-newline even though it populated the vars —
  # under `set -e` that silently kills the whole script via the EXIT trap.
  printf -- '%s %s\n' "$repo" "$state"
}

_active_yaml() {
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml
}

json_get() {
  # json_get <key-path-via-python-dict-access>
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print($1)
"
}

# ── Test 6: bash -n syntax check on the surviving reconciliation scripts ───

test_6_syntax() {
  log "Test 6: bash -n syntax check"
  local ok=1
  for f in "$LANES_SH" "$LANES_RESUME_SH" "$ACTIVE_REGISTRY_SH"; do
    if ! bash -n "$f" 2>/dev/null; then
      fail "Test 6: bash -n failed on $f"
      ok=0
    fi
  done
  [[ "$ok" -eq 1 ]] && pass "Test 6: bash -n OK on all 3 scripts"
}

# ── Test 3: adoption triple-proof matrix ────────────────────────────────────

test_3_adoption_triple_proof() {
  log "Test 3: adoption triple-proof matrix (name-only -> orphan; full proof -> adopt)"

  local repo state active_path sock
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  printf -- 'sessions: []\n' > "$active_path"
  printf -- 'total_open: 1\ntasks:\n  - id: TASK-KNOWN\n    title: known\n    priority: 1\n' \
    > "$repo/docs/tasks.yaml"

  sock="lns-test-$$-$RANDOM"
  TMUX_SOCKETS+=("$sock")

  # keepalive window: killing the only window in a tmux session kills the
  # session itself — keep one dedicated window alive across 3a/3b so the
  # session (and socket) survive `kill-window` on the test window.
  tmux -L "$sock" new-session -d -s leadv2 -n KEEPALIVE 'sleep 90' 2>/dev/null

  # 3a: name-only orphan — window name matches NO known task id, no claude PID.
  tmux -L "$sock" new-window -t leadv2 -n UNKNOWN-WINDOW 'sleep 600' 2>/dev/null

  local out3a
  out3a="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 3a: lanes-snapshot.sh exited nonzero"; return; }

  local orphaned adopted_a
  orphaned="$(printf -- '%s' "$out3a" | json_get "any(o['window']=='UNKNOWN-WINDOW' for o in d.get('orphans', []))")"
  adopted_a="$(printf -- '%s' "$out3a" | json_get "'UNKNOWN-WINDOW' in d.get('adopted', [])")"
  if [[ "$orphaned" == True && "$adopted_a" == False ]]; then
    pass "Test 3a: unknown-name window -> orphan, never adopted"
  else
    fail "Test 3a: orphaned=$orphaned adopted=$adopted_a out=$out3a"
  fi

  tmux -L "$sock" kill-window -t "leadv2:UNKNOWN-WINDOW" 2>/dev/null || true

  # 3b: full triple proof — window name == known task id, AND a live process
  # descending from the pane has "claude" in its command name. `exec -a`
  # changes argv but not macOS's `ps ... comm` value, so use a private copy
  # of sleep named claude; this is the exact signal the subject inspects.
  # symlink, NOT a copy: macOS SIGKILLs a copied Apple-signed binary
  # (signature/path mismatch, rc=137), so the fake claude died instantly and
  # 3b failed deterministically. Through a symlink the kernel execs the
  # original signed file while ps comm reports the symlink path ("…/claude"),
  # which is the exact substring the subject matches.
  ln -sf "$(command -v sleep)" "$repo/claude"
  tmux -L "$sock" new-window -t leadv2 -n TASK-KNOWN "$repo/claude 600" 2>/dev/null
  sleep 0.3

  local out3b adopted_b
  out3b="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" LEADV2_SUPERVISE_OBSERVE_ONLY=0 \
    bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 3b: lanes-snapshot.sh exited nonzero"; return; }
  adopted_b="$(printf -- '%s' "$out3b" | json_get "'TASK-KNOWN' in d.get('adopted', []) or 'TASK-KNOWN' in d.get('would_adopt', [])")"
  if [[ "$adopted_b" == True ]]; then
    pass "Test 3b: name+task-id+live-claude-PID triple proof -> adopted (or would_adopt if reconcile_cycle gated)"
  else
    fail "Test 3b: adopted=$adopted_b out=$out3b"
  fi
}

# ── Test 4: tombstone-before-prune + observe_only visibility ──────────────

test_4_tombstone_before_prune() {
  log "Test 4: tombstone-before-prune + would_prune visibility (observe_only gap fix)"

  local repo state active_path snap
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: DEAD-1
    session_id: d1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 1
    backend: tmux
    tmux_window: DEAD-1
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  cat > "$snap" <<'JSON'
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"DEAD-1":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON

  # 4a: observe_only=1 -> reported in would_prune, NOT actually removed, no tombstone this call.
  local tombstones out4a still_present would_prune_has
  tombstones="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" tombstones.yaml)"
  out4a="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=1 bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 4a: lanes-snapshot.sh exited nonzero"; return; }
  would_prune_has="$(printf -- '%s' "$out4a" | json_get "'DEAD-1' in d.get('would_prune', [])")"
  still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='DEAD-1' for s in d.get('sessions', [])))
")"
  if [[ "$would_prune_has" == True && "$still_present" == True ]]; then
    pass "Test 4a: observe_only=1 -> would_prune reports DEAD-1, row NOT removed"
  else
    fail "Test 4a: would_prune_has=$would_prune_has still_present=$still_present out=$out4a"
  fi

  # 4b: real prune (no observe_only) -> tombstone written BEFORE/with the prune, row removed.
  local removed tombstone_has
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 4b: lanes-snapshot.sh exited nonzero"; return; }
  removed="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='DEAD-1' for s in d.get('sessions', [])))
")"
  tombstone_has="false"
  if [[ -f "$tombstones" ]]; then
    tombstone_has="$(python3 -c "
import yaml
d = yaml.safe_load(open('$tombstones')) or []
print(any(t.get('task_id')=='DEAD-1' for t in d))
")"
  fi
  if [[ "$removed" == True && "$tombstone_has" == True ]]; then
    pass "Test 4b: corroborated dead row pruned AND tombstoned"
  else
    fail "Test 4b: removed=$removed tombstone_has=$tombstone_has"
  fi
}

# ── Test 5: truth-probe timeout -> unavailable ──────────────────────────────

test_5_truth_probe_timeout() {
  log "Test 5: truth-probe timeout -> unavailable (fail-open-to-EMPTY, never -clear)"

  local repo state active_path overrides_dir probe probe_completed
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  printf -- 'sessions: []\n' > "$active_path"
  overrides_dir="$repo/.claude/leadv2-overrides"
  mkdir -p "$overrides_dir"
  probe="$overrides_dir/supervise-truth-probe.sh"
  probe_completed="$state/truth-probe-completed"
  cat > "$probe" <<SH
#!/usr/bin/env bash
sleep 15
printf done > "$probe_completed"
echo '{"breaches":[]}'
SH
  chmod +x "$probe"

  local out status reason
  out="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 5: lanes-snapshot.sh exited nonzero"; return; }

  status="$(printf -- '%s' "$out" | json_get "d.get('truth_probe',{}).get('status') if isinstance(d.get('truth_probe'), dict) else d.get('truth_probe')")"
  reason="$(printf -- '%s' "$out" | json_get "d.get('truth_probe_reason')")"
  # Wall-clock assertions were flaky on loaded macOS hosts because unrelated
  # ps/tmux probes in the same snapshot can be slow. The completion marker is
  # stronger: if the 15s child survived the 12s process-group timeout it must
  # write this file, regardless of total snapshot runtime.
  if [[ "$status" == "unavailable" && "$reason" == "timeout" && ! -e "$probe_completed" ]]; then
    pass "Test 5: timed-out probe process group was killed; status never reported clear"
  else
    fail "Test 5: status=$status reason=$reason completed_marker=$([[ -e "$probe_completed" ]] && echo yes || echo no)"
  fi
}

# ── Test 7: R2-3 AND-condition death matrix (window+PID BOTH required) ─────

test_7_and_condition_death_matrix() {
  log "Test 7: R2-3 death requires BOTH window-missing AND pid-issue (tmux backend) — fix the OR"

  local repo state active_path snap sock
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"

  # 7a: window MISSING (no tmux session at all) but PID is genuinely alive
  # (this test's own $$, birth stored correctly) -- single-signal evidence,
  # must NOT corroborate as dead across 2 polls.
  # Compute birth via the EXACT same normalization leadv2-lanes-snapshot.sh's
  # _pid_birth_of() uses (" ".join(b.split())) -- a raw `tr -s ' '` can leave
  # a leading space that the python side strips, causing a false birth
  # mismatch (window-missing WOULD then pair with a spurious pid-issue and
  # wrongly satisfy the AND -- exactly the false-positive this test guards
  # against, just from a test-fixture bug instead of the real one).
  local birth_self
  birth_self="$(python3 -c "
import subprocess
r = subprocess.run(['ps', '-o', 'lstart=', '-p', '$$'], capture_output=True, text=True)
print(' '.join(r.stdout.split()))
")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<YAML
sessions:
  - task_id: LIVE-WINDOW-FLAP
    session_id: s7a
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: $$
    pid_birth: "$birth_self"
    protocol_version: 2
    backend: tmux
    tmux_window: LIVE-WINDOW-FLAP
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  local sock7a
  sock7a="lns-t7a-$$-$RANDOM"
  TMUX_SOCKETS+=("$sock7a")   # never started -- has-session fails -> tmux_windows empty -> window "missing"

  local out7a_2
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7a" bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 7a: poll 1 exited nonzero"; return; }
  out7a_2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7a" bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 7a: poll 2 exited nonzero"; return; }
  local dead7a still7a
  dead7a="$(printf -- '%s' "$out7a_2" | json_get "any(x['task_id']=='LIVE-WINDOW-FLAP' for x in d.get('dead', []))")"
  still7a="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='LIVE-WINDOW-FLAP' for s in d.get('sessions', [])))
")"
  if [[ "$dead7a" == False && "$still7a" == True ]]; then
    pass "Test 7a: window-missing ALONE (pid alive) -> NOT dead, row kept"
  else
    fail "Test 7a: dead=$dead7a still_present=$still7a (window-missing alone must not corroborate death)"
  fi

  # 7b: window PRESENT (real tmux window with matching name) but PID is dead
  # -- single-signal evidence, must NOT corroborate as dead across 2 polls.
  local sock7b
  sock7b="lns-t7b-$$-$RANDOM"
  TMUX_SOCKETS+=("$sock7b")
  tmux -L "$sock7b" new-session -d -s leadv2 -n DEAD-PID-LIVE-WINDOW 'sleep 600' 2>/dev/null

  cat > "$active_path" <<'YAML'
sessions:
  - task_id: DEAD-PID-LIVE-WINDOW
    session_id: s7b
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 2
    backend: tmux
    tmux_window: DEAD-PID-LIVE-WINDOW
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  local out7b_2
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7b" bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 7b: poll 1 exited nonzero"; return; }
  out7b_2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7b" bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 7b: poll 2 exited nonzero"; return; }
  local dead7b still7b
  dead7b="$(printf -- '%s' "$out7b_2" | json_get "any(x['task_id']=='DEAD-PID-LIVE-WINDOW' for x in d.get('dead', []))")"
  still7b="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='DEAD-PID-LIVE-WINDOW' for s in d.get('sessions', [])))
")"
  if [[ "$dead7b" == False && "$still7b" == True ]]; then
    pass "Test 7b: pid-dead ALONE (window present) -> NOT dead, row kept"
  else
    fail "Test 7b: dead=$dead7b still_present=$still7b (pid-dead alone on a tmux lane must not corroborate death)"
  fi

  # 7c: BOTH signals together (window missing AND pid dead) -- control case,
  # confirms the AND-fix still correctly detects a genuinely dead lane.
  local sock7c
  sock7c="lns-t7c-$$-$RANDOM"
  TMUX_SOCKETS+=("$sock7c")  # never started -- window missing

  cat > "$active_path" <<'YAML'
sessions:
  - task_id: TRULY-DEAD
    session_id: s7c
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 2
    backend: tmux
    tmux_window: TRULY-DEAD
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7c" bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 7c: poll 1 exited nonzero"; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock7c" bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 7c: poll 2 exited nonzero"; return; }
  local removed7c
  removed7c="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='TRULY-DEAD' for s in d.get('sessions', [])))
")"
  if [[ "$removed7c" == True ]]; then
    pass "Test 7c: window-missing AND pid-dead TOGETHER -> corroborated dead, pruned (control case)"
  else
    fail "Test 7c: removed=$removed7c (both signals together must still corroborate death)"
  fi
}

# ── Test 8: R2-4 tombstone-write-failure keeps the row (never a silent prune) ─

test_8_tombstone_failure_keeps_row() {
  log "Test 8: R2-4 tombstone write failure -> row KEPT in active.yaml, warning emitted"

  local repo state active_path snap tombstones
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: DEAD-TOMBFAIL
    session_id: d8
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 1
    backend: tmux
    tmux_window: DEAD-TOMBFAIL
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  cat > "$snap" <<'JSON'
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"DEAD-TOMBFAIL":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON

  # Sabotage the tombstone write: pre-create tombstones.yaml AS A DIRECTORY.
  # The writer's os.replace(tmp, tombstones_file) then fails with
  # IsADirectoryError (an OSError) -- isolated to the tombstone code path,
  # never touching active.yaml's own write. This avoids chmod-based sandbox
  # cleanup hazards while still exercising a real OS-level write failure.
  tombstones="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" tombstones.yaml)"
  mkdir -p "$tombstones"

  local out8
  out8="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$LANES_SH" --json 2>/dev/null)" \
    || { fail "Test 8: lanes-snapshot.sh exited nonzero (expected 0 -- tombstone failure is non-fatal)"; return; }

  local still_present warn_has
  still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='DEAD-TOMBFAIL' for s in d.get('sessions', [])))
")"
  warn_has="$(printf -- '%s' "$out8" | json_get "any('tombstone write failed' in w for w in d.get('warnings', []))")"
  if [[ "$still_present" == True && "$warn_has" == True ]]; then
    pass "Test 8: tombstone write failure -> row KEPT in active.yaml, warning present"
  else
    fail "Test 8: still_present=$still_present warn_has=$warn_has out=$out8"
  fi
}

# ── Test 9: R2-5 DEAD event dedup through new_events (once, not every poll) ─

test_9_dead_event_dedup() {
  log "Test 9: R2-5 DEAD urgent line reported once per liveness change, not every delta poll"

  local repo state active_path snap sock
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: DEAD-DEDUP
    session_id: d9
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 1
    backend: tmux
    tmux_window: DEAD-DEDUP
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  cat > "$snap" <<'JSON'
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"DEAD-DEDUP":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON

  sock="lns-t9-$$-$RANDOM"
  TMUX_SOCKETS+=("$sock")  # never started -- window missing (AND'd with pid-dead -> corroborates)

  # observe_only=1 keeps the row alive+re-evaluated identically across
  # repeated polls -- exactly the scenario that used to spam a DEAD line
  # every 5s (finding 5).
  local out9_poll1 out9_poll2
  out9_poll1="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" LEADV2_SUPERVISE_OBSERVE_ONLY=1 \
    bash "$LANES_SH" --json --since 2020-01-01T00:00:00Z 2>/dev/null)" \
    || { fail "Test 9: poll 1 exited nonzero"; return; }
  out9_poll2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" LEADV2_SUPERVISE_OBSERVE_ONLY=1 \
    bash "$LANES_SH" --json --since 2020-01-01T00:00:00Z 2>/dev/null)" \
    || { fail "Test 9: poll 2 exited nonzero"; return; }

  local dead_poll1 dead_poll2
  dead_poll1="$(printf -- '%s' "$out9_poll1" | json_get "any(x['task_id']=='DEAD-DEDUP' for x in d.get('dead', []))")"
  dead_poll2="$(printf -- '%s' "$out9_poll2" | json_get "any(x['task_id']=='DEAD-DEDUP' for x in d.get('dead', []))")"
  if [[ "$dead_poll1" == True && "$dead_poll2" == False ]]; then
    pass "Test 9: DEAD reported on the corroborating poll, suppressed (deduped) on the next unchanged poll"
  else
    fail "Test 9: poll1_dead=$dead_poll1 poll2_dead=$dead_poll2 (expected True then False)"
  fi
}

# ── Test 12: SUPERVISOR-AUDIT-01 fix — pid:null funnel row survives prune ──

test_12_pidnull_survives_prune() {
  log "Test 12: pid:null funnel row (fresh log) survives prune, no PID-only death"

  local repo state active_path snap still_present
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: FUNNEL-1
    session_id: f1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: null
    pid_birth: null
    protocol_version: 2
    backend: dispatch-code
    log_path: docs/handoff/dispatch-abc12345/developer.stream.jsonl
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  # B9 fix (fix-round-2): use the REAL leadv2-fanout.sh single-worker-funnel
  # layout — docs/handoff/dispatch-<sig8>/developer.stream.jsonl, recorded in
  # the row's log_path — not a synthetic docs/handoff/FUNNEL-1/session.log.
  # This is the exact artifact leadv2-lane-liveness.sh's resolve() must now
  # find via log_path; a synthetic path proves nothing about the real bug.
  mkdir -p "$repo/docs/handoff/dispatch-abc12345"
  printf 'dispatch-code funnel worker output\n' > "$repo/docs/handoff/dispatch-abc12345/developer.stream.jsonl"
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  cat > "$snap" <<'JSON'
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"FUNNEL-1":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON

  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 12a: lanes-snapshot.sh exited nonzero"; return; }
  still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='FUNNEL-1' for s in d.get('sessions', [])))
")"
  if [[ "$still_present" == True ]]; then
    pass "Test 12a: pid:null row with fresh log survives prune (absent PID alone is not death)"
  else
    fail "Test 12a: FUNNEL-1 was pruned despite a fresh log (still_present=$still_present)"
  fi

  # Rollback proof: LEADV2_SUPERVISE_PRUNE_V2=0 reproduces the exact prior
  # PID-only death authority on the identical fixture -- the row IS pruned.
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: FUNNEL-1
    session_id: f1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: null
    pid_birth: null
    protocol_version: 2
    backend: dispatch-code
    log_path: docs/handoff/dispatch-abc12345/developer.stream.jsonl
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  # B9 fix (fix-round-2): use the REAL leadv2-fanout.sh single-worker-funnel
  # layout — docs/handoff/dispatch-<sig8>/developer.stream.jsonl, recorded in
  # the row's log_path — not a synthetic docs/handoff/FUNNEL-1/session.log.
  # This is the exact artifact leadv2-lane-liveness.sh's resolve() must now
  # find via log_path; a synthetic path proves nothing about the real bug.
  mkdir -p "$repo/docs/handoff/dispatch-abc12345"
  printf 'dispatch-code funnel worker output\n' > "$repo/docs/handoff/dispatch-abc12345/developer.stream.jsonl"
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  cat > "$snap" <<'JSON'
{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],
 "dead_candidates":{"FUNNEL-1":"2020-01-01T00:00:00+00:00"},"reconcile_cycle_count":5}
JSON
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 LEADV2_SUPERVISE_PRUNE_V2=0 bash "$LANES_SH" --json >/dev/null 2>&1 \
    || { fail "Test 12b: lanes-snapshot.sh exited nonzero"; return; }
  still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='FUNNEL-1' for s in d.get('sessions', [])))
")"
  if [[ "$still_present" == False ]]; then
    pass "Test 12b: LEADV2_SUPERVISE_PRUNE_V2=0 reproduces exact prior PID-only prune"
  else
    fail "Test 12b: rollback flag did not reproduce prior prune behavior (still_present=$still_present)"
  fi
}

# ── Run all ──────────────────────────────────────────────────────────────

log "=== leadv2-lanes-snapshot unit tests (SUPERVISOR-DELETE-01, retargeted from test-supervise-v2.sh) ==="
log "Scripts: $LANES_SH / $LANES_RESUME_SH / $ACTIVE_REGISTRY_SH"
echo

case "${LEADV2_SUPERVISE_TEST_ONLY:-all}" in
  truth-probe)
    test_5_truth_probe_timeout
    ;;
  all)
    test_6_syntax
    test_3_adoption_triple_proof
    test_4_tombstone_before_prune
    test_5_truth_probe_timeout
    test_7_and_condition_death_matrix
    test_8_tombstone_failure_keeps_row
    test_9_dead_event_dedup
    test_12_pidnull_survives_prune
    ;;
  *)
    fail "unknown LEADV2_SUPERVISE_TEST_ONLY=${LEADV2_SUPERVISE_TEST_ONLY}"
    ;;
esac

echo
log "=== Results: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -gt 0 ]]; then
  log "Failures:"
  for e in "${ERRORS[@]}"; do
    log "  $e"
  done
  exit 1
fi
exit 0
