#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-orphan-reaper leadv2-stale-sweeper leadv2-stale-pid-sweep anti-silence-pulse leadv2-lane-liveness leadv2-worktree-cleanup
# tests/test-orphan-reaper-and-singleflight-01.sh — CONTROL-PLANE-SATURATES-01
#
# Locks both halves of the control-plane saturation fix:
#
#   A  single-flight gate: a full stale-sweep whose lock shows a LIVE owner
#      exits 0 printing "already running" and never reaches the slow tail;
#      a sweep that completes RELEASES the lock (next sweep proceeds); a
#      provably dead/mismatched holder is reclaimed.
#   B  orphan reaper, positive case: a pulse-shaped process of a session
#      with an idle transcript AND a broken owner chain is TERMed and its
#      pidfile litter removed.
#   C  orphan reaper, NEGATIVE case (live watcher of a live session must
#      survive): the same pulse fixture with a FRESH transcript is NOT
#      killed — the transcript signal vetoes the kill even though the chain
#      is broken.
#   D  three-answer kill -0 discipline: pid 1 (EPERM) reads ALIVE, not dead.
#   E  pulse owner belt (persona-engine scripts/anti-silence-pulse.sh, the
#      sibling change of this task): a pulse self-exits when its session is
#      provably dead (chain broken + idle transcript) and SURVIVES a fresh
#      transcript. SKIPPED (not failed) where the persona-engine checkout is
#      absent (leadv2 CI runner) — plugin-side cases A-D still gate.
#   F  worktree-cleanup sweep single-flight (the 13-concurrent-cleanup half
#      of the 2026-09-06 measurement): a --sweep-dead whose lock shows a
#      LIVE owner exits 0 at the gate and never walks a single worktree;
#      a --name reap is never gated (must always work); a dead holder is
#      reclaimed and the lock released on completion.
#   G  lane-liveness single-flight verdict share (the 8-parallel-python3
#      half): a second same-subject probe inside the TTL replays the cached
#      verdict byte-identically with NO new python3 (probe-count seam); a
#      LIVE in-flight owner is waited on, never barged past; a provably dead
#      in-flight holder is reclaimed; SHARE=0 restores one-probe-per-call.
#
# Mutation negative controls (paired; applied to COPIES inside the mutated
# function BODY, never at file top level — the 2026-08-25 lesson):
#   NC-A  _ssw_lock_owner_alive neutered to always report dead
#         -> case A1 flips (the sweeper storms past a live holder).
#   NC-B  _session_death_age_min neutered to never answer 'alive'
#         -> case C flips (the reaper kills a live session's pulse).
#   NC-C  _owner_transcript_dead neutered to always report dead
#         -> case E2 flips (the belt kills a fresh-transcript pulse).
#   NC-D  _ll_fresh neutered to never answer fresh
#         -> case G1 flips (every caller pays its own python3 again).
#   NC-E  _wtc_owner_alive neutered to always report dead
#         -> case F1 flips (the cleanup storms past a live holder).
#
# Hermetic: scratch dirs for control plane (LEADV2_STATE_ROOT), transcripts
# (LEADV2_REAPER_PROJECTS_DIR / PULSE_OWNER_PROJECTS_DIR), fake git repo for
# the sweeper, fixture processes with pulse-shaped argv. No real control
# plane, no network. Run:
#   bash plugins/leadv2/scripts/tests/test-orphan-reaper-and-singleflight-01.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
# The belt change rides persona-engine's lane branch first; main catches up
# at merge. Prefer the running session's own checkout (CLAUDE_PROJECT_DIR),
# then the sibling repo next to leadv2, then the laptop path (local dev).
PE_PULSE_CANDIDATES=(
  "${CLAUDE_PROJECT_DIR:-}/scripts/anti-silence-pulse.sh"
  "$REPO_ROOT/../persona-engine/scripts/anti-silence-pulse.sh"
  "/Users/kostiantyn.vlasenko/Projects/persona-engine/scripts/anti-silence-pulse.sh"
)

PASS=0; FAIL=0; SKIP=0
ok()   { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
skip() { printf '[TEST] SKIP: %s\n' "$1"; SKIP=$((SKIP+1)); }

TMP="$(mktemp -d /tmp/leadv2-reaper-singleflight-XXXXXX)"
cleanup() {
  local p
  for p in $(jobs -p 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

SID_DEAD="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
SID_LIVE="11111111-2222-3333-4444-555555555555"

# scratch control plane + transcripts + fake repo
mkdir -p "$TMP/state" "$TMP/leadv2dir" "$TMP/projects/slug" "$TMP/fakerepo" "$TMP/pulsestate"
: >"$TMP/projects/slug/$SID_LIVE.jsonl"                       # FRESH transcript
touch -t 202001010000 "$TMP/projects/slug/$SID_DEAD.jsonl"    # 26-year-idle

norm_lstart() {  # same normalization the sweeper/pulse writers use
  local s
  s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

wait_gone() {  # <pid> <timeout_s> -> 0 if the pid exited within timeout
  local pid="$1" t="$2" i
  for i in $(seq 1 $(( t * 10 ))); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -0 "$pid" 2>/dev/null && return 1
  return 0
}

# ── fixture: a pulse-shaped orphan (argv must contain anti-silence-pulse.sh)
# spawned orphaned: the spawning subshell exits immediately, so the fixture
# is reparented to launchd (ppid=1) — a genuinely broken owner chain.
cat >"$TMP/anti-silence-pulse.sh" <<'FIXTURE'
#!/usr/bin/env bash
# fixture stand-in with pulse-shaped argv: anti-silence-pulse.sh
while :; do sleep 1; done
FIXTURE
chmod +x "$TMP/anti-silence-pulse.sh"

spawn_orphan_pulse() {  # <sid> -> echoes pid of the newest fixture
  local sid="$1"
  ( nohup bash "$TMP/anti-silence-pulse.sh" >/dev/null 2>&1 & )
  sleep 0.4
  ps -axo pid,command | grep "bash $TMP/anti-silence-pulse.sh" \
    | grep -v grep | awk '{print $1}' | tail -1
}

# ── Case D: kill -0 three answers (cheap, do it first) ─────────────────────
# NOTE: capture stderr into a variable first — `kill -0 1 2>&1 | grep` under
# set -o pipefail returns kill's rc=1 even when grep matches (pipefail makes
# the WHOLE pipeline non-zero), which silently fell to the else branch.
_D_ERR="$(kill -0 1 2>&1 || true)"
if kill -0 1 2>/dev/null; then
  ok "D: pid 1 answers kill -0 rc=0 (alive)"
elif printf '%s' "$_D_ERR" | grep -qi "not permitted"; then
  ok "D: pid 1 answers EPERM (alive, never dead)"
else
  bad "D: pid 1 gave neither rc=0 nor EPERM — three-answer discipline unverifiable"
fi

# ── Case B: dead-session pulse is reaped ───────────────────────────────────
# The reaper walks $PROJECT_ROOT/docs/leadv2/anti-silence-pulse.<sid>.pid —
# the pidfile dir must be the REAL layout, not an invented "pulsestate" dir.
mkdir -p "$TMP/docs/leadv2"
DEAD_PID="$(spawn_orphan_pulse "$SID_DEAD")"
if [[ -n "${DEAD_PID:-}" ]] && kill -0 "$DEAD_PID" 2>/dev/null; then
  printf '%s\n' "$DEAD_PID" >"$TMP/docs/leadv2/anti-silence-pulse.$SID_DEAD.pid"
  LEADV2_PROJECT_ROOT="$TMP" \
  LEADV2_REAPER_PROJECTS_DIR="$TMP/projects" \
  LEADV2_REAPER_IDLE_MIN=5 \
    bash "$SCRIPTS_DIR/leadv2-orphan-reaper.sh" >"$TMP/reaper-b.log" 2>&1
  if wait_gone "$DEAD_PID" 3; then
    grep -q "TERM pid=$DEAD_PID" "$TMP/reaper-b.log" \
      && ok "B: dead-session pulse TERMed with reason line" \
      || bad "B: pulse died but no TERM line — check log: $(tail -3 "$TMP/reaper-b.log")"
    [[ ! -f "$TMP/docs/leadv2/anti-silence-pulse.$SID_DEAD.pid" ]] \
      && ok "B: dead pulse pidfile litter removed" \
      || bad "B: dead pulse pidfile still present"
  else
    bad "B: dead-session pulse survived the reaper — log: $(tail -5 "$TMP/reaper-b.log")"
  fi
else
  bad "B: fixture pulse did not spawn"
fi

# ── Case C (NEGATIVE): fresh-transcript pulse must SURVIVE the reaper ──────
LIVE_PID="$(spawn_orphan_pulse "$SID_LIVE")"
if [[ -n "${LIVE_PID:-}" ]] && kill -0 "$LIVE_PID" 2>/dev/null; then
  printf '%s\n' "$LIVE_PID" >"$TMP/docs/leadv2/anti-silence-pulse.$SID_LIVE.pid"
  LEADV2_PROJECT_ROOT="$TMP" \
  LEADV2_REAPER_PROJECTS_DIR="$TMP/projects" \
  LEADV2_REAPER_IDLE_MIN=5 \
    bash "$SCRIPTS_DIR/leadv2-orphan-reaper.sh" >"$TMP/reaper-c.log" 2>&1
  if kill -0 "$LIVE_PID" 2>/dev/null; then
    ok "C: fresh-transcript pulse SURVIVED the reaper (transcript signal vetoes the kill)"
    [[ -f "$TMP/docs/leadv2/anti-silence-pulse.$SID_LIVE.pid" ]] \
      && ok "C: live pulse pidfile kept" \
      || bad "C: live pulse pidfile was removed anyway"
  else
    bad "C: reaper KILLED a live session's pulse — log: $(tail -5 "$TMP/reaper-c.log")"
  fi
  kill "$LIVE_PID" 2>/dev/null || true
else
  bad "C: fixture pulse did not spawn"
fi

# ── Case A: sweeper single-flight gate ─────────────────────────────────────
# fake repo so the sweeper's tail has something harmless to walk; the
# registry resolves its control plane into $TMP/state-root (LEADV2_STATE_ROOT)
git -C "$TMP/fakerepo" init -q -b main 2>/dev/null || git -C "$TMP/fakerepo" init -q
git -C "$TMP/fakerepo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

run_sweeper() {  # <sandbox-sweeper-path> <log-out>
  LEADV2_PROJECT_ROOT="$TMP/fakerepo" \
  LEADV2_STATE_ROOT="$TMP/state-root" \
  LEADV2_LEADV2_DIR="$TMP/leadv2dir" \
    timeout 60 bash "$1" --non-interactive >"$2" 2>&1
}

# lock path = dirname of the registry yaml the sweeper itself resolves —
# ask the resolver, never guess the slug layout
LOCK_DIR="$TMP/state-root/.stale-sweeper-full.lock"
YAML_SANDBOX="$(LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
  bash "$SCRIPTS_DIR/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null || true)"
[[ -n "$YAML_SANDBOX" ]] && LOCK_DIR="$(dirname "$YAML_SANDBOX")/.stale-sweeper-full.lock"
sleep 120 & HOLDER=$!
A1_LOG="$TMP/sweep-a1.log"

# A1: live holder -> the sweep must exit 0 at the gate, never reaching the tail
mkdir -p "$LOCK_DIR"
printf '%s\n' "$HOLDER" >"$LOCK_DIR/owner.pid"
norm_lstart "$(ps -o lstart= -p "$HOLDER")" >"$LOCK_DIR/owner.birth"
run_sweeper "$SCRIPTS_DIR/leadv2-stale-sweeper.sh" "$A1_LOG"
A1_RC=$?
if [[ $A1_RC -eq 0 ]] && grep -q "already running (pid=$HOLDER)" "$A1_LOG"; then
  ok "A1: live lock holder -> sweeper exits 0 at the gate"
else
  bad "A1: sweeper did not stop at a live holder (rc=$A1_RC): $(grep -E 'already|reclaim' "$A1_LOG" | head -2)"
fi
# the gate path must not have released someone else's lock
kill -0 "$HOLDER" 2>/dev/null && ok "A1: live holder untouched by the gated sweeper" \
  || bad "A1: gated sweeper killed or released the live holder"

# A2: dead holder -> reclaimed, sweep proceeds and RELEASES on completion
kill "$HOLDER" 2>/dev/null; wait_gone "$HOLDER" 3 || true
printf '%s\n' "$HOLDER" >"$LOCK_DIR/owner.pid"   # leave the dead pid in place
run_sweeper "$SCRIPTS_DIR/leadv2-stale-sweeper.sh" "$TMP/sweep-a2.log"
A2_RC=$?
if [[ $A2_RC -eq 0 ]] && grep -q "provably stale holder" "$TMP/sweep-a2.log"; then
  ok "A2: dead holder reclaimed with an auditable line"
else
  bad "A2: reclaim path silent or wrong rc=$A2_RC: $(grep -E 'already|reclaim|single-flight' "$TMP/sweep-a2.log" | head -2)"
fi
if [[ ! -d "$LOCK_DIR" ]]; then
  ok "A2: lock RELEASED after a completed sweep (no permanent block)"
else
  bad "A2: lock dir survived a completed sweep: $(ls "$LOCK_DIR" 2>/dev/null)"
fi

# ── Case E: pulse owner belt (persona-engine anti-silence-pulse.sh) ────────
PE_PULSE=""
for c in "${PE_PULSE_CANDIDATES[@]}"; do
  [[ -n "$c" && -f "$c" ]] && PE_PULSE="$c" && break
done
if [[ -n "$PE_PULSE" ]] && grep -q "_owner_belt_should_exit" "$PE_PULSE"; then
  # E1: dead session (idle transcript, chain broken) -> belt self-exits
  ( export PULSE_PID_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.pid" \
           PULSE_HEARTBEAT_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.heartbeat" \
           PULSE_LOG_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.log" \
           LEADV2_ANTI_SILENCE_INTERVAL_S=1 PULSE_OWNER_IDLE_MIN=1 \
           PULSE_OWNER_PROJECTS_DIR="$TMP/projects"
    nohup bash "$PE_PULSE" >/dev/null 2>&1 & )
  sleep 4
  # identify the fixture by ITS OWN pidfile (the pulse writes $$ there at
  # startup), never by `ps | grep "bash $PE_PULSE"` — a live session arming
  # the SAME checkout's pulse (its SessionStart hook) matches that grep too,
  # and the E2 cleanup kill would then TERM the session's real pulse
  # (observed live: exit 143 mid-suite).
  BELT_PID="$(cat "$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.pid" 2>/dev/null || true)"
  if [[ -n "${BELT_PID:-}" ]] && kill -0 "$BELT_PID" 2>/dev/null; then
    if wait_gone "$BELT_PID" 5; then
      grep -q "owner belt" "$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.log" 2>/dev/null \
        && ok "E1: dead-session pulse SELF-EXITED via owner belt (auditable line)" \
        || ok "E1: dead-session pulse self-exited (no belt log line — check belt logging)"
    else
      kill "$BELT_PID" 2>/dev/null || true
      bad "E1: belt did not exit a dead-session pulse"
    fi
  else
    # already gone within the settle window — that IS the belt; require the line
    grep -q "owner belt" "$TMP/pulsestate/anti-silence-pulse.$SID_DEAD.log" 2>/dev/null \
      && ok "E1: dead-session pulse self-exited fast via owner belt (auditable line)" \
      || bad "E1: pulse vanished without a belt line — could not attribute the exit"
  fi
  # E2: fresh transcript -> belt must keep it alive
  ( export PULSE_PID_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.pid" \
           PULSE_HEARTBEAT_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.heartbeat" \
           PULSE_LOG_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.log" \
           LEADV2_ANTI_SILENCE_INTERVAL_S=1 PULSE_OWNER_IDLE_MIN=60 \
           PULSE_OWNER_PROJECTS_DIR="$TMP/projects"
    nohup bash "$PE_PULSE" >/dev/null 2>&1 & )
  sleep 4
  BELT2_PID="$(cat "$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.pid" 2>/dev/null || true)"
  if [[ -n "${BELT2_PID:-}" ]] && kill -0 "$BELT2_PID" 2>/dev/null; then
    ok "E2: fresh-transcript pulse SURVIVED the belt"
    kill "$BELT2_PID" 2>/dev/null || true
  else
    bad "E2: belt killed (or lost) a fresh-transcript pulse"
  fi
elif [[ -z "$PE_PULSE" ]]; then
  skip "E: persona-engine checkout not present (leadv2 CI runner) — belt cases skipped"
else
  skip "E: anti-silence-pulse.sh at $PE_PULSE has no owner belt (pre-belt checkout)"
fi

# ── Case F: worktree-cleanup sweep single-flight gate ───────────────────────
# Same sandbox as case A (fakerepo + state-root). The cleanup resolves its
# control plane the same way; the sweep body resolves REPO_ROOT from CWD, so
# run it from the fixture repo — a stray CWD would sweep a REAL tree.
WTC_LOCK_DIR="$(LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
  bash "$SCRIPTS_DIR/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null || true)"
[[ -n "$WTC_LOCK_DIR" ]] && WTC_LOCK_DIR="$(dirname "$WTC_LOCK_DIR")/.worktree-cleanup-sweep.lock" \
  || WTC_LOCK_DIR="$TMP/state-root/.worktree-cleanup-sweep.lock"
mkdir -p "$(dirname "$WTC_LOCK_DIR")" 2>/dev/null || true
sleep 120 & HOLDER3=$!

# F1: live holder -> gated exit, never one worktree walked, holder untouched
mkdir -p "$WTC_LOCK_DIR"
printf '%s\n' "$HOLDER3" >"$WTC_LOCK_DIR/owner.pid"
norm_lstart "$(ps -o lstart= -p "$HOLDER3")" >"$WTC_LOCK_DIR/owner.birth"
( cd "$TMP/fakerepo" && \
  LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
    timeout 60 bash "$SCRIPTS_DIR/leadv2-worktree-cleanup.sh" --sweep-dead ) >"$TMP/wtc-f1.log" 2>&1
F1_RC=$?
if [[ $F1_RC -eq 0 ]] && grep -q "sweep already running (pid=$HOLDER3)" "$TMP/wtc-f1.log"; then
  ok "F1: live lock holder -> worktree-cleanup exits 0 at the gate"
else
  bad "F1: cleanup did not stop at a live holder (rc=$F1_RC): $(grep -E 'already|reclaim|sweep' "$TMP/wtc-f1.log" | head -2)"
fi
kill -0 "$HOLDER3" 2>/dev/null && ok "F1: live holder untouched by the gated cleanup" \
  || bad "F1: gated cleanup killed or released the live holder"

# F2: --name is deliberately NOT gated — a targeted reap must always run
( cd "$TMP/fakerepo" && \
  LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
    timeout 60 bash "$SCRIPTS_DIR/leadv2-worktree-cleanup.sh" --name nonexistent-lane-xyz ) >"$TMP/wtc-f2.log" 2>&1
F2_RC=$?
if ! grep -q "sweep already running" "$TMP/wtc-f2.log"; then
  ok "F2: --name reap bypasses the sweep gate (reached its own logic, rc=$F2_RC)"
else
  bad "F2: --name reap was blocked by the sweep single-flight gate"
fi

# F3: dead holder -> reclaimed with an auditable line, sweep completes, lock released
kill "$HOLDER3" 2>/dev/null; wait_gone "$HOLDER3" 3 || true
printf '%s\n' "$HOLDER3" >"$WTC_LOCK_DIR/owner.pid"   # leave the dead pid in place
( cd "$TMP/fakerepo" && \
  LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
    timeout 60 bash "$SCRIPTS_DIR/leadv2-worktree-cleanup.sh" --sweep-dead ) >"$TMP/wtc-f3.log" 2>&1
F3_RC=$?
if grep -q "provably stale holder" "$TMP/wtc-f3.log"; then
  ok "F3: dead holder reclaimed with an auditable line"
else
  bad "F3: reclaim path silent (rc=$F3_RC): $(grep -E 'already|reclaim|single-flight' "$TMP/wtc-f3.log" | head -2)"
fi
if [[ ! -d "$WTC_LOCK_DIR" ]]; then
  ok "F3: cleanup lock RELEASED after a completed sweep"
else
  bad "F3: cleanup lock dir survived a completed sweep: $(ls "$WTC_LOCK_DIR" 2>/dev/null)"
fi

# ── Case G: lane-liveness single-flight verdict share ───────────────────────
# Same sandbox; LEADV2_TEST_CONTEXT is explicitly UNset (run-all exports it
# for the whole tree and the gate must stay off there — case G4's SHARE=0
# covers the rollback direction). The probe-count seam is the oracle: one
# line per REAL python3 probe, nothing on a cached replay.
LL_COUNT="$TMP/ll-probe-count.txt"; : >"$LL_COUNT"
run_liveness() {  # <extra-env-as-varargs...> -> stdout verdict, logs to $TMP/ll-last.log
  ( cd "$TMP/fakerepo" && env -u LEADV2_TEST_CONTEXT \
      LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
      LEADV2_LANE_LIVENESS_SHARE_TTL_S=60 \
      LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE="$LL_COUNT" \
      "$@" \
    timeout 60 bash "$SCRIPTS_DIR/leadv2-lane-liveness.sh" --all --json --no-codex \
      --project-root "$TMP/fakerepo" ) >"$TMP/ll-last.out" 2>"$TMP/ll-last.log"
}
LL_SLOT_DIR="$(dirname "$(LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
  bash "$SCRIPTS_DIR/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null)")/.lane-liveness-share"
mkdir -p "$LL_SLOT_DIR" 2>/dev/null || true

# G1: probe once, then replay inside the TTL — ONE python3 total, identical bytes
run_liveness
G1_RC1=$?
O1="$(cat "$TMP/ll-last.out")"
run_liveness
G1_RC2=$?
O2="$(cat "$TMP/ll-last.out")"
if [[ $G1_RC1 -eq 0 && $G1_RC2 -eq 0 && -n "$O1" && "$O1" == "$O2" ]]; then
  ok "G1: second same-subject probe replayed byte-identically (rc $G1_RC1/$G1_RC2)"
else
  bad "G1: replay mismatch or empty verdict (rc $G1_RC1/$G1_RC2, len ${#O1} vs ${#O2})"
fi
N_PROBES="$(grep -c '^probe ' "$LL_COUNT" || true)"
if [[ "$N_PROBES" -eq 1 ]]; then
  ok "G1: exactly ONE real probe served both callers (no second python3)"
else
  bad "G1: expected 1 probe for 2 same-subject callers, saw $N_PROBES: $(cat "$LL_COUNT")"
fi

# G2 (NEGATIVE: a live in-flight holder is never barged past): fabricate a
# live owner mid-flight with NO verdict yet -> the caller must WAIT the full
# WAIT_S window, then fall back to running its own probe — never emit a
# fabricated verdict, never steal the lock while the owner lives.
sleep 120 & HOLDER4=$!
# The slot key hashes every LEADV2_LANE_* knob with its default — rather than
# re-derive the hash here (which would fork the spec), find the slot dir the
# G1 runs actually used: the only key dir under the share root.
LL_KEY_DIR="$(find "$LL_SLOT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ -n "$LL_KEY_DIR" ]]; then
  mkdir -p "$LL_KEY_DIR/in-flight.d"
  printf '%s\n' "$HOLDER4" >"$LL_KEY_DIR/in-flight.d/owner.pid"
  norm_lstart "$(ps -o lstart= -p "$HOLDER4")" >"$LL_KEY_DIR/in-flight.d/owner.birth"
  rm -f "$LL_KEY_DIR/ts"   # no completed verdict: the waiter must NOT replay
  G2_START=$(date +%s)
  run_liveness LEADV2_LANE_LIVENESS_SHARE_WAIT_S=2
  G2_RC=$?
  G2_ELAPSED=$(( $(date +%s) - G2_START ))
  if grep -q '(unshared)' "$LL_COUNT" && [[ "$G2_RC" -eq 0 ]] && [[ "$G2_ELAPSED" -ge 2 ]]; then
    ok "G2: live in-flight owner waited out (${G2_ELAPSED}s >= 2s), then probed unshared — never barged, never fabricated"
  else
    bad "G2: rc=$G2_RC elapsed=${G2_ELAPSED}s count='$(cat "$LL_COUNT")' — barged, blocked, or fabricated"
  fi
  # the fabricated holder's lock files are NOT ours to release — verify the
  # caller left the live holder's in-flight.d alone (only the owner path cleans)
  [[ -f "$LL_KEY_DIR/in-flight.d/owner.pid" ]] \
    && ok "G2: live holder's in-flight.d left intact by the waiter" \
    || bad "G2: waiter destroyed a live holder's in-flight.d"
  kill "$HOLDER4" 2>/dev/null || true
else
  bad "G2: could not locate the share slot dir G1 used — gate layout changed?"
fi

# G3: provably dead in-flight holder -> reclaimed, probe runs owned.
# Drop the completed verdict's ts (NOT TTL=0 — a same-second run reads as
# fresh at TTL=0 and silently replays) so the reclaim path must run the probe.
if [[ -n "${LL_KEY_DIR:-}" ]]; then
  wait_gone "$HOLDER4" 3 || true
  rm -f "$LL_KEY_DIR/ts"
  mkdir -p "$LL_KEY_DIR/in-flight.d"
  printf '%s\n' "$HOLDER4" >"$LL_KEY_DIR/in-flight.d/owner.pid"
  : >"$LL_KEY_DIR/in-flight.d/owner.birth"   # dead pid: reclaim regardless of birth
  N_BEFORE="$(grep -c '^probe ' "$LL_COUNT" || true)"
  ( cd "$TMP/fakerepo" && env -u LEADV2_TEST_CONTEXT \
      LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
      LEADV2_LANE_LIVENESS_SHARE_TTL_S=60 \
      LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE="$LL_COUNT" \
    timeout 60 bash "$SCRIPTS_DIR/leadv2-lane-liveness.sh" --all --json --no-codex \
      --project-root "$TMP/fakerepo" ) >"$TMP/ll-g3.out" 2>"$TMP/ll-g3.log"
  G3_RC=$?
  N_AFTER="$(grep -c '^probe ' "$LL_COUNT" || true)"
  if [[ "$G3_RC" -eq 0 && "$N_AFTER" -gt "$N_BEFORE" ]] \
     && grep -q "provably dead in-flight holder" "$TMP/ll-g3.log"; then
    ok "G3: dead in-flight holder reclaimed with an auditable line, probe ran owned"
  else
    bad "G3: rc=$G3_RC probes $N_BEFORE->$N_AFTER log='$(grep -E 'reclaim|dead' "$TMP/ll-g3.log" | head -1)'"
  fi
fi

# G4: rollback knob — SHARE=0 restores one probe per call
N_BEFORE="$(grep -c '^probe ' "$LL_COUNT" || true)"
run_liveness LEADV2_LANE_LIVENESS_SHARE=0
run_liveness LEADV2_LANE_LIVENESS_SHARE=0
N_AFTER="$(grep -c '^probe ' "$LL_COUNT" || true)"
if [[ "$(( N_AFTER - N_BEFORE ))" -eq 2 ]]; then
  ok "G4: LEADV2_LANE_LIVENESS_SHARE=0 -> every call probes (one-step rollback works)"
else
  bad "G4: SHARE=0 still shared: $N_BEFORE -> $N_AFTER probes for 2 calls"
fi

# ── Mutation negative controls (copies; mutation INSIDE the function body) ─

# NC-A: sweeper lock-alive check neutered
sed 's|^  _ssw_pid_alive "$owner" \|\| return 1$|  return 1 # MUTATED: holder always dead|' \
  "$SCRIPTS_DIR/leadv2-stale-sweeper.sh" >"$TMP/sweeper-ncA.sh" 2>/dev/null || true
if grep -q "MUTATED: holder always dead" "$TMP/sweeper-ncA.sh"; then
  sleep 120 & HOLDER2=$!
  mkdir -p "$LOCK_DIR"
  printf '%s\n' "$HOLDER2" >"$LOCK_DIR/owner.pid"
  norm_lstart "$(ps -o lstart= -p "$HOLDER2")" >"$LOCK_DIR/owner.birth"
  LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
  LEADV2_LEADV2_DIR="$TMP/leadv2dir" \
    timeout 60 bash "$TMP/sweeper-ncA.sh" --non-interactive >"$TMP/sweep-ncA.log" 2>&1
  if grep -q "already running (pid=$HOLDER2)" "$TMP/sweep-ncA.log"; then
    bad "NC-A: mutated sweeper still gated (mutation not exercised)"
  else
    ok "NC-A: neutered lock-alive check -> 'already running' disappears (suite goes red on mutation)"
  fi
  kill "$HOLDER2" 2>/dev/null || true
  rm -rf "$LOCK_DIR"
else
  bad "NC-A: sed mutation did not apply (pattern drifted — fix the suite)"
fi

# NC-B: reaper session-death oracle neutered -> 'alive' never returned
# (structure-preserving: an unreachable condition, not a comment that
# swallows `printf 'alive'` — an EMPTY then-branch is a bash syntax error
# and would redden every case for the wrong reason)
sed "s|if (( age_min < REAPER_IDLE_MIN )); then printf 'alive'|if (( age_min < 0 )); then printf 'alive' # MUTATED: always dead|" \
  "$SCRIPTS_DIR/leadv2-orphan-reaper.sh" >"$TMP/reaper-ncB.sh"
if grep -q "MUTATED: always dead" "$TMP/reaper-ncB.sh" && bash -n "$TMP/reaper-ncB.sh" 2>/dev/null; then
  LIVE_PID2="$(spawn_orphan_pulse "$SID_LIVE")"
  printf '%s\n' "$LIVE_PID2" >"$TMP/docs/leadv2/anti-silence-pulse.$SID_LIVE.pid"
  LEADV2_PROJECT_ROOT="$TMP" LEADV2_REAPER_PROJECTS_DIR="$TMP/projects" \
  LEADV2_REAPER_IDLE_MIN=5 \
    bash "$TMP/reaper-ncB.sh" >"$TMP/reaper-ncB.log" 2>&1
  if kill -0 "$LIVE_PID2" 2>/dev/null; then
    bad "NC-B: mutated reaper STILL spared the live pulse (mutation not exercised)"
  else
    ok "NC-B: neutered death oracle -> live-session pulse gets killed (C goes red on mutation)"
  fi
  kill "$LIVE_PID2" 2>/dev/null || true
else
  bad "NC-B: sed mutation did not apply or broke syntax (pattern drifted — fix the suite)"
fi

# NC-C: pulse belt transcript oracle neutered -> fresh transcript reads dead
if [[ -n "${PE_PULSE:-}" ]] && grep -q "_owner_belt_should_exit" "$PE_PULSE"; then
  sed 's|^  (( age_min >= PULSE_OWNER_IDLE_MIN ))$|  return 0 # MUTATED: transcript always dead|' \
    "$PE_PULSE" >"$TMP/pulse-ncC.sh"
  if grep -q "MUTATED: transcript always dead" "$TMP/pulse-ncC.sh" && bash -n "$TMP/pulse-ncC.sh" 2>/dev/null; then
    ( export PULSE_PID_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.pid" \
             PULSE_HEARTBEAT_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.heartbeat" \
             PULSE_LOG_FILE="$TMP/pulsestate/anti-silence-pulse.$SID_LIVE.log" \
             LEADV2_ANTI_SILENCE_INTERVAL_S=1 PULSE_OWNER_IDLE_MIN=60 \
             PULSE_OWNER_PROJECTS_DIR="$TMP/projects"
      nohup bash "$TMP/pulse-ncC.sh" >/dev/null 2>&1 & )
    sleep 4
    NC_PID="$(ps -axo pid,command | grep "bash $TMP/pulse-ncC.sh" | grep -v grep | awk '{print $1}' | tail -1)"
    if [[ -n "${NC_PID:-}" ]] && kill -0 "$NC_PID" 2>/dev/null; then
      bad "NC-C: mutated belt did NOT kill the fresh pulse — mutation ineffective (belt never reached?)"
      kill "$NC_PID" 2>/dev/null || true
    else
      ok "NC-C: neutered transcript oracle -> fresh-transcript pulse self-exits (E2 goes red on mutation)"
    fi
  else
    bad "NC-C: sed mutation did not apply or broke syntax (pattern drifted — fix the suite)"
  fi
fi

# NC-D: lane-liveness freshness check neutered -> cached verdicts never replay
sed 's|^  (( $(date +%s) - ts <= _ll_ttl ))$|  return 1 # MUTATED: never fresh|' \
  "$SCRIPTS_DIR/leadv2-lane-liveness.sh" >"$TMP/liveness-ncD.sh"
if grep -q "MUTATED: never fresh" "$TMP/liveness-ncD.sh" && bash -n "$TMP/liveness-ncD.sh" 2>/dev/null; then
  LL_COUNT_D="$TMP/ll-ncD-count.txt"; : >"$LL_COUNT_D"
  for _i in 1 2; do
    ( cd "$TMP/fakerepo" && env -u LEADV2_TEST_CONTEXT \
        LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
        LEADV2_LANE_LIVENESS_SHARE_TTL_S=60 \
        LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE="$LL_COUNT_D" \
      timeout 60 bash "$TMP/liveness-ncD.sh" --all --json --no-codex \
        --project-root "$TMP/fakerepo" ) >/dev/null 2>&1
  done
  NC_D_PROBES="$(grep -c '^probe ' "$LL_COUNT_D" || true)"
  if [[ "$NC_D_PROBES" -ge 2 ]]; then
    ok "NC-D: neutered freshness -> every caller pays its own python3 (G1 goes red on mutation)"
  else
    bad "NC-D: mutated gate still shared ($NC_D_PROBES probe for 2 callers — mutation not exercised)"
  fi
else
  bad "NC-D: sed mutation did not apply or broke syntax (pattern drifted — fix the suite)"
fi

# NC-E: worktree-cleanup holder-alive check neutered -> gate storms past live
# holders (4-space indent: the helper lives inside the gate's if-block)
sed 's|^    _wtc_pid_alive "$owner" \|\| return 1$|    return 1 # MUTATED: holder always dead|' \
  "$SCRIPTS_DIR/leadv2-worktree-cleanup.sh" >"$TMP/wtc-ncE.sh"
if grep -q "MUTATED: holder always dead" "$TMP/wtc-ncE.sh" && bash -n "$TMP/wtc-ncE.sh" 2>/dev/null; then
  sleep 120 & HOLDER5=$!
  mkdir -p "$WTC_LOCK_DIR"
  printf '%s\n' "$HOLDER5" >"$WTC_LOCK_DIR/owner.pid"
  norm_lstart "$(ps -o lstart= -p "$HOLDER5")" >"$WTC_LOCK_DIR/owner.birth"
  ( cd "$TMP/fakerepo" && \
    LEADV2_PROJECT_ROOT="$TMP/fakerepo" LEADV2_STATE_ROOT="$TMP/state-root" \
      timeout 60 bash "$TMP/wtc-ncE.sh" --sweep-dead ) >"$TMP/wtc-ncE.log" 2>&1
  if grep -q "sweep already running (pid=$HOLDER5)" "$TMP/wtc-ncE.log"; then
    bad "NC-E: mutated cleanup still gated (mutation not exercised)"
  else
    ok "NC-E: neutered holder-alive check -> the gate storms past a live holder (F1 goes red on mutation)"
  fi
  kill "$HOLDER5" 2>/dev/null || true
  rm -rf "$WTC_LOCK_DIR"
else
  bad "NC-E: sed mutation did not apply or broke syntax (pattern drifted — fix the suite)"
fi

printf '\n[TEST] reaper-singleflight: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
