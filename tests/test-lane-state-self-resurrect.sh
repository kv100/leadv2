#!/usr/bin/env bash
# E2E-KILLRATE-01: drive the real lane_reconcile through its process/worktree
# fixtures.  Declared negative control: removing the worker-marker check from
# the helper must make dispatcher cases (a) and (b) fail.
# run-all-triggers: leadv2-lane-state.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${LEADV2_LANE_STATE_TEST_LIB:-${HERE}/../plugins/leadv2/scripts/lib/leadv2-lane-state.sh}"
[[ -f "$LIB" ]] || { echo "lane-state library missing: $LIB" >&2; exit 2; }

PASS=0; FAIL=0
ok() { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
trap 'kill "${NONANCESTOR_PID:-}" "${WORKER_PID:-}" "${PREFIX_PID:-}" 2>/dev/null || true; rm -rf "$WORK"' EXIT
ROOT="$WORK/root"
W="$ROOT/.claude/worktrees/X"
W_OLD="$ROOT/.claude/worktrees/X-old"
ACTIVE="$ROOT/docs/leadv2/active.yaml"
PS="$WORK/ps"
BIRTH="$WORK/birth"
PPID_FIX="$WORK/ppid"
WTS="$WORK/worktrees"
START='Thu Aug 27 00:00:00 2026'
mkdir -p "$W" "$W_OLD" "${ACTIVE%/*}"
printf 'worktree %s\n' "$W" > "$WTS"
# This maps the test-shell ancestor to PID 1; the real reconciler's Python
# child reaches it through ps, then consumes this observation seam.
printf '%s\t1\n' "$$" > "$PPID_FIX"

sleep 120 & NONANCESTOR_PID=$!
sleep 120 & WORKER_PID=$!
sleep 120 & PREFIX_PID=$!

birth_line() { printf '%s\t%s\n' "$1" "$START"; }
ps_line() { printf '%s %s %s\n' "$1" "$START" "$2"; }
reset_state() { printf 'meta: {}\nsessions: []\n' > "$ACTIVE"; : > "$PS"; : > "$BIRTH"; }
recover_count() {
  python3 - "$ACTIVE" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f: data=yaml.safe_load(f) or {}
print(sum(1 for row in data.get('sessions', []) if row.get('recovered')))
PY
}
reconcile() {
  LEADV2_PROJECT_ROOT="$ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$WTS" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$PS" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$BIRTH" \
  LEADV2_LANE_STATE_TEST_PPID_FILE="$PPID_FIX" \
  lane_reconcile
}
expect_count() {
  local label="$1" expected="$2" got
  got="$(recover_count)"
  [[ "$got" == "$expected" ]] && ok "$label" || bad "$label (recovered=$got expected=$expected)"
}

source "$LIB"

echo '== lane-state self-resurrection regression =='

# (a) dispatcher process is the reconciler's ancestor.
reset_state
ps_line "$$" "leadv2-dispatch-code.sh --worktree $W" >> "$PS"
birth_line "$$" >> "$BIRTH"
reconcile
expect_count 'a) ancestor dispatcher is not recovered' 0

# (b) dispatcher is not an ancestor; denylist and missing worker marker still reject it.
reset_state
ps_line "$NONANCESTOR_PID" "leadv2-dispatch-code.sh --worktree $W" >> "$PS"
birth_line "$NONANCESTOR_PID" >> "$BIRTH"
reconcile
expect_count 'b) non-ancestor dispatcher is not recovered' 0

# (c) observation commands mentioning the worktree never become a lane.
reset_state
ps_line "$NONANCESTOR_PID" "grep $W active.yaml" >> "$PS"
birth_line "$NONANCESTOR_PID" >> "$BIRTH"
reconcile
expect_count 'c1) grep mention is not recovered' 0
reset_state
ps_line "$NONANCESTOR_PID" "tail -f $W/log" >> "$PS"
birth_line "$NONANCESTOR_PID" >> "$BIRTH"
reconcile
expect_count 'c2) tail mention is not recovered' 0

# (d) a real live PID with a worker-session marker is recovered once, even
# when reconcile is invoked twice against the same fixture.
reset_state
ps_line "$WORKER_PID" "claude $W" >> "$PS"
birth_line "$WORKER_PID" >> "$BIRTH"
reconcile
reconcile
expect_count 'd) claude worker is recovered exactly once' 1

# (e) X-old is not an argv token match for X.
reset_state
ps_line "$PREFIX_PID" "claude $W_OLD" >> "$PS"
birth_line "$PREFIX_PID" >> "$BIRTH"
reconcile
expect_count 'e) path-prefix collision is not recovered' 0

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
