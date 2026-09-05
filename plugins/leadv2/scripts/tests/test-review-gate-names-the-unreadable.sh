#!/usr/bin/env bash
# run-all-triggers: leadv2-review-run
#
# REVIEW-GATE-IS-MUTE-01 — a review gate has THREE outcomes per arm, not two:
# it passed, it failed, or **it could not be read**. The third was silent.
#
# Measured live on 2026-09-05, before any edit, with the real engine: two arms
# launched, one returned a clean `REVIEW_VERDICT: PASS`, the other returned a
# body with no parsable verdict at all. The gate wrote
#
#     arms: codex,glm
#     fanout: 2/2 degraded=false launched=2 pool_ok=2 ... reason=none
#     status: pass
#
# — it listed the mute arm as though it had contributed and asserted
# `degraded=false` about a review it could not read. That is not a gate that
# stays quiet; it is a gate that states something it never checked, and it lets
# a lane merge on one opinion believing it had two.
#
# WHAT IS REAL HERE. Every case runs the REAL leadv2-review-run.sh end to end
# against a real fixture repo, with real arm binaries whose stdout the engine
# captures. The fake is exactly one level lower — the reviewer processes.
# Nothing stubs parse_review_verdict, review_floor_ok, the arm loop or the gate
# writer, and no case inspects a variable: every assertion reads the
# review-gate.md the engine actually wrote, or the decision line it emitted.
#
# DECLARED NEGATIVE CONTROL (mutation-control/, tests/mutations/catalog.yaml),
# applied by REGEX to a line INSIDE the fan-out block's body:
#   REVIEW-GATE-CALLS-A-MUTE-ARM-HEALTHY  the unreadable list stops forcing
#     degraded=true, restoring the measured production bug. Kills (2).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS}/leadv2-review-run.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# ── arm stubs. The engine captures each arm's stdout as its review body, so a
#    stub is simply a reviewer that says a particular thing.
w(){ printf '%s' "$2" > "$T/$1"; chmod +x "$T/$1"; }
w arm-pass.sh '#!/usr/bin/env bash
printf "REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nI read the diff and it is fine.\n"
exit 0
'
# ran, rc 0, a body over the floor -- and no verdict the gate can establish.
# Not a pass and not a fail: could-not-verify.
w arm-mute.sh '#!/usr/bin/env bash
printf "I looked at the diff and I am not sure what to say about it.\nNo marker line anywhere in this body.\nthird line of prose\n"
exit 0
'
w arm-null.sh '#!/usr/bin/env bash
exit 0
'
# The glm arm is invoked as `<bin> run @mission --out <file> --cwd <root>` and
# writes its body to the --out path rather than to stdout (leadv2-review-run.sh,
# run_reviewer_arm). A stub that only prints would leave an EMPTY artifact, which
# the gate classifies as below_floor -- a different unreadable reason than the one
# these cases are about. So honour --out.
w glm-pass.sh '#!/usr/bin/env bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--out" ]] && { out="$2"; shift; }; shift; done
printf "REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nI read the diff and it is fine.\n" > "$out"
exit 0
'
w glm-mute.sh '#!/usr/bin/env bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--out" ]] && { out="$2"; shift; }; shift; done
printf "I looked at the diff and I am not sure what to say about it. The change touches error handling in a way that could be right or could be wrong depending on the caller, and I would want to see the caller before committing to a view.\nNo marker line anywhere in this body, and no findings block either, so there is nothing here a gate can turn into a verdict.\nThis body is deliberately well over the review floor: the point of this case is a reviewer that ANSWERED at length and still said nothing the gate can act on.\n" > "$out"
exit 0
'

# run_gate <tag> <codex bin> <other bin> <fanout> -> sets GATE, ERRF, RC
run_gate() {
  local tag="$1" cbin="$2" obin="$3" fan="$4"
  local root="$T/repo-$tag"; mkdir -p "$root/.claude/ref"
  local handoff="$root/docs/handoff/dispatch-$tag"; mkdir -p "$handoff"
  printf 'diff --git a/x b/x\n+hello\n' > "$handoff/review.diff"
  LEADV2_DISPATCH_CODEX_BIN="$T/$cbin" \
  LEADV2_DISPATCH_ARCHITECT_BIN="$T/arm-null.sh" \
  LEADV2_DISPATCH_GLM_BIN="$T/$obin" \
  LEADV2_DISPATCH_BIN="$T/arm-null.sh" \
  LEADV2_REVIEW_FANOUT="$fan" \
    timeout 200 bash "$ENGINE" --task "$tag" --root "$root" --handoff "$handoff" \
    --diff "$handoff/review.diff" --author sonnet >"$T/$tag.out" 2>"$T/$tag.err"
  RC=$?
  GATE="$handoff/review-gate.md"
  ERRF="$T/$tag.err"
}

# ── 1. THE MUTE ARM IS NAMED. Not "an arm failed" — which arm, and why.
run_gate MUTE arm-pass.sh glm-mute.sh 2
if grep -qE '^unreadable: .*=unparsable_verdict' "$GATE" 2>/dev/null; then
  ok "a mute arm is named on the gate with its reason ($(grep -m1 '^unreadable:' "$GATE"))"
else
  bad "1: no unreadable line — gate=[$(tr '\n' '|' < "$GATE" 2>/dev/null | cut -c1-200)]"
fi

# ── 2. THE ACTIVE LIE. `degraded=false` beside an arm the gate could not read
#      is not silence, it is an assertion about something never checked.
if grep -qE '^fanout: .*degraded=true' "$GATE" 2>/dev/null \
   && grep -qE '^fanout: .*reason=[^ ]*arms_unreadable' "$GATE" 2>/dev/null; then
  ok "an unreadable arm degrades the gate (degraded=true, reason names arms_unreadable)"
else
  bad "2: $(grep -m1 '^fanout:' "$GATE" 2>/dev/null | cut -c1-160)"
fi

# ── 3. NO SILENT POLICY CHANGE. Making the third state visible must not turn a
#      passing gate into a blocking one behind the founder's back. Whether an
#      unreadable arm should BLOCK is a separate decision with a far larger
#      blast radius; this row deliberately does not take it.
if [[ "$RC" == 0 ]] && grep -qE '^status: pass' "$GATE" 2>/dev/null; then
  ok "the verdict itself is unchanged: a readable PASS still passes (rc=0)"
else
  bad "3: rc=$RC status=$(grep -m1 '^status:' "$GATE" 2>/dev/null)"
fi

# ── 4. THE DECISION LINE CARRIES IT. A gate file nobody opens is not a signal;
#      the journal line is what a lead and the ledger actually read.
if grep -qE 'review_gate task=MUTE status=pass .*unreadable=[^ ]*unparsable_verdict' "$ERRF" 2>/dev/null; then
  ok "the pass decision carries unreadable= with the arm and reason"
else
  bad "4: $(grep -m1 'status=pass' "$ERRF" 2>/dev/null | cut -c1-160)"
fi

# ── 5. SILENCE IS NOT A VALUE. When every arm was read, the gate must SAY so —
#      otherwise a reader cannot tell "all read" from "we never looked".
run_gate CLEAN arm-pass.sh glm-pass.sh 2
if grep -qE '^unreadable: none$' "$GATE" 2>/dev/null \
   && grep -qE 'status=pass .*unreadable=none' "$ERRF" 2>/dev/null; then
  ok "a fully-readable fan-out says 'unreadable: none' rather than saying nothing"
else
  bad "5: gate=[$(grep -m1 '^unreadable:' "$GATE" 2>/dev/null)] decision=[$(grep -m1 'status=pass' "$ERRF" 2>/dev/null | cut -c1-120)]"
fi

# ── 6. THE ALREADY-CLOSED HALF STAYS CLOSED. When NO arm is readable the engine
#      already failed closed (REVIEW-ARM-FAILCLOSED-02). It must keep doing so,
#      and now name the same vocabulary as the partial case.
run_gate ALLMUTE arm-mute.sh glm-mute.sh 2
if [[ "$RC" == 6 ]] && grep -qE '^status: blocked' "$GATE" 2>/dev/null \
   && grep -qE '^unreadable: ' "$GATE" 2>/dev/null; then
  ok "no readable arm still blocks (rc=6) and now names the arms in the same vocabulary"
else
  bad "6: rc=$RC gate=[$(tr '\n' '|' < "$GATE" 2>/dev/null | cut -c1-160)]"
fi

printf '[REVIEW-GATE-NAMES-THE-UNREADABLE] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
