#!/usr/bin/env bash
# PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01 — one refusal names the whole contract,
# and a record that is knowably dead on arrival refuses instead of being written.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-phase-record leadv2-dispatch-code.sh
#
# WHAT IS REAL HERE. Every case drives the real leadv2-phase-record.sh CLI
# (record / assert / show) against a real phases.d store on disk, in a scratch
# PROJECT_ROOT. Nothing stubs cmd_assert, cmd_record, _phase_satisfied or
# _verify_artifact; the only thing faked is the project root the CLI reads.
#
# DECLARED NEGATIVE CONTROLS (mutation-control/, tests/mutations/catalog.yaml).
# Both are applied by REGEX to a line INSIDE a function body — never by line
# number, which lands at top level and reddens everything for the wrong reason.
#
#   PHASE-GATE-NAMES-ONLY-ITS-OWN-SCOPE
#     in cmd_assert(): the full-contract resolve `... "$writes" full` is
#     narrowed back to `... "$writes" "$scope"`, so required=/unmet= shrink to
#     the scoped set and the gate is piecemeal again. Kills (a1),(a4).
#
#   PHASE-RECORD-WRITES-THE-DEAD-RECORD-ANYWAY
#     in cmd_record(): the artifact-integrity refusal's `exit 5` becomes
#     `_proof="unverified"`, restoring the write-it-and-warn behaviour.
#     Kills (b1),(b2),(b5).
#
# NOT covered here, and named rather than implied: "no phase is verified twice
# per assert". _verify_artifact is not a pure predicate for review (it adopts a
# ledger sidecar and journals tamper events), so a two-pass implementation
# changes its own answer. There is no seam to count invocations through from
# outside the CLI, so this suite cannot assert it directly. It is guarded, and
# was actually caught, by test-phase-precondition.sh's G7 block: the two-pass
# version turned G7b/c/e/f/g and G9a red on 2026-09-05.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PHASE_RECORD="${SCRIPTS_DIR}/leadv2-phase-record.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

newroot(){ local d; d="$(mktemp -d)"; mkdir -p "$d/docs/handoff"; printf '%s\n' "$d"; }
pr(){ local root="$1"; shift; LEADV2_PROJECT_ROOT="$root" bash "$PHASE_RECORD" "$@"; }
line_of(){ printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }
# is every element of csv $1 present in csv $2 ?
subset_of(){
  local a b x
  a="$1"; b=",$2,"
  for x in $(printf '%s' "$a" | tr ',' ' '); do
    [[ "$b" == *",$x,"* ]] || return 1
  done
  return 0
}

# ═══════════════════════════════════════ defect 1: name everything at once ═══
R1="$(newroot)"
pr "$R1" record P1 classify --status done >/dev/null 2>&1
PRE_OUT="$(pr "$R1" assert P1 --class Standard --pre-build 2>&1)"; PRE_RC=$?
PRE_MISSING="$(line_of missing "$PRE_OUT")"
PRE_REQUIRED="$(line_of required "$PRE_OUT")"
PRE_UNMET="$(line_of unmet "$PRE_OUT")"

# (a1) THE RULE. The refusal is scoped, but it names the class's whole contract.
if [[ "$PRE_RC" -eq 3 && "$PRE_MISSING" == "plan,gate1" ]] \
   && subset_of "build,test,review,close" "$PRE_REQUIRED"; then
  ok "a scoped refusal names the class's FULL mandatory contract (missing=$PRE_MISSING required=$PRE_REQUIRED)"
else
  bad "a1: rc=$PRE_RC missing=$PRE_MISSING required=$PRE_REQUIRED"
fi

# (a2) The extra facts are on their OWN lines. A dozen cases in
# test-phase-precondition.sh match the refusal with an unanchored
# `grep 'missing=.*review'` and five assert its NEGATIVE, so `review` appearing
# on the missing= line merely because it is mandatory would silently invert them.
if [[ "$PRE_MISSING" != *review* ]] && [[ "$PRE_REQUIRED" == *review* ]]; then
  ok "required= rides on its own line: a merely-mandatory phase never lands in missing="
else
  bad "a2: missing=$PRE_MISSING must not carry a phase that is only mandatory"
fi

# (a3) unmet= is what is still outstanding across that whole contract — a
# superset of the scoped missing set, and the honest answer to "what is left".
if subset_of "$PRE_MISSING" "$PRE_UNMET" && subset_of "build,test,review,close" "$PRE_UNMET"; then
  ok "unmet= spans the whole contract, not just this scope (unmet=$PRE_UNMET)"
else
  bad "a3: unmet=$PRE_UNMET should contain missing=$PRE_MISSING and the later phases"
fi

# (a4) THE CONSEQUENCE THE DEFECT COST TWO MINUTES A TIME. Whatever the LATER,
# full-scope refusal will name must already have been named by the FIRST,
# pre-build refusal. No phase may be discovered by re-dispatching.
FULL_OUT="$(pr "$R1" assert P1 --class Standard 2>&1)"
FULL_MISSING="$(line_of missing "$FULL_OUT")"
if subset_of "$FULL_MISSING" "$PRE_REQUIRED"; then
  ok "nothing the later full-scope refusal names is new (full missing=$FULL_MISSING)"
else
  bad "a4: full-scope refusal names phases the first refusal never mentioned (full=$FULL_MISSING first-required=$PRE_REQUIRED)"
fi

# (a5) The bootstrap admission — the very first thing a fresh lane ever sees —
# names the contract too, so the whole set is known before any work is done.
R2="$(newroot)"
BOOT_OUT="$(pr "$R2" assert P2 --class Standard --pre-build 2>&1)"; BOOT_RC=$?
if [[ "$BOOT_RC" -eq 0 && "$BOOT_OUT" == *admitted=bootstrap* ]] \
   && subset_of "build,test,review,close" "$(line_of required "$BOOT_OUT")"; then
  ok "the bootstrap admission names the full contract before any work is done"
else
  bad "a5: rc=$BOOT_RC out=$(printf '%s' "$BOOT_OUT" | tr '\n' ' ')"
fi

# ═════════════════════════════ defect 2: a dead-on-arrival record refuses ════
R3="$(newroot)"
pr "$R3" record P3 classify --status done >/dev/null 2>&1
mkdir -p "$R3/build-dir"

# (b1) An artifact that cannot be hashed is decidable NOW and never becomes
# valid later. Refuse, and write nothing.
B1_RC=0; pr "$R3" record P3 build --status done --artifact build-dir >/dev/null 2>&1 || B1_RC=$?
if [[ "$B1_RC" -eq 5 && ! -e "$R3/docs/handoff/dispatch-P3/phases.d/build.yaml" ]]; then
  ok "an unhashable artifact refuses (rc=5) and writes nothing"
else
  bad "b1: rc=$B1_RC file_exists=$([[ -e "$R3/docs/handoff/dispatch-P3/phases.d/build.yaml" ]] && echo yes || echo no)"
fi

# (b2) Same for an artifact that is simply not there.
B2_RC=0; pr "$R3" record P3 test --status done --artifact docs/handoff/nope.txt >/dev/null 2>&1 || B2_RC=$?
if [[ "$B2_RC" -eq 5 && ! -e "$R3/docs/handoff/dispatch-P3/phases.d/test.yaml" ]]; then
  ok "a missing artifact refuses (rc=5) and writes nothing"
else
  bad "b2: rc=$B2_RC"
fi

# (b3) THE NARROWING, and it is not optional. Verification at write time is a
# different question from verification at assert time: record-review writes the
# phase record and its provenance ledger row in one flow, so a record whose
# artifact is REAL but whose remaining evidence has not landed yet must still be
# written. Refusing this class broke six green cases on 2026-09-05.
printf 'real build output\n' > "$R3/build-out.txt"
B3_RC=0; pr "$R3" record P3 build --status done --artifact build-out.txt >/dev/null 2>&1 || B3_RC=$?
if [[ "$B3_RC" -eq 0 ]] && grep -q '^proof: unverified' "$R3/docs/handoff/dispatch-P3/phases.d/build.yaml" 2>/dev/null; then
  ok "a real artifact whose other evidence has not landed is still recorded, stamped unverified"
else
  bad "b3: rc=$B3_RC yaml=$(cat "$R3/docs/handoff/dispatch-P3/phases.d/build.yaml" 2>/dev/null | tr '\n' ' ')"
fi

# (b4) classify and diverge are the phases assert does not verify, so they are
# the phases this refusal must never touch. cmd_resolve records classify on
# every single dispatch; refusing it would refuse every lane.
B4_RC=0; pr "$R3" record P3 diverge --status done >/dev/null 2>&1 || B4_RC=$?
if [[ "$B4_RC" -eq 0 && -e "$R3/docs/handoff/dispatch-P3/phases.d/diverge.yaml" ]]; then
  ok "classify/diverge are never refused (assert does not verify them either)"
else
  bad "b4: diverge record rc=$B4_RC"
fi

# (b5) WHY WRITING IT WAS WORSE THAN NOTHING. A lane's bootstrap grace is "this
# lane has no phase record at all". Writing an unprovable record ends that grace
# without satisfying anything — it converts a lane that would have been admitted
# into one that is refused. A refusal must leave the grace intact.
R4="$(newroot)"
mkdir -p "$R4/plan-dir"
B5_RC=0; pr "$R4" record P4 plan --status done --artifact plan-dir >/dev/null 2>&1 || B5_RC=$?
B5_OUT="$(pr "$R4" assert P4 --class Standard --pre-build 2>&1)"; B5_ARC=$?
if [[ "$B5_RC" -eq 5 && "$B5_ARC" -eq 0 && "$B5_OUT" == *admitted=bootstrap* ]]; then
  ok "a refused record leaves the lane's bootstrap grace intact"
else
  bad "b5: record rc=$B5_RC assert rc=$B5_ARC out=$(printf '%s' "$B5_OUT" | tr '\n' ' ')"
fi

rm -rf "$R1" "$R2" "$R3" "$R4"
printf '[PHASE-GATE-NAMES-EVERYTHING] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
