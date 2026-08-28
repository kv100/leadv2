#!/usr/bin/env bash
# test-gate1-discipline.sh — PHASE-DISCIPLINE-01 D4 coverage for
# leadv2-gate1-prompt.sh: Heavy/high-risk NEVER auto-accepts in any mode
# (DRY_RUN/BOT_MODE included), the async path is a BLOCKING leadv2-ask
# question with a decline default, Standard timeout auto-accept is journaled
# gate1_auto_accepted vs answered, and an accept RECORDS same-task
# classify/plan/gate1 under the admission receipt's sig8 (the Phase-4
# re-entry bridge).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GATE1_SRC="${PLUGIN_DIR}/scripts/leadv2-gate1-prompt.sh"
PHASE_RECORD="${PLUGIN_DIR}/scripts/leadv2-phase-record.sh"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Isolated plugin dir: gate1-prompt + a stub leadv1-ask sibling (resolved via
# dirname BASH_SOURCE) + the REAL phase-record sibling (the bridge target).
mkdir -p "$TMP/scripts" "$TMP/root/docs/handoff" "$TMP/root/.claude/scripts"
cp "$GATE1_SRC" "$TMP/scripts/leadv2-gate1-prompt.sh"
cp "$PHASE_RECORD" "$TMP/scripts/leadv2-phase-record.sh"
chmod +x "$TMP/scripts/"*.sh
# Stub ledger emitter at <root>/.claude/scripts/lv2-ledger-emit.py (where the
# gate looks first): records the payload json to $GATE1_LEDGER_OUT.
cat >"$TMP/root/.claude/scripts/lv2-ledger-emit.py" <<'EOF'
import os, sys
with open(os.environ.get("GATE1_LEDGER_OUT", "/dev/null"), "a") as fh:
    fh.write(sys.argv[1] + "\n")
EOF

make_ask_stub() { # $1=answer-to-print
  cat >"$TMP/scripts/leadv2-ask.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1"
EOF
  chmod +x "$TMP/scripts/leadv2-ask.sh"
}

seed_receipt() { # $1=task_id $2=sig8 -> admission receipt on disk
  mkdir -p "$TMP/root/docs/handoff/dispatch-$2"
  cat >"$TMP/root/docs/handoff/dispatch-$2/admission-receipt.yaml" <<EOF
receipt_v: 1
task_id: $1
mission_digest: 0000000000000000000000000000000000000000000000000000000000000000
task_class: Standard
route: phases
source: judge
work_kind: build
recorded_at: 2026-08-28T00:00:00Z
EOF
}

# ── 1. Standard daemon timeout: rc=2, ledger outcome gate1_auto_accepted ────
rm -f "$TMP/ledger.jsonl"
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_DAEMON=1 LEADV2_GATE1_AUTO_ACCEPT_SEC=0 \
    GATE1_LEDGER_OUT="$TMP/ledger.jsonl" \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T1 Standard "do the thing" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 2 ]] && pass "standard daemon: timeout auto-accept rc=2" || fail "standard daemon rc=$rc (want 2)"
grep -q 'gate1_auto_accepted' "$TMP/ledger.jsonl" 2>/dev/null \
  && pass "standard timeout journaled outcome=gate1_auto_accepted" || fail "ledger: $(cat "$TMP/ledger.jsonl" 2>/dev/null)"

# ── 2. Heavy + DRY_RUN: auto-accept modes are IGNORED ────────────────────────
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_DRY_RUN=1 GATE1_LEDGER_OUT=/dev/null \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T2 Heavy "big thing" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 1 ]] && pass "heavy+DRY_RUN: declined on EOF, NOT auto-accepted (rc=1)" \
  || fail "heavy+DRY_RUN rc=$rc (auto-accept modes must be ignored for heavy)"

# ── 3. high-risk Standard + BOT_MODE: ignored too ────────────────────────────
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_BOT_MODE=1 GATE1_LEDGER_OUT=/dev/null \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T3 Standard "touch payments" safety_publish_payments ) \
  </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 1 ]] && pass "risk=safety_publish_payments+BOT_MODE: NOT auto-accepted (rc=1)" \
  || fail "high-risk bot rc=$rc"

# ── 4. Heavy async: blocking leadv2-ask, decline default on timeout ─────────
make_ask_stub "go"
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_ASYNC_QUESTIONS=1 GATE1_LEDGER_OUT="$TMP/ledger2.jsonl" \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T4 Heavy "big thing" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && pass "heavy async: answered go -> accepted (rc=0)" || fail "heavy async go rc=$rc"
grep -q '"outcome":"answered"' "$TMP/ledger2.jsonl" 2>/dev/null \
  && pass "heavy async accept journaled outcome=answered" || fail "ledger2: $(cat "$TMP/ledger2.jsonl" 2>/dev/null)"
make_ask_stub "n"
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_ASYNC_QUESTIONS=1 GATE1_LEDGER_OUT=/dev/null \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T5 Heavy "big thing" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 1 ]] && pass "heavy async: default/decline -> rc=1 (timeout can never accept)" \
  || fail "heavy async decline rc=$rc"

# ── 5. Accept records same-task phases under the receipt's sig8 ──────────────
seed_receipt T6 cafef00d
mkdir -p "$TMP/root/docs/handoff/T6"
printf 'decisions:\n  - d1\noff_limits: []\nplan:\n  steps:\n    - s1\n' \
  >"$TMP/root/docs/handoff/T6/context.yaml"
make_ask_stub "go"
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_ASYNC_QUESTIONS=1 GATE1_LEDGER_OUT=/dev/null \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T6 Heavy "big thing" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && pass "gate T6 accepted via async go" || fail "gate T6 rc=$rc"
[[ -s "$TMP/root/docs/handoff/dispatch-cafef00d/.gate1-passed" ]] \
  && pass "non-empty gate1 sentinel mirrored under dispatch-<sig8>" || fail "sentinel not mirrored"
[[ -f "$TMP/root/docs/handoff/dispatch-cafef00d/phases.d/gate1.yaml" ]] \
  && pass "gate1 phase recorded under receipt sig8" || fail "gate1.yaml missing"
# THE re-entry proof: phase-record assert --pre-build passes for this sig8...
out="$(cd "$TMP/root" && LEADV2_PROJECT_ROOT="$TMP/root" bash "$PHASE_RECORD" assert cafef00d --class Standard --pre-build 2>/dev/null)"; prc=$?
[[ $prc -eq 0 ]] && pass "assert --pre-build passes after gate1 accept (Phase-4 re-entry admitted)" \
  || fail "pre-build assert rc=$prc out=$out"
# ...while a task with NO gate1 record is still refused (the enforcement core).
out="$(cd "$TMP/root" && LEADV2_PROJECT_ROOT="$TMP/root" bash "$PHASE_RECORD" assert deadbeef --class Standard --pre-build 2>/dev/null)"; prc=$?
[[ $prc -eq 3 ]] && pass "cold Standard without records refused (assert rc=3)" \
  || fail "cold assert rc=$prc out=$out"

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
