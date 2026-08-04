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
    if printf '%s\n' "$_out" | grep -q 'deadbeef sonnet.*active'; then
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
    _wkrs="$(printf '%s\n' "$_out" | grep -c '^  .* \(active\|closing\) | font=Menlo' || true)"
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
# contains sig8) + terminal row for that sig8 → expect "closing".
: > "$RESERVATIONS"
: > "$TERMINALS"
printf '{"task_sig":"beef00001234567890ab","arm":"glm","state":"confirmed","created_epoch":%s,"task_id":"CLO-B"}\n' "$((NOW - 60))" > "$RESERVATIONS"
printf '{"task_sig":"beef00001234567890ab","terminal":"landed","cause":"empty_diff"}\n' > "$TERMINALS"
PS_STUB="100 bash /scripts/glm-coder.sh __run_child /home/.claude/cache/glm-runs/260803-160000-beef0000-abcd"
_out="$(widget)"
if printf '%s\n' "$_out" | grep -q 'CLO-B.*closing'; then
  ok "(d) glm worker + terminal → closing state"
else
  _title="$(printf '%s\n' "$_out" | sed -n '1p')"
  bad "(d) expected closing state, got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
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
  "🛠 FEED-SCAN-USABLE-CAN glm "*)
    # Must appear exactly ONCE in the dropdown (not doubled by reservation-only)
    _detail_count="$(printf '%s\n' "$_out" | grep -c 'FEED-SCAN-USABLE-CAN.*active' || true)"
    if [ "$_detail_count" -eq 1 ]; then
      ok "(f) founder-named glm lane → ACTIVE once with human name"
    else
      bad "(f) expected 1 active detail line, got $_detail_count (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(f) expected '🛠 FEED-SCAN-USABLE-CAN glm ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
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
PS_STUB="1 sleep 1"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
case "$_title" in
  "🛠 CODEX-FOUNDER-TASK-0 codex "*)
    _detail_count="$(printf '%s\n' "$_out" | grep -c 'CODEX-FOUNDER-TASK-0.*active' || true)"
    if [ "$_detail_count" -eq 1 ]; then
      ok "(g) founder-named codex pid-file → ACTIVE once with human name"
    else
      bad "(g) expected 1 active detail line, got $_detail_count (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    fi
    ;;
  *)
    bad "(g) expected '🛠 CODEX-FOUNDER-TASK-0 codex ...', got '$_title' (out=$(printf '%s' "$_out" | tr '\n' '|'))"
    ;;
esac
rm -rf "$HANDOFF/CODEX-FOUNDER-TASK-02"

printf '\ntest-status-surface-single-lead: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
