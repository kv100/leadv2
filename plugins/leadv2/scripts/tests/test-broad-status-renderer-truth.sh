#!/usr/bin/env bash
# tests/test-broad-status-renderer-truth.sh — BROAD-STATUS-RENDERER-01 +
# STATUS-FORMAT-IN-RENDERER-01.
#
# BROAD-STATUS-RENDERER-01 fixed four false-unknowns the renderer showed
# despite already holding the facts (dispatch id, owns, disk, pid-birth).
# STATUS-FORMAT-IN-RENDERER-01 then found the artifact still wasn't in the
# founder's committed shape (docs/founder-status-format.md): five columns
# instead of three, a hex id in column 1, a raw prepass excerpt in column
# 2, and finished lanes still sitting in the live table. The fix moves
# "Кто делает"/"Уже на диске" into a detail block below the table, derives
# column 1/2 from the lane's MISSION TITLE only (never the prepass excerpt,
# never *.stream.jsonl — lib/leadv2_lane_naming.py), and evicts dead:*
# rows into a "Закрыто сегодня" paragraph.
#
# The renderer (leadv2-broad-status.sh) is a pure join over the collector
# snapshot; the facts arrive from leadv2-lane-detail.sh. So this suite runs
# the REAL lane-detail.sh + REAL renderer against a hermetic fixture and
# only stubs what is out of scope: lane-liveness (verdicts are another
# script's contract, HARD RULE 2), the collector shell (supervise.sh is a
# fixed canned "lanes" table — its liveness is NOT under test here), and the
# composer claude call. Cases:
#
#   T1  detail block carries the dispatch id, no false "unknown" marker
#   T2  col-2 (Что делает) resolves from the mission title (lane-mission.md
#       heading), NEVER from architect-prepass.md — even when a prepass
#       exists, the prepass text must not leak into the founder table
#   T3  detail block enumerates the handoff artifacts (count + a filename)
#   T4  honesty: a lane with NO dispatch dir and NO binding renders the
#       true unknowns — id unknown, name unknown, "—", "пока ничего"
#   T5  norm_birth collapses the Darwin double-space form; birth_matches
#       never declares a live pid dead on it (and still catches a real reuse)
#   T6  prev-beat compat: a .broad-status-prev.json written by the OLD flat
#       disk shape does not break the next beat, and the lane's name still
#       resolves fresh from its mission title
#   T7  tombstone row (no lane_detail row at all): the id it already holds
#       renders in col-1 with an honest "(имя неизвестно)"; the genuinely
#       absent detail facts stay honest too
#   T8  header is exactly the 3-column contract shape
#   T9  col-1 of a mission-titled lane is a human name, never a hex id
#   T10 col-2 is one plain sentence: no markdown, no TASK_ID:/ROLE:/Verdict
#   T11 a dead:* lane is absent from the live table and present in
#       «Закрыто сегодня» with its cause
#   T12 the un-nameable lane renders "<id> (имя неизвестно)" / "—" — never
#       an invented name
#   T13 name stability: the mission heading is rewritten mid-lane; col-1
#       stays the name frozen on first resolution
#   T14 "Кто делает"/"Уже на диске" facts still appear, in the detail block
#   T15 the degraded path renders the 3-column header too
#
# Hermetic: throwaway LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT, stubbed lane
# liveness / collector / claude, no network, no crontab, no real supervise.
# Run: bash scripts/tests/test-broad-status-renderer-truth.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

LANE_DETAIL_SH="$SCRIPT_DIR/leadv2-lane-detail.sh"
BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"
STATUS_SURFACE_SH="$SCRIPT_DIR/leadv2-status-surface.sh"
PID_BIRTH_PY="$SCRIPT_DIR/lib/leadv2_pid_birth.py"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir broad-status-renderer-truth)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── fixture: one dispatch lane with a full handoff dir, one naked lane,
#    one tombstoned dispatch lane, one dead:* lane ─────────────────────────
mkdir -p "$REPO/docs/leadv2/tasks/dispatch-aabbccdd" \
         "$REPO/docs/handoff/dispatch-aabbccdd"
cat >"$REPO/docs/leadv2/active.yaml" <<'EOF'
sessions:
  - task_id: dispatch-aabbccdd
    provider: codex
    lead_model: gpt-5.6
EOF
# No "dispatch_task_bound" line on purpose: the binding map must MISS so the
# only correct source of the dispatch id is the task id itself (D1).
cat >"$REPO/docs/leadv2/tasks/dispatch-aabbccdd/journal.md" <<'EOF'
2026-08-17T10:00:00Z dispatch_classified task=dispatch-aabbccdd kind=codex_fitting_dev
EOF
printf '# Fixture prepass heading\nVerdict up front: this must never reach the founder table.\n' \
  >"$REPO/docs/handoff/dispatch-aabbccdd/architect-prepass.md"
# lane-mission.md with YAML front-matter + MISSION: boilerplate — rung 1 must
# skip both and land on the heading. This heading is the ONLY source col-1/
# col-2 may draw from — the prepass above must never leak into them.
cat >"$REPO/docs/handoff/dispatch-aabbccdd/lane-mission.md" <<'EOF'
---
MISSION: boilerplate that must never reach the table
handle: dispatch-aabbccdd
---
# Browser door retry queue fix: retries now survive a daemon restart.
Body line after the heading, this must never reach the table either.
EOF
printf 'review gate fixture\n' >"$REPO/docs/handoff/dispatch-aabbccdd/review-gate.md"
python3 - "$REPO/docs/handoff/dispatch-aabbccdd/x.stream.jsonl" <<'EOF'
import sys
with open(sys.argv[1], "w") as fh:
    fh.write('{"v":1}\n' * 900)  # ~7.2 KB — largest file, tops the size list
EOF

# ── stubs ──────────────────────────────────────────────────────────────────
cat >"$STUBS/liveness.sh" <<'EOF'
#!/usr/bin/env bash
# Fixed verdicts — liveness is leadv2-lane-liveness.sh's contract (HARD
# RULE 2), never re-derived here.
cat <<'JSON'
{"lanes": [
  {"lane": "dispatch-aabbccdd", "verdict": "alive", "age_s": 30,
   "log_path": "docs/handoff/dispatch-aabbccdd/x.stream.jsonl",
   "pid": null, "pid_alive": null, "reason": null},
  {"lane": "plain-task-01", "verdict": "alive", "age_s": 30,
   "log_path": null, "pid": null, "pid_alive": null, "reason": null}
]}
JSON
EOF
cat >"$STUBS/collector.sh" <<EOF
#!/usr/bin/env bash
# Snapshot with a CANNED supervise "lanes" table (supervise liveness is out
# of scope) but the REAL lane-detail.sh output — that join is what's broken.
out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --out) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "\$out" ]] && exit 1
detail="\$(LEADV2_LANE_LIVENESS_BIN="$STUBS/liveness.sh" \
  bash "$LANE_DETAIL_SH" --project-root "$REPO" --json)" || detail='{"ok":false,"error":"lane-detail failed"}'
LEADV2_DETAIL="\$detail" python3 -c '
import json, os
detail = json.loads(os.environ["LEADV2_DETAIL"])
snap = {"sections": {
  "lanes": {"ok": True, "data": {"table": [
    {"task_id": "dispatch-aabbccdd", "phase": "build", "minutes_in_phase": 5,
     "status": "live", "status_reason": "writing", "waiting": False,
     "where": "terminal", "protocol_version": 2},
    {"task_id": "plain-task-01", "phase": "build", "minutes_in_phase": 5,
     "status": "live", "status_reason": "writing", "waiting": False,
     "where": "terminal", "protocol_version": 2},
    {"task_id": "dispatch-ffeeddcc", "phase": "intake", "minutes_in_phase": 339,
     "status": "dead", "status_reason": "pid birth mismatch (reuse)",
     "waiting": False, "where": "terminal record", "protocol_version": 2},
    {"task_id": "dispatch-eeddccbb", "phase": "build", "minutes_in_phase": 12,
     "status": "dead:sentinel_finalized", "status_reason": "финализирован сторожем",
     "waiting": False, "where": "terminal record", "protocol_version": 2}],
    "questions": [], "degraded": []}},
  "lane_detail": {"ok": bool(detail.get("ok")), "data": detail}}}
print(json.dumps(snap))' >"\$out"
EOF
cat >"$STUBS/collector-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "$STUBS/liveness.sh" "$STUBS/collector.sh" "$STUBS/collector-fail.sh" "$STUBS/claude.sh"

beat_env() {  # <beat-at> [cmd...]
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="$1" \
    LEADV2_BROAD_STATUS_DISPATCHED="1" \
    "${@:2}"
}

run_beat() { beat_env "$1" bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true; }
lane_row() { grep -m1 "^| $1 " "$FOUNDER_STATUS" 2>/dev/null || true; }

# ── beat 1: the happy fixture ───────────────────────────────────────────────
run_beat "2026-08-17T15:00:00Z"
if [[ ! -f "$FOUNDER_STATUS" ]]; then
  fail "fixture: founder-status.md not written — aborting table cases"
  printf -- '%s\n' "${ERRORS[@]:-}" >&2; exit 1
fi
CONTENT="$(cat "$FOUNDER_STATUS")"
# fix-round-4 (R3-1): col-1 is now the lane IDENTITY (task_id/sig8, never a
# mission-title fragment -- BROAD-STATUS-ROWS-02's IDENTITY decision), so the
# fixture's live row is found by its identity, not by the old human-name text.
ROW="$(printf '%s' "$CONTENT" | grep -m1 '^| dispatch-aabbccdd ')"
# PULSE-READABLE-01 rule 6: the per-lane detail block, the full queue and
# the full «Закрыто сегодня» paragraph are no longer in the compact beat
# (founder-status.md) — they are written, in full, to
# founder-status-full.md. Tests that assert their CONTENT now read that
# file instead.
FULL_STATUS="$REPO/docs/leadv2/founder-status-full.md"
FULL_CONTENT="$(cat "$FULL_STATUS" 2>/dev/null || true)"

# T1 — detail block (full doc) carries the dispatch id, no false "unknown" marker.
if printf '%s' "$FULL_CONTENT" | grep -q 'dispatch-aabbccdd —' \
   && ! printf '%s' "$FULL_CONTENT" | grep -q 'dispatch-aabbccdd (dispatch id unknown)'; then
  pass "T1: detail block carries dispatch-aabbccdd, no false unknown marker"
else
  fail "T1: detail block wrong: $(printf '%s' "$FULL_CONTENT" | grep 'Детали линий' || echo '<none>')"
fi

# T2 — col-2 resolves from the mission title, NEVER the prepass excerpt.
if printf '%s' "$ROW" | grep -q 'retries now survive a daemon restart' \
   && ! printf '%s' "$CONTENT" | grep -q 'Fixture prepass heading' \
   && ! printf '%s' "$CONTENT" | grep -q 'Verdict up front' \
   && ! printf '%s' "$CONTENT" | grep -q 'Body line after the heading'; then
  pass "T2: col-2 from mission title, prepass excerpt never leaked"
else
  fail "T2: col-2 wrong or prepass leaked: ${ROW:-<no row>}"
fi

# T3 — detail block (full doc) enumerates the handoff artifacts (x.stream.jsonl
# is the fixture's largest file by construction).
if printf '%s' "$FULL_CONTENT" | grep -q 'x.stream.jsonl' \
   && printf '%s' "$FULL_CONTENT" | grep -Eq '[0-9]+ файл'; then
  pass "T3: detail block shows handoff file count + a filename"
else
  fail "T3: detail block does not show handoff artifacts"
fi

# ── T7 (PULSE-READABLE-01 supersedes the old assertion) — a bucket-form
#    "dead" tombstone row (status="dead", no colon — exactly the
#    2026-08-21 founder-rejected shape) must be ABSENT from the live table,
#    not rendered as junk. It is corroborated evidence, not evicted from
#    the FULL doc, so it must still land in founder-status-full.md's
#    "Закрыто сегодня" paragraph with its real cause. ────────────────────
ROW7="$(lane_row 'dispatch-ffeeddcc')"
FULL_STATUS="$REPO/docs/leadv2/founder-status-full.md"
if [[ -z "$ROW7" ]] && [[ -f "$FULL_STATUS" ]] \
   && grep -q 'pid birth mismatch (reuse)' "$FULL_STATUS"; then
  pass "T7: bucket-form dead tombstone row absent from live table, present in full doc"
else
  fail "T7: tombstone row wrong: live-table-row=${ROW7:-<none>} full-doc=$(test -f "$FULL_STATUS" && grep -c 'pid birth mismatch' "$FULL_STATUS" || echo '<no file>')"
fi

# ── T4 / T12 — honesty: the naked lane keeps its TRUE unknowns. Rule 3
#    (PULSE-READABLE-01) drops the "(имя неизвестно)" suffix — the bare
#    dispatch-id fallback is rendered ONCE, never doubled. ─────────────────
ROW4="$(lane_row 'plain-task-01 (dispatch id unknown)')"
if printf '%s' "$ROW4" | grep -q '^| plain-task-01 (dispatch id unknown) |' \
   && printf '%s' "$ROW4" | grep -q '| — |' \
   && ! printf '%s' "$ROW4" | grep -q 'имя неизвестно'; then
  pass "T4: no dispatch dir/binding -> unknowns stay honest, no (имя неизвестно) suffix"
else
  fail "T4: honesty invariant broken: ${ROW4:-<no row>}"
fi
if [[ -f "$FULL_STATUS" ]] && grep -q 'plain-task-01 (dispatch id unknown) — .* — пока ничего' "$FULL_STATUS"; then
  pass "T12: un-nameable lane never invents a name, disk fact stays honest (full doc)"
else
  fail "T12: un-nameable lane detail wrong"
fi

# ── T8 — header is exactly the 3-column contract shape ─────────────────────
if printf '%s' "$CONTENT" | grep -qF '| Линия | Что делает | Состояние |' \
   && printf '%s' "$CONTENT" | grep -qF '|---|---|---|'; then
  pass "T8: header is the exact 3-column contract shape"
else
  fail "T8: header wrong"
fi
# a live row has exactly 3 cells (4 pipes).
if [[ "$(printf '%s' "$ROW" | grep -o '|' | wc -l | tr -d ' ')" == "4" ]]; then
  pass "T8: live row has exactly 3 cells"
else
  fail "T8: live row cell count wrong: ${ROW:-<no row>}"
fi

# ── T9 — col-1 is the lane IDENTITY, never a human name (fix-round-4,
#    R3-1: this assertion predates BROAD-STATUS-ROWS-02's IDENTITY decision.
#    It used to require the OPPOSITE -- a human name, no hex id -- which is
#    exactly the bug that decision fixed: two lanes sharing a long common
#    mission-title prefix collapsed to the same truncated name and rendered
#    as one indistinguishable row. task_id is unique per lane by
#    construction, so col-1 must be the id, deliberately re-specified here
#    rather than weakened). ──────────────────────────────────────────────────
COL1="$(printf '%s' "$ROW" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
if [[ "$COL1" == "dispatch-aabbccdd" ]]; then
  pass "T9: col-1 is the lane identity (task_id), never a human name"
else
  fail "T9: col-1 wrong: ${ROW:-<no row>}"
fi

# ── T10 — col-2 is one plain sentence, no markdown / boilerplate tokens ────
COL2="$(printf '%s' "$ROW" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//')"
if [[ -n "$COL2" ]] \
   && ! printf '%s' "$COL2" | grep -qE '\*\*|`|#|TASK_ID:|ROLE:|Verdict' \
   && [[ "$(printf '%s' "$COL2" | wc -l | tr -d ' ')" == "0" || "$(printf '%s' "$COL2" | wc -l | tr -d ' ')" == "1" ]] \
   && [[ "${#COL2}" -le 140 ]]; then
  pass "T10: col-2 is a plain, markdown-free sentence <=140 chars"
else
  fail "T10: col-2 fails the plain-sentence contract: [$COL2]"
fi

# ── T11 — a dead:* lane is absent from the live table, present in
#    «Закрыто сегодня» with its cause. ──────────────────────────────────────
if ! printf '%s' "$CONTENT" | grep -q '^| dispatch-eeddccbb'; then
  pass "T11a: dead:sentinel_finalized lane absent from the live table"
else
  fail "T11a: dead lane still rendered in the live table"
fi
CLOSED_LINE="$(printf '%s' "$FULL_CONTENT" | grep -m1 '^Закрыто сегодня:')"
if printf '%s' "$CLOSED_LINE" | grep -q 'dispatch-eeddccbb' \
   && printf '%s' "$CLOSED_LINE" | grep -q 'финализирован сторожем'; then
  pass "T11b: dead lane present in «Закрыто сегодня» with its cause"
else
  fail "T11b: closed paragraph wrong: ${CLOSED_LINE:-<none>}"
fi

# ── T14 — "Кто делает"/"Уже на диске" facts still appear, in the detail
#    block below the table (not lost, only relocated). ─────────────────────
if printf '%s' "$FULL_CONTENT" | grep -q 'Детали линий:' \
   && printf '%s' "$FULL_CONTENT" | grep -q 'codex/gpt-5.6' \
   && printf '%s' "$FULL_CONTENT" | grep -Eq '[0-9]+ файл.*KB'; then
  pass "T14: worker + disk facts survive in the detail block"
else
  fail "T14: detail block missing worker/disk facts"
fi

# ── T13 — identity stability (fix-round-4, R3-1 restatement): col-1 is
#    derived from task_id, never the mission title, so a mid-lane mission
#    rewrite CANNOT destabilize it -- this is the whole point of the
#    IDENTITY decision (two lanes sharing a mission-title prefix used to
#    collapse into one row; task_id never collides). Col-2 (Что делает) is
#    NOT frozen -- it tracks current work -- so it legitimately updates to
#    the new heading. ────────────────────────────────────────────────────
cat >"$REPO/docs/handoff/dispatch-aabbccdd/lane-mission.md" <<'EOF'
# Completely different rewritten heading
This body must never appear either.
EOF
run_beat "2026-08-17T15:15:00Z"
CONTENT2="$(cat "$FOUNDER_STATUS")"
ROW2="$(printf '%s' "$CONTENT2" | grep -m1 '^| dispatch-aabbccdd ')"
if [[ -n "$ROW2" ]] && printf '%s' "$ROW2" | grep -q 'Completely different rewritten heading'; then
  pass "T13: identity stays stable across a mid-lane mission rewrite, description updates"
else
  fail "T13: identity or description wrong after rewrite: ${ROW2:-<no row>}"
fi

# ── beat 3: prepass removed -> mission title (already rewritten by T13
#    above) unaffected (rung 1 is always lane-mission.md; the prepass was
#    never the source, T2c). ────────────────────────────────────────────
rm "$REPO/docs/handoff/dispatch-aabbccdd/architect-prepass.md"
run_beat "2026-08-17T15:30:00Z"
CONTENT3="$(cat "$FOUNDER_STATUS")"
ROW3="$(printf '%s' "$CONTENT3" | grep -m1 '^| dispatch-aabbccdd ')"
if printf '%s' "$ROW3" | grep -q 'Completely different rewritten heading'; then
  pass "T2c: prepass removed -> description unaffected (mission was always the source)"
else
  fail "T2c: prepass removal broke the description: ${ROW3:-<no row>}"
fi

# ── T5 — one pid-birth rule, one inode ─────────────────────────────────────
T5_OUT="$(python3 - "$PID_BIRTH_PY" <<'EOF'
import os, re, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
try:
    from leadv2_pid_birth import norm_birth, pid_birth_of, birth_matches
except Exception as e:
    print(f"import_failed: {e.__class__.__name__}: {e}"); sys.exit(0)

a = norm_birth("Sun Aug  3 10:00:00 2026 ")   # Darwin double-space + padding
b = norm_birth("Sun Aug 3 10:00:00 2026")
print("norm_ok" if a == b == "Sun Aug 3 10:00:00 2026" else "norm_bad")

live = pid_birth_of(os.getpid())
doubled = re.sub(r" ", "  ", live or "") if live else ""   # legacy stored form
print("match_ok" if birth_matches(doubled, live) else "match_bad")
print("reuse_ok" if not birth_matches("Mon Jan  1 00:00:00 1990", live) else "reuse_bad")
print("unknown_ok" if birth_matches(None, live) and birth_matches(live, None) else "unknown_bad")
EOF
)"
for tok in norm_ok match_ok reuse_ok unknown_ok; do
  if printf '%s' "$T5_OUT" | grep -q "$tok"; then
    pass "T5: $tok (pid-birth module)"
  else
    fail "T5: expected $tok from module, got: $(printf '%s' "$T5_OUT" | tr '\n' ' ')"
  fi
done
# The SwiftBar 10-s path must route its comparison through the shared rule —
# the raw edge-only `str(birth).strip()` comparison is the D4 defect itself
# (a comment mentioning the OLD form is fine; executable code is not).
if grep -q 'birth_matches(birth, lstart(pid))' "$STATUS_SURFACE_SH" \
   && ! grep -v '^[[:space:]]*#' "$STATUS_SURFACE_SH" | grep -q 'str(birth).strip()'; then
  pass "T5: status-surface compares births via the shared module"
else
  fail "T5: status-surface still has its own edge-only birth comparison"
fi

# ── T6 — old flat prev-shape survives the next beat (R1); the lane's name
#    still resolves fresh from its mission title when no frozen name is
#    carried by the old shape. ──────────────────────────────────────────────
mkdir -p "$REPO/docs/leadv2"
cat >"$REPO/docs/leadv2/.broad-status-prev.json" <<'EOF'
{"beat_at": "2026-08-17T14:00:00Z", "lanes": {"dispatch-aabbccdd":
  {"stream_bytes": 7290, "disk_key": ["4 files changed, 100 insertions(+)", 4, 0]}}}
EOF
run_beat "2026-08-17T16:00:00Z"
CONTENT6="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$CONTENT6" | grep -qF '| Линия | Что делает | Состояние |' \
   && ! printf '%s' "$CONTENT6" | grep -q 'СТАТУС НЕ СОБРАН'; then
  pass "T6: old flat prev-shape does not break the beat"
else
  fail "T6: beat broke on old prev-shape: $(printf '%s' "$CONTENT6" | head -3 | tr '\n' ' ')"
fi

# ── T15 — the degraded path renders the 3-column header too ────────────────
DEGRADED_ENV_OUT="$(env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
  LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector-fail.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-17T17:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="1" \
  bash "$BROAD_STATUS_SH" 2>&1)"
DEGRADED_CONTENT="$(cat "$FOUNDER_STATUS")"
if printf '%s' "$DEGRADED_CONTENT" | grep -qF '| Линия | Что делает | Состояние |' \
   && printf '%s' "$DEGRADED_CONTENT" | grep -q 'degraded=1'; then
  pass "T15: degraded path renders the 3-column header"
else
  fail "T15: degraded path header wrong: $(printf '%s' "$DEGRADED_CONTENT" | head -3 | tr '\n' ' ')"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
