#!/usr/bin/env bash
# tests/test-gate1-async-route.sh — FORK-SESSION-SCRIPT-HAS-NO-SUITES-01.
#
# Covers leadv2-fork-session.sh's cmd_ask (H2: the pending Gate-1 question
# survives a retry). Fresh authoring against the current positional CLI --
# see test-fork-session-guard.sh's header for why the orphaned branch's
# suites are not ported.
#
# Tests:
#   1. bash -n syntax check.
#   2. a fresh ask writes a fork-ask record + a control-plane question
#      record (status: pending), then times out with exit 3 (bounded poll,
#      short LEADV2_FORK_ASK_POLL_SEC/LEADV2_ASK_POLL_INTERVAL for the test)
#      -- gate NOT passed, no answer manufactured.
#   3. re-invoking the SAME question polls the SAME qid: no second
#      question record is created.
#   4. once the control-plane record is answered (simulating /leadv2
#      reply), a re-invoke returns exit 0 with the chosen label on stdout,
#      and the fork-ask record is cleaned up (idempotent: the next question
#      starts clean).
#   5. a DIFFERENT question while one is genuinely pending is refused
#      (exit 1) without touching the pending record.
#   6. --cancel-pending withdraws the fork-ask record (but not the
#      question record itself) -- a fresh ask afterward is a new question.
#
# Run: bash scripts/tests/test-gate1-async-route.sh
# run-all-triggers: leadv2-fork-session

set -euo pipefail
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FS_SH="${SCRIPT_DIR}/../leadv2-fork-session.sh"
STATE_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$FS_SH" 2>/dev/null; then pass "syntax check"; else fail "syntax check"; fi

_new_sandbox() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "t@t.example"
  git -C "$d" config user.name "t"
  mkdir -p "$d/plugins/leadv2"
  printf '# plugin marker\n' > "$d/plugins/leadv2/.claude-plugin-marker"
  echo init > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}

_cproot() { PROJECT_ROOT="$1" bash "$STATE_SH" --no-link root; }

_answer_pending() { # <cproot> <task_id> <selected-label>
  local cp="$1" tid="$2" sel="$3" qid
  qid="$(grep '^qid:' "${cp}/fork-ask/${tid}.yaml" | awk '{print $2}')"
  python3 - "${cp}/questions/${qid}.yaml" "$sel" <<'PYEOF'
import sys, yaml
p, sel = sys.argv[1], sys.argv[2]
with open(p, encoding="utf-8") as f:
    d = yaml.safe_load(f)
d["status"] = "answered"
d["answer"] = {"selected": sel, "decided_by": "test", "answered_at": "2026-09-06T00:00:00Z"}
with open(p, "w", encoding="utf-8") as f:
    yaml.safe_dump(d, f, sort_keys=False, allow_unicode=True)
PYEOF
}

# ── Test 2: fresh ask writes records, times out with exit 3 ────────────────
d="$(_new_sandbox)"
out="$(LEADV2_PROJECT_ROOT="$d" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
  timeout 5 bash "$FS_SH" ask t1 "pick one" --option "a|opt a" --option "b|opt b" 2>"$d/.stderr")" && rc=0 || rc=$?
cp1="$(_cproot "$d")"
if [[ "$rc" -eq 3 ]] && [[ -f "${cp1}/fork-ask/t1.yaml" ]] && grep -q "^status: pending" "${cp1}"/questions/*.yaml 2>/dev/null; then
  pass "fresh ask: exit 3 (bounded poll timeout), fork-ask + pending question record written"
else
  fail "fresh ask (rc=$rc, fork-ask exists=$([[ -f "${cp1}/fork-ask/t1.yaml" ]] && echo yes || echo no))"
fi

# ── Test 3: same question re-polls the SAME qid ─────────────────────────────
qid_before="$(grep '^qid:' "${cp1}/fork-ask/t1.yaml" | awk '{print $2}')"
LEADV2_PROJECT_ROOT="$d" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
  timeout 5 bash "$FS_SH" ask t1 "pick one" --option "a|opt a" --option "b|opt b" >/dev/null 2>&1 && rc=0 || rc=$?
qid_after="$(grep '^qid:' "${cp1}/fork-ask/t1.yaml" | awk '{print $2}')"
nq="$(ls "${cp1}/questions/" | wc -l | tr -d ' ')"
if [[ "$rc" -eq 3 ]] && [[ "$qid_before" == "$qid_after" ]] && [[ "$nq" -eq 1 ]]; then
  pass "same question re-invoke polls the same qid, no second question record"
else
  fail "same-question re-poll (rc=$rc before=$qid_before after=$qid_after nq=$nq)"
fi

# ── Test 4: answered record -> exit 0 + label, fork-ask record cleaned up ──
_answer_pending "$cp1" t1 "a"
out="$(LEADV2_PROJECT_ROOT="$d" LEADV2_FORK_ASK_POLL_SEC=5 LEADV2_ASK_POLL_INTERVAL=1 \
  timeout 10 bash "$FS_SH" ask t1 "pick one" --option "a|opt a" --option "b|opt b" 2>/dev/null)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == "a" ]] && [[ ! -f "${cp1}/fork-ask/t1.yaml" ]]; then
  pass "answered record: exit 0 with the chosen label, fork-ask record cleaned up"
else
  fail "answered record (rc=$rc out='$out' record_gone=$([[ ! -f "${cp1}/fork-ask/t1.yaml" ]] && echo yes || echo no))"
fi

# ── Test 5: a DIFFERENT question while one is pending is refused ───────────
d2="$(_new_sandbox)"
LEADV2_PROJECT_ROOT="$d2" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
  timeout 5 bash "$FS_SH" ask t2 "question one" --option "a|opt a" >/dev/null 2>&1 && rc=0 || rc=$?
cp2="$(_cproot "$d2")"
LEADV2_PROJECT_ROOT="$d2" bash "$FS_SH" ask t2 "a totally different question" --option "x|opt x" \
  >/dev/null 2>"$d2/.stderr" && rc2=0 || rc2=$?
if [[ "$rc2" -eq 1 ]] && grep -qi "DIFFERENT Gate-1 question" "$d2/.stderr" \
   && [[ -f "${cp2}/fork-ask/t2.yaml" ]]; then
  pass "a different question while one is pending is refused, the pending record survives"
else
  fail "different-question refusal (rc2=$rc2 stderr='$(cat "$d2/.stderr" 2>/dev/null)')"
fi

# ── Test 6: --cancel-pending withdraws the fork-ask record ──────────────────
LEADV2_PROJECT_ROOT="$d2" bash "$FS_SH" ask t2 --cancel-pending >/dev/null 2>"$d2/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ ! -f "${cp2}/fork-ask/t2.yaml" ]]; then
  pass "--cancel-pending withdraws the fork-ask record"
else
  fail "--cancel-pending (rc=$rc record_gone=$([[ ! -f "${cp2}/fork-ask/t2.yaml" ]] && echo yes || echo no))"
fi
LEADV2_PROJECT_ROOT="$d2" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
  timeout 5 bash "$FS_SH" ask t2 "a fresh new question now" --option "y|opt y" >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]] && [[ -f "${cp2}/fork-ask/t2.yaml" ]]; then
  pass "after cancel, a fresh ask is treated as a genuinely new question"
else
  fail "post-cancel fresh ask (rc=$rc)"
fi

# ── Mutation control: the DIFFERENT-question refusal ────────────────────────
# Mutate the fingerprint comparison so ANY pending record is treated as "the
# same question" -- a genuinely different Gate-1 question would then be
# silently swallowed into polling the wrong qid instead of being refused.
MUTANT="${SCRIPT_DIR}/../.gate1-mutant-$$.sh"
trap 'rm -f "$MUTANT"' EXIT
cp "$FS_SH" "$MUTANT"
python3 - "$MUTANT" <<'PYEOF' && mutate_rc=0 || mutate_rc=$?
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '    elif [[ "$rec_fp" != "$fingerprint" ]]; then'
assert anchor in s, "mutation anchor not found: " + anchor
mutant = s.replace(anchor, '    elif [[ 1 -eq 0 ]]; then', 1)
assert mutant != s
open(p, "w", encoding="utf-8").write(mutant)
PYEOF
if [[ "$mutate_rc" -ne 0 ]]; then
  fail "mutation anchor not found in leadv2-fork-session.sh -- source drifted, control cannot run"
else
  pass "mutation landed inside cmd_ask's fingerprint-mismatch branch"

  d3="$(_new_sandbox)"
  LEADV2_PROJECT_ROOT="$d3" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
    timeout 5 bash "$MUTANT" ask t3 "question one" --option "a|opt a" >/dev/null 2>&1 && true || true
  LEADV2_PROJECT_ROOT="$d3" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
    timeout 5 bash "$MUTANT" ask t3 "a totally different question" --option "x|opt x" \
    >/dev/null 2>"$d3/.stderr" && mrc=0 || mrc=$?
  if [[ "$mrc" -eq 3 ]]; then
    pass "RED with the mutation: a different question is silently polled instead of refused (exit 3, not 1)"
  else
    fail "RED with the mutation: expected exit 3 (silently swallowed), got rc=$mrc"
  fi

  d4="$(_new_sandbox)"
  LEADV2_PROJECT_ROOT="$d4" LEADV2_FORK_ASK_POLL_SEC=1 LEADV2_ASK_POLL_INTERVAL=1 \
    timeout 5 bash "$FS_SH" ask t4 "question one" --option "a|opt a" >/dev/null 2>&1 && true || true
  LEADV2_PROJECT_ROOT="$d4" bash "$FS_SH" ask t4 "a totally different question" --option "x|opt x" \
    >/dev/null 2>"$d4/.stderr" && grc=0 || grc=$?
  if [[ "$grc" -eq 1 ]]; then
    pass "GREEN without the mutation: the real script still refuses the different question"
  else
    fail "GREEN regreen: expected rc=1, got $grc"
  fi
fi

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
