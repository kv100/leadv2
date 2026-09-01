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
# T1  IDENTITY (T1a/T1b/T1c): two lanes with mission titles sharing a long
#     common prefix must render as two rows with DISTINCT "Линия" values
#     (the lane identity — task_id, dispatch id only as fallback — not the
#     human title); T1c additionally falsifies that the dispatch id must
#     NOT outrank a resolved task_id.
# T2  DEDUPE: a collector that reports the same task_id twice (own-repo
#     duplicate, or the same lane surfacing via two collector paths) must
#     still render exactly ONE row for that lane.
# T3  CROSS-REPO PRESENCE (T3a/T3b): lanes from two different repo roots
#     (one own-repo, one foreign — `repo` field set) must BOTH render, the
#     foreign one prefixed with its repo slug.
# T4  REPO-AWARE DEDUP: a bare task_id shared by an own-repo and a
#     foreign-repo lane must render as TWO rows (T4a), and the foreign row
#     must NOT carry the own-repo lane's lane_detail facts — stream_bytes,
#     "пишет сейчас" — fabricated liveness from a join it never made (T4b,
#     fix-round-3 NEW-1).
# T5  MISSING TASK_ID: two lanes that both lack a task_id must not collapse
#     into a single degraded row.
# T6  CLOSED-LANE HUMAN NAME: a terminal lane's "Закрыто сегодня" line
#     carries both the row identity and the human mission name.
#
# Each T is proven with a RED/GREEN mutation pair (mutation inside
# leadv2-broad-status.sh's function body, reverted after); RED artifacts
# for this round live in docs/handoff/BROAD-STATUS-ROWS-02/round3-red/.
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

# PULSE-REPO-SCOPED-03: the renderer now shows a foreign-repo lane only when
# THIS repo dispatched it (dispatch record <root>/docs/leadv2/tasks/<tid>/).
# These fixtures' foreign rows ARE the "dispatched from here" case, so seed
# the dispatch records up front — the suite's own contracts (identity, dedup,
# digest keys) are unchanged.
mkdir -p "$REPO/docs/leadv2/tasks/FOREIGN-LANE-01" \
         "$REPO/docs/leadv2/tasks/SHARED-ID-01" \
         "$REPO/docs/leadv2/tasks/DIGEST-KEY-01"

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
    {"task_id": "BROAD-STATUS-ROWS-01", "status": "active"},
    {"task_id": "BROAD-STATUS-ROWS-02", "status": "active"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "BROAD-STATUS-ROWS-01", "dispatch_id": "aaaaaaaa", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 111, "mission_title":
     "BROAD-STATUS-ROWS-01 -- the status pulse duplicates one lane and drops another (Light)"},
    {"task_id": "BROAD-STATUS-ROWS-02", "dispatch_id": "bbbbbbbb", "worker": "sonnet",
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
    {"task_id": "DUP-LANE-01", "status": "active"},
    {"task_id": "DUP-LANE-01", "status": "active"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "DUP-LANE-01", "dispatch_id": "cccccccc", "worker": "sonnet",
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
    {"task_id": "OWN-REPO-LANE-01", "status": "active"},
    {"task_id": "FOREIGN-LANE-01", "status": "active", "repo": "persona-engine", "age_s": 120}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "OWN-REPO-LANE-01", "dispatch_id": "eeeeeeee", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 444, "mission_title":
     "OWN-REPO-LANE-01 -- lives in the own repo"}
  ]}}
}}))' >"$out"
EOF

# ── stub collector: T4 repo-aware dedup fixture ─────────────────────────
# fix-round-2 (High #1): same bare task_id from an own-repo row and a
# foreign-repo row must render as TWO rows -- their rendered identity
# differs ("SHARED-ID-01" vs "persona-engine/SHARED-ID-01") even though
# the dedup key's task_id fragment is identical.
cat >"$STUBS/collector-repo-aware-dedup.sh" <<'EOF'
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
    {"task_id": "SHARED-ID-01", "status": "active"},
    {"task_id": "SHARED-ID-01", "status": "active", "repo": "persona-engine", "age_s": 60}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "SHARED-ID-01", "dispatch_id": "12121212", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 55, "mission_title":
     "SHARED-ID-01 -- own-repo half of the shared id"}
  ]}}
}}))' >"$out"
EOF

# ── stub collector: T5 missing-task_id fixture ──────────────────────────
# fix-round-2 (High #2): two DIFFERENT lanes that both lack a task_id must
# not collapse into a single row -- the second must still render as a
# degraded row, never silently vanish.
cat >"$STUBS/collector-missing-task-id.sh" <<'EOF'
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
    {"status": "active", "age_s": 30},
    {"status": "active", "age_s": 90}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": []}}
}}))' >"$out"
EOF

# ── stub collector: T6 closed-lane human-name fixture ───────────────────
# fix-round-2 (Medium): the "Закрыто сегодня" line must carry the row
# IDENTITY (task_id) for keying AND the human-readable mission name in
# prose -- losing the name when :519 was reworked to identity-only left
# the founder reading a bare id with no idea what the lane was.
cat >"$STUBS/collector-closed-name.sh" <<'EOF'
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
    {"task_id": "CLOSED-NAME-01", "status": "dead", "status_reason": "worker exited"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "CLOSED-NAME-01", "dispatch_id": "beadbeef", "worker": "sonnet",
     "mission_title": "CLOSED-NAME-01 -- retire the stale queue worker"}
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
T1_ROW_COUNT="$(printf '%s' "$T1_CONTENT" | grep -cE '^\| BROAD-STATUS-ROWS-0[12] ')"
if [[ "$T1_ROW_COUNT" -eq 2 ]]; then
  pass "T1a: two lanes with a shared mission-title prefix render as TWO distinct-identity rows"
else
  fail "T1a: expected 2 identity rows, got $T1_ROW_COUNT: $T1_CONTENT"
fi
# High #3 falsifier: identity must be the raw task_id (BROAD-STATUS-ROWS-0N),
# NEVER the bound dispatch id (dispatch-aaaaaaaa / dispatch-bbbbbbbb) -- a
# real task_id must always outrank the dispatch id per decision IDENTITY.
if printf '%s' "$T1_CONTENT" | grep -q '^| BROAD-STATUS-ROWS-01 ' \
    && printf '%s' "$T1_CONTENT" | grep -q '^| BROAD-STATUS-ROWS-02 '; then
  pass "T1b: both lane identities present verbatim (as task_id) in the Линия column"
else
  fail "T1b: lane identities missing/collapsed: $T1_CONTENT"
fi
if printf '%s' "$T1_CONTENT" | grep -qE '^\| dispatch-(aaaaaaaa|bbbbbbbb) '; then
  fail "T1c: identity rendered the dispatch id instead of the task_id: $T1_CONTENT"
else
  pass "T1c: task_id outranks the bound dispatch id in the Линия column"
fi

# ── T2: DEDUPE — same task_id twice in the collector's table ────────────
beat_env "$STUBS/collector-dup-tid.sh" "2026-08-30T01:30:00Z"
T2_CONTENT="$(cat "$FOUNDER_STATUS")"
T2_ROW_COUNT="$(printf '%s' "$T2_CONTENT" | grep -cE '^\| DUP-LANE-01 ')"
if [[ "$T2_ROW_COUNT" -eq 1 ]]; then
  pass "T2: a task_id reported twice by the collector still renders exactly ONE row"
else
  fail "T2: expected exactly 1 row for the duplicated task_id, got $T2_ROW_COUNT: $T2_CONTENT"
fi

# ── T3: CROSS-REPO PRESENCE — own-repo + foreign-repo lanes both render ─
beat_env "$STUBS/collector-cross-repo.sh" "2026-08-30T02:00:00Z"
T3_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$T3_CONTENT" | grep -q '^| OWN-REPO-LANE-01 '; then
  pass "T3a: own-repo lane renders"
else
  fail "T3a: own-repo lane missing: $T3_CONTENT"
fi
if printf '%s' "$T3_CONTENT" | grep -q '^| persona-engine/FOREIGN-LANE-01 '; then
  pass "T3b: foreign-repo lane renders, prefixed with its repo slug"
else
  fail "T3b: foreign-repo lane missing from the table: $T3_CONTENT"
fi

# ── T4: REPO-AWARE DEDUP — same bare task_id, own-repo + foreign-repo ───
beat_env "$STUBS/collector-repo-aware-dedup.sh" "2026-08-30T02:30:00Z"
T4_CONTENT="$(cat "$FOUNDER_STATUS")"
T4_OWN="$(printf '%s' "$T4_CONTENT" | grep -cE '^\| SHARED-ID-01 ')"
T4_FOREIGN="$(printf '%s' "$T4_CONTENT" | grep -cE '^\| persona-engine/SHARED-ID-01 ')"
if [[ "$T4_OWN" -eq 1 ]] && [[ "$T4_FOREIGN" -eq 1 ]]; then
  pass "T4a: a bare task_id shared by an own-repo and a foreign-repo lane renders as TWO rows"
else
  fail "T4a: repo-blind dedup key ate one of the two lanes (own=$T4_OWN foreign=$T4_FOREIGN): $T4_CONTENT"
fi
# fix-round-3 (NEW-1): the foreign row must NOT join the own-repo lane's
# lane_detail facts via the bare task_id -- a foreign lane silent for a
# minute (age_s=60) must never render the own lane's "пишет сейчас (55
# байт в потоке)" liveness, which would be a fabricated claim.
T4_FOREIGN_LINE="$(printf '%s' "$T4_CONTENT" | grep -E '^\| persona-engine/SHARED-ID-01 ')"
if printf '%s' "$T4_FOREIGN_LINE" | grep -qE '55 байт|пишет сейчас'; then
  fail "T4b: foreign row fabricated the own-repo lane's liveness: $T4_FOREIGN_LINE"
else
  pass "T4b: foreign row does not carry the own-repo lane's stream_bytes/writing_now"
fi

# ── T5: MISSING TASK_ID — two lanes, neither carries a task_id ──────────
beat_env "$STUBS/collector-missing-task-id.sh" "2026-08-30T03:00:00Z"
T5_CONTENT="$(cat "$FOUNDER_STATUS")"
T5_ROW_COUNT="$(printf '%s' "$T5_CONTENT" | grep -cE '^\| \? \(dispatch id unknown\) ')"
if [[ "$T5_ROW_COUNT" -eq 2 ]]; then
  pass "T5: two task_id-less lanes both render as distinct degraded rows, neither vanishes"
else
  fail "T5: expected 2 degraded rows for task_id-less lanes, got $T5_ROW_COUNT: $T5_CONTENT"
fi

# ── T6: CLOSED-LANE HUMAN NAME — identity AND the name, not either/or ───
beat_env "$STUBS/collector-closed-name.sh" "2026-08-30T03:30:00Z"
FULL_STATUS_T6="$REPO/docs/leadv2/founder-status-full.md"
T6_CLOSED_LINE="$(grep -m1 '^Закрыто сегодня:' "$FULL_STATUS_T6" 2>/dev/null || true)"
if printf '%s' "$T6_CLOSED_LINE" | grep -q 'CLOSED-NAME-01' \
    && printf '%s' "$T6_CLOSED_LINE" | grep -qi 'retire the stale queue'; then
  pass "T6: closed line carries both the identity and the human mission name"
else
  fail "T6: closed line lost identity or human name: ${T6_CLOSED_LINE:-<none>}"
fi

# ── T7: DIGEST KEY IS (repo, task_id) — fix-round-4 R3-4 negative control
#    for fix-round-3 NEW-5, which had zero suite failures on revert. Beat A:
#    only an own-repo lane DIGEST-KEY-01. Beat B: the SAME own lane plus a
#    NEW foreign lane sharing the bare task_id DIGEST-KEY-01. If the delta
#    digest is keyed on bare task_id (the round-2 shape), the foreign
#    lane's key collides with the already-known own lane's key and the
#    delta line reports 0 raised -- a genuinely new lane appearing on the
#    board with no announcement. Keyed on (repo, task_id), it must report
#    exactly 1 raised. ──────────────────────────────────────────────────
cat >"$STUBS/collector-digest-key-a.sh" <<'EOF'
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
    {"task_id": "DIGEST-KEY-01", "status": "active"}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "DIGEST-KEY-01", "dispatch_id": "cccccccc", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 10, "mission_title": "DIGEST-KEY-01 -- own lane"}
  ]}}
}}))' >"$out"
EOF
cat >"$STUBS/collector-digest-key-b.sh" <<'EOF'
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
    {"task_id": "DIGEST-KEY-01", "status": "active"},
    {"task_id": "DIGEST-KEY-01", "status": "active", "repo": "persona-engine", "age_s": 30}
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
    {"task_id": "DIGEST-KEY-01", "dispatch_id": "cccccccc", "worker": "sonnet",
     "writing_now": True, "stream_bytes": 10, "mission_title": "DIGEST-KEY-01 -- own lane"}
  ]}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-digest-key-a.sh" "$STUBS/collector-digest-key-b.sh"

beat_env "$STUBS/collector-digest-key-a.sh" "2026-08-30T07:00:00Z"
beat_env "$STUBS/collector-digest-key-b.sh" "2026-08-30T07:30:00Z"
T7_CONTENT="$(cat "$FOUNDER_STATUS")"
T7_DELTA="$(printf '%s' "$T7_CONTENT" | grep -m1 '^С прошлого удара:')"
if printf '%s' "$T7_DELTA" | grep -q '+1 линии подняты'; then
  pass "T7: digest key is (repo, task_id) — a new foreign lane sharing a bare id with a known own lane is counted as raised"
else
  fail "T7: digest key collapsed the foreign lane into the own lane's key, delta wrong: ${T7_DELTA:-<none>}"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
