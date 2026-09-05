#!/usr/bin/env bash
# LANE-WRITES-SILENTLY-DROPS-REAL-TOP-LEVEL-DIRS-01 — a rejected write-set entry
# must be NAMED, and rejection must stay rejection.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-code
#
# WHAT IS REAL HERE. The suite lifts the production `_prepass_writes` body out of
# leadv2-dispatch-code.sh and sources it, the same way test-plan-in-lane.sh lifts
# _deliver_plan_into_lane. Only `_prepass_file` (which resolves the artifact path)
# is faked, so every accept/reject decision under test is the real one.
#
# WHY THIS EXISTS. L12 drops an entry that is wildcard-free, slash-free and an
# existing directory under the work root, as an over-broad synonym for the whole
# tree. `scripts/` normalises to `scripts` and is dropped; `scripts/*` — the
# IDENTICAL set, spelled differently — is kept. The drop was silent, so an author
# who declared correctly got `no_lane_writes`, i.e. "you declared nothing": the
# accusation landed on the author while the parser had thrown the entries away.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml). In _prepass_writes,
# `dropped+=("${entry}=bare_existing_dir")` reverts to a bare `continue`, which
# restores the silence. Kills (a) and (d) and leaves (b),(c) green — which is the
# point of the pair: (c) is what proves the fix did not simply disable the check.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

python3 - "$DISPATCH" "$T/prepass-writes.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_prepass_writes() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/prepass-writes.sh"

# WORK_ROOT must contain a REAL directory named like the entry, or the case under
# test cannot fire at all — that existence is the whole trigger for L12.
mkdir -p "$T/work/scripts" "$T/work/tests" "$T/art"
WORK_ROOT="$T/work"
_prepass_file() { printf '%s/%s.md' "$T/art" "$1"; }

decl(){ printf 'LANE_WRITES: %s\n' "$1" > "$T/art/$2.md"; }
noline(){ printf 'no declaration here at all\n' > "$T/art/$1.md"; }

# (a) the reported defect: a correctly-scoped subdirectory, declared with a slash.
decl 'scripts/, tests/' A
A_KEPT="$(_prepass_writes A)"; A_DROP="$(_prepass_writes A dropped)"
if [[ -z "$A_KEPT" && "$A_DROP" == *"scripts/=bare_existing_dir"* && "$A_DROP" == *"tests/=bare_existing_dir"* ]]; then
  ok "a bare existing dir is still rejected, and BOTH rejected entries are named"
else
  bad "a: kept='$A_KEPT' dropped='$A_DROP'"
fi

# (b) the remedy the refusal now prints must actually work — otherwise the advice
# is as misleading as the silence was. Same set, different spelling, kept.
decl 'scripts/*, tests/*' B
B_KEPT="$(_prepass_writes B)"; B_DROP="$(_prepass_writes B dropped)"
if [[ "$B_KEPT" == "scripts/*,tests/*" && -z "$B_DROP" ]]; then
  ok "the spelling the refusal recommends is kept, and nothing is reported dropped"
else
  bad "b: kept='$B_KEPT' dropped='$B_DROP'"
fi

# (c) THE MANDATORY PAIRED NEGATIVE. A mission with no LANE_WRITES line at all must
# still yield an empty write set AND an empty dropped list — the two are different
# events and naming one must not have turned the check off for the other.
noline C
C_KEPT="$(_prepass_writes C)"; C_DROP="$(_prepass_writes C dropped)"
if [[ -z "$C_KEPT" && -z "$C_DROP" ]]; then
  ok "a mission with no LANE_WRITES line still declares nothing, with nothing named"
else
  bad "c: kept='$C_KEPT' dropped='$C_DROP'"
fi

# (d) the entry L12 was actually written against stays rejected, and is named too.
decl '**/*' D
D_KEPT="$(_prepass_writes D)"; D_DROP="$(_prepass_writes D dropped)"
if [[ -z "$D_KEPT" && "$D_DROP" == *"**/*=whole_tree"* ]]; then
  ok "a whole-tree synonym is still rejected and named as such"
else
  bad "d: kept='$D_KEPT' dropped='$D_DROP'"
fi

# (e) a mixed declaration must not lose its good half — rejection is per entry.
decl 'scripts/, plugins/leadv2/scripts/*' E
E_KEPT="$(_prepass_writes E)"; E_DROP="$(_prepass_writes E dropped)"
if [[ "$E_KEPT" == "plugins/leadv2/scripts/*" && "$E_DROP" == "scripts/=bare_existing_dir" ]]; then
  ok "a mixed declaration keeps its valid entry and names only the rejected one"
else
  bad "e: kept='$E_KEPT' dropped='$E_DROP'"
fi

printf '[LANE-WRITES-REJECTION-IS-NAMED] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
