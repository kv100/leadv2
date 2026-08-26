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

# T15 R3: the active.yaml session used to key ownership on `pid: $$` alone,
# relying on leadv2-task-anchor.sh's process_ancestors() walking the REAL
# OS process tree (via `ps -o ppid=`) up to this test's own PID. That walk
# is environment-dependent — its depth/success varies with how many layers
# of shell/subshell/container wrap the test runner (measured: 7/0 in one
# checkout, 5/2 in another) — so cases (b)/(c) could silently fall through
# to the NO-active-task thread-anchor path instead of genuinely exercising
# the active-task path, and still "pass" on a coincidentally-similar output
# shape. Fix: key ownership on the WORKTREE-match fallback instead (a plain
# os.path.realpath() string compare, no `ps`, no process-tree walk) by
# giving the session a `pid` guaranteed dead (works.max pid_max is far below
# 999999999 on Linux and macOS, so os.kill() reliably raises
# ProcessLookupError) and a `worktree` that matches $REPO exactly. This is
# fully hermetic — no dependency on this test process's real ancestry or on
# ~/.claude state (LEADV2_TASK_ANCHOR_STATE_DIR already isolates the latter).
#
# NOTE: a *numeric* pid — even a deliberately-dead one like 999999999 — does
# NOT fall through to the worktree match: leadv2-task-anchor.sh's own logic
# treats any int-parseable pid outside this process's ancestry as "a
# different session, possibly stale" and unconditionally `continue`s past
# the worktree check for both the os.kill()-succeeds and
# ProcessLookupError branches (main(), the active.yaml matching loop —
# "Never select it by worktree fallback"). The worktree fallback is reached
# ONLY when the pid field fails int(...) entirely (TypeError/ValueError ->
# session_pid = None). Omitting `pid` is therefore the correct hermetic
# fixture, not an oversight.
cat > "$REPO/docs/leadv2/active.yaml" <<EOF
sessions:
  - task_id: t15-fixture
    phase: build
    worktree: "$REPO"
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

# (a) first turn -> full injection. R3 sentinel: assert the ACTIVE-TASK
# path was genuinely entered (task_id echoed back), not a coincidentally
# similar no-task thread-anchor shape.
a_out="$(run_anchor "$SESSION_ID")"
if [[ -n "$a_out" && "$a_out" == *"ACTIVE TASK: t15-fixture"* ]]; then
  pass "(a) first turn: task-anchor emits a full injection (active-task path confirmed)"
else
  fail "(a) first turn produced no full active-task injection: [$a_out]"
fi

# (b) second turn, unchanged state -> stub, <=5 lines, and still the
# active-task stub (not the no-task thread-anchor's "thread anchor
# unchanged" marker — that would mean ownership silently fell through).
b_out="$(run_anchor "$SESSION_ID")"
b_lines=$(printf -- '%s' "$b_out" | grep -c . || true)
if [[ "$b_out" == *"ACTIVE TASK: t15-fixture"* ]] \
   && [[ "$b_out" == *"This message does not replace it"* ]] \
   && [[ "$b_out" != "$a_out" ]] \
   && [[ "$b_lines" -le 5 ]]; then
  pass "(b) second turn unchanged: stub, ${b_lines} line(s) <=5, active-task path confirmed"
else
  fail "(b) unchanged turn did not collapse to a <=5-line active-task stub: lines=${b_lines} out=[$b_out]"
fi

# (c) state changed (goal line in context.yaml) -> full again. open-threads.md
# only feeds the no-active-task thread anchor; the active-task full block's
# content comes from docs/handoff/<task_id>/context.yaml + STATE.md instead.
mkdir -p "$REPO/docs/handoff/t15-fixture"
cat > "$REPO/docs/handoff/t15-fixture/context.yaml" <<'EOF'
goal: a freshly changed goal line
EOF
c_out="$(run_anchor "$SESSION_ID")"
if [[ "$c_out" == *"ACTIVE TASK: t15-fixture"* ]] \
   && [[ "$c_out" != *"This message does not replace it"* ]] \
   && [[ "$c_out" == *"a freshly changed goal line"* ]]; then
  pass "(c) changed state: full re-inject reflects the new goal, active-task path confirmed"
else
  fail "(c) changed state failed to force a full re-inject: [$c_out]"
fi

# (c.delta) T15 R1: the cheap stat()-based pre-check must not itself go
# stale — a second unchanged turn after (c)'s full re-inject must still
# collapse back to the stub (proves the cheap-hash store after a "full"
# outcome actually persisted, not just the original body-hash gate).
c_delta_out="$(run_anchor "$SESSION_ID")"
c_delta_lines=$(printf -- '%s' "$c_delta_out" | grep -c . || true)
if [[ "$c_delta_out" == *"ACTIVE TASK: t15-fixture"* ]] \
   && [[ "$c_delta_out" == *"This message does not replace it"* ]] \
   && [[ "$c_delta_lines" -le 5 ]]; then
  pass "(c.delta) turn after a full re-inject collapses back to the stub"
else
  fail "(c.delta) did not collapse back to stub after a full re-inject: lines=${c_delta_lines} out=[$c_delta_out]"
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
# user-prompt-context.sh must dedup ONLY the true duplicate — the
# [LEADV2_ACTIVE] header and the "SILENCE PROTOCOL" paragraph, both of
# which task-anchor.sh's own DIRECTIVE already covers. It must NOT drop
# unique information: [ORCHESTRATOR_ROLE] itself (trimmed, not suppressed)
# still carries the no-direct-code delegate rule and the post-compact
# resume-read instruction, and [LEADV2_PHASE_HINT] (severity/round-cap
# gate) has no equivalent in task-anchor.sh at all. R2 explicitly forbids
# information loss — a stale "tag absent" assertion here would just
# re-introduce the bug this fix removes.
e_sid="injector-dedup-e-$$"
e_upc_default="$(run_upc "$e_sid" "1" 2>/dev/null || true)"
if [[ "$e_upc_default" != *"[LEADV2_ACTIVE]"* ]] \
   && [[ "$e_upc_default" != *"SILENCE PROTOCOL"* ]] \
   && [[ "$e_upc_default" == *"[ORCHESTRATOR_ROLE]"* ]] \
   && [[ "$e_upc_default" == *"NEVER write .py/.sh"* ]]; then
  pass "(e) default handoff: true duplicate suppressed, unique content preserved"
else
  fail "(e) default handoff lost unique content or kept the duplicate: [$e_upc_default]"
fi

# (e, control) LEADV2_ANCHOR_OWNS_CONTEXT=0 must re-enable the FULL legacy
# path — proves (e)'s dedup above is the flag working, not a coincidental
# no-op. T15 R4: byte-compare, not a single grep. Two independent
# first-time sessions (never touched, so neither hits the per-session
# ORCH_SENTINEL short-circuit) against identical fixture state must
# produce byte-identical output — this is a far stronger check than
# "does substring X appear once": it catches any accidental
# nondeterminism or partial-emission drift across the whole legacy body,
# not just the one tag a plain grep would look at.
e_upc_legacy_a="$(run_upc "${e_sid}-legacy-a" "0" 2>/dev/null || true)"
e_upc_legacy_b="$(run_upc "${e_sid}-legacy-b" "0" 2>/dev/null || true)"
if [[ "$e_upc_legacy_a" == *"[LEADV2_ACTIVE]"* ]] \
   && [[ "$e_upc_legacy_a" == *"[ORCHESTRATOR_ROLE]"* ]] \
   && [[ "$e_upc_legacy_a" == *"SILENCE PROTOCOL"* ]] \
   && [[ "$e_upc_legacy_a" == "$e_upc_legacy_b" ]]; then
  pass "(e control) LEADV2_ANCHOR_OWNS_CONTEXT=0 re-enables the full legacy path, byte-identical across two independent runs"
else
  fail "(e control) legacy path missing content or non-reproducible: a=[$e_upc_legacy_a] b=[$e_upc_legacy_b]"
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
