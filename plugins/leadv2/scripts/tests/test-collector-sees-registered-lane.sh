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

printf '[collector-sees-registered-lane] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
