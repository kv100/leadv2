#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-gate1-prompt
# test-gate1-discipline.sh — PHASE-DISCIPLINE-01 D4 coverage for
# leadv2-gate1-prompt.sh: Heavy/high-risk NEVER auto-accepts in any mode
# (DRY_RUN/BOT_MODE included), the async path is a BLOCKING leadv2-ask
# question with a decline default, Standard timeout auto-accept is journaled
# gate1_auto_accepted vs answered, and an accept RECORDS same-task
# classify/plan/gate1 under the admission receipt's sig8 (the Phase-4
# re-entry bridge).
#
# Negative control (C3b): section 5's foreign-task control depends on
# leadv2_admission_find_receipt_for_task's `task_id` equality check in its
# receipt-scan predicate. The suite applies that exact mutation (dropping the
# task_id match) to a temp copy of the lib and asserts the join breaks —
# proving the control isn't a tautology.
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
mkdir -p "$TMP/scripts/lib" "$TMP/root/docs/handoff" "$TMP/root/.claude/scripts"
cp "$GATE1_SRC" "$TMP/scripts/leadv2-gate1-prompt.sh"
cp "$PHASE_RECORD" "$TMP/scripts/leadv2-phase-record.sh"
cp "${PLUGIN_DIR}/scripts/lib/leadv2-admission-class.sh" "$TMP/scripts/lib/leadv2-admission-class.sh"
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

seed_receipt() { # $1=task_id $2=intake mission -> stdout sig8
  local tid="$1" intake="$2" digest sig8
  digest="$(printf '%s' "$intake" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}')"
  sig8="${digest:0:8}"
  mkdir -p "$TMP/root/docs/handoff/dispatch-$sig8"
  cat >"$TMP/root/docs/handoff/dispatch-$sig8/admission-receipt.yaml" <<EOF
receipt_v: 1
task_id: $tid
mission_digest: $digest
task_class: Standard
route: phases
source: judge
work_kind: build
recorded_at: 2026-08-28T00:00:00Z
EOF
  printf '%s\n' "$sig8"
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

# ── 5. A real intake-to-build join uses the receipt's TASK ID, not a matching
# digest. The Gate-1 call below passes T6_BUILD — a BUILD-phase mission whose
# digest is deliberately different from the T6_INTAKE text used to seed the
# receipt — as the plan_summary. _gate1_accept resolves the receipt via
# leadv2_admission_find_receipt_for_task(root, task_id), which matches on
# task_id alone; it never re-derives sig8 from plan_summary. So if the join
# were (wrongly) keyed on a digest of the CURRENT mission text instead of the
# task_id, this call would fail to find T6's receipt and every assertion below
# would go red.
T6_INTAKE='intake: refactor the billing worker safely'
T6_BUILD='build: implement the approved billing-worker refactor with tests'
T6_SIG8="$(seed_receipt T6 "$T6_INTAKE")"
mkdir -p "$TMP/root/docs/handoff/T6"
printf 'decisions:\n  - d1\noff_limits: []\nplan:\n  steps:\n    - s1\n' \
  >"$TMP/root/docs/handoff/T6/context.yaml"
make_ask_stub "go"
( cd "$TMP" && LEADV2_PROJECT_ROOT="$TMP/root" LEADV2_ASYNC_QUESTIONS=1 GATE1_LEDGER_OUT=/dev/null \
    bash "$TMP/scripts/leadv2-gate1-prompt.sh" T6 Heavy "$T6_BUILD" ) </dev/null >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && pass "gate T6 accepted via async go (build-phase mission, digest differs from intake)" || fail "gate T6 rc=$rc"
[[ -s "$TMP/root/docs/handoff/dispatch-${T6_SIG8}/.gate1-passed" ]] \
  && pass "non-empty gate1 sentinel mirrored under dispatch-<sig8>" || fail "sentinel not mirrored"
[[ -f "$TMP/root/docs/handoff/dispatch-${T6_SIG8}/phases.d/gate1.yaml" ]] \
  && pass "gate1 phase recorded under receipt sig8" || fail "gate1.yaml missing"
# THE re-entry proof: records are keyed by the real receipt digest, even though
# the build mission has a different digest.
out="$(cd "$TMP/root" && LEADV2_PROJECT_ROOT="$TMP/root" bash "$PHASE_RECORD" assert "$T6_SIG8" --class Standard --pre-build 2>/dev/null)"; prc=$?
[[ $prc -eq 0 ]] && pass "real intake receipt sig8 passes after Gate-1 accept" \
  || fail "pre-build assert rc=$prc out=$out"
# ...while a task with NO gate1 record is still refused (the enforcement core).
out="$(cd "$TMP/root" && LEADV2_PROJECT_ROOT="$TMP/root" bash "$PHASE_RECORD" assert deadbeef --class Standard --pre-build 2>/dev/null)"; prc=$?
[[ $prc -eq 3 ]] && pass "cold Standard without records refused (assert rc=3)" \
  || fail "cold assert rc=$prc out=$out"

# CONTROL: a different task's receipt must NOT satisfy T6's join. Seed a
# second intake receipt for task T7 and confirm leadv2_admission_find_receipt_
# for_task resolves T7 to its OWN (different) sig8 — never T6's — so a
# foreign task's Gate-1 records can never be mistaken for this task's pass.
T7_SIG8="$(seed_receipt T7 'intake: unrelated task about search indexing')"
[[ "$T7_SIG8" != "$T6_SIG8" ]] && pass "control: T7 receipt sig8 differs from T6's" \
  || fail "control: sig8 collision between T6 and T7"
out="$(cd "$TMP/root" && LEADV2_PROJECT_ROOT="$TMP/root" bash "$PHASE_RECORD" assert "$T7_SIG8" --class Standard --pre-build 2>/dev/null)"; prc=$?
[[ $prc -eq 3 ]] && pass "control: T7 receipt (no gate1 recorded) refused despite T6 having passed" \
  || fail "control: T7 assert rc=$prc out=$out (T6's pass leaked to T7)"

# NEGATIVE CONTROL (C3b): named mutation this suite must kill —
# leadv2_admission_find_receipt_for_task's `d.get("task_id") == task_id` join
# predicate. If dropped, ANY single valid receipt on disk (e.g. T7's) would
# satisfy a lookup for T6, and the control above would go GREEN when it must
# be RED. Apply the mutation to a temp copy of the admission-class lib and
# assert find_receipt_for_task("T6") wrongly resolves to T7's sig8 (proving
# the mutation breaks the join the way the control depends on).
MUT_LIB="$TMP/scripts/lib/leadv2-admission-class.mut.sh"
python3 - "${PLUGIN_DIR}/scripts/lib/leadv2-admission-class.sh" "$MUT_LIB" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = 'if (d.get("task_id") == task_id and re.fullmatch(r"[0-9a-f]{64}", digest)'
new = 'if (True and re.fullmatch(r"[0-9a-f]{64}", digest)'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
mut_status=$?
if [[ $mut_status -ne 0 ]]; then
  fail "control: mutation source pattern not found (lib drifted, update mutation)"
else
  # shellcheck disable=SC1090
  source "$MUT_LIB"
  mut_row="$(leadv2_admission_find_receipt_for_task "$TMP/root" T6 2>/dev/null)"
  # With the task_id check dropped, >1 receipt exists (T6, T7) so the
  # `len(rows) != 1` guard now trips and returns rc=1/empty (a DIFFERENT
  # break than "wrongly matches T7", but still proves the join predicate is
  # load-bearing: removing it changes find_receipt_for_task's behaviour from
  # "resolves exactly T6" to "cannot resolve anything").
  [[ -z "$mut_row" ]] && pass "control: mutated join (task_id check removed) no longer resolves T6 uniquely — mutation caught" \
    || fail "control: mutated lib still resolved T6 correctly (mut_row=$mut_row) — mutation NOT caught"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
