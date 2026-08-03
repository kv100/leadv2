#!/usr/bin/env bash
# Fixture coverage for SWIFTBAR-SINGLE-LEAD-01. Every input is sandboxed;
# nothing reads or writes the operator's live leadv2 state.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
SURFACE="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.sh"
WRAPPER="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.10s.sh"
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

widget() {
  PATH="${TEST_PATH:-$PATH}" \
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

printf '{"task_sig":"abcdef1234567890","arm":"codex","state":"running","created_epoch":%s}\n' \
  "$((NOW - 120))" > "$RESERVATIONS"
assert_title "active dispatch" "🛠 abcdef12 codex 2m"

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

printf '\ntest-status-surface-single-lead: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
