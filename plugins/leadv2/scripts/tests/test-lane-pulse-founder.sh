#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-broad-status.sh leadv2-lane-pulse-watch.sh
# tests/test-lane-pulse-founder.sh — MON-PULSE-01 fix-round 2 (H4): the lane
# pulse has a DEMONSTRATED route to the founder.
#
# Round-2 review H4: the watcher appends to tasks/<id>/pulse.md, but the
# dispatcher discards its stdout and NOTHING read the file — a terminal could
# be "pulsed" and still invisible. The fix wires the beat composer
# (leadv2-broad-status.sh, driven by leadv2-pulse-beat.sh) to surface each
# board lane's LAST pulse line verbatim in founder-status.md.
#
#   F1  full route, real binaries: fake lane journal -> REAL watcher pulses
#       -> REAL beat tick (leadv2-pulse-beat.sh --now) -> REAL composer ->
#       founder-status.md contains the lane's dispatch_terminal pulse line.
#   F2  no pulse.md, no section: a board with lanes that never pulsed does
#       not render an empty "Пульс линий" header (the section is evidence,
#       not furniture).
#
# Hermetic: scratch repo (non-git -> leadv2-state-path degrades to
# <repo>/docs/leadv2), fake collector, fake pump, fake heartbeat, alarm
# state pinned into the scratch tree. No network, no real control plane.
# Run: bash scripts/tests/test-lane-pulse-founder.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
WATCH="$SCRIPT_DIR/leadv2-lane-pulse-watch.sh"
BEAT="$SCRIPT_DIR/leadv2-pulse-beat.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-lane-pulse-founder-XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

REPO="$TMP/repo"
LANE_DIR="$REPO/docs/leadv2/tasks/dispatch-e4f5a6b7"
mkdir -p "$LANE_DIR"
J="$LANE_DIR/journal.md"
PULSE="$LANE_DIR/pulse.md"
FOUNDER="$REPO/docs/leadv2/founder-status.md"
SIG="e4f5a6b7"

# ── step 1: fake lane journal — spawn then terminal (the incident shape) ────
printf '%s\n' \
  "- 2026-08-28T10:00:00Z [decision] worker_spawned by=router model=glm task=${SIG} handle=h1" \
  "- 2026-08-28T10:00:25Z [decision] dispatch_terminal task=${SIG} terminal=landed cause=verified" \
  > "$J"

# ── step 2: the REAL watcher pulses it (no seams: real pulse writer too) ─────
bash "$WATCH" --sig "$SIG" --root "$REPO" --state-dir "$TMP/state" \
  --interval 1 --timeout 10 >/dev/null 2>&1
if [[ -f "$PULSE" ]] && grep -q "dispatch_terminal" "$PULSE"; then
  : # step proven by F1's end state; keep the intermediate check loud anyway
else
  bad "precondition: watcher wrote no pulse ($(cat "$PULSE" 2>/dev/null | tr '\n' ';'))"
fi

# ── fakes: collector (snapshot with our lane on the board), pump, heartbeat ──
cat > "$TMP/fake-collector.sh" <<EOF
#!/usr/bin/env bash
# fake leadv2-status-collector.sh — writes the staged snapshot JSON to --out
out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --out) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "\$out" <<'J'
{
  "sections": {
    "lanes": {"ok": true, "data": {"table": [
      {"task_id": "dispatch-${SIG}", "status": "running"}
    ]}},
    "lane_detail": {"ok": true, "data": {"lanes": []}},
    "repo_facts": {"ok": true, "data": {}}
  }
}
J
EOF
chmod +x "$TMP/fake-collector.sh"

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/fake-pump.sh"; chmod +x "$TMP/fake-pump.sh"
printf '#!/usr/bin/env bash\necho "[]"\n' > "$TMP/fake-hb.sh"; chmod +x "$TMP/fake-hb.sh"

# ── step 3: the beat tick — REAL pulse-beat --now -> REAL broad-status ──────
LEADV2_PROJECT_ROOT="$REPO" \
LEADV2_STATE_ROOT="$REPO/docs/leadv2" \
LEADV2_ALARM_STATE_DIR="$REPO/docs/leadv2/.alarm-state" \
LEADV2_STATUS_COLLECTOR_BIN="$TMP/fake-collector.sh" \
LEADV2_BACKLOG_PUMP_BIN="$TMP/fake-pump.sh" \
LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
LEADV2_BROAD_STATUS_BEAT_AT="2026-08-28T10:01:00Z" \
  bash "$BEAT" --now >/dev/null 2>&1
rc=$?

# ── F1: founder-status.md contains the lane's pulse line ─────────────────────
if [[ $rc -eq 0 && -f "$FOUNDER" ]] \
   && grep -q "Пульс линий" "$FOUNDER" \
   && grep -q "dispatch-${SIG}: \[" "$FOUNDER" \
   && grep -q "dispatch_terminal | " "$FOUNDER"; then
  ok "F1 founder route: journal -> watcher pulse -> beat tick -> founder-status.md lane line"
else
  bad "F1 founder route: rc=$rc founder=$(grep -A2 'Пульс линий' "$FOUNDER" 2>/dev/null | tr '\n' ';')"
fi

# ── F2: no pulse.md anywhere -> no empty section header ──────────────────────
REPO2="$TMP/repo2"
mkdir -p "$REPO2/docs/leadv2/tasks/dispatch-11223344"
: > "$REPO2/docs/leadv2/tasks/dispatch-11223344/journal.md"
LEADV2_PROJECT_ROOT="$REPO2" \
LEADV2_STATE_ROOT="$REPO2/docs/leadv2" \
LEADV2_ALARM_STATE_DIR="$REPO2/docs/leadv2/.alarm-state" \
LEADV2_STATUS_COLLECTOR_BIN="$TMP/fake-collector.sh" \
LEADV2_BACKLOG_PUMP_BIN="$TMP/fake-pump.sh" \
LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
LEADV2_BROAD_STATUS_BEAT_AT="2026-08-28T10:02:00Z" \
  bash "$BEAT" --now >/dev/null 2>&1
if [[ $? -eq 0 && -f "$REPO2/docs/leadv2/founder-status.md" ]] \
   && ! grep -q "Пульс линий" "$REPO2/docs/leadv2/founder-status.md"; then
  ok "F2 no-pulse board: no empty pulse section rendered"
else
  bad "F2 no-pulse board: section rendered without evidence ($(grep -n 'Пульс линий' "$REPO2/docs/leadv2/founder-status.md" 2>/dev/null))"
fi

printf 'test-lane-pulse-founder: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
