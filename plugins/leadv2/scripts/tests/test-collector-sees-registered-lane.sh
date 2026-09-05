#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-status-collector.sh
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
# PULSE-REPO-SCOPED-03 ownership mark. The renderer keeps a foreign-repo row
# only when THIS repo dispatched it, and the dispatch journal directory
# docs/leadv2/tasks/<task_id>/ is what says so. That rule landed after this
# fixture was written, so the board-level case asserted the older behaviour --
# every foreign row the collector could see appears -- and could only fail.
#
# Creating the mark is not a workaround: it makes the fixture the case this
# suite is actually about, and the one the collector's LEADV2_LANES_ALL_REPOS=1
# pin exists to rescue -- a lane THIS repo dispatched whose registry row lives
# in another repo must stay visible here. The other half of the rule (a
# foreign row this repo never dispatched is dropped) is pinned separately
# below; an assumption worth pinning is worth pinning on both sides.
mkdir -p "$REPO/docs/leadv2/tasks/dispatch-f9ecad31"
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
  # Every case must measure a fresh render. The status snapshot is cached with
  # a TTL, so without this the board after a mutation could be the board from
  # before it -- and the suite's own mutation control was passing on exactly
  # that: it asserts the foreign lane is ABSENT, and while the board-level
  # case was broken the lane was absent from every render regardless of the
  # mutation. A control whose expected outcome is "absent" is worthless until
  # something has been shown to make it present.
  rm -f "$STATE/board/status-snapshot.json" "$STATE/board/status-snapshot-journal.jsonl" 2>/dev/null || true
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

# ── the other half of PULSE-REPO-SCOPED-03 ─────────────────────────────────
#
# The case above proves an OWNED foreign lane survives. Without this one the
# suite would stay green if the repo-scoping rule were deleted entirely, and
# the board would fill with other repos' lanes again -- which is the state
# PULSE-REPO-SCOPED-03 was written to end.
UNOWNED=dispatch-c0ffee01
mkdir -p "$FOREIGN/docs/handoff/${UNOWNED}"
printf '{"event":"writing"}\n' > "$FOREIGN/docs/handoff/${UNOWNED}/developer.stream.jsonl"
cat >> "$STATE/persona-engine/active.yaml" <<EOF
  - task_id: ${UNOWNED}
    pid: $$
    phase: build
    log_path: docs/handoff/${UNOWNED}/developer.stream.jsonl
    started_at: 2026-08-30T11:06:43Z
EOF
rm -f "$FOUNDER_STATUS"
run_board
if grep -q "^| persona-engine/${UNOWNED}" "$FOUNDER_STATUS" 2>/dev/null; then
  fail "repo-scoping: a foreign lane this repo never dispatched reached the board (${UNOWNED})"
elif grep -q '^| persona-engine/dispatch-f9ecad31' "$FOUNDER_STATUS" 2>/dev/null; then
  pass "repo-scoping: the owned foreign lane stays, the unowned one is dropped"
else
  # Both absent is not the same fact as "the unowned one was dropped": it
  # means the board rendered nothing at all and this case proved nothing.
  fail "repo-scoping: neither lane is on the board -- nothing was measured (table: $(grep '^|' "$FOUNDER_STATUS" 2>/dev/null | head -2 | tr '\n' ' '))"
fi

# Mutation control: disable the collector's own-process pin (leadv2-status-
# collector.sh's _sc_lanes_section) and prove the SAME fixture goes red at
# the board layer -- then revert and prove green again. Never a scratch
# copy: the production file is mutated in place and restored via git.
COLLECTOR_PROD="$SCRIPT_DIR/leadv2-status-collector.sh"
SNAPSHOT_PROD="$SCRIPT_DIR/leadv2-lanes-snapshot.sh"
cp "$COLLECTOR_PROD" "$TMP/collector.sh.orig"
cp "$SNAPSHOT_PROD" "$TMP/lanes-snapshot.sh.orig"
# Restore both even if this suite dies between mutation and revert: these are
# the real production files, mutated in place, and a suite that leaves one
# mutated is the vandal shape that has already cost us a working tree once.
trap 'cp -f "$TMP/collector.sh.orig" "$COLLECTOR_PROD" 2>/dev/null || true; cp -f "$TMP/lanes-snapshot.sh.orig" "$SNAPSHOT_PROD" 2>/dev/null || true' EXIT
python3 - "$COLLECTOR_PROD" "$SNAPSHOT_PROD" <<'PY'
import sys
# Remove the PROPERTY, not one implementation of it -- and it is STILL not
# enough. Read this before touching the assertion below.
#
# The control used to strip only the collector's explicit
# `LEADV2_LANES_ALL_REPOS=1` pin. leadv2-lanes-snapshot.sh DEFAULTS the same
# variable to 1, so that single-site mutation left the property intact; both
# sites are now removed. Measured 2026-09-05, three ways, all with the board
# rendering correctly:
#
#   pin removed, ownership mark present   -> foreign lane still on the board
#   pin removed, ownership mark absent    -> foreign lane still on the board
#   pin AND snapshot default removed      -> foreign lane still on the board
#
# So the visibility of a foreign-repo lane on this board is NOT governed by
# either of the two things that claim to govern it. There is a third discovery
# path and it has not been identified. That is a product question about the
# collector/renderer, not a suite defect, and it is left RED on purpose: the
# assertion is the honest one, and the way to make it green is to find the
# path, not to lower the bar.
#
# Why nobody noticed until now: while the board-level case above was broken,
# the lane was absent from EVERY render, so this control's assertion --
# "absent after the mutation" -- held for free. A control whose expected
# outcome is an absence proves nothing until something has been shown to make
# the thing present. Fixing the case above is what made this control able to
# fail at all.
collector_path, snapshot_path = sys.argv[1], sys.argv[2]

with open(collector_path) as f:
    text = f.read()
needle = "    LEADV2_LANES_ALL_REPOS=1 \\\n"
assert needle in text, "mutation anchor not found in leadv2-status-collector.sh"
with open(collector_path, "w") as f:
    f.write(text.replace(needle, "", 1))

with open(snapshot_path) as f:
    snap = f.read()
snap_needle = 'ALL_REPOS="${LEADV2_LANES_ALL_REPOS:-1}"'
assert snap_needle in snap, "mutation anchor not found in leadv2-lanes-snapshot.sh"
with open(snapshot_path, "w") as f:
    f.write(snap.replace(snap_needle, 'ALL_REPOS="${LEADV2_LANES_ALL_REPOS:-0}"', 1))
PY
rm -f "$FOUNDER_STATUS"
run_board
if grep -q '^| persona-engine/dispatch-f9ecad31' "$FOUNDER_STATUS" 2>/dev/null; then
  fail "mutation control: foreign lane still visible with BOTH all-repos sites removed (collector pin + lanes-snapshot default) -- a third, unidentified discovery path renders foreign lanes; see the note above, and do not silence this by weakening the assertion"
else
  pass "mutation control: removing the collector's all-repos pin reproduces the empty-of-foreign-lanes board (RED)"
fi
cp "$TMP/collector.sh.orig" "$COLLECTOR_PROD"
cp "$TMP/lanes-snapshot.sh.orig" "$SNAPSHOT_PROD"
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
