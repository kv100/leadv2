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

# T15 R3 (V2): leadv2-task-anchor.sh's full-anchor path shells out to
# leadv2-journal.sh via os.path.expanduser("~/.claude/.../leadv2-journal.sh")
# (task-anchor.sh:956-958) whenever it builds the journal-tail lines. Without
# isolating HOME, this suite would probe (and possibly execute) whatever
# real ~/.claude tree the CI/dev machine happens to have — not hermetic, and
# a source of flakiness across machines. Point HOME at an empty fixture dir
# for the rest of this suite so neither candidate path exists and the
# journal-tail lookup deterministically no-ops.
#
# Caveat discovered while wiring this up: leadv2-task-anchor.sh's load_yaml()
# soft-imports PyYAML and silently degrades to {} without it (by design, for
# machines that lack it) — and on this machine PyYAML only resolves via the
# REAL HOME's user site-packages (`python3 -c "import site;
# print(site.getusersitepackages())"`), not a system/venv install. A bare
# HOME swap therefore made every active.yaml read return {} and the whole
# suite silently fall through to the no-active-task thread-anchor path — a
# false pass waiting to happen, not a hermetic run. Compute the real site dir
# BEFORE overriding HOME and keep it importable via PYTHONPATH so the fixture
# HOME isolates the journal-script lookup ONLY, without also gutting YAML.
REAL_USER_SITE="$(python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || true)"
FIXTURE_HOME="$ROOT/home"
mkdir -p "$FIXTURE_HOME"
export HOME="$FIXTURE_HOME"
if [[ -n "$REAL_USER_SITE" ]]; then
  export PYTHONPATH="${REAL_USER_SITE}${PYTHONPATH:+:${PYTHONPATH}}"
fi
if ! python3 -c "import yaml" 2>/dev/null; then
  fail "harness precondition: PyYAML not importable under fixture HOME + PYTHONPATH shim — active.yaml reads would silently degrade to {}"
fi

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
# no-op.
#
# T15 R3 (V3): comparing two LIVE executions of the CURRENT script against
# each other (the previous form of this control) only proves determinism —
# it cannot catch a regression that changed the legacy path's OUTPUT itself,
# because both sides run the same (possibly-broken) code. The true golden
# is the pre-T15 hook body at base 9e9677b (the commit this fix-round
# branched from, before ANCHOR_OWNS_CONTEXT=0 handling was touched): pull
# that exact file out of git history into a temp copy and execute THAT as
# the reference implementation, then byte-compare its output against the
# CURRENT script's output for LEADV2_ANCHOR_OWNS_CONTEXT=0. A genuine
# regression in the legacy path now shows up as a diff against real
# pre-change behavior, not just non-determinism.
#
# To refresh the golden after an intentional legacy-path change: bump
# GOLDEN_BASE_REV below to the new base commit and re-run this suite —
# no separate regeneration step, the golden is derived live from git.
GOLDEN_BASE_REV="9e9677b"
# leadv2-user-prompt-context.sh sources leadv2-mode-isolation.sh via a path
# relative to its OWN dirname — so the golden copy needs its sibling from
# the same rev alongside it, not just the one file, or the source line fails.
GOLDEN_DIR="$ROOT/upc-golden-${GOLDEN_BASE_REV}"
mkdir -p "$GOLDEN_DIR"
GOLDEN_UPC="$GOLDEN_DIR/leadv2-user-prompt-context.sh"
if ! git -C "$PLUGIN_ROOT" show "${GOLDEN_BASE_REV}:plugins/leadv2/hooks/leadv2-user-prompt-context.sh" > "$GOLDEN_UPC" 2>/dev/null \
   || ! git -C "$PLUGIN_ROOT" show "${GOLDEN_BASE_REV}:plugins/leadv2/hooks/leadv2-mode-isolation.sh" > "$GOLDEN_DIR/leadv2-mode-isolation.sh" 2>/dev/null; then
  fail "(e control) could not extract golden $GOLDEN_BASE_REV hook pair from git history"
else
  chmod +x "$GOLDEN_UPC"
  run_golden_upc() {
    local sid="$1"
    LEADV2_TASK_ID="t15-fixture" LEADV2_ANCHOR_OWNS_CONTEXT="0" \
      bash "$GOLDEN_UPC" <<<"$(payload "$sid")"
  }
  e_upc_legacy_current="$(run_upc "${e_sid}-legacy-current" "0" 2>/dev/null || true)"
  e_upc_legacy_golden="$(run_golden_upc "${e_sid}-legacy-golden" 2>/dev/null || true)"
  if [[ "$e_upc_legacy_current" == *"[LEADV2_ACTIVE]"* ]] \
     && [[ "$e_upc_legacy_current" == *"[ORCHESTRATOR_ROLE]"* ]] \
     && [[ "$e_upc_legacy_current" == *"SILENCE PROTOCOL"* ]] \
     && [[ "$e_upc_legacy_current" == "$e_upc_legacy_golden" ]]; then
    pass "(e control) LEADV2_ANCHOR_OWNS_CONTEXT=0 legacy path byte-identical to the checked-in ${GOLDEN_BASE_REV} golden"
  else
    fail "(e control) legacy path diverges from ${GOLDEN_BASE_REV} golden: current=[$e_upc_legacy_current] golden=[$e_upc_legacy_golden]"
  fi
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
