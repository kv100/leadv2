#!/usr/bin/env bash
# ARM-PRODUCED-NOTHING-IS-ONE-WORD-FOR-TWO-EVENTS-01 — three events, three words, and
# the old word still on all three.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-dispatch-product-close
#
# WHY. Measured 2026-09-05 on the live journal of task 11b25531: `arm_quota_failed
# arm=glm` is written, and the NEXT line rewrites it as `arm_advance ...
# reason=arm_produced_nothing`. Three different events arrive under that one word —
# a provider that refused on quota, a model that ran and produced an empty diff, and
# a worker never shown the artifacts its mission names — and each calls for a
# different decision: wait, change arm, fix delivery. A reader who sees only the word
# concludes something about the MODEL for two events it had no part in.
#
# WHAT IS REAL HERE. The production `_pc_produced_nothing_cause` body is lifted out of
# leadv2-dispatch-product-close.sh and sourced with the closure its real caller
# provides. Its rules are not restated anywhere in this file. Only the journal binary
# is faked, to a script that prints a fixture journal.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the quota branch's
# `printf 'quota_denied'` becomes `printf 'empty_output'`, collapsing two events back
# into one word. Kills (a) and leaves (b),(c),(d) green — (d) is the half that proves
# the split did not simply rename one event into another.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/leadv2-dispatch-product-close.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

python3 - "$SRC" "$T/cause.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_pc_produced_nothing_cause() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/cause.sh"

# The closure the real caller provides. JOURNAL_BIN is a real executable file here
# because the predicate tests `-f` on it and then runs it.
TASK=abc12345; AUTHOR=glm; FOUNDER_TASK_ID=MY-TASK-01
JOURNAL_BIN="$T/journal.sh"
printf '#!/usr/bin/env bash\ncat "%s/journal.txt" 2>/dev/null || true\n' "$T" > "$JOURNAL_BIN"
chmod +x "$JOURNAL_BIN"
: > "$T/journal.txt"
mkdir -p "$T/lane/docs/handoff/MY-TASK-01"
_lane_root="$T/lane"

# (a) the provider refused on quota — the model never ran. Nothing here is the arm's.
printf 'arm_quota_failed task=abc12345 arm=glm handle=h1\n' > "$T/journal.txt"
A="$(_pc_produced_nothing_cause)"
[[ "$A" == "quota_denied" ]] && ok "a quota refusal is quota_denied, not the model's failure" || bad "a: got '$A'"

# (b) the worker was spawned into a tree with no directory for its own task — the
# mission text names paths that are not there. A delivery fault.
: > "$T/journal.txt"
rm -rf "$T/lane/docs/handoff/MY-TASK-01"
B="$(_pc_produced_nothing_cause)"
[[ "$B" == "no_artifacts_delivered" ]] && ok "a lane with no task dir is no_artifacts_delivered" || bad "b: got '$B'"

# (c) the model ran with its artifacts in place and produced nothing. Only THIS one is
# a statement about the arm.
mkdir -p "$T/lane/docs/handoff/MY-TASK-01"
C="$(_pc_produced_nothing_cause)"
[[ "$C" == "empty_output" ]] && ok "an arm that ran with its artifacts present is empty_output" || bad "c: got '$C'"

# (d) THE MANDATORY PAIRED NEGATIVE, in two parts. Splitting must not have renamed one
# event into another: the three answers must be three DISTINCT words, and none of the
# three may be empty (an empty cause would silently reintroduce the single word at the
# emit site, where it is interpolated).
if [[ -n "$A" && -n "$B" && -n "$C" && "$A" != "$B" && "$B" != "$C" && "$A" != "$C" ]]; then
  ok "the three events yield three distinct non-empty words ($A / $B / $C)"
else
  bad "d: not three distinct non-empty words: '$A' '$B' '$C'"
fi

# (e) quota evidence for a DIFFERENT arm must not be borrowed — the journal line is
# keyed by task AND arm, and a neighbouring arm's refusal is not this arm's excuse.
printf 'arm_quota_failed task=abc12345 arm=codex handle=h9\n' > "$T/journal.txt"
E="$(_pc_produced_nothing_cause)"
[[ "$E" == "empty_output" ]] && ok "another arm's quota refusal is not borrowed as this arm's cause" || bad "e: got '$E'"

printf '[PRODUCED-NOTHING-CAUSE] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
