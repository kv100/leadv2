#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-broad-status.sh
# tests/test-beat-stamp-agreement.sh — ANTI-SILENCE-ONE-MECHANISM-01.
#
# The founder's report: founder-status.md carried a line-1 stamp hours
# behind its own mtime, and earlier the same morning the ready-line's at=
# and the artifact's line-1 stamp disagreed outright. The relay contract
# (leadv2-task-anchor.sh's thread directive) tells the lead to compare the
# two and, on mismatch, publish that fact instead of the file — so a
# disagreement does not lie, it goes SILENT. This suite locks:
#
#   1. happy path -> ready-line at= and founder-status.md line-1 stamp are
#      byte-identical.
#   2. degraded path (collector failure) -> same.
#   3. render failure (bad collector JSON) -> same; and a FAILED write (no
#      artifact write permission at all) carries no path= token.
#   4. a degraded beat still emits live lane facts computed independently
#      of the failed collector/renderer (ANTI-SILENCE-ONE-MECHANISM-01
#      [Critical] fallback-must-speak fix in _write_degraded_status).
#   5. zero live lanes -> the beat still emits a truthful "живые линии: 0"
#      fact, never nothing (no idleness guard).
#
# Hermetic: LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT point at a throwaway
# fixture tree, never a real repo or real state root. The collector and
# claude binaries are stubs; nothing here shells out to a real project.
# Run: bash plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

BROAD_STATUS_SH="${SCRIPT_DIR}/leadv2-broad-status.sh"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir beat-stamp-agreement)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE"

LOG_FILE="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" supervise-loop.log)"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"
ACTIVE_YAML="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" --no-link active.yaml)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cat >"$STUBS/collector.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
printf '{"sections": {}}' >"$out"
EOF
cat >"$STUBS/bad-collector.sh" <<'EOF'
#!/usr/bin/env bash
# Writes a snapshot that is NOT valid JSON -> the deterministic render fails.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
printf 'this-is-not-json' >"$out"
EOF
chmod +x "$STUBS/collector.sh" "$STUBS/bad-collector.sh"

beat_env() {  # <beat-at> <collector-bin> [extra env...]
  local beat_at="$1" collector="$2"; shift 2
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$collector" \
    LEADV2_BROAD_STATUS_BEAT_AT="$beat_at" \
    LEADV2_BROAD_STATUS_DISPATCHED="2" \
    "$@" bash "$BROAD_STATUS_SH" >/dev/null 2>&1
}

ready_at() {  # last ready/failed line's at=
  grep -E 'BROAD_STATUS_(READY|FAILED) ' "$LOG_FILE" 2>/dev/null \
    | tail -n1 | sed -n 's/.* at=\([^ ]*\).*/\1/p'
}
line1_stamp() { head -n1 "$FOUNDER_STATUS" 2>/dev/null | awk '{print $1}'; }
has_path_token() { grep -q 'BROAD_STATUS_READY .*path=' "$LOG_FILE" 2>/dev/null; }

write_active_yaml() {  # writes docs test fixture sessions
  mkdir -p "$(dirname "$ACTIVE_YAML")"
  cat >"$ACTIVE_YAML"
}

# ── 1. happy path ────────────────────────────────────────────────────────
write_active_yaml <<'EOF'
sessions: []
EOF
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
beat_env "2026-08-31T09:00:00Z" "$STUBS/collector.sh" || true
if [[ -f "$FOUNDER_STATUS" ]]; then
  if [[ -n "$(ready_at)" && "$(ready_at)" == "$(line1_stamp)" ]]; then
    pass "T1: happy path — ready-line at= == artifact line-1 stamp"
  else
    fail "T1: stamp mismatch: at=$(ready_at) line1=$(line1_stamp)"
  fi
else
  fail "T1: founder-status.md not written"
fi

# ── 2. degraded path (collector failure) ────────────────────────────────
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
beat_env "2026-08-31T09:30:00Z" /nonexistent-collector || true
if [[ -n "$(ready_at)" && "$(ready_at)" == "$(line1_stamp)" ]]; then
  pass "T2: degraded path — ready-line at= == artifact line-1 stamp"
else
  fail "T2: stamp mismatch: at=$(ready_at) line1=$(line1_stamp)"
fi

# ── 3a. render failure ──────────────────────────────────────────────────
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
beat_env "2026-08-31T10:00:00Z" "$STUBS/bad-collector.sh" || true
if [[ -n "$(ready_at)" && "$(ready_at)" == "$(line1_stamp)" ]]; then
  pass "T3a: render failure — ready-line at= == artifact line-1 stamp"
else
  fail "T3a: stamp mismatch: at=$(ready_at) line1=$(line1_stamp)"
fi

# ── 3b. artifact unwritable -> FAILED line carries no path= token ───────
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  log "SKIP: T3b (running as root — chmod cannot block writes)"
else
  RO_DIR="$TMP/ro-status"; mkdir -p "$RO_DIR"
  printf 'STALE-BYTES-KEEP\n' >"$RO_DIR/founder-status.md"
  chmod 500 "$RO_DIR"
  : >"$LOG_FILE"
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN=/nonexistent-collector \
    LEADV2_FOUNDER_STATUS_PATH="$RO_DIR/founder-status.md" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-31T10:30:00Z" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
  chmod 700 "$RO_DIR"
  if grep -q 'BROAD_STATUS_FAILED' "$LOG_FILE" && ! has_path_token; then
    pass "T3b: unwritable artifact — FAILED line, no path= token"
  else
    fail "T3b: expected FAILED-with-no-path=: $(cat "$LOG_FILE")"
  fi
fi

# ── 4. degraded beat still emits live lane facts ────────────────────────
write_active_yaml <<'EOF'
sessions:
  - task_id: dispatch-abc123
    phase: build
    stale: false
  - task_id: dispatch-def456
    phase: review
    stale: true
EOF
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
beat_env "2026-08-31T11:00:00Z" /nonexistent-collector || true
if grep -q 'СТАТУС НЕ СОБРАН' "$FOUNDER_STATUS" 2>/dev/null \
    && grep -q 'живые линии: 2' "$FOUNDER_STATUS" 2>/dev/null \
    && grep -q 'dispatch-abc123' "$FOUNDER_STATUS" 2>/dev/null \
    && grep -q 'dispatch-def456' "$FOUNDER_STATUS" 2>/dev/null; then
  pass "T4: degraded beat names live lanes, not just staleness"
else
  fail "T4: degraded artifact lacks live-lane facts: $(cat "$FOUNDER_STATUS" 2>/dev/null)"
fi

# ── 5. zero live lanes -> still truthful, never silent ──────────────────
write_active_yaml <<'EOF'
sessions: []
EOF
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
beat_env "2026-08-31T11:30:00Z" /nonexistent-collector || true
if grep -q 'живые линии: 0' "$FOUNDER_STATUS" 2>/dev/null; then
  pass "T5: zero live lanes — beat still emits a truthful fact"
else
  fail "T5: zero-lane beat produced no lane-fact line: $(cat "$FOUNDER_STATUS" 2>/dev/null)"
fi

echo "----------------------------------------"
echo "test-beat-stamp-agreement: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
