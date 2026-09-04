#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-broad-status.sh
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
# T5  CROSS-REPO CAP SURVIVAL: 7 own + 1 foreign — the foreign lane must
#     survive TABLE_ROW_CAP, and the own budget left for own-repo rows is
#     asserted to the exact count (fix-round-3 NEW-9).
# T6  FOREIGN CAP IS BOUNDED, BUT THE RESERVE IS A FLOOR NOT A CEILING
#     (fix-round-3 NEW-2, re-specified fix-round-4 R3-2): 10 foreign + 0
#     own — a foreign surge must still be capped (never rendered without
#     bound; leadv2-lanes-snapshot.sh applies no cap/status filter to
#     foreign rows at the source), but with ZERO own-repo rows competing
#     for the table there is nothing for FOREIGN_ROW_RESERVE to protect —
#     foreign must fill the WHOLE TABLE_ROW_CAP, not just its reserved
#     slice. Round-3's version applied the reserve unconditionally: 2 of 6
#     slots filled, 4 sitting empty, while the beat told the founder "8
#     строк таблицы не поместилось" — a lie, since only 4 rows actually
#     failed to fit.
# T7  OWN-REPO FLOOR SURVIVES A FOREIGN SURGE (fix-round-3 NEW-3): 6
#     foreign + 7 own — own-repo rows must keep a floor of TABLE_ROW_CAP -
#     FOREIGN_ROW_RESERVE, never be evicted to zero and folded into
#     "мусорных/лишних строк" the founder is told about his own board.
#
# Hermetic: throwaway LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT, stubbed
# collector / claude, no network, no crontab, no real dispatch.
# Run: bash scripts/tests/test-broad-status-lanes-blind.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

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

# T5 fixture: 7 own-repo active lanes (TABLE_ROW_CAP=6 alone would drop one)
# PLUS 1 foreign-repo lane appended after them, byte-identical in shape to
# how leadv2-lanes-snapshot.sh actually merges foreign rows (own-repo ranked
# and capped first, foreign rows APPENDED to the end) -- BROAD-STATUS-ROWS-02
# fix-round-2 Critical: a plain `[:TABLE_ROW_CAP]` slice cuts the trailing
# foreign row every time own-repo lanes alone fill the cap.
cat >"$STUBS/collector-cap-cross-repo.sh" <<'EOF'
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
import json, os
own = [{"task_id": f"OWN-CAP-{i:02d}", "status": "active"} for i in range(1, 8)]
foreign = [{"task_id": "FOREIGN-CAP-01", "status": "active", "repo": "persona-engine", "age_s": 30}]
# PULSE-REPO-SCOPED-03: the renderer shows a foreign lane only when THIS repo
# dispatched it; these fixture foreign rows are the dispatched case, so the
# stub seeds their dispatch records (<root>/docs/leadv2/tasks/<tid>/) itself.
for _f in foreign:
    os.makedirs(os.path.join(os.environ["LEADV2_PROJECT_ROOT"], "docs", "leadv2", "tasks", _f["task_id"]), exist_ok=True)
own_detail = [
    {"task_id": f"OWN-CAP-{i:02d}", "dispatch_id": f"{i:08x}", "worker": "sonnet",
     "writing_now": True, "stream_bytes": i, "mission_title": f"OWN-CAP-{i:02d} -- filler lane {i}"}
    for i in range(1, 8)
]
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": own + foreign, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": own_detail}}
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

# ── T5: CROSS-REPO CAP SURVIVAL (folded in from BROAD-STATUS-ROWS-02) ───
# 7 own-repo lanes + 1 foreign lane, TABLE_ROW_CAP=6: the foreign lane must
# survive the cap and must never be counted among the "мусорных/лишних
# строк" the founder is told were hidden as junk.
beat_env "$STUBS/collector-cap-cross-repo.sh" "2026-08-30T04:00:00Z"
T5_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$T5_CONTENT" | grep -q '^| persona-engine/FOREIGN-CAP-01 '; then
  pass "T5a: a foreign-repo lane survives the TABLE_ROW_CAP even with 7 own-repo lanes ahead of it"
else
  fail "T5a: foreign-repo lane was cut by the row cap: $T5_CONTENT"
fi
T5_OWN_ROWS="$(printf '%s' "$T5_CONTENT" | grep -cE '^\| OWN-CAP-[0-9]+ ')"
# fix-round-3 (NEW-9): assert the EXACT expected count, not `-ge 1` -- the
# loose bound passed even with 6 of 7 own lanes evicted (NEW-3) and could
# not see that regression. TABLE_ROW_CAP=6, FOREIGN_ROW_RESERVE=2,
# foreign_slots=min(1,2)=1 -> own budget = 6-1 = 5.
if [[ "$T5_OWN_ROWS" -eq 5 ]]; then
  pass "T5b: exactly 5 own-repo rows render (own budget = TABLE_ROW_CAP - foreign_slots)"
else
  fail "T5b: expected exactly 5 own-repo rows, got $T5_OWN_ROWS: $T5_CONTENT"
fi

# ── T6: FOREIGN CAP IS BOUNDED — 10 foreign, 0 own (fix-round-3 NEW-2) ───
# leadv2-lanes-snapshot.sh applies no cap and no status filter to foreign
# rows, so round-2's unconditional "foreign rows are never truncated"
# defeated TABLE_ROW_CAP without bound. Foreign must be capped too.
cat >"$STUBS/collector-foreign-only.sh" <<'EOF'
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
import json, os
foreign = [{"task_id": f"FOREIGN-ONLY-{i:02d}", "status": "active",
            "repo": "persona-engine", "age_s": 30} for i in range(1, 11)]
# PULSE-REPO-SCOPED-03: seed dispatch records — these rows are the
# dispatched-foreign case under test (the hidden-rows cap).
for _f in foreign:
    os.makedirs(os.path.join(os.environ["LEADV2_PROJECT_ROOT"], "docs", "leadv2", "tasks", _f["task_id"]), exist_ok=True)
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": foreign, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": []}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-foreign-only.sh"

beat_env "$STUBS/collector-foreign-only.sh" "2026-08-30T04:30:00Z"
T6_CONTENT="$(cat "$FOUNDER_STATUS")"
T6_FOREIGN_ROWS="$(printf '%s' "$T6_CONTENT" | grep -cE '^\| persona-engine/FOREIGN-ONLY-[0-9]+ ')"
if [[ "$T6_FOREIGN_ROWS" -eq 6 ]]; then
  pass "T6a: 10 foreign lanes, 0 own — table is FILLED (6 of TABLE_ROW_CAP), not starved to FOREIGN_ROW_RESERVE"
else
  fail "T6a: foreign rows not filling the cap when own=0, got $T6_FOREIGN_ROWS rows: $T6_CONTENT"
fi
# fix-round-4 (R3-2): the hidden-count must equal what was ACTUALLY dropped
# (10 supplied - 6 rendered = 4), never the old inflated "8" that came from
# applying the reserve as a ceiling even with no own rows to protect.
if printf '%s' "$T6_CONTENT" | grep -q '4 чужих строк не поместилось' \
   && ! printf '%s' "$T6_CONTENT" | grep -q '8 строк'; then
  pass "T6b: hidden count matches what was actually dropped (4, not 8)"
else
  fail "T6b: hidden count wrong: $(printf '%s' "$T6_CONTENT" | grep 'не поместилось' || echo '<none>')"
fi

# ── T7: OWN-REPO FLOOR SURVIVES A FOREIGN SURGE — 6 foreign, 7 own ──────
# fix-round-3 (NEW-3): round-2's `max(0, TABLE_ROW_CAP - foreign_count)`
# let enough foreign lanes evict EVERY own-repo row, so the founder's own
# live lanes were folded into "мусорных/лишних строк" -- the exact lie
# this task exists to delete, pointed at the founder's own board.
cat >"$STUBS/collector-foreign-surge.sh" <<'EOF'
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
import json, os
own = [{"task_id": f"OWN-SURGE-{i:02d}", "status": "active"} for i in range(1, 8)]
foreign = [{"task_id": f"FOREIGN-SURGE-{i:02d}", "status": "active",
            "repo": "persona-engine", "age_s": 30} for i in range(1, 7)]
# PULSE-REPO-SCOPED-03: seed dispatch records — dispatched-foreign case.
for _f in foreign:
    os.makedirs(os.path.join(os.environ["LEADV2_PROJECT_ROOT"], "docs", "leadv2", "tasks", _f["task_id"]), exist_ok=True)
own_detail = [
    {"task_id": f"OWN-SURGE-{i:02d}", "dispatch_id": f"{i:08x}", "worker": "sonnet",
     "writing_now": True, "stream_bytes": i, "mission_title": f"OWN-SURGE-{i:02d} -- filler lane {i}"}
    for i in range(1, 8)
]
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": own + foreign, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": own_detail}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-foreign-surge.sh"

beat_env "$STUBS/collector-foreign-surge.sh" "2026-08-30T05:00:00Z"
T7_CONTENT="$(cat "$FOUNDER_STATUS")"
T7_OWN_ROWS="$(printf '%s' "$T7_CONTENT" | grep -cE '^\| OWN-SURGE-[0-9]+ ')"
if [[ "$T7_OWN_ROWS" -eq 4 ]]; then
  pass "T7: 6 foreign + 7 own — own-repo floor holds at 4 rows (TABLE_ROW_CAP - FOREIGN_ROW_RESERVE), never zero"
else
  fail "T7: own-repo lanes starved by a foreign surge, got $T7_OWN_ROWS own rows: $T7_CONTENT"
fi

# ── T8: MALFORMED ROW IS UNREADABLE, NOT ABSENT (fix-round-4 R3-3) ──────
# The L1 fix (fix-round-3) stopped a non-dict table row from crashing the
# whole beat, but dropped it UNCOUNTED -- so a collector table containing
# only malformed elements rendered as a plain empty table, indistinguishable
# from a genuinely empty board (LANE-DETAIL-BLIND-01's failure mode, one
# level down: a malformed ROW is unreadable, not absent).
cat >"$STUBS/collector-malformed-rows.sh" <<'EOF'
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
  "lanes": {"ok": True, "data": {"table": ["not-a-row", None, 42], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": []}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-malformed-rows.sh"

beat_env "$STUBS/collector-malformed-rows.sh" "2026-08-30T06:00:00Z"
T8_CONTENT="$(cat "$FOUNDER_STATUS")"
if ! printf '%s' "$T8_CONTENT" | grep -q 'ДОСКА ПУСТА'; then
  pass "T8a: 3 malformed rows, lanes.ok=true — no false 'ДОСКА ПУСТА' claim"
else
  fail "T8a: malformed rows rendered as a false empty board: $T8_CONTENT"
fi
if printf '%s' "$T8_CONTENT" | grep -q '3 строк' && printf '%s' "$T8_CONTENT" | grep -qi 'не читаются'; then
  pass "T8b: malformed row count (3) surfaced, named as unreadable"
else
  fail "T8b: malformed rows dropped silently, not surfaced: $T8_CONTENT"
fi

# ── T8c: THE REMEDY IS THE TABLE ITSELF, NOT JUST THE PROSE ABOVE IT
#     (fix-round-5 R3-3) ─────────────────────────────────────────────────
# round-4 counted and named the malformed rows in a prefix line, but the
# table BODY still printed only "(живых линий нет)" beneath it -- a reader
# counting rows inside the table saw zero, not three-unreadable. Each
# malformed row must now render as its own NAMED row inside the table.
T8C_TABLE_ROWS="$(printf '%s' "$T8_CONTENT" | grep -cE '^\| \(строка [0-9]+ повреждена\) \|')"
if [[ "$T8C_TABLE_ROWS" -eq 3 ]]; then
  pass "T8c: all 3 malformed rows render as named rows INSIDE the table, not just counted in a prefix line"
else
  fail "T8c: expected 3 named malformed rows inside the table, got $T8C_TABLE_ROWS: $T8_CONTENT"
fi
if ! printf '%s' "$T8_CONTENT" | grep -qF '(живых линий нет)'; then
  pass "T8d: table no longer prints the positive-looking '(живых линий нет)' placeholder when rows are merely unreadable"
else
  fail "T8d: table still prints the false-empty placeholder alongside unreadable rows: $T8_CONTENT"
fi

# ── T9: MU3 CONTROL — the table_prefix degraded line specifically
#     (fix-round-5, reviewer mutation MU3: `if malformed_row_count:` ->
#     `if False:` at the table_prefix append site) ───────────────────────
# T8b/T8c both also pass off the in-table named rows added by R3-3's remedy,
# so neither kills MU3 on its own -- this fixture asserts the table_prefix
# line's own, distinct wording ("НЕ ЧИТАЮТСЯ N строк(и) таблицы
# (повреждённый формат...)"), which exists ONLY at that one call site and
# disappears completely if MU3 guts it, independent of the in-table rows.
cat >"$STUBS/collector-malformed-mix.sh" <<'EOF'
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
      {"task_id": "GOOD-MX-01", "status": "active"}, "bad-row", None
  ], "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": [
      {"task_id": "GOOD-MX-01", "dispatch_id": "aa11bb22", "worker": "sonnet",
       "writing_now": True, "stream_bytes": 5, "mission_title": "GOOD-MX-01 -- a real lane"}
  ]}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-malformed-mix.sh"

beat_env "$STUBS/collector-malformed-mix.sh" "2026-08-30T06:15:00Z"
T9_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$T9_CONTENT" | grep -qF 'НЕ ЧИТАЮТСЯ 2 строк(и) таблицы'; then
  pass "T9: MU3 control — table_prefix's own degraded-line wording is present (survives with the fix intact)"
else
  fail "T9: table_prefix degraded line missing or reworded: $T9_CONTENT"
fi

# ── T10: OWN=1..3 x FOREIGN=1..5 MATRIX (fix-round-5 N4-1/N4-2) ─────────
# N4-1: round-4's floor/reserve special-cased only `own==0`, so the ordinary
# board (WIP is 1-3 own lanes/session) fell into the reserve branch even
# when everything fit under TABLE_ROW_CAP=6 -- "2 own + 4 foreign" (6 lanes,
# 6 slots) rendered only 4 rows and reported 2 lanes as "not fitting" when
# they plainly did. Every own/foreign pair below where own+foreign<=6 must
# render ALL rows and print NO hidden-count sentence; every pair where the
# total exceeds 6 must still hit the reserve/floor split and print one.
cat >"$STUBS/collector-own-foreign-matrix.sh" <<'EOF'
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
import json, os
own_n = int(os.environ["MATRIX_OWN_N"])
foreign_n = int(os.environ["MATRIX_FOREIGN_N"])
tag = f"{own_n}-{foreign_n}"
own = [{"task_id": f"OWN-MX-{tag}-{i:02d}", "status": "active"} for i in range(1, own_n + 1)]
foreign = [{"task_id": f"FOREIGN-MX-{tag}-{i:02d}", "status": "active",
            "repo": "persona-engine", "age_s": 30} for i in range(1, foreign_n + 1)]
# PULSE-REPO-SCOPED-03: seed dispatch records — dispatched-foreign case.
for _f in foreign:
    os.makedirs(os.path.join(os.environ["LEADV2_PROJECT_ROOT"], "docs", "leadv2", "tasks", _f["task_id"]), exist_ok=True)
own_detail = [
    {"task_id": f"OWN-MX-{tag}-{i:02d}", "dispatch_id": f"{i:08x}", "worker": "sonnet",
     "writing_now": True, "stream_bytes": i, "mission_title": f"OWN-MX-{tag}-{i:02d} -- filler lane {i}"}
    for i in range(1, own_n + 1)
]
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": own + foreign, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": own_detail}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-own-foreign-matrix.sh"

for OWN_N in 1 2 3; do
  for FOREIGN_N in 1 2 3 4 5; do
    TOTAL=$(( OWN_N + FOREIGN_N ))
    if [[ "$TOTAL" -le 6 ]]; then
      EXP_OWN="$OWN_N"; EXP_FOREIGN="$FOREIGN_N"; EXP_HIDDEN=0
    else
      FSLOTS=2
      [[ "$FOREIGN_N" -lt 2 ]] && FSLOTS="$FOREIGN_N"
      OWN_BUDGET=$(( 6 - FSLOTS ))
      EXP_OWN="$OWN_N"
      [[ "$OWN_N" -gt "$OWN_BUDGET" ]] && EXP_OWN="$OWN_BUDGET"
      EXP_FOREIGN="$FSLOTS"
      EXP_HIDDEN=1
    fi
    export MATRIX_OWN_N="$OWN_N" MATRIX_FOREIGN_N="$FOREIGN_N"
    beat_env "$STUBS/collector-own-foreign-matrix.sh" "2026-08-30T07:00:00Z"
    unset MATRIX_OWN_N MATRIX_FOREIGN_N
    MX_CONTENT="$(cat "$FOUNDER_STATUS")"
    GOT_OWN="$(printf '%s' "$MX_CONTENT" | grep -cE "^\| OWN-MX-${OWN_N}-${FOREIGN_N}-[0-9]+ ")"
    GOT_FOREIGN="$(printf '%s' "$MX_CONTENT" | grep -cE "^\| persona-engine/FOREIGN-MX-${OWN_N}-${FOREIGN_N}-[0-9]+ ")"
    if [[ "$GOT_OWN" -eq "$EXP_OWN" && "$GOT_FOREIGN" -eq "$EXP_FOREIGN" ]]; then
      pass "T10 own=$OWN_N foreign=$FOREIGN_N: rendered $GOT_OWN own + $GOT_FOREIGN foreign rows (expected $EXP_OWN/$EXP_FOREIGN)"
    else
      fail "T10 own=$OWN_N foreign=$FOREIGN_N: rendered $GOT_OWN own + $GOT_FOREIGN foreign, expected $EXP_OWN/$EXP_FOREIGN: $MX_CONTENT"
    fi
    if [[ "$EXP_HIDDEN" -eq 0 ]]; then
      if ! printf '%s' "$MX_CONTENT" | grep -q 'не поместилось'; then
        pass "T10 own=$OWN_N foreign=$FOREIGN_N: no hidden-count sentence — everything fit under the cap"
      else
        fail "T10 own=$OWN_N foreign=$FOREIGN_N: false hidden-count sentence when total ($TOTAL) <= cap (6): $MX_CONTENT"
      fi
    else
      if printf '%s' "$MX_CONTENT" | grep -q 'не поместилось'; then
        pass "T10 own=$OWN_N foreign=$FOREIGN_N: hidden-count sentence present — total ($TOTAL) exceeds the cap"
      else
        fail "T10 own=$OWN_N foreign=$FOREIGN_N: missing hidden-count sentence when total ($TOTAL) > cap (6): $MX_CONTENT"
      fi
    fi
  done
done

# ── T11: MU6 CONTROL — round-robin spreads foreign slots across repos
#     (fix-round-5, reviewer mutation MU6: replace the round-robin
#     `while`/`_repo_buckets` block with a flat first-N encounter-order
#     slice) ────────────────────────────────────────────────────────────
# 3 foreign repos x 4 lanes each + 7 own lanes, FOREIGN_ROW_RESERVE=2. A
# flat first-N slice takes the first 2 rows in table order, which (per the
# collector's own grouping) are both from the FIRST repo -- repo 2 and 3
# get zero, every beat, forever. Round-robin BY REPO must give repo 1 and
# repo 2 one slot each and never both slots to a single repo.
cat >"$STUBS/collector-roundrobin-repos.sh" <<'EOF'
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
import json, os
own = [{"task_id": f"OWN-RR-{i:02d}", "status": "active"} for i in range(1, 8)]
foreign = []
for repo in ("m3-market", "persona-engine", "respiro-ios"):
    for i in range(1, 5):
        foreign.append({"task_id": f"{repo}-RR-{i:02d}", "status": "active",
                         "repo": repo, "age_s": 30})
# PULSE-REPO-SCOPED-03: seed dispatch records — dispatched-foreign case.
for _f in foreign:
    os.makedirs(os.path.join(os.environ["LEADV2_PROJECT_ROOT"], "docs", "leadv2", "tasks", _f["task_id"]), exist_ok=True)
own_detail = [
    {"task_id": f"OWN-RR-{i:02d}", "dispatch_id": f"{i:08x}", "worker": "sonnet",
     "writing_now": True, "stream_bytes": i, "mission_title": f"OWN-RR-{i:02d} -- filler lane {i}"}
    for i in range(1, 8)
]
print(json.dumps({"sections": {
  "lanes": {"ok": True, "data": {"table": own + foreign, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"lanes": own_detail}}
}}))' >"$out"
EOF
chmod +x "$STUBS/collector-roundrobin-repos.sh"

beat_env "$STUBS/collector-roundrobin-repos.sh" "2026-08-30T07:30:00Z"
T11_CONTENT="$(cat "$FOUNDER_STATUS")"
T11_M3="$(printf '%s' "$T11_CONTENT" | grep -cE '^\| m3-market/m3-market-RR-[0-9]+ ')"
T11_PE="$(printf '%s' "$T11_CONTENT" | grep -cE '^\| persona-engine/persona-engine-RR-[0-9]+ ')"
T11_RI="$(printf '%s' "$T11_CONTENT" | grep -cE '^\| respiro-ios/respiro-ios-RR-[0-9]+ ')"
if [[ "$T11_M3" -eq 1 && "$T11_PE" -eq 1 && "$T11_RI" -eq 0 ]]; then
  pass "T11: round-robin gives repo 1 (m3-market) and repo 2 (persona-engine) one foreign slot each, not both to one repo"
else
  fail "T11: foreign slots not spread across repos — m3-market=$T11_M3 persona-engine=$T11_PE respiro-ios=$T11_RI: $T11_CONTENT"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
