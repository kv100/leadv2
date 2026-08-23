#!/usr/bin/env bash
# tests/test-broad-status-lanes-blind.sh — LANE-DETAIL-BLIND-01.
#
# DEFECT: leadv2-broad-status.sh reads `sections.lane_detail.ok` (detail_ok)
# and surfaces a loud prefix line when THAT section fails, but never reads
# `sections.lanes.ok` -- the section table_rows is actually built from. When
# the collector's "lanes" sub-section fails in isolation (leadv2-lanes-
# snapshot.sh missing/erroring while the rest of the collector run
# succeeds -- exactly the persona-engine 2026-08-21 shape: a real file
# genuinely absent from .claude/scripts/), table_rows silently becomes [],
# live_lane_count becomes 0, and PULSE-EMPTY-BOARD-01's headline fires:
# "ДОСКА ПУСТА -- ничего не выполняется" -- a confident false claim of zero
# activity that is byte-identical to a genuinely empty board. Five live
# sonnet lanes dispatched via leadv2-dispatch-code.sh were running while the
# founder saw this headline all evening.
#
# T1  RENDERER FALSIFIER: lanes section fails (ok:false, captured stderr as
#     `data`), lane_detail succeeds normally -- the false "ДОСКА ПУСТА"
#     headline must NOT appear; a distinct "не вижу линии" headline naming
#     the raw collector fail reason must appear instead.
# T2  CONTROL CASE: lanes section SUCCEEDS with a genuinely empty table --
#     "ДОСКА ПУСТА" must still fire. The fix must not blanket-suppress the
#     legitimate empty-board headline, only the false one.
# T3  table_prefix carries the same distinct marker (belt-and-suspenders:
#     a reader who only looks at the table region, not the headline, must
#     still see it).
# T4  LANES-SNAPSHOT B1-CONTRACT regression lock: a malformed active.yaml
#     must make leadv2-lanes-snapshot.sh --json exit non-zero with a typed
#     {"error":"registry_error",...} -- NEVER rc=0 with a silently-empty
#     table:[]. This is what the lanes_ok gate above depends on being true;
#     if lanes-snapshot.sh ever starts degrading silently instead of
#     failing loudly, this is the test that catches it. Documented in the
#     task brief as a LIKELY PRE-EXISTING PASS (the B1 contract predates
#     this fix) -- reported as a locking regression test, not manufactured
#     evidence of this fix.
#
# Hermetic: throwaway LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT, stubbed
# collector / claude, no network, no crontab, no real dispatch.
# Run: bash scripts/tests/test-broad-status-lanes-blind.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"
LANES_SNAPSHOT_SH="$SCRIPT_DIR/leadv2-lanes-snapshot.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir broad-status-lanes-blind)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── stubs ────────────────────────────────────────────────────────────────
# T1 fixture: byte-identical in shape to the live persona-engine snapshot --
# `lanes` failed (ok:false, data = the captured stderr string
# _sc_run_section writes on a non-zero exit / missing script), everything
# else (lane_detail) succeeded normally.
FAIL_REASON='bash: /home/claudebot/persona-engine/.claude/scripts/leadv2-lanes-snapshot.sh: No such file or directory'
cat >"$STUBS/collector-lanes-fail.sh" <<EOF
#!/usr/bin/env bash
out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --out) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "\$out" ]] && exit 1
python3 -c '
import json
print(json.dumps({"sections": {
  "lanes": {"ok": False, "data": "$FAIL_REASON"},
  "lane_detail": {"ok": True, "data": {"lanes": []}}
}}))' >"\$out"
EOF

# T2 fixture: lanes section SUCCEEDS with a genuinely empty table.
cat >"$STUBS/collector-genuinely-empty.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
python3 -c '
import json
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": [], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": []}}
}}))' >"$out"
EOF

cat >"$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "$STUBS"/*.sh

beat_env() {  # <collector-stub> <beat-at>
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$1" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="$2" \
    LEADV2_BROAD_STATUS_DISPATCHED="1" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
}

# ── T1: RENDERER FALSIFIER ──────────────────────────────────────────────
beat_env "$STUBS/collector-lanes-fail.sh" "2026-08-21T20:00:00Z"
if [[ ! -f "$FOUNDER_STATUS" ]]; then
  fail "T1 fixture: founder-status.md not written — aborting"
  printf -- '%s\n' "${ERRORS[@]:-}" >&2; exit 1
fi
T1_CONTENT="$(cat "$FOUNDER_STATUS")"

if ! printf '%s' "$T1_CONTENT" | grep -q 'ДОСКА ПУСТА'; then
  pass "T1a: false 'ДОСКА ПУСТА' headline absent when the lanes section itself failed"
else
  fail "T1a: false empty-board headline still fires on a lanes-section failure: $T1_CONTENT"
fi

if printf '%s' "$T1_CONTENT" | grep -qi 'НЕ ВИЖУ ЛИНИИ'; then
  pass "T1b: distinct 'не вижу линии' marker present"
else
  fail "T1b: no distinct lanes-unavailable marker: $T1_CONTENT"
fi

if printf '%s' "$T1_CONTENT" | grep -qF "$FAIL_REASON"; then
  pass "T1c: the raw collector fail reason is surfaced verbatim, not a generic placeholder"
else
  fail "T1c: raw fail reason missing from beat: $T1_CONTENT"
fi

# ── T2: CONTROL CASE — a genuinely empty board must still say so ────────
beat_env "$STUBS/collector-genuinely-empty.sh" "2026-08-21T20:30:00Z"
T2_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$T2_CONTENT" | grep -q 'ДОСКА ПУСТА — ничего не выполняется'; then
  pass "T2: a genuinely empty board (lanes.ok=true, table=[]) still fires the real empty-board headline"
else
  fail "T2: legitimate empty-board headline suppressed: $T2_CONTENT"
fi
if ! printf '%s' "$T2_CONTENT" | grep -qi 'НЕ ВИЖУ ЛИНИИ'; then
  pass "T2b: no false 'не вижу линии' marker on a genuinely successful, genuinely empty collector run"
else
  fail "T2b: false lanes-unavailable marker fired on a healthy empty board: $T2_CONTENT"
fi

# ── T3: table_prefix also carries the marker (belt-and-suspenders) ──────
FULL_STATUS="$REPO/docs/leadv2/founder-status-full.md"
if [[ -f "$FULL_STATUS" ]]; then
  # T3 reuses the T2 fixture's absence and T1's presence by re-running T1
  # once more so founder-status-full.md reflects the lanes-fail beat.
  :
fi
beat_env "$STUBS/collector-lanes-fail.sh" "2026-08-21T21:00:00Z"
T3_FULL="$(cat "$FULL_STATUS" 2>/dev/null || true)"
if printf '%s' "$T3_FULL" | grep -qi 'НЕ ВИЖУ ЛИНИИ'; then
  pass "T3: table_prefix (full doc) also carries the lanes-unavailable marker"
else
  fail "T3: table region has no honest marker in the full doc: $T3_FULL"
fi

# ── T4: LANES-SNAPSHOT B1-CONTRACT regression lock ──────────────────────
T4_ROOT="$TMP/t4-proj"
mkdir -p "$T4_ROOT/docs/leadv2"
git -C "$T4_ROOT" init -q
lv2_assert_scratch_repo "$T4_ROOT"
printf 'sessions: [this is not valid: yaml: at all: -\n' >"$T4_ROOT/docs/leadv2/active.yaml"
T4_OUT="$(LEADV2_PROJECT_ROOT="$T4_ROOT" bash "$LANES_SNAPSHOT_SH" --json 2>&1)"
T4_RC=$?
T4_HAS_TYPED_ERROR="$(printf '%s' "$T4_OUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("not_json"); sys.exit(0)
print("registry_error" if d.get("error") == "registry_error" else "wrong_error:" + str(d.get("error")))
' 2>/dev/null || echo "not_json")"
if [[ "$T4_RC" -ne 0 ]] && [[ "$T4_HAS_TYPED_ERROR" == "registry_error" ]]; then
  pass "T4: malformed active.yaml -> leadv2-lanes-snapshot.sh exits non-zero with a typed registry_error (pre-existing PASS, locked as a regression guard)"
else
  fail "T4: B1 contract broken — rc=$T4_RC typed_error=$T4_HAS_TYPED_ERROR out=$T4_OUT"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
