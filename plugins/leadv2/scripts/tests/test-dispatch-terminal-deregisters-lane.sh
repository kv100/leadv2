#!/usr/bin/env bash
# test-dispatch-terminal-deregisters-lane.sh — LANE-DEREGISTRATION (T16 §10).
#
# Closed/terminal lanes never left docs/leadv2/active.yaml: rows accumulated
# until lead_session_lane_cap refused every new dispatch and a human had to
# prune by hand (3x on 2026-08-26/27). A TRUE terminal (landed|dead|
# pass_unlanded) written via write-terminal must now REMOVE the lane's
# registration row; retryable terminals (parked|refused|no_work) must NOT —
# a later attempt may have re-registered the same identity.
#
# Runs the REAL dispatch-ledger CLI against an isolated HOME + fixture state
# root (LEAD-CONTROL-PLANE-01 layout: ~/.claude/leadv2-state/<slug>/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="${SCRIPT_DIR}/../leadv2-dispatch-ledger.sh"

pass=0
fail=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
mkdir -p "$home"

repo="$tmp/repos/t16lane"
mkdir -p "$repo"
(cd "$repo" && git init -q && git config user.email test@example.invalid \
  && git config user.name lane-dereg-test && git commit -q --allow-empty -m init)
# REAL-REPO marker: keeps leadv2-state-path.sh's EPHEMERAL-REDIRECT from
# moving the fixture state under .ephemeral/<slug> (scratch-repo predicate).
: > "$repo/REAL-REPO"

state="$home/.claude/leadv2-state/t16lane"
mkdir -p "$state"
ACTIVE="$state/active.yaml"
TERMINALS="$tmp/terminal-ledger.jsonl"

seed_row() { # <task_id> -- (re)register a lane row
  python3 - "$ACTIVE" "$1" <<'PY'
import sys, yaml
path, task = sys.argv[1:3]
try:
    with open(path) as f: data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}
rows = [s for s in (data.get("sessions") or []) if s.get("task_id") != task]
rows.append({"task_id": task, "session_id": "s-test", "lead_session_id": "s-test",
             "worktree": "/tmp/wt", "phase": "review", "pid": 999999,
             "started_at": "2026-08-27T00:00:00Z", "dead_at": None})
data["sessions"] = rows
with open(path, "w") as f: yaml.safe_dump(data, f)
PY
}

row_exists() { # <task_id>
  python3 - "$ACTIVE" "$1" <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as f: data = yaml.safe_load(f) or {}
except FileNotFoundError:
    sys.exit(1)
sys.exit(0 if any(isinstance(s, dict) and s.get("task_id") == sys.argv[2]
                  for s in (data.get("sessions") or [])) else 1)
PY
}

run_terminal() { # <sig8> <founder> <terminal>
  # Isolated HOME hides the user site-packages (PyYAML lives there) — carry
  # the REAL ones via PYTHONPATH, the test-drift-guard-safety-fixes.sh pattern.
  env HOME="$home" PROJECT_ROOT="$repo" \
    PYTHONPATH="$(python3 -c 'import site; print(site.getusersitepackages())')" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$TERMINALS" \
    bash "$LEDGER" write-terminal "$1" "$2" "$3" "t16-test" >/dev/null 2>&1
}

# ── Case 1: register -> terminal(landed) -> row gone (the mission's contract) ──
seed_row "dispatch-1111aaaa"
run_terminal "1111aaaa" "" "landed"
if row_exists "dispatch-1111aaaa"; then
  printf '[TEST] FAIL: Case 1: lane row survived a landed terminal\n' >&2; fail=$((fail+1))
else
  printf '[TEST] PASS: Case 1: landed terminal removes the lane row\n'; pass=$((pass+1))
fi

# ── Case 2: founder_task_id identity is removed too ──────────────────────────
seed_row "T16-FOUNDER-ID"
run_terminal "2222bbbb" "T16-FOUNDER-ID" "dead"
if row_exists "T16-FOUNDER-ID"; then
  printf '[TEST] FAIL: Case 2: founder-id row survived a dead terminal\n' >&2; fail=$((fail+1))
else
  printf '[TEST] PASS: Case 2: dead terminal removes the founder-id row\n'; pass=$((pass+1))
fi

# ── Case 3: retryable terminal (parked) keeps the row ────────────────────────
seed_row "dispatch-3333cccc"
run_terminal "3333cccc" "" "parked"
if row_exists "dispatch-3333cccc"; then
  printf '[TEST] PASS: Case 3: parked terminal keeps the lane row\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: parked terminal must not remove the row\n' >&2; fail=$((fail+1))
fi

# ── Case 4: dedup (terminal already recorded) never removes a row ────────────
seed_row "dispatch-4444dddd"
run_terminal "4444dddd" "" "landed"        # removes row, records terminal
seed_row "dispatch-4444dddd"               # simulate a racing re-registration
run_terminal "4444dddd" "" "landed"        # dedup path (write-once) -- must keep row
if row_exists "dispatch-4444dddd"; then
  printf '[TEST] PASS: Case 4: dedup retry keeps the (re-registered) row\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: dedup retry removed a re-registered row\n' >&2; fail=$((fail+1))
fi

# ── Case 5: fail-open -- no state dir at all, terminal write still succeeds ──
rm -rf "$state"
run_terminal "5555eeee" "" "landed"
if grep -q '"task_sig":"5555eeee"' "$TERMINALS"; then
  printf '[TEST] PASS: Case 5: terminal write succeeds with no active.yaml\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 5: terminal row missing after no-state run\n' >&2; fail=$((fail+1))
fi

printf '\n[TEST] dispatch-terminal lane deregistration: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
