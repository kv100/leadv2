#!/usr/bin/env bash
# GLM-FAILED-TWICE-UNREACHABLE-01 — the escalation is unreachable from this flag ON
# PURPOSE, and the cap that makes it so had no test at all.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-code
#
# THE ANSWER TO "WHAT IS 'TWICE' COUNTED FROM". Nothing. It is not computed from
# outcomes at all: `--glm-failures N` is caller-supplied and no GLM-failure ledger backs
# it, so any value that would trip the glm_failed_twice rule is forced to 0 and the
# ignore is journaled. That matters for a second reason measured 2026-09-06: over 76,043
# journals, 3,926 of ~4,000 attributed arm_produced_nothing rows name glm, and those
# outcomes conflated quota refusals with model failure — so had this rule ever been
# computed FROM outcomes, it would have escalated away from glm on infrastructure
# refusals. It never was, and this cap is why.
#
# The real, evidence-backed escalation is elsewhere and untouched: arm_advance walks the
# chain per round, and _record_quota_lockout benches a provider from an OBSERVED
# post-spawn failure (primary_arm_benched source=postspawn_failure:<arm>).
#
# WHAT IS REAL HERE. The production _glm_failures_flag_is_ignored is lifted out of
# leadv2-dispatch-code.sh and sourced. Before this row it lived inline in cmd_dispatch,
# reachable only by running a real dispatch, and NO suite pinned it — so removing the cap
# in the name of "making glm_failed_twice reachable" would have gone green while making
# GLM-FIRST bypassable on request alone.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the threshold comparison is
# inverted to `(( _n >= 99 ))`, which lets 2 through. Kills (a) and (b); (c),(d) stay
# green — they guard the other direction, that the cap did not start swallowing values
# that were always legitimate no-ops.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

python3 - "$SRC" "$T/cap.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_glm_failures_flag_is_ignored() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/cap.sh"

ignored(){ if _glm_failures_flag_is_ignored "$1"; then printf 'ignored'; else printf 'passed'; fi; }

# (a) the exact spoof the cap exists for: a caller asking for the escalation by number.
[[ "$(ignored 2)" == "ignored" ]] \
  && ok "--glm-failures 2 is ignored: the escalation is not reachable by asking for it" \
  || bad "a: 2 -> $(ignored 2)"

# (b) and no larger number sneaks past the threshold either.
[[ "$(ignored 7)" == "ignored" && "$(ignored 99)" == "ignored" ]] \
  && ok "any value at or above the trip threshold is ignored, not just the exact one" \
  || bad "b: 7 -> $(ignored 7), 99 -> $(ignored 99)"

# (c) PAIRED NEGATIVE. Values below the threshold were always no-ops and must pass
# through untouched — a cap that swallows everything is not a cap, it is a mute.
[[ "$(ignored 0)" == "passed" && "$(ignored 1)" == "passed" ]] \
  && ok "values below the threshold still pass through unchanged" \
  || bad "c: 0 -> $(ignored 0), 1 -> $(ignored 1)"

# (d) PAIRED NEGATIVE, second half. Garbage must not be silently promoted to a capped
# value: a non-numeric flag is not "two failures", and treating it as ignorable would
# hide a caller typo behind the same journal line as a real spoof.
[[ "$(ignored abc)" == "passed" && "$(ignored '')" == "passed" && "$(ignored -3)" == "passed" ]] \
  && ok "a non-numeric or empty flag is not treated as a capped value" \
  || bad "d: abc -> $(ignored abc), empty -> $(ignored ''), -3 -> $(ignored -3)"

printf '[GLM-FAILURES-FLAG-IS-CAPPED] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
