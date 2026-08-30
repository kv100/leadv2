#!/usr/bin/env bash
# A founder board must read registered lanes from every control-plane repo,
# even when the caller's ambient environment disables the optional snapshot
# extension. This uses the real collector and snapshot, with a throwaway
# state base and a foreign registered live lane.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "$SCRIPT_DIR/leadv2-temp.sh"

COLLECTOR_SH="$SCRIPT_DIR/leadv2-status-collector.sh"
TMP="$(lv2_mktemp_dir collector-sees-registered-lane)"
REPO="$TMP/board"
FOREIGN="$TMP/persona-engine"
STATE="$TMP/state"
STUBS="$TMP/stubs"
OUT="$TMP/snapshot.json"
PASS=0
FAIL=0

pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$REPO" "$FOREIGN" "$STATE" "$STUBS"
git -C "$REPO" init -q
git -C "$FOREIGN" init -q
lv2_assert_scratch_repo "$REPO"

mkdir -p "$STATE/board" "$STATE/persona-engine" \
  "$FOREIGN/docs/handoff/dispatch-f9ecad31"
printf '%s\n' "$REPO" > "$STATE/board/.repo-root"
printf '%s\n' "$FOREIGN" > "$STATE/persona-engine/.repo-root"
printf 'sessions: []\n' > "$STATE/board/active.yaml"
printf '{"event":"writing"}\n' > "$FOREIGN/docs/handoff/dispatch-f9ecad31/developer.stream.jsonl"
cat > "$STATE/persona-engine/active.yaml" <<EOF
sessions:
  - task_id: dispatch-f9ecad31
    pid: $$
    phase: build
    log_path: docs/handoff/dispatch-f9ecad31/developer.stream.jsonl
    started_at: 2026-08-30T11:06:43Z
EOF
cat > "$STUBS/liveness.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"lanes":[],"jobs":[],"availability":"unavailable"}\n'
EOF
chmod +x "$STUBS/liveness.sh"

# The red condition: the collector must not inherit this opt-out for the
# founder's global board.
env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" \
  LEADV2_LANES_ALL_REPOS=0 LEADV2_LANE_LIVENESS_BIN="$STUBS/liveness.sh" \
  bash "$COLLECTOR_SH" --project-root "$REPO" --out "$OUT" >/dev/null

ROW="$(python3 - "$OUT" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
lanes = doc.get("sections", {}).get("lanes", {})
for row in (lanes.get("data", {}) or {}).get("table", []):
    if row.get("task_id") == "dispatch-f9ecad31" and row.get("repo") == "persona-engine":
        print("found")
PY
)"
if [[ "$ROW" == "found" ]]; then
  pass "registered persona-engine lane survives collector despite ambient all-repos=0"
else
  fail "registered lane missing from collector snapshot"
fi

# ── board-level case: real collector feeds the real renderer ───────────────
# The two checks above only prove the collector's JSON is correct one layer
# below what the founder reads. PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 round 3:
# a collector regression must go red at founder-status.md itself, not just in
# a snapshot file nobody reads directly. Neither LEADV2_STATUS_COLLECTOR_BIN
# nor LEADV2_BROAD_STATUS_CLAUDE_BIN's data path is stubbed here — only the
# LLM prose tail (claude.sh) is, since that call is out of scope for this
# check and would otherwise require network access.
BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"
cat > "$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "$STUBS/claude.sh"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

run_board() {
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE/board" LEADV2_STATE_BASE="$STATE" \
    LEADV2_LANES_ALL_REPOS=0 LEADV2_LANE_LIVENESS_BIN="$STUBS/liveness.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-30T18:00:00Z" \
    LEADV2_BROAD_STATUS_DISPATCHED="1" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
}

run_board
if grep -q '^| persona-engine/dispatch-f9ecad31' "$FOUNDER_STATUS" 2>/dev/null; then
  pass "board-level: real collector + real renderer show the foreign lane on founder-status.md"
else
  fail "board-level: foreign lane missing from founder-status.md: $(grep '^|' "$FOUNDER_STATUS" 2>/dev/null | head -3)"
fi

# Mutation control: disable the collector's own-process pin (leadv2-status-
# collector.sh's _sc_lanes_section) and prove the SAME fixture goes red at
# the board layer -- then revert and prove green again. Never a scratch
# copy: the production file is mutated in place and restored via git.
COLLECTOR_PROD="$SCRIPT_DIR/leadv2-status-collector.sh"
cp "$COLLECTOR_PROD" "$TMP/collector.sh.orig"
python3 - "$COLLECTOR_PROD" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
needle = "    LEADV2_LANES_ALL_REPOS=1 \\\n"
assert needle in text, "mutation anchor not found in leadv2-status-collector.sh"
text = text.replace(needle, "", 1)
with open(path, "w") as f:
    f.write(text)
PY
rm -f "$FOUNDER_STATUS"
run_board
if grep -q '^| persona-engine/dispatch-f9ecad31' "$FOUNDER_STATUS" 2>/dev/null; then
  fail "mutation control: foreign lane still visible with the collector's all-repos pin removed (RED expected)"
else
  pass "mutation control: removing the collector's all-repos pin reproduces the empty-of-foreign-lanes board (RED)"
fi
cp "$TMP/collector.sh.orig" "$COLLECTOR_PROD"
bash -n "$COLLECTOR_PROD" || fail "mutation control: leadv2-status-collector.sh failed to parse after revert"
rm -f "$FOUNDER_STATUS"
run_board
if grep -q '^| persona-engine/dispatch-f9ecad31' "$FOUNDER_STATUS" 2>/dev/null; then
  pass "mutation control: reverted collector.sh restores the foreign lane on the board (GREEN)"
else
  fail "mutation control: foreign lane still missing after revert"
fi

printf '[collector-sees-registered-lane] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
