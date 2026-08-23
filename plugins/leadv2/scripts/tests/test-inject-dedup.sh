#!/usr/bin/env bash
# HOOK-INJECT-DEDUP-01: content-hash gate on the thread-anchor per-turn
# injection in leadv2-task-anchor.sh. No provider, network, or model call.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
ANCHOR="$PLUGIN_ROOT/hooks/leadv2-task-anchor.sh"
PRECOMPACT="$PLUGIN_ROOT/hooks/leadv2-pre-compact-checkpoint.sh"
PASS=0
FAIL=0
ROOT="$(lv2_mktemp_dir "leadv2-inject-dedup")"
SESSION_ID="inject-dedup-$$"
TMP_MARKER="/tmp/.leadv2-task-anchor-full-${SESSION_ID}-covertask"

cleanup() { rm -rf "$ROOT"; rm -f "$TMP_MARKER"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf -- '[TEST] FAIL: %s\n' "$1"; }

REPO="$ROOT/repo"
STATE_DIR="$ROOT/state"
mkdir -p "$REPO/docs/leadv2" "$STATE_DIR"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m init

# An open-threads doc so build_thread_anchor() has non-empty content to gate.
cat > "$REPO/docs/leadv2/open-threads.md" <<'EOF'
## Some open thread

Body line one.
Body line two.
EOF

payload() {
  local sid="$1"
  python3 - "$REPO" "$sid" <<'PYEOF'
import json, sys
sid = sys.argv[2]
d = {"cwd": sys.argv[1], "prompt": "ok"}
if sid:
    d["session_id"] = sid
print(json.dumps(d))
PYEOF
}

run_anchor() {
  local sid="$1"
  LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$ANCHOR" <<<"$(payload "$sid")"
}

if bash -n "$ANCHOR" && bash -n "$PRECOMPACT"; then
  pass "hook scripts parse"
else
  fail "hook scripts parse"
fi

# G2 -> G3: first fire is full, second fire (unchanged content, same day) is the marker.
first_out="$(run_anchor "$SESSION_ID")"
second_out="$(run_anchor "$SESSION_ID")"
if [[ "$first_out" == *"open-threads.md"* || -n "$first_out" ]] \
   && [[ "$second_out" == *"thread anchor unchanged"* ]] \
   && [[ "$second_out" != "$first_out" ]]; then
  pass "G2->G3: second identical fire collapses to a one-line marker"
else
  fail "G2->G3 failed: first=[$first_out] second=[$second_out]"
fi

# G4: content change forces a full re-inject.
cat >> "$REPO/docs/leadv2/open-threads.md" <<'EOF'

## A newly added thread
EOF
changed_out="$(run_anchor "$SESSION_ID")"
if [[ "$changed_out" != *"thread anchor unchanged"* ]]; then
  pass "G4: changed content re-injects full block"
else
  fail "G4 failed: got marker after content changed: $changed_out"
fi

# G5: date flip forces full re-inject even if body is byte-identical to the
# last full inject, because the stored digest binds body+date. Simulate by
# hand-writing yesterday's digest into the hash-state file directly.
hash_file="$STATE_DIR/.inject-hash.${SESSION_ID}.thread-anchor"
if [[ -f "$hash_file" ]]; then
  yesterday="$(python3 -c "import time; print(time.strftime('%Y-%m-%d', time.gmtime(time.time()-86400)))")"
  stale_digest="$(python3 -c "
import hashlib, sys
body = sys.argv[1]
day = sys.argv[2]
print(hashlib.sha256((body + '\n' + day + '\n').encode('utf-8')).hexdigest())
" "$changed_out" "$yesterday")"
  printf '%s' "$stale_digest" > "$hash_file"
  date_flip_out="$(run_anchor "$SESSION_ID")"
  if [[ "$date_flip_out" != *"thread anchor unchanged"* ]]; then
    pass "G5: a stored digest from a prior day forces full re-inject"
  else
    fail "G5 failed: got marker despite stale day-stamped digest"
  fi
else
  fail "G5 setup: expected hash-state file not found at $hash_file"
fi

# G0: kill-switch disables the gate — every fire is full, never a marker.
kill_out_1="$(LEADV2_INJECT_DEDUP=0 LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$ANCHOR" <<<"$(payload "${SESSION_ID}-g0")")"
kill_out_2="$(LEADV2_INJECT_DEDUP=0 LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$ANCHOR" <<<"$(payload "${SESSION_ID}-g0")")"
if [[ "$kill_out_1" != *"thread anchor unchanged"* && "$kill_out_2" != *"thread anchor unchanged"* ]]; then
  pass "G0: LEADV2_INJECT_DEDUP=0 disables the gate on every fire"
else
  fail "G0 failed: kill-switch did not force full both times"
fi

# G1: no session id at all -- gate must fail open (full), never crash the hook.
g1_out_1="$(LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$ANCHOR" <<<"$(payload "")")"
g1_out_2="$(LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$ANCHOR" <<<"$(payload "")")"
if [[ "$g1_out_1" != *"thread anchor unchanged"* && "$g1_out_2" != *"thread anchor unchanged"* ]]; then
  pass "G1: missing session id never collapses to the marker"
else
  fail "G1 failed: missing session id produced a marker"
fi

# G6: an unwritable state dir must fail open, and the hook must still exit 0.
if [[ "$(id -u)" != "0" ]]; then
  BAD_STATE_DIR="$ROOT/unwritable"
  mkdir -p "$BAD_STATE_DIR"
  chmod 000 "$BAD_STATE_DIR"
  g6_ok=1
  g6_out_1="$(LEADV2_TASK_ANCHOR_STATE_DIR="$BAD_STATE_DIR/nested" bash "$ANCHOR" <<<"$(payload "${SESSION_ID}-g6")")" || g6_ok=0
  g6_out_2="$(LEADV2_TASK_ANCHOR_STATE_DIR="$BAD_STATE_DIR/nested" bash "$ANCHOR" <<<"$(payload "${SESSION_ID}-g6")")" || g6_ok=0
  chmod 755 "$BAD_STATE_DIR"
  if [[ "$g6_ok" == "1" && "$g6_out_1" != *"thread anchor unchanged"* && "$g6_out_2" != *"thread anchor unchanged"* ]]; then
    pass "G6: unwritable state dir fails open, hook still exits 0"
  else
    fail "G6 failed: g6_ok=$g6_ok out1=[$g6_out_1] out2=[$g6_out_2]"
  fi
else
  pass "G6: skipped under root (chmod 000 is not enforced)"
fi

# R2: PreCompact must clear the stored digest so the very next prompt after
# /compact is a full re-inject, not a stale marker.
run_anchor "$SESSION_ID" >/dev/null
verify_marker="$(run_anchor "$SESSION_ID")"
if [[ "$verify_marker" != *"thread anchor unchanged"* ]]; then
  fail "R2 setup: expected a marker before compaction, got a full re-inject"
else
  pass "R2 setup: marker present before compaction"
fi
compact_payload="$(python3 - "$REPO" "$SESSION_ID" <<'PYEOF'
import json, sys
print(json.dumps({"cwd": sys.argv[1], "session_id": sys.argv[2]}))
PYEOF
)"
LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT" <<<"$compact_payload" >/dev/null
if [[ ! -f "$hash_file" ]]; then
  pass "R2: PreCompact removes the stored digest for the compacting session"
else
  fail "R2 failed: hash-state file survived PreCompact"
fi
post_compact_out="$(run_anchor "$SESSION_ID")"
if [[ "$post_compact_out" != *"thread anchor unchanged"* ]]; then
  pass "R2: first prompt after /compact is a full re-inject, not a marker"
else
  fail "R2 failed: first prompt after /compact still collapsed to a marker"
fi

# G5b (HOOK-INJECT-DEDUP-01): a scheduled-decision classification flip
# (DUE TODAY -> OVERDUE for the SAME row id) forces a full re-inject even
# though open-threads.md is byte-identical to the last fire. The sandbox
# repo has no .claude/hooks/scheduled-decisions-nearest.sh, so
# nearest_due_line() returns None and the rendered body genuinely does not
# vary with the Due date -- this isolates G5b from G4 cleanly.
SD_SESSION_ID="inject-dedup-sd-$$"
write_sd_ledger() {
  local due="$1"
  cat > "$REPO/docs/leadv2/scheduled-decisions.md" <<EOF
## SD-TEST-01 — Some decision

| **Due** | ${due} |
EOF
}
# NOTE: _nearest_decision_signature() classifies against LOCAL
# datetime.date.today() (matching the sibling renderer's own grammar), not
# UTC -- so both fixture dates must be derived from the same local clock via
# python, or a UTC/local day-boundary mismatch can silently classify both
# fixtures into the same OVERDUE tier and mask the flip this test exists to
# catch.
today_date="$(python3 -c "import datetime; print(datetime.date.today().isoformat())")"
past_date="$(python3 -c "import datetime; print((datetime.date.today() - datetime.timedelta(days=3)).isoformat())")"

write_sd_ledger "$today_date"
sd_first_out="$(run_anchor "$SD_SESSION_ID")"
sd_second_out="$(run_anchor "$SD_SESSION_ID")"
if [[ "$sd_second_out" == *"thread anchor unchanged"* ]]; then
  pass "G5b setup: unchanged ledger (DUE TODAY) still collapses to marker"
else
  fail "G5b setup failed: expected marker on unchanged fire, got: $sd_second_out"
fi

# Flip ONLY the Due date across the overdue boundary; id and every other
# byte stay identical.
write_sd_ledger "$past_date"
sd_flip_out="$(run_anchor "$SD_SESSION_ID")"
if [[ "$sd_flip_out" != *"thread anchor unchanged"* ]]; then
  pass "G5b: DUE_TODAY -> OVERDUE classification flip forces full re-inject"
else
  fail "G5b failed: got marker despite classification flip: $sd_flip_out"
fi
rm -f "$REPO/docs/leadv2/scheduled-decisions.md"

# Finding 3: PreCompact must also clear the task-mode full-anchor marker
# glob (/tmp/.leadv2-task-anchor-full-<sid>-<task>). The sandbox repo never
# has an active task, so leadv2-task-anchor.sh's task-mode branch (:645)
# never runs and never creates this file on its own -- create it explicitly
# so R2's PreCompact coverage of the glob is actually exercised.
: > "$TMP_MARKER"
LEADV2_TASK_ANCHOR_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT" <<<"$compact_payload" >/dev/null
if [[ ! -f "$TMP_MARKER" ]]; then
  pass "finding-3: PreCompact clears the /tmp task-anchor-full marker glob"
else
  fail "finding-3 failed: /tmp task-anchor-full marker survived PreCompact"
fi

# Finding 5: the fail-open WARN line must actually reach stderr (requires
# the 2>/dev/null redirect removed from the python3 heredoc invocation).
# Reuse the existing G6 unwritable-state-dir case -- a real PermissionError,
# no test-only error-injection backdoor.
if [[ "$(id -u)" != "0" ]]; then
  WARN_STATE_DIR="$ROOT/unwritable-warn"
  mkdir -p "$WARN_STATE_DIR"
  chmod 000 "$WARN_STATE_DIR"
  warn_err="$(LEADV2_TASK_ANCHOR_STATE_DIR="$WARN_STATE_DIR/nested" bash "$ANCHOR" <<<"$(payload "${SESSION_ID}-warn")" 2>&1 >/dev/null)" || true
  chmod 755 "$WARN_STATE_DIR"
  if [[ "$warn_err" == *"[inject-dedup] fail-open:"* ]]; then
    pass "finding-5: fail-open path emits a [inject-dedup] fail-open: WARN on stderr"
  else
    fail "finding-5 failed: no WARN line found on stderr: $warn_err"
  fi
else
  pass "finding-5: skipped under root (chmod 000 is not enforced)"
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
