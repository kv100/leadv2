#!/usr/bin/env bash
# Mutation: bypass the task-record rank comparison in the writer.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"; LIB="${ROOT}/scripts/lib/leadv2-admission-class.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
source "$LIB"
sig=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
leadv2_admission_write_receipt "$T" aaaaaaaa HEAVY-THEN-LIGHT "$sig" Heavy phases judge build
leadv2_admission_write_receipt "$T" bbbbbbbb HEAVY-THEN-LIGHT bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb Light dispatch flag build
[[ "$(leadv2_admission_read_task_receipt "$T" HEAVY-THEN-LIGHT)" == Heavy ]]
leadv2_admission_write_receipt "$T" cccccccc LIGHT-THEN-HEAVY cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc Light dispatch judge build
leadv2_admission_write_receipt "$T" dddddddd LIGHT-THEN-HEAVY dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd Heavy phases judge build
[[ "$(leadv2_admission_read_task_receipt "$T" LIGHT-THEN-HEAVY)" == Heavy ]]
[[ "$(_lv2_class_rank Heavy)" -gt "$(_lv2_class_rank Light)" ]]

M="$T/leadv2-admission-class.mut.sh"
cp "$ROOT/scripts/lib/leadv2-lane-guard.sh" "$T/leadv2-lane-guard.sh"
python3 - "$LIB" "$M" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = 'if [[ -n "${existing_cls}" ]] && (( $(_lv2_class_rank "${existing_cls}") > $(_lv2_class_rank "${cls}") )); then'
assert old in s
open(sys.argv[2], 'w').write(s.replace(old, 'if false; then', 1))
PY
(
  source "$M"
  leadv2_admission_write_receipt "$T/mut" 11111111 MUT-TASK "$sig" Heavy phases judge build
  leadv2_admission_write_receipt "$T/mut" 22222222 MUT-TASK bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb Light dispatch flag build
  [[ "$(leadv2_admission_read_task_receipt "$T/mut" MUT-TASK)" == Heavy ]]
) && { echo 'mutation survived: Heavy-then-Light was demoted' >&2; exit 1; } || :
echo 'PASS: task-class floor holds Heavy-then-Light and Light-then-Heavy; mutation is red'
