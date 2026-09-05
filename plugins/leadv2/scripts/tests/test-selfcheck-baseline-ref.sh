#!/usr/bin/env bash
# GATE-BLOCKS-ON-BASE-RED-UNLISTABLE-SUITES-01 — the inherited-red classifier must
# read a baseline that EXISTS, and must keep charging the lane for its own red.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-builder-selfcheck
#
# WHY THIS SUITE EXISTS SEPARATELY. test-builder-selfcheck-gate.sh drives the whole
# gate, but every fixture it builds is a fresh repo with NO `origin` remote — so
# `merge-base HEAD origin/main` is empty there and both orderings of the baseline
# lookup behave identically. It therefore cannot tell a stale reference from a
# fresh one, and the mutation below would survive it. Measured, not assumed: the
# gate suite is 38/0 either way. This suite builds the one shape that separates
# them — a repo whose origin/main is deliberately BEHIND local main.
#
# WHAT IS REAL HERE. The production `_selfcheck_baseline_verdict` body is lifted
# out of lib/leadv2-builder-selfcheck.sh and sourced with the same closure
# variables the real caller sets. Nothing about its logic is restated here.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the baseline lookup's
# first line reverts to `origin/main`, restoring the stale reference. Kills (a).
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LIB="${ROOT}/scripts/lib/leadv2-builder-selfcheck.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

python3 - "$LIB" "$T/verdict.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('  _selfcheck_baseline_verdict() {')
end = s.index('\n  }\n', start) + 4
open(sys.argv[2], 'w').write(s[start:end].replace('\n  ', '\n').lstrip())
PY

# The closure the real caller provides. _lv2_selfcheck_timeout_run is the lib's own
# bounded runner; here it is the one collaborator we fake, to a plain bash call.
baseline_on=1; timeout_s=60; depth=0
# real call shape: <timeout_s> <logfile> -- <cmd...>; drop the first three and run the rest.
_lv2_selfcheck_timeout_run() { shift 3; "$@"; }
source "$T/verdict.sh"

# A repo whose origin/main is a real remote branch left BEHIND local main -- the
# shape our own working agreement produces, since we deliberately do not push.
git init -q "$T/up"; git -C "$T/up" config user.email t@e; git -C "$T/up" config user.name t
mkdir -p "$T/up/tests"; printf 'seed\n' > "$T/up/seed"
git -C "$T/up" add -A; git -C "$T/up" commit -qm seed
git clone -q "$T/up" "$T/repo"; git -C "$T/repo" config user.email t@e; git -C "$T/repo" config user.name t
# Two suites added AFTER the last push: one red for reasons that have nothing to do
# with any lane, one green. Neither exists at origin/main.
mkdir -p "$T/repo/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/repo/tests/inherited-red.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/repo/tests/inherited-green.sh"
git -C "$T/repo" add -A; git -C "$T/repo" commit -qm "suites added since the last push"
diff_root="$T/repo"

# (a) THE DEFECT. A suite that is red on current main and absent from the stale
# origin/main must be attributed to main, not to the builder.
_baseline_dir=""; _baseline_tried=0; _baseline_ok=0; _baseline_base=""
A="$(_selfcheck_baseline_verdict tests/inherited-red.sh)"
if [[ "$A" == "SKIP_RED" ]]; then
  ok "a suite red on local main is inherited, not charged to the lane (SKIP_RED)"
else
  bad "a: got '$A', wanted SKIP_RED (stale baseline turns an inherited red into a lane fault)"
fi

# (b) PAIRED NEGATIVE, the one that matters. A suite that PASSES on the baseline is
# the lane's own red and must still block. If this ever flips, the fix stopped being
# a reference correction and became a hole.
_baseline_dir=""; _baseline_tried=0; _baseline_ok=0; _baseline_base=""
B="$(_selfcheck_baseline_verdict tests/inherited-green.sh)"
if [[ "$B" == "FAIL" ]]; then
  ok "a suite green on the baseline is still the lane's own red (FAIL)"
else
  bad "b: got '$B', wanted FAIL"
fi

# (c) a suite the LANE introduces has no baseline copy at all and must still block --
# a lane's own new suite has to be green.
_baseline_dir=""; _baseline_tried=0; _baseline_ok=0; _baseline_base=""
C="$(_selfcheck_baseline_verdict tests/never-existed.sh)"
if [[ "$C" == "FAIL" ]]; then
  ok "a suite with no baseline copy still blocks (FAIL)"
else
  bad "c: got '$C', wanted FAIL"
fi

# (d) the explicit off switch must still mean "lane red is a lane fault, full stop".
baseline_on=0
_baseline_dir=""; _baseline_tried=0; _baseline_ok=0; _baseline_base=""
D="$(_selfcheck_baseline_verdict tests/inherited-red.sh)"
baseline_on=1
if [[ "$D" == "FAIL" ]]; then
  ok "LEADV2_BUILDER_SELFCHECK_BASELINE=0 still charges every red to the lane"
else
  bad "d: got '$D', wanted FAIL"
fi

printf '[SELFCHECK-BASELINE-REF] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
