#!/usr/bin/env bash
# Mutation: make the task receipt read in _admission_classify return empty.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"; LIB="${ROOT}/scripts/lib/leadv2-admission-class.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
source "$LIB"
sig=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
leadv2_admission_write_receipt "$T" aaaaaaaa HEAVY-TASK "$sig" Heavy phases judge build
[[ "$(leadv2_admission_read_task_receipt "$T" HEAVY-TASK)" == Heavy ]]
[[ "$(_lv2_class_rank Heavy)" -gt "$(_lv2_class_rank Light)" ]]
echo 'PASS: Heavy task record remains a class floor for a short resume'
