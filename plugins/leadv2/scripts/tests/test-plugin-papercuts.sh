#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: codex-task.sh leadv2-dispatch-code.sh leadv2-pulse-beat.sh leadv2-routing.yaml leadv2-single-lead-beat-loop.sh
# tests/test-plugin-papercuts.sh — PLUGIN-PAPERCUTS-01 (2026-08-31, four
# plugin-level defects, each hitting every adopted repo).
#
#   P1  the loop beats THROUGH reader errors (UNKNOWN passes never stop or
#       silence it — even with the since-retired UNKNOWN_MAX knob explicitly
#       set) and stops only on ZERO_MAX consecutive REAL zeros, removing its
#       pidfile. Round 2 replaced the original P1, which asserted the
#       UNKNOWN_MAX stop that main deliberately retired (fix-round 3 H-2):
#       the monitor going blind is exactly when the beat is still needed,
#       and the lifetime leak is bounded by WATCHER-LIFECYCLE-LEAK-01 (TERM
#       reaping + singleton claim + MAX_S cap), not by counting reader
#       errors. See docs/handoff/PLUGIN-PAPERCUTS-01/report-round-2.md §1.
#   P2  a suite run ⇒ leaves no beat loop behind, and the loop's pidfile
#       cleanup is ownership-checked: a late-exiting OLD loop must not delete
#       a NEWER loop's live claim (pre-fix `rm -f $PID_FILE` unconditionally —
#       the "killed one, they respawned" multiplicity mechanism).
#   P3  a routing cell whose tier the launcher rejects ⇒ loud validation error
#       at RESOLUTION time, not a spawn-time death that silently falls through
#       to a costlier arm (routing.yaml pinned tier: spark; codex-task.sh
#       accepts only top|standard|volume and bans spark outright).
#   P4  a spawn failure that falls through to a costlier arm ⇒ logged as a
#       FAILURE naming the arm and the launcher's own reason (detail=), not
#       indistinguishable from a deliberate routing choice.
#   P5  --resume-lane <bare-name> ⇒ works (regression guard).
#   P6  --resume-lane <absolute path> ⇒ works (pre-fix: mangled
#       looked_for=<wt>/<abs-path> refusal with no guidance).
#   P7  a backlog add that cannot persist ⇒ non-zero exit, never a success
#       line. Script under test: the consuming repo's scripts/task-add.sh
#       (persona-engine checkout — repo-local defect, copied into the fixture;
#       pre-fix, a dead Supabase printed "task already exists" over [] and
#       exited 0).
#   P8  the detached --now watcher's argv carries --owner=<repo>:<lane>
#       (PLUGIN-PAPERCUTS-01 follow-on: bare argv made safe orphan sweeps
#       impossible; the stamp is derived from PROJECT_ROOT + git branch).
#
# Declared negative control (RUN RED in the lane report): P6 — reverting the
# path-form --resume-lane acceptance makes this suite fail.
#
# Hermetic: fixture git repos under mktemp, stub heartbeat/beat/journal/GLM/
# codex/lane-worktree/liveness/curl binaries, LEADV2_PULSE_MODE=0 +
# LEADV2_SINGLE_LEAD_BEAT=0 on every dispatch run so no REAL watcher is ever
# armed from a fixture. Never kills a process outside the fixture tree; kill
# targets come only from pids this suite recorded or from fixture pidfiles it
# created via LEADV2_SINGLE_LEAD_BEAT_LOOP_PID. No network, no real lanes, no
# real backlog. Run: bash plugins/leadv2/scripts/tests/test-plugin-papercuts.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOOP="$SCRIPT_DIR/leadv2-single-lead-beat-loop.sh"
DISPATCH="$SCRIPT_DIR/leadv2-dispatch-code.sh"
RESOLVER="$SCRIPT_DIR/lib/leadv2-glm-policy-resolve.py"
# The backlog writer lives in the CONSUMING repo (repo-local defect — see the
# lane report); the suite exercises a copy of it inside the fixture tree.
TASK_ADD="${HOME}/Projects/persona-engine/scripts/task-add.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-plugin-papercuts-XXXXXX)"

# Suite hygiene (P2 in the large): every kill target is either a pid THIS
# suite recorded or a pid read from a pidfile created under $TMP. Never a
# process outside the fixture tree.
PIDS=""
kill_recorded() {
  local p
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
}
wait_gone() {  # <pid> <timeout-s> -> 0 when the pid is gone
  local pid="$1" deadline=$(( $(date +%s) + ${2:-5} ))
  while (( $(date +%s) < deadline )); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.3
  done
  kill -0 "$pid" 2>/dev/null && return 1 || return 0
}
wait_beats() {  # <min-lines> <timeout-s> -> 0 when the beats log has >= min lines
  local _min="$1" _deadline=$(( $(date +%s) + ${2:-10} )) _n
  while (( $(date +%s) < _deadline )); do
    _n="$(wc -l < "$P1_BEATS" 2>/dev/null | tr -d ' ')"
    [[ "${_n:-0}" -ge "$_min" ]] && return 0
    sleep 0.3
  done
  return 1
}
cleanup() {
  kill_recorded
  local f p
  for f in "$TMP"/*.pid "$TMP"/*.loop.pid; do
    [[ -f "$f" ]] || continue
    p="$(cat "$f" 2>/dev/null | tr -d ' ')"
    [[ "$p" =~ ^[0-9]+$ ]] && kill "$p" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

# ── shared beat-loop fixture knobs ────────────────────────────────────────────
HB_UNKNOWN="$TMP/hb-unknown.sh"   # reader error every pass -> UNKNOWN
printf '#!/usr/bin/env bash\nexit 0\n' > "$HB_UNKNOWN"; chmod +x "$HB_UNKNOWN"
HB_LIVE="$TMP/hb-live.sh"         # one live lane -> the loop keeps beating
printf '#!/usr/bin/env bash\nprintf %s\n' "'[{\"status\":\"running\"}]'" > "$HB_LIVE"
chmod +x "$HB_LIVE"
BEAT_STUB="$TMP/beat-stub.sh"     # beat writer seam, records invocations
printf '#!/usr/bin/env bash\ndate +%%s >> "%s/beats.log"\n' "$TMP" > "$BEAT_STUB"
chmod +x "$BEAT_STUB"

loop_env() {  # <pidfile> [extra env assignments as args]
  # NOTE: no LEADV2_PULSE_MODE/LEADV2_SINGLE_LEAD_BEAT kill-switch here — the
  # loop itself no-ops under either. We invoke the loop DIRECTLY in this part,
  # so those switches (meant to stop DISPATCH arming real watchers) must stay
  # unset; dispatch runs below carry them in e2e_setup instead.
  local pidfile="$1"; shift
  env LEADV2_PROJECT_ROOT="$TMP/fixture-root" \
      LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$pidfile" \
      LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
      LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX=99 \
      "$@"
}

# ═══ P1: the loop beats through reader errors; only REAL zeros stop it ═══════
printf '\ntest: P1 loop beats through reader errors, stops only on real zeros\n'
mkdir -p "$TMP/fixture-root"
HB_ZERO="$TMP/hb-zero.sh"         # readable registry, zero live lanes -> REAL zero
printf '#!/usr/bin/env bash\nprintf "[]\\n"\n' > "$HB_ZERO"; chmod +x "$HB_ZERO"
P1_BEATS="$TMP/beats.log"

# ── P1a: UNKNOWN (reader-error) passes never stop or silence the loop ────────
P1A_PIDFILE="$TMP/p1a.loop.pid"; : > "$P1_BEATS"
RUNNER="$TMP/p1a-runner.sh"       # the production shape: nohup detached, run exits
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
env LEADV2_PROJECT_ROOT="$TMP/fixture-root" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$P1A_PIDFILE" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX=99 \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX=2 \
    LEADV2_SESSION_KIND=lead \
    LEADV2_LANE_HEARTBEAT_BIN="$HB_UNKNOWN" \
    LEADV2_PULSE_BEAT_BIN="$BEAT_STUB" \
  nohup bash "$LOOP" >/dev/null 2>&1 </dev/null &
echo \$! > "$TMP/p1a.pid"
EOF
chmod +x "$RUNNER"
bash "$RUNNER"
P1A_PID="$(cat "$TMP/p1a.pid" 2>/dev/null | tr -d ' ')"
PIDS="$PIDS $P1A_PID"
# Vacuous-run guard: the loop must be ALIVE ~1s after launch (kill-switch or a
# crash exits instantly).
sleep 1
if [[ "$P1A_PID" =~ ^[0-9]+$ ]] && ! kill -0 "$P1A_PID" 2>/dev/null; then
  bad "P1a setup: loop pid $P1A_PID died immediately — the loop never ran (vacuous)"
else
  # bounded wait for >=3 beats: a fixed sleep flaked under load (the loop's
  # first pass can exceed any fixed window). The assertions below are unchanged.
  wait_beats 3 15 || true
  P1A_BEATS="$(wc -l < "$P1_BEATS" | tr -d ' ')"
  P1A_CLAIM="$(cat "$P1A_PIDFILE" 2>/dev/null | tr -d ' ')"
  if [[ "${P1A_BEATS:-0}" -ge 3 ]] \
     && kill -0 "$P1A_PID" 2>/dev/null \
     && [[ "$P1A_CLAIM" == "$P1A_PID" ]]; then
    ok "P1a: $P1A_BEATS beats through reader errors — loop alive, claim held (UNKNOWN_MAX inert)"
  else
    bad "P1a: loop silenced/stopped on reader errors (beats=${P1A_BEATS:-0}, alive=$(kill -0 "$P1A_PID" 2>/dev/null && echo y || echo n), claim=$P1A_CLAIM)"
  fi
fi
kill "$P1A_PID" 2>/dev/null || true
wait_gone "$P1A_PID" 5 || true
: > "$P1_BEATS"

# ── P1b: ZERO_MAX consecutive REAL zeros stop the loop; pidfile removed ──────
P1B_PIDFILE="$TMP/p1b.loop.pid"
RUNNER="$TMP/p1b-runner.sh"
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
env LEADV2_PROJECT_ROOT="$TMP/fixture-root" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$P1B_PIDFILE" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX=2 \
    LEADV2_SESSION_KIND=lead \
    LEADV2_LANE_HEARTBEAT_BIN="$HB_ZERO" \
    LEADV2_PULSE_BEAT_BIN="$BEAT_STUB" \
  nohup bash "$LOOP" >/dev/null 2>&1 </dev/null &
echo \$! > "$TMP/p1b.pid"
EOF
chmod +x "$RUNNER"
bash "$RUNNER"
P1B_PID="$(cat "$TMP/p1b.pid" 2>/dev/null | tr -d ' ')"
PIDS="$PIDS $P1B_PID"
sleep 1
if [[ "$P1B_PID" =~ ^[0-9]+$ ]] && ! kill -0 "$P1B_PID" 2>/dev/null; then
  bad "P1b setup: loop pid $P1B_PID died immediately — the loop never ran (vacuous)"
else
  if wait_beats 1 15; then   # the loop must beat at least once before it may stop
    if wait_gone "$P1B_PID" 20; then
      if [[ ! -f "$P1B_PIDFILE" ]]; then
        ok "P1b: loop beat, then stopped itself after ZERO_MAX=2 real zeros; pidfile removed"
      else
        bad "P1b: loop exited but left its pidfile behind ($P1B_PIDFILE)"
      fi
    else
      bad "P1b: beat loop kept beating on a genuinely empty board (pid $P1B_PID still alive)"
    fi
  else
    bad "P1b: fixture loop never beat — assertions would be vacuous"
  fi
fi

# ═══ P2: a suite leaves no loop behind + pidfile cleanup is ownership-checked ═
printf '\ntest: P2 pidfile cleanup must not delete a NEWER loop claim / suite leaves nothing\n'
# The loop's REAL pid must be read from the pidfile, never from `$!`:
# `loop_env ... &` backgrounds a FUNCTION, so bash forks a subshell whose pid
# $! reports, and the loop's own $$ (what the pidfile records) is a CHILD pid
# whenever the subshell does not exec the final command — a race (measured:
# 2 flakes in 5 standalone iterations). Poll the pidfile and adopt whatever
# live pid it names.
_arm_loop() {  # <pidfile> -> echoes the loop pid; empty on timeout
  local _pf="$1" _owner="" _dl=$(( $(date +%s) + 8 ))
  while (( $(date +%s) < _dl )); do
    _owner="$(cat "$_pf" 2>/dev/null | tr -d ' ')"
    if [[ "$_owner" =~ ^[0-9]+$ ]] && kill -0 "$_owner" 2>/dev/null; then
      printf '%s' "$_owner"; return 0
    fi
    sleep 0.3
  done
  return 1
}
P2A_PIDFILE="$TMP/p2a.loop.pid"
loop_env "$P2A_PIDFILE" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX=0 \
    LEADV2_LANE_HEARTBEAT_BIN="$HB_LIVE" \
    LEADV2_SESSION_KIND=lead \
    LEADV2_PULSE_BEAT_BIN="$BEAT_STUB" \
    bash "$LOOP" >/dev/null 2>&1 &
P2A_PID="$(_arm_loop "$P2A_PIDFILE")"
[[ -n "$P2A_PID" ]] && PIDS="$PIDS $P2A_PID"
if [[ -n "$P2A_PID" ]]; then
  # Simulate the multiplicity race: A's pidfile claim disappears while A still
  # runs; a NEW dispatch arms loop B, which takes over the pidfile.
  rm -f "$P2A_PIDFILE"
  P2B_PIDFILE="$TMP/p2b.loop.pid"
  loop_env "$P2B_PIDFILE" \
      LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX=0 \
      LEADV2_LANE_HEARTBEAT_BIN="$HB_LIVE" \
      LEADV2_SESSION_KIND=lead \
      LEADV2_PULSE_BEAT_BIN="$BEAT_STUB" \
      bash "$LOOP" >/dev/null 2>&1 &
  P2B_PID="$(_arm_loop "$P2B_PIDFILE")"
  [[ -n "$P2B_PID" ]] && PIDS="$PIDS $P2B_PID"
  if [[ -n "$P2B_PID" ]]; then
    kill "$P2A_PID" 2>/dev/null || true   # the OLD loop exits late
    if wait_gone "$P2A_PID" 5; then
      if [[ "$(cat "$P2B_PIDFILE" 2>/dev/null | tr -d ' ')" == "$P2B_PID" ]] \
         && kill -0 "$P2B_PID" 2>/dev/null; then
        ok "P2a: old loop exited WITHOUT deleting the newer loop's pidfile claim"
      else
        bad "P2a: old loop's exit deleted the NEWER loop's pidfile claim (respawn multiplicity)"
      fi
    else
      bad "P2a: old loop pid $P2A_PID did not exit after TERM"
    fi
  else
    bad "P2a setup: loop B never took ownership of the pidfile"
  fi
else
  bad "P2a setup: loop A never armed (no live pid in $P2A_PIDFILE)"
fi
kill_recorded   # do not leak loops into later assertions
# P2b: a suite-scope run that arms a loop must leave NOTHING behind on exit.
SIM_SUITE="$TMP/sim-suite.sh"
cat > "$SIM_SUITE" <<EOF
#!/usr/bin/env bash
set -u
SIM_PIDFILE="$TMP/sim.loop.pid"
env LEADV2_PROJECT_ROOT="$TMP/fixture-root" \\
    LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="\$SIM_PIDFILE" \\
    LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \\
    LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX=99 \\
    LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX=1 \\
    LEADV2_LANE_HEARTBEAT_BIN="$HB_UNKNOWN" \\
    LEADV2_PULSE_BEAT_BIN="$BEAT_STUB" \\
  nohup bash "$LOOP" >/dev/null 2>&1 </dev/null &
SIM_PID=\$!
cleanup_sim() { kill "\$SIM_PID" 2>/dev/null || true; }
trap cleanup_sim EXIT
sleep 1
exit 0
EOF
chmod +x "$SIM_SUITE"
bash "$SIM_SUITE"; SIM_RC=$?
SIM_PID="$(cat "$TMP/sim.loop.pid" 2>/dev/null | tr -d ' ')"
[[ -n "$SIM_PID" ]] && PIDS="$PIDS $SIM_PID"
if [[ "$SIM_RC" -eq 0 ]] && { [[ -z "$SIM_PID" ]] || wait_gone "$SIM_PID" 8; }; then
  ok "P2b: suite-scope run exited leaving no beat loop behind"
else
  bad "P2b: suite-scope run rc=$SIM_RC left beat loop pid ${SIM_PID:-?} alive"
fi

# ═══ dispatch fixture (P3–P6) — harness template: test-phase-precondition.sh ══
E2E_SANDBOX="$TMP/e2e"
E2E_REPO="$E2E_SANDBOX/repo"
mkdir -p "$E2E_REPO"
# Empty git template dir: the sandbox intermittently denies reading
# /Library/.../git-core/templates ("fatal: cannot copy ... Operation not
# permitted", measured 2026-08-31) — GIT_TEMPLATE_DIR keeps git init/worktree
# hermetic and immune to that flake.
mkdir -p "$E2E_SANDBOX/git-template-empty"
export GIT_TEMPLATE_DIR="$E2E_SANDBOX/git-template-empty"
( cd "$E2E_REPO" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
E2E_REPO_PHYS="$(cd "$E2E_REPO" && pwd -P)"   # macOS /tmp -> /private/tmp
# The resume lane MUST be a real git worktree of the fixture repo: placement
# validates the candidate's owning git root against PROJECT_ROOT, and a plain
# directory is refused as foreign_repo (measured pre-fix).
mkdir -p "$E2E_REPO/.claude/worktrees"
git -C "$E2E_REPO" worktree add -q "$E2E_REPO/.claude/worktrees/PPC-LANE-A" -b PPC-LANE-A 2>/dev/null \
  || printf 'P5/P6 fixture: git worktree add failed\n' >&2
E2E_CACHE="$E2E_SANDBOX/cache"; E2E_STATE="$E2E_SANDBOX/state"; E2E_STUB_RUNS="$E2E_SANDBOX/glm-runs"
GLM_STUB="$E2E_SANDBOX/glm-stub.sh"
cat > "$GLM_STUB" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg)
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"; exit 0 ;;
  status)
    [[ -n "${2:-}" && -f "$RUNS/$2" ]] && exit 0
    exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$GLM_STUB"
CODEX_FAIL_STUB="$E2E_SANDBOX/codex-fail-stub.sh"
cat > "$CODEX_FAIL_STUB" <<'SH'
#!/usr/bin/env bash
# codex-task.sh seam stub: rejects the tier the way the real launcher does.
case "${1:-}" in
  task)
    echo "[codex-task] unknown --tier: spark (expected top|standard|volume)" >&2
    exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$CODEX_FAIL_STUB"
CODEX_OK_STUB="$E2E_SANDBOX/codex-ok-stub.sh"
printf '#!/usr/bin/env bash\necho "PPC fixture task started in the background as task-fixture01-stub01."\nexit 0\n' > "$CODEX_OK_STUB"
chmod +x "$CODEX_OK_STUB"
SUBSESSION_STUB="$E2E_SANDBOX/subsession-stub.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s SESSION_ID=ppc-stub\\n" "$$"\nexit 0\n' > "$SUBSESSION_STUB"
chmod +x "$SUBSESSION_STUB"
E2E_JOURNAL="$E2E_SANDBOX/journal-stub.sh"; E2E_JOURNAL_LOG="$E2E_SANDBOX/journal.log"
printf '#!/usr/bin/env bash\necho "$*" >> "%s" 2>/dev/null || true\n' "$E2E_JOURNAL_LOG" > "$E2E_JOURNAL"
chmod +x "$E2E_JOURNAL"
LANE_WT_STUB="$E2E_SANDBOX/lane-wt-stub.sh"
cat > "$LANE_WT_STUB" <<SH
#!/usr/bin/env bash
[[ "\${1:-}" == "path-of" ]] || exit 0
ref="\${2:-}"
d="${E2E_REPO}/.claude/worktrees/\$ref"
[[ -d "\$d" ]] && printf '%s\n' "\$d"
exit 0
SH
chmod +x "$LANE_WT_STUB"
mkdir -p "$E2E_REPO/.claude/worktrees/PPC-LANE-A" "$E2E_STUB_RUNS"

write_routing_yaml() {  # <codex_default_tier>
  mkdir -p "$E2E_REPO/.claude/ref"
  # glm_policy MUST be indented 2 spaces under a parent key — the resolver's
  # block extractor matches `^  glm_policy:` (leadv2-glm-policy-resolve.py
  # extract_glm_policy_block). At column 0 the block silently parses to all
  # defaults (arm=glm reason=glm_default) and the codex path is never reached.
  cat > "$E2E_REPO/.claude/ref/leadv2-routing.yaml" <<EOF
router:
  glm_policy:
    codex_fitting_mission_kinds: [tooling]
    codex_default_tier: ${1}
    sonnet_exceptions: []
capability_matrix:
  - { arm: glm, provider: glm, model: glm-5.3, tier: standard, cost: 1, kinds: [code, docs, tooling], sizes: [standard, heavy, bulk], review: false, protected: false }
  - { arm: codex, provider: codex, model: gpt-5.6, tier: ${1}, cost: 3, kinds: [code, docs, tooling], sizes: [standard], review: true, protected: true }
  - { arm: sonnet, provider: claude, model: sonnet, tier: standard, cost: 5, kinds: [code, docs, tooling], sizes: [standard, heavy], review: true, protected: true }
effort_matrix:
  - { default: true, effort: medium }
EOF
}

e2e_setup() {
  : > "${E2E_JOURNAL_LOG}"
  export LEADV2_PROJECT_ROOT="$E2E_REPO"
  export CLAUDE_PROJECT_DIR="$E2E_REPO"
  # The dispatch runs below MUST execute with cwd INSIDE $E2E_REPO: invoked
  # from the lane worktree, the foreign-root guard (dispatch-code.sh:339-407)
  # sees env-root(fixture) != cwd-git-root(worktree) and re-roots PROJECT_ROOT
  # to the worktree — the fixture routing yaml is then never read and the
  # PLUGIN's config arms (freepool) leak into the fixture (measured: P6 refused
  # with freepool_refused_lock_busy, an arm the fixture yaml does not define).
  # e2e_dispatch runs every invocation from inside the fixture repo.
  export LEADV2_DISPATCH_CODEX_BIN="$CODEX_OK_STUB"   # NEVER the real launcher
  e2e_dispatch() {  # <rc-var> <stderr-file> <dispatch args...>
    local _rcvar="$1" _errf="$2"; shift 2
    ( cd "$E2E_REPO" && bash "$DISPATCH" "$@" ) >/dev/null 2>"$_errf" \
      || eval "${_rcvar}=\$?"
  }
  export LEADV2_DISPATCH_CACHE_DIR="$E2E_CACHE"
  export LEADV2_STATE_BASE="$E2E_STATE"
  export LEADV2_DISPATCH_GLM_BIN="$GLM_STUB"
  export LEADV2_DISPATCH_SUBSESSION_BIN="$SUBSESSION_STUB"
  export LEADV2_STUB_GLM_RUNS="$E2E_STUB_RUNS"
  export LEADV2_JOURNAL_BIN="$E2E_JOURNAL"
  export LEADV2_ROUTER_V2=0
  export LEADV2_LANE_SHAPE=off
  export LEADV2_DISPATCH_E2E_GATE=0
  export LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_DISPATCH_PENDING_TTL_S=5
  export LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  export LEADV2_DISPATCH_LANE_WORKTREE_BIN="$LANE_WT_STUB"
  export LEADV2_DISPATCH_LANE_LIVENESS_BIN="/bin/true"   # fail-open: lane not live
  # hermeticity: the arbiter lib, task judge, and cost estimator would invoke a
  # REAL `claude -p` from inside the fixture dispatch — stub/disable all three.
  # NOTE: /dev/null is NOT a regular file, so the lib lookup's `[[ -f ]]`
  # rejects it and falls back to the real lib — use an empty regular file.
  : > "$E2E_SANDBOX/no-arbiter.lib"
  export LEADV2_ROUTE_ARBITER_LIB="$E2E_SANDBOX/no-arbiter.lib"   # no route_arbiter fn
  export LEADV2_TASK_JUDGE_BIN="$E2E_SANDBOX/judge-stub.sh"
  export LEADV2_DISPATCH_COST_ESTIMATE=0
  # fixture-leak regression guard: a test dispatch must NEVER arm real watchers
  export LEADV2_PULSE_MODE=0
  export LEADV2_SINGLE_LEAD_BEAT=0
  unset LEADV2_REQUIRE_PHASES LEADV2_LANE_START_SHA 2>/dev/null || true
}
# fast offline judge: no `claude -p`, deterministic JSON
printf '#!/usr/bin/env bash\nprintf %s\n' "'{\"work_kind\":\"build\",\"complexity\":\"simple\",\"duration_class\":\"short\"}'" > "$E2E_SANDBOX/judge-stub.sh"
chmod +x "$E2E_SANDBOX/judge-stub.sh"

# ═══ P3: a routing cell whose tier the launcher rejects ⇒ loud error ═════════
printf '\ntest: P3 rejected codex tier fails LOUDLY at resolution, no fallthrough\n'
e2e_setup
write_routing_yaml spark
P3_RC=0
P3_ERR="$TMP/p3.err"
e2e_dispatch P3_RC "$P3_ERR" --kind tooling "PPC-P3 mission tier rejection probe"
if [[ "$P3_RC" -ne 0 ]] \
   && grep -q "route_tier_invalid" "$E2E_JOURNAL_LOG" \
   && grep -q "tier=spark" "$E2E_JOURNAL_LOG" \
   && grep -q "not launchable" "$P3_ERR" \
   && ! grep -q "route_resolved" "$E2E_JOURNAL_LOG"; then
  ok "P3: tier=spark refused at resolution (rc=$P3_RC, route_tier_invalid journaled, no route_resolved)"
else
  bad "P3: expected loud rejection (rc!=0 + route_tier_invalid + no route_resolved); got rc=$P3_RC, journal: $(tail -2 "$E2E_JOURNAL_LOG" 2>/dev/null | tr '\n' ';')"
fi
# positive control: a tier the launcher accepts resolves normally
e2e_setup
write_routing_yaml volume
P3B_RC=0
e2e_dispatch P3B_RC /dev/null --kind tooling "PPC-P3 mission tier volume positive control"
if [[ "$P3B_RC" -eq 0 ]] && grep -q "route_resolved" "$E2E_JOURNAL_LOG"; then
  ok "P3b: tier=volume resolves and dispatches normally (rc=0)"
else
  bad "P3b: valid tier should resolve cleanly; rc=$P3B_RC"
fi

# ═══ P4: spawn-time fallthrough is logged as a FAILURE naming arm + reason ═══
printf '\ntest: P4 spawn fallthrough journals a failure naming the arm and reason\n'
e2e_setup
write_routing_yaml volume
export LEADV2_DISPATCH_CODEX_BIN="$CODEX_FAIL_STUB"   # launcher rejects the tier
P4_RC=0
e2e_dispatch P4_RC /dev/null --kind tooling "PPC-P4 mission codex launcher fails at spawn" --spawn
if grep -q "spawn_failed by=router model=codex" "$E2E_JOURNAL_LOG" \
   && grep -q "detail=.*unknown --tier" "$E2E_JOURNAL_LOG" \
   && grep -q "route_fallback from=codex" "$E2E_JOURNAL_LOG"; then
  ok "P4: codex spawn failure journaled with arm + launcher reason, then route_fallback"
else
  bad "P4: journal missing spawn_failed(model=codex)+detail or route_fallback(from=codex); got: $(grep -E 'spawn_failed|route_fallback' "$E2E_JOURNAL_LOG" 2>/dev/null | head -2 | tr '\n' ';')"
fi

# ═══ P5: --resume-lane <bare-name> still works (regression guard) ═════════════
printf '\ntest: P5 --resume-lane bare name resolves the lane worktree\n'
e2e_setup
P5_RC=0
e2e_dispatch P5_RC "$TMP/p5.err" --kind tooling "PPC-P5 mission resume bare name" \
  --resume-lane PPC-LANE-A
if [[ "$P5_RC" -eq 0 ]] \
   && grep -q "lane_placement_pinned" "$E2E_JOURNAL_LOG" \
   && grep -q "path=${E2E_REPO_PHYS}/.claude/worktrees/PPC-LANE-A" "$E2E_JOURNAL_LOG"; then
  ok "P5: bare lane name pins the lane worktree (rc=0)"
else
  bad "P5: bare name should pin cleanly; rc=$P5_RC err=$(tail -1 "$TMP/p5.err" 2>/dev/null)"
fi

# ═══ P6: --resume-lane <absolute path> works (DECLARED NEGATIVE CONTROL) ═════
printf '\ntest: P6 --resume-lane absolute path pins the same worktree\n'
e2e_setup
P6_RC=0
e2e_dispatch P6_RC "$TMP/p6.err" --kind tooling "PPC-P6 mission resume absolute path" \
  --resume-lane "${E2E_REPO}/.claude/worktrees/PPC-LANE-A"
if [[ "$P6_RC" -eq 0 ]] \
   && grep -q "lane_placement_pinned" "$E2E_JOURNAL_LOG" \
   && grep -q "path=${E2E_REPO_PHYS}/.claude/worktrees/PPC-LANE-A" "$E2E_JOURNAL_LOG"; then
  ok "P6: absolute path form pins the lane worktree (rc=0)"
else
  bad "P6: absolute path form refused; rc=$P6_RC err=$(tail -2 "$TMP/p6.err" 2>/dev/null | tr '\n' ';')"
fi
# P6b: a genuinely bad ref still refuses, but WITH the accepted shapes.
e2e_setup
P6B_RC=0
e2e_dispatch P6B_RC "$TMP/p6b.err" --kind tooling "PPC-P6b mission bad ref" \
  --resume-lane "PPC-NO-SUCH-LANE"
if [[ "$P6B_RC" -eq 5 ]] && grep -q "accepted shapes" "$TMP/p6b.err"; then
  ok "P6b: unknown ref refuses with rc=5 and a message showing the accepted shapes"
else
  bad "P6b: unknown ref should refuse rc=5 with guidance; rc=$P6B_RC err=$(tail -1 "$TMP/p6b.err" 2>/dev/null)"
fi

# ═══ P7: a backlog add that cannot persist exits non-zero, never success ══════
printf '\ntest: P7 task-add.sh dead-write refusal (fixture copy, stubbed curl)\n'
if [[ ! -f "$TASK_ADD" ]]; then
  bad "P7 setup: consuming repo script not found at $TASK_ADD — cannot run the fixture"
else
  TA_REPO="$TMP/taskadd"
  mkdir -p "$TA_REPO/scripts"
  cp "$TASK_ADD" "$TA_REPO/scripts/task-add.sh"
  CURL_STUB_DIR="$TMP/bin"; mkdir -p "$CURL_STUB_DIR"
  # dead curl: network unreachable, like a downed Supabase
  printf '#!/usr/bin/env bash\nexit 7\n' > "$CURL_STUB_DIR/curl"; chmod +x "$CURL_STUB_DIR/curl"
  P7_RC=0
  ( cd "$TA_REPO" \
    && PATH="$CURL_STUB_DIR:$PATH" \
       SUPABASE_URL="http://fixture.invalid" SUPABASE_SERVICE_ROLE_KEY="fixture" \
       bash scripts/task-add.sh "PPC-P7 dead write probe" --group ppc-fixture \
         --acceptance-cmd 'true' --expect '0' \
       >"$TMP/p7.out" 2>"$TMP/p7.err" ) || P7_RC=$?
  if [[ "$P7_RC" -ne 0 ]] && grep -q "NOTHING was written" "$TMP/p7.err"; then
    ok "P7: dead Supabase ⇒ rc=$P7_RC with an explicit nothing-persisted error"
  else
    bad "P7: dead write must exit non-zero with the refusal error; rc=$P7_RC out=$(tail -1 "$TMP/p7.out" 2>/dev/null) err=$(tail -1 "$TMP/p7.err" 2>/dev/null)"
  fi
  # positive control: a persisting POST returns the row and exits 0
  rm -f "$CURL_STUB_DIR/curl"
  cat > "$CURL_STUB_DIR/curl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *probe_registry*) exit 0 ;;                                   # merge, output ignored
  *work_items*) printf '[{"id":"fixture-row","fingerprint":"abc"}]'; exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$CURL_STUB_DIR/curl"
  P7B_RC=0
  ( cd "$TA_REPO" \
    && PATH="$CURL_STUB_DIR:$PATH" \
       SUPABASE_URL="http://fixture.invalid" SUPABASE_SERVICE_ROLE_KEY="fixture" \
       bash scripts/task-add.sh "PPC-P7 live write probe" --group ppc-fixture \
         --acceptance-cmd 'true' --expect '0' \
       >"$TMP/p7b.out" 2>"$TMP/p7b.err" ) || P7B_RC=$?
  if [[ "$P7B_RC" -eq 0 ]] && grep -q "fixture-row" "$TMP/p7b.out"; then
    ok "P7b: persisting write still succeeds (rc=0, row returned)"
  else
    bad "P7b: healthy write should exit 0 with the row; rc=$P7B_RC out=$(tail -1 "$TMP/p7b.out" 2>/dev/null)"
  fi
fi

# ═══ P8: the spawned --now watcher carries --owner=<repo>:<lane> in argv ══════
# PLUGIN-PAPERCUTS-01 defect 1, follow-on constraint: a reparented watcher's
# argv is the only thing identifying its owner — a bare
# "pulse-beat.sh --now" made a safe orphan sweep impossible (2026-08-31
# census). PATH-shimmed nohup/setsid capture the spawn argv WITHOUT running
# the real watcher, so nothing leaks out of the fixture.
printf '\ntest: P8 watcher argv carries --owner=<repo>:<lane>\n'
P8_DIR="$TMP/p8-repo"
mkdir -p "$P8_DIR"
git -C "$P8_DIR" init -q -b worktree-P8-LANE 2>/dev/null \
  || { git -C "$P8_DIR" init -q && git -C "$P8_DIR" checkout -q -b worktree-P8-LANE; }
P8_SHIMS="$TMP/p8-shims"; mkdir -p "$P8_SHIMS"
for _s in nohup setsid; do
  printf '#!/bin/sh\nprintf ":%%s " "$0" >> "%s/spawn.log"\nfor _a in "$@"; do printf "[%%s]" "$_a" >> "%s/spawn.log"; done\nprintf "\n" >> "%s/spawn.log"\nexit 0\n' \
    "$P8_SHIMS" "$P8_SHIMS" "$P8_SHIMS" > "$P8_SHIMS/$_s"
  chmod +x "$P8_SHIMS/$_s"
done
rm -f "$P8_SHIMS/spawn.log"
# LEADV2_STATE_ROOT pins the control-plane state under the fixture: fresh
# throttle clock (due) and no live loop sentinel — otherwise the gates would
# consult the REAL shared state and rightly refuse to spawn.
PATH="$P8_SHIMS:$PATH" LEADV2_PROJECT_ROOT="$P8_DIR" LEADV2_STATE_ROOT="$TMP/p8-state" \
  LEADV2_SINGLE_LEAD_BEAT=1 \
  bash "$SCRIPT_DIR/leadv2-pulse-beat.sh" --check >"$TMP/p8.out" 2>"$TMP/p8.err"
# the spawn is backgrounded and the parent exits at once — wait (bounded) for
# the shim to be scheduled before asserting
_p8_w=0
while (( _p8_w < 10 )) && [[ ! -s "$P8_SHIMS/spawn.log" ]]; do sleep 0.3; _p8_w=$((_p8_w+1)); done
if grep -q -- "--owner=p8-repo:worktree-P8-LANE" "$P8_SHIMS/spawn.log" 2>/dev/null; then
  ok "P8: spawned watcher argv carries the owner stamp ($(grep -o -- '--owner=[^ >]*' "$P8_SHIMS/spawn.log" | head -1))"
else
  bad "P8: watcher spawn must carry --owner=<repo>:<lane>; spawn.log=$(cat "$P8_SHIMS/spawn.log" 2>/dev/null | head -1)"
fi
# explicit caller pin wins over derivation (P8 stamped the throttle clock —
# reset it so P8b is due again)
find "$TMP/p8-state" -name .pulse-beat-last -delete 2>/dev/null
rm -f "$P8_SHIMS/spawn.log"
PATH="$P8_SHIMS:$PATH" LEADV2_PROJECT_ROOT="$P8_DIR" LEADV2_STATE_ROOT="$TMP/p8-state" \
  LEADV2_SINGLE_LEAD_BEAT=1 LEADV2_BEAT_OWNER_TAG="other-repo:worktree-OTHER" \
  bash "$SCRIPT_DIR/leadv2-pulse-beat.sh" --check >/dev/null 2>&1
_p8_w=0
while (( _p8_w < 10 )) && [[ ! -s "$P8_SHIMS/spawn.log" ]]; do sleep 0.3; _p8_w=$((_p8_w+1)); done
if grep -q -- "--owner=other-repo:worktree-OTHER" "$P8_SHIMS/spawn.log" 2>/dev/null; then
  ok "P8b: explicit LEADV2_BEAT_OWNER_TAG overrides derivation"
else
  bad "P8b: caller-pinned owner tag must win; spawn.log=$(cat "$P8_SHIMS/spawn.log" 2>/dev/null | head -1)"
fi

printf '\ntest-plugin-papercuts: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
