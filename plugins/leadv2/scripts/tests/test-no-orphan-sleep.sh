#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-sleep.sh
# test-no-orphan-sleep.sh — FORK-STORM-KILLS-HOOKS-01.
#
# Grades the fork-free wait + orphan-proof reaping contract of
# scripts/lib/leadv2-sleep.sh (all fixtures live in $(mktemp -d); the suite
# never kills or inspects any process outside its own fixture tree):
#   1a. a watcher TERM-killed mid-wait  ⇒ its child does not survive (reaping);
#   1b. a watcher SIGKILLed mid-wait    ⇒ nothing survives (wait forks nothing,
#       so there is nothing to orphan — the founder's 56-orphan case);
#   2.  a watcher exiting normally      ⇒ no child survives (EXIT-trap guard);
#   3.  the converted poll loop wakes on time, terminates on its stop
#       condition, and spawns no sleep process while looping.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${TEST_DIR}/../lib/leadv2-sleep.sh"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

[ -f "$LIB" ] || { echo "FAIL: helper missing: $LIB"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/no-orphan-sleep.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# Fixture watcher: sources the real helper, arms reaping, spawns one real
# child (sleep 30 — a fixture process inside $TMP-scoped lifetime), reports
# the child pid, then parks in the fork-free wait for WAIT_SECS.
cat > "$TMP/watcher.sh" <<WEOF
#!/usr/bin/env bash
set -u
. "$LIB"
leadv2_reap_arm
leadv2_spawn sleep 30
printf '%s' "\$LEADV2_CHILD_PIDS" > "\$1"
leadv2_wait "\$2"
WEOF
chmod +x "$TMP/watcher.sh"

# await_child_death PID: poll up to 6s for `kill -0` to start failing.
await_child_death() {
  local _i=0
  while [ "$_i" -lt 60 ]; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
    _i=$((_i + 1))
  done
  return 1
}

# ── 1a. TERM mid-wait: reaping kills the child ───────────────────────────────
bash "$TMP/watcher.sh" "$TMP/p1" 30 &
WP1=$!
_i=0
while [ ! -s "$TMP/p1" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i+1)); done
if [ -s "$TMP/p1" ]; then
  CHILD1="$(cat "$TMP/p1")"
  kill -TERM "$WP1" 2>/dev/null
  if await_child_death "$CHILD1"; then
    ok "1a: TERM-killed watcher mid-wait leaves no child behind (child $CHILD1 reaped)"
  else
    bad "1a: child $CHILD1 survived its TERM-killed watcher (orphan class)"
  fi
else
  bad "1a: fixture watcher never reported its child pid"
  kill -9 "$WP1" 2>/dev/null
fi
wait "$WP1" 2>/dev/null

# ── 1b. SIGKILL mid-wait: nothing to orphan (fork-free wait) ─────────────────
bash "$TMP/watcher.sh" "$TMP/p2" 30 &
WP2=$!
_i=0
while [ ! -s "$TMP/p2" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i+1)); done
CHILD2="$(tr -d " " < "$TMP/p2")"
KIDS2="$(pgrep -P "$WP2" 2>/dev/null | tr -d ' ')"
if [ "$KIDS2" = "$CHILD2" ]; then
  ok "1b: mid-wait the watcher's ONLY child is the spawned one - the wait itself forked nothing"
else
  bad "1b: watcher mid-wait children=[$KIDS2] want exactly [$CHILD2] (wait is forking)"
fi
# SIGKILL itself: the fork-free wait leaves NO process behind (the spawned
# fixture child dies with its own 30s lifetime - a real child of a SIGKILLed
# watcher cannot be reaped by any trap, which is why the wait must not be one).
kill -9 "$WP2" 2>/dev/null
wait "$WP2" 2>/dev/null
KIDS_AFTER="$(pgrep -P "$WP2" 2>/dev/null | tr -d ' ')"
if [ -z "$KIDS_AFTER" ]; then
  ok "1b: SIGKILLed watcher mid-wait adds no orphaned wait-process (none existed)"
else
  bad "1b: processes left under SIGKILLed watcher: $KIDS_AFTER"
fi

# ── 2. normal exit: EXIT-trap reaping ────────────────────────────────────────
bash "$TMP/watcher.sh" "$TMP/p3" 1 &
WP3=$!
while [ ! -s "$TMP/p3" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i+1)); done
CHILD3="$(cat "$TMP/p3" 2>/dev/null)"
wait "$WP3" 2>/dev/null
RC3=$?
if [ "$RC3" -eq 0 ]; then
  ok "2: watcher exited normally with rc=0"
else
  bad "2: watcher exit rc=$RC3 (want 0)"
fi
if await_child_death "$CHILD3"; then
  ok "2: normally-exiting watcher leaves no child behind (child $CHILD3 reaped)"
else
  bad "2: child $CHILD3 survived a NORMAL watcher exit (EXIT trap not reaping)"
fi

# ── 3. converted poll loop: wakes on time, terminates, forks no sleep ────────
cat > "$TMP/loop.sh" <<LEOF
#!/usr/bin/env bash
set -u
. "$LIB"
i=0
while [ "\$i" -lt 1 ]; do
  leadv2_wait 3
  i=\$((i + 1))
done
LEOF
chmod +x "$TMP/loop.sh"
T0="$(date +%s)"
bash "$TMP/loop.sh" &
LP=$!
sleep 1.5
MIDSAMPLE="$(pgrep -P "$LP" 2>/dev/null | tr '
' ' ')"
wait "$LP" 2>/dev/null
LRC=$?
T1="$(date +%s)"
ELAPSED=$((T1 - T0))
if [ "$LRC" -eq 0 ]; then
  ok "3: poll loop terminated on its stop condition (rc=0)"
else
  bad "3: poll loop rc=$LRC"
fi
if [ "$ELAPSED" -ge 3 ] && [ "$ELAPSED" -le 8 ]; then
  ok "3: poll loop woke on time (3x1s wait took ${ELAPSED}s)"
else
  bad "3: poll loop elapsed ${ELAPSED}s, want 3..8"
fi
if [ -z "$MIDSAMPLE" ]; then
  ok "3: poll loop spawned no sleep process mid-flight (fork-free wait)"
else
  bad "3: poll loop children mid-flight: ${MIDSAMPLE} (sleep reappeared)"
fi

# hygiene: the helper must not leave fifo names in tmp
LEFT_FIFOS="$(ls "${TMPDIR:-/tmp}"/leadv2-wait.*.fifo 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFT_FIFOS" -eq 0 ]; then
  ok "hygiene: no leftover leadv2-wait fifo names"
else
  bad "hygiene: ${LEFT_FIFOS} leftover fifo names in tmp"
fi

echo "no-orphan-sleep: pass=${PASS} fail=${FAIL}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
