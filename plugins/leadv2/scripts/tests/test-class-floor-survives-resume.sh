#!/usr/bin/env bash
# Mutation: bypass the task-record rank comparison on _admission_classify's
# same-digest resume branch.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"; LIB="${ROOT}/scripts/lib/leadv2-admission-class.sh"; DISPATCH="${ROOT}/scripts/leadv2-dispatch-code.sh"
T="$(mktemp -d)"
cleanup() { local rc=$?; rm -rf "$T"; exit "$rc"; }
trap cleanup EXIT
source "$LIB"
sig=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
leadv2_admission_write_receipt "$T" aaaaaaaa HEAVY-THEN-LIGHT "$sig" Heavy phases judge build
leadv2_admission_write_receipt "$T" bbbbbbbb HEAVY-THEN-LIGHT bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb Light dispatch flag build
[[ "$(leadv2_admission_read_task_receipt "$T" HEAVY-THEN-LIGHT)" == Heavy ]]
leadv2_admission_write_receipt "$T" cccccccc LIGHT-THEN-HEAVY cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc Light dispatch judge build
leadv2_admission_write_receipt "$T" dddddddd LIGHT-THEN-HEAVY dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd Heavy phases judge build
[[ "$(leadv2_admission_read_task_receipt "$T" LIGHT-THEN-HEAVY)" == Heavy ]]
[[ "$(_lv2_class_rank Heavy)" -gt "$(_lv2_class_rank Light)" ]]

# Drive the real dispatcher classifier through its digest-match return. The
# founder task was escalated after this signature was first admitted Light;
# resuming that unchanged mission must still route through phases as Heavy.
python3 - "$DISPATCH" "$T/classify.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('_admission_classify() {')
end = s.index('\n}\n', start) + 3
open(sys.argv[2], 'w').write(s[start:end])
PY
source "$T/classify.sh"
emit() { :; }
founder_task_id="RESUME-FLOOR"
PROJECT_ROOT="$T/production"
mission='resume unchanged mission'
digest=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
leadv2_admission_write_receipt "$PROJECT_ROOT" dddddddd "$founder_task_id" "$digest" Light dispatch judge build
leadv2_admission_write_receipt "$PROJECT_ROOT" eeeeeeee "$founder_task_id" eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee Heavy phases judge build
TASK_JUDGE_BIN=/nonexistent
_admission_classify "$mission" "$digest" dddddddd '' 0
[[ "$ADMISSION_CLASS" == Heavy && "$ADMISSION_ROUTE" == phases && "$ADMISSION_SOURCE" == task_record ]]

M="$T/leadv2-admission-class.mut.sh"
cp "$ROOT/scripts/lib/leadv2-lane-guard.sh" "$T/leadv2-lane-guard.sh"
python3 - "$DISPATCH" "$M" "$T/classify-mut.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = 'if [[ -n "${task_floor}" ]] && (( $(_lv2_class_rank "${task_floor}") > $(_lv2_class_rank "${ADMISSION_CLASS}") )); then'
assert old in s
open(sys.argv[2], 'w').write(s.replace(old, 'if false; then', 1))
mut = open(sys.argv[2]).read()
start = mut.index('_admission_classify() {')
end = mut.index('\n}\n', start) + 3
open(sys.argv[3], 'w').write(mut[start:end])
PY
(
  source "$T/classify-mut.sh"
  founder_task_id="RESUME-FLOOR"; PROJECT_ROOT="$T/production"; TASK_JUDGE_BIN=/nonexistent
  _admission_classify "$mission" "$digest" dddddddd '' 0
  [[ "$ADMISSION_CLASS" == Heavy && "$ADMISSION_ROUTE" == phases ]]
) && { echo 'mutation survived: same-digest resume bypassed the class floor' >&2; exit 1; } || :
echo 'PASS: real _admission_classify preserves the task-class floor across same-digest resume; mutation is red'
