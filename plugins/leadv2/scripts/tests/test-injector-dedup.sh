#!/usr/bin/env bash
# T15 — dedup of the per-turn UserPromptSubmit injectors.
#
# HOOK-INJECT-DEDUP-01 (see test-inject-dedup.sh) already put a content-hash
# gate on leadv2-task-anchor.sh's own output. This suite covers the
# remaining T15 claim: that a SECOND registered UserPromptSubmit hook
# (leadv2-user-prompt-context.sh) does not re-inject the same
# [LEADV2_ACTIVE]/[ORCHESTRATOR_ROLE] content task-anchor.sh already owns —
# i.e. no double-injection across the two files that fire on every turn,
# not just within one file's own gate.
#
# Cases (T15 mission, letters kept for cross-reference):
#   a) first turn                          -> task-anchor full injection
#   b) second turn, unchanged state        -> task-anchor stub, <=5 lines
#   c) state changed (new open-thread)     -> task-anchor full again
#   d) state sidecar unwritable/corrupted  -> fail-open, full injection
#   e) both hooks fire the same turn       -> user-prompt-context.sh does
#      NOT also emit [LEADV2_ACTIVE]/[ORCHESTRATOR_ROLE] under the default
#      LEADV2_ANCHOR_OWNS_CONTEXT=1 handoff (old path is neutralized without
#      needing to unregister the file: it still owns compact-intercept,
#      stop-hook-warning relay, and per-turn budget tracking, none of which
#      task-anchor.sh covers). LEADV2_ANCHOR_OWNS_CONTEXT=0 is asserted to
#      re-enable the old path, proving the flag is load-bearing and not
#      coincidentally empty.
#
# No provider, network, or model call. stdlib bash + python3 + jq.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
ANCHOR="$PLUGIN_ROOT/hooks/leadv2-task-anchor.sh"
UPC="$PLUGIN_ROOT/hooks/leadv2-user-prompt-context.sh"
PASS=0
FAIL=0
ROOT="$(lv2_mktemp_dir "leadv2-injector-dedup")"
SESSION_ID="injector-dedup-$$"

cleanup() { rm -rf "$ROOT"; rm -f "/tmp/leadv2-orch-role-${SESSION_ID}"; }
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

cat > "$REPO/docs/leadv2/open-threads.md" <<'EOF'
## Some open thread

Body line one.
Body line two.
EOF

# active.yaml so leadv2-user-prompt-context.sh's [LEADV2_ACTIVE]/
# [ORCHESTRATOR_ROLE] path has something to fire on when its gate is open.
cat > "$REPO/docs/leadv2/active.yaml" <<EOF
sessions:
  - task_id: t15-fixture
    phase: build
    pid: $$
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

run_upc() {
  local sid="$1"
  local owns="${2:-1}"
  LEADV2_TASK_ID="t15-fixture" LEADV2_ANCHOR_OWNS_CONTEXT="$owns" \
    bash "$UPC" <<<"$(payload "$sid")"
}

if bash -n "$ANCHOR" && bash -n "$UPC"; then
  pass "hook scripts parse"
else
  fail "hook scripts parse"
fi

# (a) first turn -> full injection.
a_out="$(run_anchor "$SESSION_ID")"
if [[ -n "$a_out" && "$a_out" != *"thread anchor unchanged"* ]]; then
  pass "(a) first turn: task-anchor emits a full injection"
else
  fail "(a) first turn produced no full injection: [$a_out]"
fi

# (b) second turn, unchanged state -> stub, <=5 lines. (a_out is the
# ACTIVE TASK full block since $REPO/docs/leadv2/active.yaml selects
# t15-fixture; the active-task stub text differs from the no-task
# thread-anchor's "thread anchor unchanged" marker.)
b_out="$(run_anchor "$SESSION_ID")"
b_lines=$(printf -- '%s' "$b_out" | grep -c . || true)
if [[ "$b_out" == *"This message does not replace it"* ]] \
   && [[ "$b_out" != "$a_out" ]] \
   && [[ "$b_lines" -le 5 ]]; then
  pass "(b) second turn unchanged: stub, ${b_lines} line(s) <=5"
else
  fail "(b) unchanged turn did not collapse to a <=5-line stub: lines=${b_lines} out=[$b_out]"
fi

# (c) state changed (goal line in context.yaml) -> full again. open-threads.md
# only feeds the no-active-task thread anchor; the active-task full block's
# content comes from docs/handoff/<task_id>/context.yaml + STATE.md instead.
mkdir -p "$REPO/docs/handoff/t15-fixture"
cat > "$REPO/docs/handoff/t15-fixture/context.yaml" <<'EOF'
goal: a freshly changed goal line
EOF
c_out="$(run_anchor "$SESSION_ID")"
if [[ "$c_out" != *"This message does not replace it"* ]] \
   && [[ "$c_out" == *"a freshly changed goal line"* ]]; then
  pass "(c) changed state: full re-inject reflects the new goal"
else
  fail "(c) changed state failed to force a full re-inject: [$c_out]"
fi

# (d) state sidecar unwritable -> fail-open, full injection (never silently
# collapsed to the stub) even though content is otherwise unchanged from (c).
UNWRITABLE_STATE="$ROOT/unwritable/nested"
mkdir -p "$ROOT/unwritable"
chmod 000 "$ROOT/unwritable"
d_out="$(LEADV2_TASK_ANCHOR_STATE_DIR="$UNWRITABLE_STATE" bash "$ANCHOR" <<<"$(payload "$SESSION_ID")" 2>/dev/null || true)"
chmod 755 "$ROOT/unwritable"
if [[ -n "$d_out" && "$d_out" != *"This message does not replace it"* ]]; then
  pass "(d) unwritable state sidecar: fail-open to full injection"
else
  fail "(d) unwritable state sidecar did not fail open: [$d_out]"
fi

# (e) both hooks fire the same turn. Default LEADV2_ANCHOR_OWNS_CONTEXT=1:
# user-prompt-context.sh must NOT also emit the overlapping blocks
# task-anchor.sh already owns — no double-injection.
e_sid="injector-dedup-e-$$"
e_upc_default="$(run_upc "$e_sid" "1" 2>/dev/null || true)"
if [[ "$e_upc_default" != *"[LEADV2_ACTIVE]"* ]] && [[ "$e_upc_default" != *"[ORCHESTRATOR_ROLE]"* ]]; then
  pass "(e) default handoff: user-prompt-context.sh does not duplicate task-anchor's content"
else
  fail "(e) user-prompt-context.sh duplicated overlapping content under the default handoff: [$e_upc_default]"
fi

# (e, control) LEADV2_ANCHOR_OWNS_CONTEXT=0 must re-enable the old path —
# proves (e)'s pass above is the flag working, not a coincidental no-op.
e_upc_legacy="$(run_upc "${e_sid}-legacy" "0" 2>/dev/null || true)"
if [[ "$e_upc_legacy" == *"[LEADV2_ACTIVE]"* ]] || [[ "$e_upc_legacy" == *"[ORCHESTRATOR_ROLE]"* ]]; then
  pass "(e control) LEADV2_ANCHOR_OWNS_CONTEXT=0 re-enables the old path"
else
  fail "(e control) LEADV2_ANCHOR_OWNS_CONTEXT=0 did not re-enable the old path: [$e_upc_legacy]"
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
