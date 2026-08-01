#!/usr/bin/env bash
# tests/test-supervise-fanout-guard.sh — smoke tests for
# hooks/leadv2-supervise-fanout-guard.sh (LEADV2-SUPERVISE-GUARD-01,
# fix round: review_round_2 — C1 per-session scoping, H1 haiku-worker gate,
# H2 fail-closed unknown-type gate)
# Usage: bash tests/test-supervise-fanout-guard.sh
# Exit 0 = all pass; non-zero = failure count
set -euo pipefail

GUARD="${BASH_SOURCE[0]%/*}/../hooks/leadv2-supervise-fanout-guard.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

# Sandboxed control-plane root — never touches the real ~/.claude/leadv2-state.
TMP_DIR="$(mktemp -d)"
BG_PID=""
cleanup() {
  [[ -n "$BG_PID" ]] && kill "$BG_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

REPO_DIR="${TMP_DIR}/repo"
mkdir -p "$REPO_DIR"
(cd "$REPO_DIR" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init)

STATE_ROOT="${TMP_DIR}/state"
mkdir -p "$STATE_ROOT"
SENTINEL="${STATE_ROOT}/.supervise-active"

# SELF_PID — the identity the guard itself will compute (via
# leadv2-active-registry.sh::_lv2_durable_pid) when invoked as a direct child
# of THIS test script, one hop deep, exactly matching how run_guard()/the
# direct `bash "$GUARD"` calls below invoke it. Using this instead of the
# test script's own literal `$$` makes "self session" sentinels correct
# whether this suite runs standalone or nested inside a live Claude Code
# session (where the durable-pid ancestor walk finds the real outer `claude`
# process rather than this script's own pid).
# The guard's direct PPID is this test shell ($$). Reproduce the helper's
# ancestor walk from that exact starting pid; a nested command-substitution
# bash has a different short-lived PPID and made this test flaky outside
# Claude Code.
SELF_PID="$(python3 - "$$" <<'PYEOF'
import subprocess, sys
start = int(sys.argv[1])
pid = start
seen = set()
while pid > 1 and pid not in seen:
    seen.add(pid)
    comm = subprocess.run(['ps', '-o', 'comm=', '-p', str(pid)], capture_output=True, text=True).stdout.strip().split('/')[-1].lower()
    if 'claude' in comm:
        print(pid)
        break
    raw = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
    nxt = int(raw) if raw else 0
    if nxt in (0, 1, pid):
        print(start)
        break
    pid = nxt
else:
    print(start)
PYEOF
)"

run_guard() {
  # $1 = payload json ; env overrides via remaining args
  local payload="$1"; shift
  LEADV2_STATE_ROOT="$STATE_ROOT" env "$@" bash "$GUARD" <<<"$payload" >/dev/null 2>&1
}

WORKER_PAYLOAD="{\"tool_input\":{\"subagent_type\":\"developer\",\"model\":\"sonnet\"},\"cwd\":\"${REPO_DIR}\"}"
WORKER_HAIKU_PAYLOAD="{\"tool_input\":{\"subagent_type\":\"developer\",\"model\":\"claude-haiku-4-5\"},\"cwd\":\"${REPO_DIR}\"}"
HAIKU_EXPLORE_PAYLOAD="{\"tool_input\":{\"subagent_type\":\"Explore\",\"model\":\"claude-haiku-4-5\"},\"cwd\":\"${REPO_DIR}\"}"
UNKNOWN_TYPE_PAYLOAD="{\"tool_input\":{\"subagent_type\":\"qa-engineer\",\"model\":\"sonnet\"},\"cwd\":\"${REPO_DIR}\"}"

# ---------------------------------------------------------------------------
# (a) No sentinel present -> worker spawn is ALLOWED (exit 0)
# ---------------------------------------------------------------------------
rm -f "$SENTINEL"
exit_code=0
run_guard "$WORKER_PAYLOAD" || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
  pass "(a) no sentinel: worker spawn allowed"
else
  fail "(a) no sentinel: worker spawn should be allowed (exit=$exit_code)"
fi

# ---------------------------------------------------------------------------
# (b) Live sentinel (our own pid, definitely alive), NO mode key + worker spawn
# -> ALLOWED. Default flip (e060fd1, "supervisor spawn-gate default
# interactive-lanes, any subagent_type" -- founder ruling): a missing/unknown
# mode normalizes to "interactive-lanes", which is a permissive allow, not a
# deny. Only an explicit mode="legacy-relay" reaches the strict deny-worker
# gate (see (b2) below).
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"
b_stdout=""
b_exit=0
LEADV2_STATE_ROOT="$STATE_ROOT" bash "$GUARD" <<<"$WORKER_PAYLOAD" >"$TMP_DIR/b.stdout" 2>/dev/null || b_exit=$?
b_stdout="$(<"$TMP_DIR/b.stdout")"
if [[ $b_exit -eq 0 ]]; then
  pass "(b) live sentinel, no mode + worker spawn (developer) is allowed (default=interactive-lanes)"
else
  fail "(b) live sentinel, no mode + worker spawn should allow (exit=$b_exit stdout=${b_stdout:0:120})"
fi

# ---------------------------------------------------------------------------
# (b2) Live sentinel with explicit mode="legacy-relay" + worker spawn -> BLOCKED.
# Keeps the strict-mode deny contract under test after (b) moved to ALLOW.
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'legacy-relay'}, open('$SENTINEL', 'w'))
"
b2_stdout=""
b2_exit=0
LEADV2_STATE_ROOT="$STATE_ROOT" bash "$GUARD" <<<"$WORKER_PAYLOAD" >"$TMP_DIR/b2.stdout" 2>/dev/null || b2_exit=$?
b2_stdout="$(<"$TMP_DIR/b2.stdout")"
if [[ $b2_exit -eq 2 ]] && printf '%s' "$b2_stdout" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['hookSpecificOutput']['permissionDecision']=='deny'" 2>/dev/null; then
  pass "(b2) legacy-relay sentinel + worker spawn (developer) is denied (exit 2 + deny JSON)"
else
  fail "(b2) legacy-relay sentinel + worker spawn should deny (exit=$b2_exit stdout=${b2_stdout:0:120})"
fi

# Reset sentinel to the no-mode (interactive-lanes default) form used by (c)-(e).
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"

# ---------------------------------------------------------------------------
# (c) Live sentinel + Explore/haiku discovery -> ALLOWED (exit 0), sentinel untouched
# ---------------------------------------------------------------------------
exit_code=0
run_guard "$HAIKU_EXPLORE_PAYLOAD" || exit_code=$?
if [[ $exit_code -eq 0 && -f "$SENTINEL" ]]; then
  pass "(c) live sentinel + Explore(haiku) allowed, sentinel untouched"
else
  fail "(c) live sentinel + Explore(haiku) should be allowed (exit=$exit_code, sentinel_exists=$( [[ -f "$SENTINEL" ]] && echo yes || echo no))"
fi

# ---------------------------------------------------------------------------
# (d) H1: live sentinel, NO mode key + WORKER on a haiku model -> ALLOWED.
# Post-e060fd1 default (interactive-lanes) does not gate on model at all; the
# haiku carve-out is orthogonal to this case. Model is not a gate under the
# permissive default.
# ---------------------------------------------------------------------------
d_exit=0
run_guard "$WORKER_HAIKU_PAYLOAD" || d_exit=$?
if [[ $d_exit -eq 0 ]]; then
  pass "(d) H1: live sentinel, no mode + developer on haiku model is allowed (default=interactive-lanes)"
else
  fail "(d) H1: haiku worker spawn should be allowed (exit=$d_exit)"
fi

# ---------------------------------------------------------------------------
# (d2) H1: live sentinel with explicit mode="legacy-relay" + WORKER on a haiku
# model -> BLOCKED. No model carve-out under the strict gate.
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'legacy-relay'}, open('$SENTINEL', 'w'))
"
d2_exit=0
run_guard "$WORKER_HAIKU_PAYLOAD" || d2_exit=$?
if [[ $d2_exit -eq 2 ]]; then
  pass "(d2) H1: legacy-relay sentinel + developer on haiku model is denied (no model carve-out)"
else
  fail "(d2) H1: legacy-relay haiku worker spawn should be denied (exit=$d2_exit)"
fi
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"

# ---------------------------------------------------------------------------
# (e) H2: live sentinel, NO mode key + an UNRECOGNIZED subagent_type ->
# ALLOWED under the permissive interactive-lanes default (any subagent_type).
# ---------------------------------------------------------------------------
e_exit=0
run_guard "$UNKNOWN_TYPE_PAYLOAD" || e_exit=$?
if [[ $e_exit -eq 0 ]]; then
  pass "(e) H2: live sentinel, no mode + unrecognized subagent_type (qa-engineer) is allowed (default=interactive-lanes)"
else
  fail "(e) H2: unrecognized subagent_type should be allowed (exit=$e_exit)"
fi

# ---------------------------------------------------------------------------
# (e2) H2: live sentinel with explicit mode="legacy-relay" + an UNRECOGNIZED
# subagent_type -> BLOCKED (fail-closed default branch under the strict gate).
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'legacy-relay'}, open('$SENTINEL', 'w'))
"
e2_exit=0
run_guard "$UNKNOWN_TYPE_PAYLOAD" || e2_exit=$?
if [[ $e2_exit -eq 2 ]]; then
  pass "(e2) H2: legacy-relay sentinel + unrecognized subagent_type (qa-engineer) is denied (fail-closed)"
else
  fail "(e2) H2: legacy-relay unrecognized subagent_type should be denied (exit=$e2_exit)"
fi
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"

# ---------------------------------------------------------------------------
# (f) Stale sentinel (dead pid) + worker spawn -> ALLOWED and sentinel self-cleaned
# ---------------------------------------------------------------------------
# Pick a pid almost certainly dead: a very high number outside normal ranges.
python3 -c "
import json
json.dump({'pid': 999999, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"
exit_code=0
run_guard "$WORKER_PAYLOAD" || exit_code=$?
if [[ $exit_code -eq 0 && ! -f "$SENTINEL" ]]; then
  pass "(f) stale (dead-pid) sentinel: worker spawn allowed + sentinel self-cleaned"
else
  fail "(f) stale sentinel should allow + self-clean (exit=$exit_code, sentinel_exists=$( [[ -f "$SENTINEL" ]] && echo yes || echo no))"
fi

# ---------------------------------------------------------------------------
# (g) LEADV2_SUPERVISE_GUARD=0 disables the guard even with a live
# self-owned sentinel
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"
exit_code=0
run_guard "$WORKER_PAYLOAD" LEADV2_SUPERVISE_GUARD=0 || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
  pass "(g) LEADV2_SUPERVISE_GUARD=0 disables guard (worker spawn allowed)"
else
  fail "(g) LEADV2_SUPERVISE_GUARD=0 should disable guard (exit=$exit_code)"
fi

# ---------------------------------------------------------------------------
# (h) C1: live sentinel that does NOT belong to this call's session (a live
# but unrelated pid, simulating an unrelated concurrent /leadv2 session on
# the same repo, or a fanout child whose own durable pid never matches the
# supervising session's) -> worker spawn is ALLOWED, sentinel left untouched.
# ---------------------------------------------------------------------------
sleep 60 &
BG_PID=$!
python3 -c "
import json
json.dump({'pid': $BG_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"
h_exit=0
run_guard "$WORKER_PAYLOAD" || h_exit=$?
if [[ $h_exit -eq 0 && -f "$SENTINEL" ]]; then
  pass "(h) C1: live sentinel owned by a DIFFERENT session does not block worker spawn, sentinel untouched"
else
  fail "(h) C1: different-session sentinel should not block (exit=$h_exit, sentinel_exists=$( [[ -f "$SENTINEL" ]] && echo yes || echo no))"
fi
kill "$BG_PID" 2>/dev/null || true
wait "$BG_PID" 2>/dev/null || true
BG_PID=""

# ---------------------------------------------------------------------------
# (i) Fanout child (LEADV2_ASYNC_QUESTIONS=1) is NEVER blocked, even against
# a live sentinel that (for this test) intentionally matches this call's own
# pid — the env marker short-circuits before any session comparison.
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z'}, open('$SENTINEL', 'w'))
"
i_exit=0
run_guard "$WORKER_PAYLOAD" LEADV2_ASYNC_QUESTIONS=1 || i_exit=$?
if [[ $i_exit -eq 0 ]]; then
  pass "(i) fanout child (LEADV2_ASYNC_QUESTIONS=1) is never blocked by the supervise sentinel"
else
  fail "(i) fanout child should never be blocked (exit=$i_exit)"
fi
rm -f "$SENTINEL"

# ---------------------------------------------------------------------------
# (j) MODE SPLIT (fix-2 R2-1): live sentinel, mode="interactive-lanes"
# (explicit compatibility mode) + worker (developer) spawn from the OWNING
# session -> ALLOWED. Full-cycle relay remains the default.
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'interactive-lanes'}, open('$SENTINEL', 'w'))
"
j_exit=0
run_guard "$WORKER_PAYLOAD" || j_exit=$?
if [[ $j_exit -eq 0 ]]; then
  pass "(j) mode=interactive-lanes: owning-session worker (developer) spawn is ALLOWED"
else
  fail "(j) mode=interactive-lanes should allow worker spawn (exit=$j_exit)"
fi
rm -f "$SENTINEL"

# ---------------------------------------------------------------------------
# (l) MODE OWNERSHIP: a supervise snapshot from a different live process
# must not steal the sentinel from the interactive supervisor. This models
# the background supervise-loop and an ordinary concurrent lead.
# ---------------------------------------------------------------------------
sleep 60 &
BG_PID=$!
python3 -c "
import json
json.dump({'pid': $BG_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'legacy-relay'}, open('$SENTINEL', 'w'))
"
cat > "$STATE_ROOT/active.yaml" <<'EOF'
version: 2
meta:
  hard_limit: 3
sessions: []
EOF
supervise_rc=0
LEADV2_STATE_ROOT="$STATE_ROOT" \
LEADV2_PROJECT_ROOT="$REPO_DIR" \
LEADV2_SUPERVISE_OBSERVE_ONLY=1 \
  bash "${BASH_SOURCE[0]%/*}/../scripts/leadv2-supervise.sh" --json \
  >"$TMP_DIR/supervise-owner.json" 2>"$TMP_DIR/supervise-owner.err" || supervise_rc=$?
owner_after="$(python3 -c "import json; print(json.load(open('$SENTINEL')).get('pid',''))")"
if [[ "$supervise_rc" -eq 0 && "$owner_after" == "$BG_PID" ]]; then
  pass "(l) background/concurrent snapshot does not steal supervisor sentinel ownership"
else
  fail "(l) supervisor ownership changed (rc=$supervise_rc expected=$BG_PID actual=$owner_after)"
fi
kill "$BG_PID" 2>/dev/null || true
wait "$BG_PID" 2>/dev/null || true
BG_PID=""
rm -f "$SENTINEL"

# ---------------------------------------------------------------------------
# (k) MODE SPLIT (fix-2 R2-1): live sentinel, mode="legacy-relay" (explicit)
# + worker spawn from the OWNING session -> BLOCKED (original guard purpose:
# a session watching only external tmux fanout with no in-session lanes).
# ---------------------------------------------------------------------------
python3 -c "
import json
json.dump({'pid': $SELF_PID, 'started_at': '2026-07-16T00:00:00Z', 'mode': 'legacy-relay'}, open('$SENTINEL', 'w'))
"
k_exit=0
run_guard "$WORKER_PAYLOAD" || k_exit=$?
if [[ $k_exit -eq 2 ]]; then
  pass "(k) mode=legacy-relay: owning-session worker (developer) spawn is BLOCKED"
else
  fail "(k) mode=legacy-relay should deny worker spawn (exit=$k_exit)"
fi
rm -f "$SENTINEL"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
