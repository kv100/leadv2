#!/usr/bin/env bash
# Fixture coverage for SWIFTBAR-SINGLE-LEAD-01. Every input is sandboxed;
# nothing reads or writes the operator's live leadv2 state.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
SURFACE="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.sh"
WRAPPER="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.5s.sh"
STATUS_RENDER="${ROOT}/plugins/leadv2/scripts/leadv2-status-render.sh"

PASS=0
FAIL=0
ok()  { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(mktemp -d -t leadv2-single-lead)"
trap 'rm -rf "$FIX"' EXIT
STATE="$FIX/state"
LEDGERS="$FIX/ledgers"
RUNS="$FIX/runs"
HANDOFF="$FIX/handoff"
QUESTIONS="$FIX/questions"
PROJECT="$FIX/project"
LIMITS="$FIX/limits"
mkdir -p "$STATE" "$LEDGERS" "$RUNS" "$HANDOFF" "$QUESTIONS" \
  "$PROJECT/docs/leadv2" "$LIMITS"

REPO="fixture-repo"
NOW="$(date +%s)"
RESERVATIONS="$LEDGERS/$REPO.jsonl"
TERMINALS="$STATE/dispatch-ledger.jsonl"
SNAPSHOT="$PROJECT/docs/leadv2/status-snapshot.json"
TASKS="$FIX/tasks.yaml"
: > "$RESERVATIONS"
: > "$TERMINALS"
printf 'meta: {}\nsessions: []\n' > "$STATE/active.yaml"
printf 'meta: {}\ntasks: []\n' > "$TASKS"

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$SNAPSHOT" <<EOF
{
  "collected_at": "$STAMP",
  "project_root": "$PROJECT",
  "sections": {
    "single_lead": {
      "ok": true,
      "data": {
        "supervise_active": false,
        "ledger_tail": [],
        "ledger_path": "$RESERVATIONS",
        "ledger_ok": true
      }
    },
    "repo_facts": {
      "ok": true,
      "data": {"fixture_alarm": false, "fixture_count": 0}
    }
  }
}
EOF

# PS_STUB: a non-empty ps snapshot with NO leadv2 workers, so the process
# census is deterministic and does not leak the operator's real running
# workers. Individual cases override by setting PS_STUB before calling widget.
PS_STUB="1 sleep 1"

widget() {
  PATH="${TEST_PATH:-$PATH}" \
  LEADV2_STATUS_SYNC=1 \
  LEADV2_STATUS_RENDERER="$SURFACE" \
  LEADV2_STATUS_STATE_DIR="$STATE" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGERS" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS" \
  LEADV2_STATUS_REPO="$REPO" \
  LEADV2_STATUS_STATE_ROOT="${SL_STATE_ROOT:-}" \
  LEADV2_STATUS_AGGREGATE="${SL_AGGREGATE:-1}" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="$TASKS" \
  LEADV2_STATUS_HANDOFF_DIR="$HANDOFF" \
  LEADV2_STATUS_QUESTIONS_DIR="$QUESTIONS" \
  LEADV2_STATUS_PROJECT_ROOT="$PROJECT" \
  LEADV2_STATUS_SNAPSHOT="$SNAPSHOT" \
  LEADV2_STATUS_SD_HOOK="$FIX/no-sd-hook" \
  LEADV2_STATUS_URGENT_LOG="$FIX/no-urgent-log" \
  LEADV2_LIMITS_CACHE_DIR="$LIMITS" \
  LEADV2_LIMITS_REFRESH_SH="$FIX/no-limits-refresh" \
  LEADV2_STATUS_PS_SNAPSHOT="$PS_STUB" \
  /bin/bash "$WRAPPER" 2>&1
}

assert_title() {
  local label="$1" expected="$2" out title
  out="$(widget)"
  title="$(printf '%s\n' "$out" | sed -n '1p')"
  if [ "$title" = "$expected" ]; then
    ok "$label -> $expected"
  else
    bad "$label expected '$expected', got '$title' (output=$(printf '%s' "$out" | tr '\n' '|'))"
  fi
}

echo "== single-lead fixture titles =="

# H1: prove the collector's raw single_lead section is consumed by the
# snapshot renderer instead of being dead snapshot data.
_rendered="$(/bin/bash "$STATUS_RENDER" --project-root "$PROJECT" --snapshot "$SNAPSHOT" --max-age-sec 3600 2>&1)"
if printf '%s\n' "$_rendered" | grep -q 'DISPATCH LEDGER: no recent rows'; then
  ok "status-render consumes snapshot single_lead section"
else
  bad "status-render omitted snapshot single_lead section ($_rendered)"
fi

assert_title "no-dispatch idle" "⚪ idle"

printf '{"task_sig":"abcdef1234567890","arm":"codex","state":"confirmed","created_epoch":%s}\n' \
  "$((NOW - 120))" > "$RESERVATIONS"
assert_title "active dispatch" "🛠 abcdef12 codex 2m"

# Finding 1: a bogus-state row must NOT count as active. Real writer values
# are ONLY "pending"/"confirmed"; any other state is stale/foreign.
printf '{"task_sig":"bogus000000000001","arm":"codex","state":"aborted","created_epoch":%s,"task_id":"BOGUS"}\n' \
  "$((NOW - 60))" >> "$RESERVATIONS"
assert_title "bogus state filtered" "🛠 abcdef12 codex 2m"

cat > "$QUESTIONS/q-fixture.yaml" <<'EOF'
status: pending
question: Continue fixture?
options:
  - label: yes
EOF
assert_title "pending question" "❓1"
rm -f "$QUESTIONS/q-fixture.yaml"

printf '{malformed-ledger\n' > "$RESERVATIONS"
_broken="$(widget)"
_broken_title="$(printf '%s\n' "$_broken" | sed -n '1p')"
case "$_broken_title" in
  "⚠️ ledger "*) ok "malformed ledger -> ⚠" ;;
  *) bad "malformed ledger expected ⚠ title, got '$_broken_title'" ;;
esac

# Simulate a modern macOS SwiftBar PATH with no python3 while retaining only
# the small Unix toolbox required to launch/render the widget.
: > "$RESERVATIONS"
NO_PY_BIN="$FIX/no-python-bin"
mkdir -p "$NO_PY_BIN"
for cmd in bash dirname readlink basename date awk stat sed head grep tr mktemp \
  cut rm tail wc sort git; do
  src="$(command -v "$cmd" 2>/dev/null || true)"
  [ -n "$src" ] && ln -s "$src" "$NO_PY_BIN/$cmd"
done
_no_python="$(TEST_PATH="$NO_PY_BIN" widget)"
_no_python_title="$(printf '%s\n' "$_no_python" | sed -n '1p')"
case "$_no_python_title" in
  "⚠️ ledger "*) ok "python3 unavailable -> ⚠ (no legacy fallthrough)" ;;
  *) bad "python3 unavailable expected ⚠ title, got '$_no_python_title' (output=$(printf '%s' "$_no_python" | tr '\n' '|'))" ;;
esac

# ── SWIFTBAR-ACTIVE-SOURCE-02: process census tests ──────────────────────
echo ""
echo "== process census (SWIFTBAR-ACTIVE-SOURCE-02) =="

# Reset ledgers to clean state for census tests
: > "$RESERVATIONS"
: > "$TERMINALS"

# (a) live claude-subsession + no terminal → active with task_id from --task-id
PS_STUB="100 bash /scripts/claude-subsession.sh --role developer --model sonnet --task-id dispatch-deadbeef --mission-file /tmp/m.txt"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 deadbeef sonnet "*)
    # Also verify the detail line appears in the dropdown
    if printf '%s\n' "$_out" | grep -q 'deadbeef · worker · sonnet'; then
      ok "(a) live claude-subsession → active with sig8"
    else
      bad "(a) detail line missing for live worker (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(a) expected '🛠 deadbeef sonnet ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    ;;
esac

# (a2) reservation provides human task_id, process provides liveness
printf '{"task_sig":"deadbeef1234567890","arm":"sonnet","state":"confirmed","created_epoch":%s,"task_id":"FEED-SCAN"}\n' \
  "$((NOW - 300))" > "$RESERVATIONS"
PS_STUB="100 bash /scripts/claude-subsession.sh --role developer --model sonnet --task-id dispatch-deadbeef --mission-file /tmp/m.txt"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 FEED-SCAN sonnet "*)
    ok "(a2) human task_id from reservation preferred over sig8"
    ;;
  *)
    bad "(a2) expected '🛠 FEED-SCAN sonnet ...', got '$_title'"
    ;;
esac

# (b) worker gone + terminal → idle
: > "$RESERVATIONS"
printf '{"task_sig":"deadbeef1234567890","terminal":"landed","cause":"empty_diff","founder_task_id":"OLD-TASK"}\n' > "$TERMINALS"
PS_STUB="1 sleep 1"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
if [ "$_title" = "⚪ idle" ]; then
  ok "(b) worker gone + terminal → idle"
else
  bad "(b) expected idle, got '$_title'"
fi

# (c) Finding 4: exactly 3 entries — 2 live workers whose sigs match their
# own reservations + 1 unrelated pending reservation-only lane. No ranges.
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"bbbb222200000000","arm":"sonnet","state":"confirmed","created_epoch":%s,"task_id":"TASK-A"}\n' "$((NOW - 120))" > "$RESERVATIONS"
printf '{"task_sig":"cccc333300000000","arm":"glm","state":"confirmed","created_epoch":%s,"task_id":"TASK-B"}\n' "$((NOW - 300))" >> "$RESERVATIONS"
printf '{"task_sig":"dddd444400000000","arm":"codex","state":"pending","created_epoch":%s,"task_id":"TASK-C"}\n' "$((NOW - 60))" >> "$RESERVATIONS"
PS_STUB="100 bash /scripts/claude-subsession.sh --role developer --model sonnet --task-id dispatch-bbbb2222 --mission-file /tmp/m.txt
200 bash /scripts/glm-coder.sh __run_child /home/.claude/cache/glm-runs/260803-160000-cccc3333-abcd"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 3: "*)
    # Verify all 3 worker detail lines appear in the dropdown
    _wkrs="$(printf '%s\n' "$_out" | grep -cE '^  [^|]+ · [^|]+ · [^|]+ \| font=Menlo' || true)"
    if [ "$_wkrs" -eq 3 ]; then
      ok "(c) exactly 3 entries (2 live + 1 reservation-only)"
    else
      bad "(c) expected 3 worker detail lines, got $_wkrs (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(c) expected '🛠 3: ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    ;;
esac

# (d) Finding 5: "closing" for a NON-sonnet arm — glm-shaped argv (run-id
# contains sig8) + terminal row for that sig8. Founder rule: no terminal
# lanes in the title or the body; a "closing" detail row is a terminal lane
# in the body.  Expect idle + no trace of the lane.
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"beef00001234567890ab","arm":"glm","state":"confirmed","created_epoch":%s,"task_id":"CLO-B"}\n' "$((NOW - 60))" > "$RESERVATIONS"
printf '{"task_sig":"beef00001234567890ab","terminal":"landed","cause":"empty_diff","created_epoch":%s}\n' "$((NOW - 30))" > "$TERMINALS"
PS_STUB="100 bash /scripts/glm-coder.sh __run_child /home/.claude/cache/glm-runs/260803-160000-beef0000-abcd"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
if [ "$_title" = "⚪ idle" ] && ! printf '%s\n' "$_out" | grep -q 'CLO-B'; then
  ok "(d) glm worker + terminal → idle (no terminal lanes in body)"
else
  bad "(d) expected idle + no trace of the lane, got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi

# (e) empty everything → idle
: > "$RESERVATIONS"
: > "$TERMINALS"
PS_STUB="1 sleep 1"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
if [ "$_title" = "⚪ idle" ]; then
  ok "(e) empty everything → idle"
else
  bad "(e) expected idle, got '$_title'"
fi

# ── founder-named lane tests (critic finding: human task_id in run-id) ────
echo ""
echo "== founder-named lanes (human task_id in run-id segment) =="

# (f) glm worker with a human-named run-id lane segment + matching task_id
# reservation → shown ACTIVE once with the human name, not idle, not doubled.
# Note: the display truncates task_id to 20 chars for the menu-bar width.
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"feedscan12345678","arm":"glm","state":"confirmed","created_epoch":%s,"task_id":"FEED-SCAN-USABLE-CANDIDATES-01"}\n' \
  "$((NOW - 180))" > "$RESERVATIONS"
PS_STUB="300 bash /scripts/glm-coder.sh __run_child /home/.claude/cache/glm-runs/260803-160000-FEED-SCAN-USABLE-CANDIDATES-01-a1b2"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 FEED-SCAN-USABLE-CA… glm "*)
    # Must appear exactly ONCE in the dropdown (not doubled by reservation-only)
    _detail_count="$(printf '%s\n' "$_out" | grep -cE '^  FEED-SCAN-USABLE-CAN.* · glm ' || true)"
    if [ "$_detail_count" -eq 1 ]; then
      ok "(f) founder-named glm lane → ACTIVE once with human name"
    else
      bad "(f) expected 1 active detail line, got $_detail_count (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(f) expected '🛠 FEED-SCAN-USABLE-CA… glm ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    ;;
esac

# (g) codex pid-file with a founder-named handoff dir → ACTIVE once with human name.
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"codexfnd1234567000","arm":"codex","state":"confirmed","created_epoch":%s,"task_id":"CODEX-FOUNDER-TASK-02"}\n' \
  "$((NOW - 90))" > "$RESERVATIONS"
mkdir -p "$HANDOFF/CODEX-FOUNDER-TASK-02"
# Write a fake pid that is guaranteed alive: use $$ (the test shell itself).
printf '%s\n' "$$" > "$HANDOFF/CODEX-FOUNDER-TASK-02/.session-runner.pid"
# MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 C3: codex census now requires
# argv corroboration against the ps snapshot, so the pid must actually show
# up there running a recognized worker script (not just be alive).
PS_STUB="$$ codex exec --sandbox workspace-write -C /tmp"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 CODEX-FOUNDER-TASK-… codex "*)
    _detail_count="$(printf '%s\n' "$_out" | grep -cE '^  CODEX-FOUNDER-TASK-0.* · codex ' || true)"
    if [ "$_detail_count" -eq 1 ]; then
      ok "(g) founder-named codex pid-file → ACTIVE once with human name"
    else
      bad "(g) expected 1 active detail line, got $_detail_count (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(g) expected '🛠 CODEX-FOUNDER-TASK-… codex ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    ;;
esac
rm -rf "$HANDOFF/CODEX-FOUNDER-TASK-02"

# ── MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 §4 ─────────────────────────
echo ""
echo "== T-term: fresh vs stale terminal rows (Rule R retention) =="
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"aaaaaaaa11112222","arm":"sonnet","state":"confirmed","created_epoch":%s,"task_id":"M1A-FACT-QUALITY-01"}\n' \
  "$((NOW - 3000))" > "$RESERVATIONS"
printf '{"task_sig":"aaaaaaaa11112222","terminal":"no_work","task_id":"M1A-FACT-QUALITY-01","created_epoch":%s}\n' \
  "$((NOW - 600))" > "$TERMINALS"
PS_STUB="1 sleep 1"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
if [ "$_title" = "⚪ idle" ] && ! printf '%s\n' "$_out" | grep -q 'M1A-FACT-QUALITY-01'; then
  ok "(T-term-1) stale terminal (10m) drops the lane entirely"
else
  bad "(T-term-1) expected idle + no trace of the lane, got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi

printf '{"task_sig":"aaaaaaaa11112222","terminal":"no_work","task_id":"M1A-FACT-QUALITY-01","created_epoch":%s}\n' \
  "$((NOW - 60))" > "$TERMINALS"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
# Founder rule: no terminal lanes in the title or body.  A fresh terminal
# row drops the lane entirely, same as a stale one.
if [ "$_title" = "⚪ idle" ] && ! printf '%s\n' "$_out" | grep -q 'M1A-FACT-QUALITY-01'; then
  ok "(T-term-2) fresh terminal (60s) drops the lane entirely"
else
  bad "(T-term-2) expected idle + no trace of the lane, got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi

echo ""
echo "== T-lead: the lead's own session is never a lane (C3) =="
# codex_census() reads <PROJECT_ROOT>/docs/handoff (hardcoded), NOT the
# overridable LEADV2_STATUS_HANDOFF_DIR ($HANDOFF) used elsewhere in this
# fixture — the pid file must live under $PROJECT/docs/handoff to actually
# exercise the census path rather than accidentally passing via reservation
# fallback.
PHANDOFF="$PROJECT/docs/handoff"
: > "$RESERVATIONS"
: > "$TERMINALS"
rm -rf "$PHANDOFF"
mkdir -p "$PHANDOFF/dispatch-ff000000"
printf '%s\n' "$$" > "$PHANDOFF/dispatch-ff000000/.session-runner.pid"
PS_STUB="$$ bash /scripts/leadv2-codex-lead.sh --task-id dispatch-ff000000"
_out="$(widget)"
if printf '%s\n' "$_out" | grep -q 'ff000000'; then
  bad "(T-lead-1) lead's own session rendered as a lane (out=$(printf '%s' "$_out" | tr '\n' '|'))"
else
  ok "(T-lead-1) lead's own session excluded from lanes"
fi
rm -rf "$PHANDOFF/dispatch-ff000000"

# Companion positive: same shape, but the pid's argv is a real worker runner.
mkdir -p "$PHANDOFF/dispatch-ff111111"
printf '%s\n' "$$" > "$PHANDOFF/dispatch-ff111111/.session-runner.pid"
PS_STUB="$$ bash /scripts/leadv2-codex-session-runner.sh --task-id dispatch-ff111111"
_out="$(widget)"
if printf '%s\n' "$_out" | grep -q 'ff111111'; then
  ok "(T-lead-2) real codex session-runner still visible (exclusion is targeted)"
else
  bad "(T-lead-2) real session-runner wrongly excluded (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi
rm -rf "$PHANDOFF/dispatch-ff111111"

echo ""
echo "== T-multi: aggregation across repos (repo label on foreign lanes) =="
: > "$RESERVATIONS"
: > "$TERMINALS"
SL_STATE_ROOT="$FIX/state_root"
mkdir -p "$SL_STATE_ROOT/repo-b"
: > "$SL_STATE_ROOT/repo-b/dispatch-ledger.jsonl"
printf '{"task_sig":"bb112233bbccdd","arm":"sonnet","state":"confirmed","created_epoch":%s,"task_id":"REPO-B-TASK-01"}\n' \
  "$((NOW - 120))" > "$LEDGERS/repo-b.jsonl"
PS_STUB="1 sleep 1"
_out="$(widget)"
unset SL_STATE_ROOT
if printf '%s\n' "$_out" | grep -q 'REPO-B-TASK-01.*· repo-b | font=Menlo'; then
  ok "(T-multi) foreign-repo lane visible with its repo label"
else
  bad "(T-multi) expected repo-b lane with repo suffix (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi
rm -f "$LEDGERS/repo-b.jsonl"

echo ""
echo "== T-unverifiable: repo lacking a terminal ledger contributes zero rows =="
: > "$RESERVATIONS"
: > "$TERMINALS"
SL_STATE_ROOT="$FIX/state_root2"
mkdir -p "$SL_STATE_ROOT"
printf '{"task_sig":"cc998877ccddee","arm":"glm","state":"confirmed","created_epoch":%s,"task_id":"REPO-C-TASK-01"}\n' \
  "$((NOW - 60))" > "$LEDGERS/repo-c.jsonl"
PS_STUB="1 sleep 1"
_out="$(widget)"
unset SL_STATE_ROOT
# Founder rule: no 'terminals unreadable' rows at all. The suppression
# still holds (no REPO-C lane); the warning is gone.
if ! printf '%s\n' "$_out" | grep -q 'REPO-C-TASK-01'; then
  ok "(T-unverifiable) repo with unreadable terminals contributes no rows"
else
  bad "(T-unverifiable) expected no REPO-C lane (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi
rm -f "$LEDGERS/repo-c.jsonl"

echo ""
echo "== T-name: lane_label fallback + architect phase (C4) =="
# lane_phase()'s architect/review dir check is also hardcoded to
# <PROJECT_ROOT>/docs/handoff (see T-lead comment above), not $HANDOFF.
: > "$RESERVATIONS"
: > "$TERMINALS"
rm -rf "$PHANDOFF"
printf '{"task_sig":"m1afact0011223344","arm":"opus","state":"confirmed","created_epoch":%s,"task_id":"","lane_label":"M1A-FACT-QUALITY-01"}\n' \
  "$((NOW - 720))" > "$RESERVATIONS"
mkdir -p "$PHANDOFF/dispatch-m1afact0-architect"
PS_STUB="1 sleep 1"
_out="$(widget)"
if printf '%s\n' "$_out" | grep -q 'M1A-FACT-QUALITY-01 · architect'; then
  ok "(T-name-1) lane_label resolves the human name + architect phase"
else
  bad "(T-name-1) expected 'M1A-FACT-QUALITY-01 · architect' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi

printf '{"task_sig":"deadfeed99887766","arm":"sonnet","state":"confirmed","created_epoch":%s}\n' \
  "$((NOW - 30))" >> "$RESERVATIONS"
_out="$(widget)"
if printf '%s\n' "$_out" | grep -q 'deadfeed · queued'; then
  ok "(T-name-2) no name fields at all -> sig8 fallback"
else
  bad "(T-name-2) expected sig8 fallback 'deadfeed · queued' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi
rm -rf "$PHANDOFF/dispatch-m1afact0-architect"

printf '\ntest-status-surface-single-lead: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
