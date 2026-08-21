#!/usr/bin/env bash
# tests/test-pulse-readable-rendering.sh — PULSE-READABLE-01.
#
# Reproduces the founder-rejected 2026-08-21 beat shape directly: a lane
# table where 5 of 6 rows are tombstoned pid-birth-mismatch junk
# ("(имя неизвестно) | — | pid birth mismatch (reuse)", status bucket
# "dead" with NO colon — leadv2-lanes-snapshot.sh:649/1113-1122), and
# asserts the NEW compact beat contract:
#   T1  junk (pid-birth-mismatch, bucket-form dead) rows are absent from
#       the live table
#   T2  the literal string "(имя неизвестно)" never appears anywhere in
#       the compact beat
#   T3  the compact beat is <=14 lines (rule 7)
#   T4  the product-truth line 1 is present, with the beat timestamp/product
#       metrics ahead of the table (rule 1) -- and prints "н/д" (never "0")
#       for a metric repo_facts does not supply
#   T5  everything cut from the compact beat (full lane detail, full queue,
#       full closed paragraph) is still present, in full, in
#       founder-status-full.md (rule 6 "nothing is lost")
#   T6  [BROAD_STATUS]/[BROAD_STATUS_END] markers and the BEAT_AT stamp on
#       line 1 survive (rule 7's relay contract)
#
# Hermetic: throwaway LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT, a hand-crafted
# collector stub (no dependency on the real lane-detail.sh, so this suite
# is decoupled from the pre-existing, out-of-scope "mission_title" field
# mismatch tracked separately), stubbed claude call, no network.
# Run: bash scripts/tests/test-pulse-readable-rendering.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir pulse-readable-rendering)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"
FULL_STATUS="$REPO/docs/leadv2/founder-status-full.md"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$REPO/docs/leadv2"

# ── collector stub: the EXACT founder-rejected shape — 1 legit live lane,
#    5 tombstoned pid-birth-mismatch junk rows (bucket "dead", no colon,
#    reason "pid birth mismatch (reuse)"), no lane_detail row for the junk
#    (matches leadv2-lanes-snapshot.sh's tombstone-table-row shape). ───────
cat > "$STUBS/collector.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]
junk_reasons = [
    "pid birth mismatch (reuse)", "pid birth mismatch (reuse)",
    "pid birth mismatch (reuse)", "pid birth mismatch (reuse)",
    "pid birth mismatch (reuse)",
]
table = [{"task_id": "dispatch-live1", "phase": "build", "minutes_in_phase": 5,
          "status": "live", "status_reason": "writing", "waiting": False,
          "where": "terminal", "protocol_version": 2}]
for i, reason in enumerate(junk_reasons):
    table.append({
        "task_id": f"dispatch-junk{i}", "phase": "intake", "minutes_in_phase": 500 + i,
        "status": "dead", "status_reason": reason,
        "waiting": False, "where": "terminal record", "protocol_version": 2,
    })
snap = {"sections": {
    "lanes": {"ok": True, "data": {"table": table, "questions": [], "degraded": []}},
    "lane_detail": {"ok": True, "data": {"lanes": [
        {"task_id": "dispatch-live1", "verdict": "alive", "worker": "codex/gpt-5.6",
         "stream_bytes": 1200, "stream_mtime_age_s": 10, "writing_now": True,
         "disk": None, "mission_title": None, "terminal_reason": None},
    ]}},
    "repo_facts": {"ok": True, "data": {"comments_today": 14, "comments_floor": 60}},
}}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(snap, fh)
PY
EOF
chmod +x "$STUBS/collector.sh"

cat > "$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$STUBS/claude.sh"

# queued/landed content so founder-status-full.md's overflow has something
# real to carry (T5).
git -C "$REPO" config user.email test@test.local
git -C "$REPO" config user.name test
git -C "$REPO" commit --allow-empty -q -m "seed commit for landed-today"

beat_env() {
  LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-21T08:09:49Z" \
    LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" "$@"
}
beat_env bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true

if [[ ! -f "$FOUNDER_STATUS" ]]; then
  fail "fixture: founder-status.md not written — aborting"
  printf -- '%s\n' "${ERRORS[@]:-}" >&2; exit 1
fi
CONTENT="$(cat "$FOUNDER_STATUS")"
FULL_CONTENT="$(cat "$FULL_STATUS" 2>/dev/null || true)"

# ── T1: junk rows absent from the live table ────────────────────────────
if ! printf '%s' "$CONTENT" | grep -q 'pid birth mismatch'; then
  pass "T1: pid-birth-mismatch junk rows absent from the compact beat"
else
  fail "T1: junk row leaked into compact beat:
$CONTENT"
fi

# ── T2: the literal "(имя неизвестно)" string never appears ────────────
if ! printf '%s' "$CONTENT" | grep -q 'имя неизвестно'; then
  pass "T2: literal (имя неизвестно) is gone from the compact beat"
else
  fail "T2: (имя неизвестно) still present:
$CONTENT"
fi

# ── T3: whole beat <=14 lines ─────────────────────────────────────────
LINE_COUNT="$(printf '%s\n' "$CONTENT" | wc -l | tr -d ' ')"
if [[ "$LINE_COUNT" -le 14 ]]; then
  pass "T3: compact beat is <=14 lines (actual: $LINE_COUNT)"
else
  fail "T3: compact beat too long: $LINE_COUNT lines
$CONTENT"
fi

# ── T4: product-truth line 1 present, missing metric prints н/д never 0 ──
if printf '%s' "$CONTENT" | grep -qE '·.*комменты 14/60' \
   && printf '%s' "$CONTENT" | grep -qE '·.*посты н/д' \
   && ! printf '%s' "$CONTENT" | grep -qE '·.*посты 0/'; then
  pass "T4: product line shows real comments count and н/д (never 0) for the missing posts metric"
else
  fail "T4: product line wrong:
$CONTENT"
fi

# ── T5: nothing cut is lost — full doc carries the junk row + its cause ──
if printf '%s' "$FULL_CONTENT" | grep -q 'dispatch-junk0' \
   && printf '%s' "$FULL_CONTENT" | grep -q 'pid birth mismatch (reuse)'; then
  pass "T5: full doc (founder-status-full.md) still carries every cut junk row + cause"
else
  fail "T5: full doc missing cut content:
$FULL_CONTENT"
fi
if printf '%s' "$CONTENT" | grep -q 'founder-status-full.md'; then
  pass "T5b: compact beat points at the full doc"
else
  fail "T5b: compact beat has no pointer to the full doc"
fi

# ── T6: markers + BEAT_AT stamp on line 1 survive ────────────────────────
FIRST_LINE="$(printf '%s\n' "$CONTENT" | head -1)"
if printf '%s' "$FIRST_LINE" | grep -q '^2026-08-21T08:09:49Z \[BROAD_STATUS\]' \
   && printf '%s' "$CONTENT" | grep -qF '[BROAD_STATUS_END]'; then
  pass "T6: [BROAD_STATUS]/[BROAD_STATUS_END] markers + BEAT_AT stamp intact"
else
  fail "T6: marker/stamp contract broken: $FIRST_LINE"
fi

printf '\n[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
