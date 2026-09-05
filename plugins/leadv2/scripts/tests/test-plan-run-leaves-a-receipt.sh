#!/usr/bin/env bash
# PLAN-RUN-LIVE-PATH-UNVERIFIED-01 — make "did this run at all" answerable.
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-plan-run
#
# WHY A RECEIPT AND NOT A JOURNAL LINE. leadv2-plan-run.sh sends its whole output to
# stderr by an explicit decision in the file ("never calls the lane's journal emit"),
# and TESTS-POLLUTE-REAL-JOURNAL-01 exists because writing into the lane's journal from
# the wrong place has burned us before. Both are left intact. The measured problem was
# narrower: assert-precedence -- the guard that stops acceptance criteria being written
# after the diff -- has exactly one production caller, and it is plan-run. 1020
# docs/handoff/dispatch-* dirs carry 0 .precedence-err artifacts and 0
# precedence_violated rows, which is consistent BOTH with the guard never running and
# with plan-run never running, and nothing could tell the two apart.
#
# NOT RUN HERE: plan-run itself. Running it dispatches -- a probe with side effects is
# not a probe. The production _plan_run_receipt is lifted and run instead.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml): the append inside the
# function body is dropped, restoring a run that leaves no trace. Kills (a) and (b);
# leaves (c) and (d) green -- a receipt that cannot fail the run, and cannot invent a
# directory, is the half that must survive any rewording.
set -uo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="${ROOT}/scripts/leadv2-plan-run.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

[[ -f "$SRC" ]] || { printf 'FAIL: %s not found\n[PLAN-RUN-RECEIPT] pass=0 fail=1\n' "$SRC"; exit 1; }

python3 - "$SRC" "$T/fn.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding='utf-8').read()
k = '_plan_run_receipt() {'
i = s.index(k)
j = s.index('\n}\n', i) + 3
io.open(sys.argv[2], 'w', encoding='utf-8').write(s[i:j])
PY
[[ -s "$T/fn.sh" ]] || { printf 'FAIL: could not lift the function\n[PLAN-RUN-RECEIPT] pass=0 fail=1\n'; exit 1; }
# shellcheck disable=SC1090
. "$T/fn.sh"

# (a) the fact the row needs: a run leaves something countable in its own handoff dir.
mkdir -p "$T/h1"
_plan_run_receipt "$T/h1"
if [[ -s "$T/h1/.plan-run-started" ]] && grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z plan-run started pid=[0-9]+$' "$T/h1/.plan-run-started"; then
  ok "a run leaves a timestamped receipt in its own handoff dir"
else
  bad "a: no usable receipt: $(cat "$T/h1/.plan-run-started" 2>/dev/null | tr '\n' ' ' | cut -c1-90)"
fi

# (b) two runs must be distinguishable, or the receipt answers "ever" but not "how
# often" -- and "how often" is the question the census actually asked.
_plan_run_receipt "$T/h1"
if [[ "$(grep -c 'plan-run started' "$T/h1/.plan-run-started" 2>/dev/null)" -eq 2 ]]; then
  ok "a second run appends rather than replacing, so runs can be counted"
else
  bad "b: expected 2 rows, got $(grep -c 'plan-run started' "$T/h1/.plan-run-started" 2>/dev/null)"
fi

# (c) PAIRED NEGATIVE: the receipt must never be able to fail the run it is measuring.
# An unwritable dir, a missing dir and an empty argument all return 0 and stay silent.
chmod 500 "$T/h1" 2>/dev/null || true
out="$( _plan_run_receipt "$T/h1" 2>&1 )"; rc1=$?
chmod 700 "$T/h1" 2>/dev/null || true
out2="$( _plan_run_receipt "$T/definitely-absent" 2>&1 )"; rc2=$?
out3="$( _plan_run_receipt "" 2>&1 )"; rc3=$?
if [[ "$rc1" -eq 0 && "$rc2" -eq 0 && "$rc3" -eq 0 && -z "$out$out2$out3" ]]; then
  ok "an unwritable, missing or unnamed handoff dir cannot fail or noise up the run"
else
  bad "c: rc=$rc1/$rc2/$rc3 out='$out$out2$out3'"
fi

# (d) PAIRED NEGATIVE TWO: the receipt must not CREATE the directory. A measurement that
# manufactures its own subject would put a stamp in every path anyone ever passed.
[[ -e "$T/definitely-absent" ]] && bad "d: the receipt created the directory it was asked about" \
                                || ok "the receipt never manufactures the dir it stamps"

printf '[PLAN-RUN-RECEIPT] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
