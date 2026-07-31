#!/usr/bin/env bash
# tests/test-statusline-supervisor-gate.sh — SUPERVISOR-HARDENING-01 item 4a
# test for leadv2-lane-status-line.sh's supervisor-only gate (the dirty file).
#
# Feeds the statusLine renderer a synthetic {"current_dir":...} payload on stdin
# against a throwaway fixture state dir (LEADV2_STATE_ROOT) and an isolated
# HOME/TMPDIR so it never touches the founder's real settings.json, the real
# control plane, or the real lane caches:
#   • gate OFF (no live sentinel) → base line only, NO lanes digest token
#   • gate ON  (live sentinel)    → lanes digest token present
#   • LEADV2_STATUS_LINE=0        → pure passthrough of the user command, no
#                                   lanes segment (regression guard on the
#                                   dirty statusline file's rollback block)
#
# The statusline script resolves the sentinel via its own bundled
# leadv2-state-path.sh (STATE_PATH_SH), which honours LEADV2_STATE_ROOT, so we
# never mutate a real repo's docs/leadv2 links. Run:
#   bash scripts/tests/test-statusline-supervisor-gate.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUSLINE="${SCRIPT_DIR}/leadv2-lane-status-line.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

_REAP_PIDS=()
cleanup() { for p in "${_REAP_PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

if bash -n "${STATUSLINE}" 2>/dev/null; then pass "bash -n statusline script"; else fail "bash -n statusline script"; fi

# ── Isolation sandbox ──────────────────────────────────────────────────────
# HOME → empty settings.json (no user statusLine.command) so the gate-OFF path
#        self-renders the minimal base line deterministically.
# TMPDIR → isolates memo / cache / sidecar files (keyed off PAINT_CWD).
# LEADV2_STATE_ROOT → forces sentinel resolution at a throwaway path.
SANDBOX="$(lv2_mktemp_dir statusline-gate)"
HOME_ISOLATED="${SANDBOX}/home"
TMPDIR_ISOLATED="${SANDBOX}/tmp"
STATE_ROOT="${SANDBOX}/state"
mkdir -p "$HOME_ISOLATED/.claude" "$TMPDIR_ISOLATED" "$STATE_ROOT"
SENTINEL="${STATE_ROOT}/.supervise-active"
PAINT_CWD="${SANDBOX}/repo"   # any path; resolver uses LEADV2_STATE_ROOT, not git
mkdir -p "$PAINT_CWD"

payload() { printf '{"current_dir":"%s","model":{"display_name":"TestModel"}}' "$PAINT_CWD"; }

# Run the statusline with the isolation env. CLAUDE_PROJECT_DIR unset so the
# resolver never borrows the ambient real-project control plane.
run_statusline() {
  env -u CLAUDE_PROJECT_DIR \
      HOME="$HOME_ISOLATED" \
      TMPDIR="$TMPDIR_ISOLATED" \
      LEADV2_STATE_ROOT="$STATE_ROOT" \
      "$@" \
      bash "$STATUSLINE" <<<"$(payload)"
}

# ── Case 1: gate OFF (no sentinel) → base line, NO "lanes" token ───────────
rm -f "$SENTINEL"
out="$(run_statusline env LEADV2_STATUS_LINE=1)"
if printf '%s' "$out" | grep -qi 'lanes'; then
  fail "case 1 (gate OFF): lanes token leaked into non-supervisor line: $out"
else
  pass "case 1 (gate OFF): no lanes digest token"
fi
if printf '%s' "$out" | grep -q 'TestModel'; then
  pass "case 1 (gate OFF): base line present (model rendered)"
else
  fail "case 1 (gate OFF): base line missing: $out"
fi

# ── Case 2: gate ON (live sentinel) → "lanes" token present ────────────────
sleep 30 & live_pid=$!; _REAP_PIDS+=("$live_pid")
kill -0 "$live_pid" 2>/dev/null && printf '{"pid":%s,"started_at":"now"}' "$live_pid" >"$SENTINEL"
# Fresh TMPDIR so no stale memo/cache pretends gate state from case 1.
TMPDIR_ON="${SANDBOX}/tmp-on"; mkdir -p "$TMPDIR_ON"
out="$(env -u CLAUDE_PROJECT_DIR HOME="$HOME_ISOLATED" TMPDIR="$TMPDIR_ON" \
       LEADV2_STATE_ROOT="$STATE_ROOT" LEADV2_STATUS_LINE=1 \
       bash "$STATUSLINE" <<<"$(payload)")"
if printf '%s' "$out" | grep -qi 'lanes'; then
  pass "case 2 (gate ON): lanes digest token present"
else
  fail "case 2 (gate ON): lanes token missing: $out"
fi

# ── Case 3: LEADV2_STATUS_LINE=0 → pure passthrough, no lanes segment ──────
# Stage a user statusLine.command so the rollback path has something to run;
# assert its marker is passed through byte-identical and NO lanes segment is
# appended (regression guard on the dirty file's rollback block).
printf '%s' '{"statusLine":{"command":"printf PASSTHROUGH_MARKER"}}' \
  >"$HOME_ISOLATED/.claude/settings.json"
rm -f "$SENTINEL"
out="$(run_statusline env LEADV2_STATUS_LINE=0)"
if printf '%s' "$out" | grep -q 'PASSTHROUGH_MARKER'; then
  pass "case 3 (rollback): user command passed through"
else
  fail "case 3 (rollback): user command not passed through: $out"
fi
if printf '%s' "$out" | grep -qi 'lanes'; then
  fail "case 3 (rollback): lanes segment leaked into passthrough: $out"
else
  pass "case 3 (rollback): no lanes segment in passthrough"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
