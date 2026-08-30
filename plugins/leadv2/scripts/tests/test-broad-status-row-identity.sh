#!/usr/bin/env bash
# tests/test-broad-status-row-identity.sh — BROAD-STATUS-ROWS-01.
#
# DEFECT (measured 2026-08-30T01:03:00Z): leadv2-broad-status.sh derived the
# "Линия" column from human_name(mission_title) -- a <=5-word truncation of
# the mission title. Two lanes whose mission titles share a long common
# prefix (e.g. two rounds of the same task, "BROAD-STATUS-ROWS-01 — the
# status pulse ..." / "BROAD-STATUS-ROWS-02 — the status pulse ...")
# collapsed to the IDENTICAL short name once the leading id token was
# stripped, so the founder saw one lane rendered twice (same byte count,
# same everything) and the other lane nowhere.
#
# T1  IDENTITY: two lanes with mission titles sharing a long common prefix
#     must render as two rows with DISTINCT "Линия" values (the lane
#     identity — dispatch id / task_id — not the human title).
# T2  DEDUPE: a collector that reports the same task_id twice (own-repo
#     duplicate, or the same lane surfacing via two collector paths) must
#     still render exactly ONE row for that lane.
# T3  CROSS-REPO PRESENCE: lanes from two different repo roots (one
#     own-repo, one foreign — `repo` field set) must BOTH render.
#
# Each T below is proven with a RED/GREEN mutation pair: the assertion is
# shown failing against a real code mutation inside leadv2-broad-status.sh's
# function body (not a grep-for-a-string stand-in), then passing again once
# the mutation is reverted.
#
# Hermetic: throwaway LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT, stubbed
# collector / claude, no network, no crontab, no real dispatch.
# Run: bash scripts/tests/test-broad-status-row-identity.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir broad-status-row-identity)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── stub collector: T1/T2 fixture ───────────────────────────────────────
# Two lanes whose mission titles share the long common prefix that
# survives human_name()'s leading-id-token strip + 5-word truncation, so
# BOTH would collapse to the same short name under the pre-fix renderer.
cat >"$STUBS/collector-shared-prefix.sh" <<'EOF'
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
  "lanes": {"ok": True, "data": {"table": [
    {"task_id": "dispatch-aaaaaaaa", "status": "active"},
    {"task_id": "dispatch-bbbbbbbb", "status": "active"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "dispatch-aaaaaaaa", "dispatch_id": "aaaaaaaa", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 111, "mission_title":
     "BROAD-STATUS-ROWS-01 -- the status pulse duplicates one lane and drops another (Light)"},
    {"task_id": "dispatch-bbbbbbbb", "dispatch_id": "bbbbbbbb", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 222, "mission_title":
     "BROAD-STATUS-ROWS-02 -- the status pulse duplicates one lane and drops another (Light)"}
  ]}}
}}))' >"$out"
EOF

# ── stub collector: T2 dedupe fixture ───────────────────────────────────
# A single lane surfacing TWICE in the lanes table under the same task_id
# (the observed duplicate-row shape, regardless of upstream cause).
cat >"$STUBS/collector-dup-tid.sh" <<'EOF'
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
  "lanes": {"ok": True, "data": {"table": [
    {"task_id": "dispatch-cccccccc", "status": "active"},
    {"task_id": "dispatch-cccccccc", "status": "active"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "dispatch-cccccccc", "dispatch_id": "cccccccc", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 333, "mission_title":
     "DUP-LANE-01 -- one lane must never render twice"}
  ]}}
}}))' >"$out"
EOF

# ── stub collector: T3 cross-repo fixture ───────────────────────────────
# One own-repo lane (no `repo` field, joins lane_detail) + one foreign-repo
# lane (repo=persona-engine, no lane_detail join — foreign rows never join
# the own-repo-only lane_detail section).
cat >"$STUBS/collector-cross-repo.sh" <<'EOF'
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
  "lanes": {"ok": True, "data": {"table": [
    {"task_id": "dispatch-eeeeeeee", "status": "active"},
    {"task_id": "dispatch-ffffffff", "status": "active", "repo": "persona-engine", "age_s": 120}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "dispatch-eeeeeeee", "dispatch_id": "eeeeeeee", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 444, "mission_title":
     "OWN-REPO-LANE-01 -- lives in the own repo"}
  ]}}
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

# ── T1: IDENTITY — two lanes, shared mission-title prefix ──────────────
beat_env "$STUBS/collector-shared-prefix.sh" "2026-08-30T01:00:00Z"
if [[ ! -f "$FOUNDER_STATUS" ]]; then
  fail "T1 fixture: founder-status.md not written — aborting"
  printf -- '%s\n' "${ERRORS[@]:-}" >&2; exit 1
fi
T1_CONTENT="$(cat "$FOUNDER_STATUS")"
T1_ROW_COUNT="$(printf '%s' "$T1_CONTENT" | grep -cE '^\| dispatch-')"
if [[ "$T1_ROW_COUNT" -eq 2 ]]; then
  pass "T1a: two lanes with a shared mission-title prefix render as TWO distinct-identity rows"
else
  fail "T1a: expected 2 identity rows, got $T1_ROW_COUNT: $T1_CONTENT"
fi
if printf '%s' "$T1_CONTENT" | grep -q '^| dispatch-aaaaaaaa ' \
    && printf '%s' "$T1_CONTENT" | grep -q '^| dispatch-bbbbbbbb '; then
  pass "T1b: both lane identities present verbatim in the Линия column"
else
  fail "T1b: lane identities missing/collapsed: $T1_CONTENT"
fi

# ── T2: DEDUPE — same task_id twice in the collector's table ────────────
beat_env "$STUBS/collector-dup-tid.sh" "2026-08-30T01:30:00Z"
T2_CONTENT="$(cat "$FOUNDER_STATUS")"
T2_ROW_COUNT="$(printf '%s' "$T2_CONTENT" | grep -cE '^\| dispatch-cccccccc ')"
if [[ "$T2_ROW_COUNT" -eq 1 ]]; then
  pass "T2: a task_id reported twice by the collector still renders exactly ONE row"
else
  fail "T2: expected exactly 1 row for the duplicated task_id, got $T2_ROW_COUNT: $T2_CONTENT"
fi

# ── T3: CROSS-REPO PRESENCE — own-repo + foreign-repo lanes both render ─
beat_env "$STUBS/collector-cross-repo.sh" "2026-08-30T02:00:00Z"
T3_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$T3_CONTENT" | grep -q '^| dispatch-eeeeeeee '; then
  pass "T3a: own-repo lane renders"
else
  fail "T3a: own-repo lane missing: $T3_CONTENT"
fi
if printf '%s' "$T3_CONTENT" | grep -q '^| persona-engine/dispatch-ffffffff '; then
  pass "T3b: foreign-repo lane renders, prefixed with its repo slug"
else
  fail "T3b: foreign-repo lane missing from the table: $T3_CONTENT"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
