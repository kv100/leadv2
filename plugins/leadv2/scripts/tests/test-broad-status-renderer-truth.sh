#!/usr/bin/env bash
# tests/test-broad-status-renderer-truth.sh — BROAD-STATUS-RENDERER-01.
#
# The founder status table said "unknown" for four facts it already holds:
#   D1 "(dispatch id unknown)" while the row's own task id IS dispatch-<hex>
#   D2 "Что делает" = "—" while docs/handoff/dispatch-<id>/lane-mission.md exists
#   D3 "Уже на диске" = "пока ничего" while docs/handoff/dispatch-<id>/ holds artifacts
#   D4 "pid birth mismatch (reuse)" from an un-normalised stored lstart
#      (double interior space on single-digit days) — third copy of the rule.
#
# The renderer (leadv2-broad-status.sh) is a pure join over the collector
# snapshot; the nulls arrive from leadv2-lane-detail.sh. So this suite runs
# the REAL lane-detail.sh + REAL renderer against a hermetic fixture and
# only stubs what is out of scope: lane-liveness (verdicts are another
# script's contract, HARD RULE 2), the collector shell (supervise.sh is a
# fixed canned "lanes" table — its liveness is NOT under test here), and the
# composer claude call. Cases:
#
#   T1 col-1 of a dispatch-* lane reads "dispatch-<hex>", no unknown marker
#   T2 col-2 resolves from architect-prepass.md; with the prepass removed,
#      from lane-mission.md WITH the mission-source annotation (no forgery)
#   T3 col-5 shows the handoff artifacts (count + a filename)
#   T4 honesty: a lane with NO dispatch dir and NO binding still renders the
#      true unknowns (dispatch id unknown / — / пока ничего)
#   T5 norm_birth collapses the Darwin double-space form; birth_matches
#      never declares a live pid dead on it (and still catches a real reuse);
#      status-surface routes its pid_alive comparison through the shared rule
#   T6 prev-beat compat: a .broad-status-prev.json written by the OLD flat
#      disk shape does not break the next beat (R1)
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

# ── fixture: one dispatch lane with a full handoff dir, one naked lane ─────
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
printf '# Fixture prepass heading\nПервая строка summary.\n' \
  >"$REPO/docs/handoff/dispatch-aabbccdd/architect-prepass.md"
# lane-mission.md with YAML front-matter + MISSION: boilerplate — rung 2 must
# skip both and land on the heading.
cat >"$REPO/docs/handoff/dispatch-aabbccdd/lane-mission.md" <<'EOF'
---
MISSION: boilerplate that must never reach the table
handle: dispatch-aabbccdd
---
# Fixture mission heading
Body line after the heading.
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
     "waiting": False, "where": "terminal record", "protocol_version": 2}],
    "questions": [], "degraded": []}},
  "lane_detail": {"ok": bool(detail.get("ok")), "data": detail}}}
print(json.dumps(snap))' >"\$out"
EOF
cat >"$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"тестовый хвост: фикстура, очередь пуста."}'
EOF
chmod +x "$STUBS/liveness.sh" "$STUBS/collector.sh" "$STUBS/claude.sh"

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

# ── beat 1: the happy fixture (T1 T2a T3) ───────────────────────────────────
run_beat "2026-08-17T15:00:00Z"
if [[ ! -f "$FOUNDER_STATUS" ]]; then
  fail "fixture: founder-status.md not written — aborting table cases"
  printf -- '%s\n' "${ERRORS[@]:-}" >&2; exit 1
fi
ROW="$(lane_row dispatch-aabbccdd)"

# T1 — the id the row already holds is rendered, not declared unknown.
if printf '%s' "$ROW" | grep -q '^| dispatch-aabbccdd |' \
   && ! printf '%s' "$ROW" | grep -q 'dispatch id unknown'; then
  pass "T1: col-1 is dispatch-aabbccdd, no '(dispatch id unknown)'"
else
  fail "T1: col-1 wrong: ${ROW:-<no row>}"
fi

# T2a — "Что делает" resolves from architect-prepass.md.
if printf '%s' "$ROW" | grep -q 'Fixture prepass heading'; then
  pass "T2a: col-2 carries the prepass heading"
else
  fail "T2a: col-2 is not the prepass heading: ${ROW:-<no row>}"
fi

# T3 — "Уже на диске" enumerates the handoff artifacts (top by size:
# x.stream.jsonl is the fixture's largest file by construction).
if printf '%s' "$ROW" | grep -q 'x.stream.jsonl' \
   && printf '%s' "$ROW" | grep -Eq '[0-9]+ файл' \
   && ! printf '%s' "$ROW" | grep -q 'пока ничего'; then
  pass "T3: col-5 shows handoff file count + a filename"
else
  fail "T3: col-5 does not show handoff artifacts: ${ROW:-<no row>}"
fi

# ── beat 2: prepass removed -> mission rung, visibly labelled (T2b) ────────
rm "$REPO/docs/handoff/dispatch-aabbccdd/architect-prepass.md"
run_beat "2026-08-17T15:30:00Z"
ROW="$(lane_row dispatch-aabbccdd)"
if printf '%s' "$ROW" | grep -q 'Fixture mission heading' \
   && printf '%s' "$ROW" | grep -q 'из миссии'; then
  pass "T2b: prepass gone -> mission heading WITH mission-source annotation"
else
  fail "T2b: mission fallback wrong: ${ROW:-<no row>}"
fi
if printf '%s' "$ROW" | grep -q 'boilerplate that must never reach'; then
  fail "T2c: MISSION: boilerplate/front-matter leaked into the table"
else
  pass "T2c: front-matter + MISSION: boilerplate skipped"
fi

# ── T7 — tombstone row (no lane_detail row at all): the id it already
#    holds renders; the genuinely-absent detail columns stay honest. This is
#    the shape of the 5 real rows that kept "(dispatch id unknown)" after the
#    lane-detail fix — supervise renders them from persisted tombstones.
ROW7="$(lane_row dispatch-ffeeddcc)"
if printf '%s' "$ROW7" | grep -q '^| dispatch-ffeeddcc |' \
   && ! printf '%s' "$ROW7" | grep -q 'dispatch id unknown' \
   && printf '%s' "$ROW7" | grep -q '| — |' \
   && printf '%s' "$ROW7" | grep -q 'пока ничего'; then
  pass "T7: tombstone dispatch row shows its id; unknown detail stays unknown"
else
  fail "T7: tombstone row wrong: ${ROW7:-<no row>}"
fi

# ── T4 — honesty: the naked lane keeps its TRUE unknowns ───────────────────
ROW4="$(lane_row plain-task-01)"
if printf '%s' "$ROW4" | grep -q 'plain-task-01 (dispatch id unknown)' \
   && printf '%s' "$ROW4" | grep -q '| — |' \
   && printf '%s' "$ROW4" | grep -q 'пока ничего'; then
  pass "T4: no dispatch dir/binding -> unknowns stay honest"
else
  fail "T4: honesty invariant broken: ${ROW4:-<no row>}"
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

# ── T6 — old flat prev-shape survives the next beat (R1) ───────────────────
mkdir -p "$REPO/docs/leadv2"
cat >"$REPO/docs/leadv2/.broad-status-prev.json" <<'EOF'
{"beat_at": "2026-08-17T14:00:00Z", "lanes": {"dispatch-aabbccdd":
  {"stream_bytes": 7290, "disk_key": ["4 files changed, 100 insertions(+)", 4, 0]}}}
EOF
run_beat "2026-08-17T16:00:00Z"
if grep -q '^| dispatch-aabbccdd |' "$FOUNDER_STATUS" \
   && ! grep -q 'СТАТУС НЕ СОБРАН' "$FOUNDER_STATUS"; then
  pass "T6: old flat prev-shape does not break the beat"
else
  fail "T6: beat broke on old prev-shape: $(head -3 "$FOUNDER_STATUS" | tr '\n' ' ')"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
