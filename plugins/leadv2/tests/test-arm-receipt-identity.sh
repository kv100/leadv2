#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-arm-receipts.sh
# tests/test-arm-receipt-identity.sh — offline tests for
# plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh (ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01, P3 Part A).
#
# Covers: argument validation, that a written close record carries all three
# identity fields (lane_id, decision_id, attempt_id) non-null, that two
# distinct attempts against the same launch tuple are recorded as two
# distinct rows (never collapsed), and that the reader always returns `n`
# alongside its token sums.
#
# E2E-KILLRATE-01 negative controls this suite is the RED half of:
#   1. drop attempt_id inside lv2_arm_receipt_write's record body.
#   3. drop `n` from lv2_arm_receipt_read's printed output.
# Usage: bash tests/test-arm-receipt-identity.sh
# Exit 0 = all pass; non-zero = failure count.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SELF_DIR}/../scripts/lib/leadv2-arm-receipts.sh"

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export LEADV2_ARM_RECEIPTS_LEDGER="${TMP}/arm-receipts.jsonl"

# shellcheck disable=SC1090
source "${LIB}"

# --- wrong arg count is rejected --------------------------------------------
if lv2_arm_receipt_write a b c 2>/dev/null; then
  fail "wrong_arg_count: write should refuse a 3-arg call"
else
  pass "wrong_arg_count: write refuses a non-23-arg call"
fi

# --- missing identity is rejected -------------------------------------------
if lv2_arm_receipt_write "" "dec1" "att1" open claude developer claude sonnet mid low personal \
    "" "" "" "" "" "" "" "" "" "" "" "" 2>/dev/null; then
  fail "missing_identity: write should refuse an empty lane_id"
else
  pass "missing_identity: write refuses an empty lane_id"
fi

# --- bad phase is rejected ---------------------------------------------------
if lv2_arm_receipt_write lane1 dec1 att1 sideways claude developer claude sonnet mid low personal \
    "" "" "" "" "" "" "" "" "" "" "" "" 2>/dev/null; then
  fail "bad_phase: write should refuse phase=sideways"
else
  pass "bad_phase: write refuses a non open/close phase"
fi

# --- a real close record carries all three identity fields non-null --------
: > "${LEADV2_ARM_RECEIPTS_LEDGER}"
lv2_arm_receipt_write lane-A dec-A att-A close claude developer claude sonnet mid low personal \
  2026-09-01T00:00:00Z 2026-09-01T00:01:00Z 60 \
  100 200 10 5 3 win 0 terminal_result false

line="$(tail -n 1 "${LEADV2_ARM_RECEIPTS_LEDGER}")"
identity_ok="$(python3 -c '
import json, sys
rec = json.loads(sys.argv[1])
ok = bool(rec.get("lane_id")) and bool(rec.get("decision_id")) and bool(rec.get("attempt_id"))
print("yes" if ok else "no")
' "${line}")"
if [[ "${identity_ok}" == "yes" ]]; then
  pass "identity_fields: written record carries lane_id+decision_id+attempt_id"
else
  fail "identity_fields: written record is missing an identity field (attempt_id dropped?)"
fi

# --- two distinct attempts are recorded distinctly, never collapsed --------
lv2_arm_receipt_write lane-A dec-A att-B close claude developer claude sonnet mid low personal \
  2026-09-01T00:02:00Z 2026-09-01T00:03:00Z 60 \
  50 60 1 1 2 win 0 terminal_result false

n_lines="$(wc -l < "${LEADV2_ARM_RECEIPTS_LEDGER}" | tr -d '[:space:]')"
distinct_attempts="$(python3 -c '
import json, sys
seen = set()
with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        seen.add(rec.get("attempt_id"))
print(len(seen))
' "${LEADV2_ARM_RECEIPTS_LEDGER}")"
if [[ "${n_lines}" == "2" && "${distinct_attempts}" == "2" ]]; then
  pass "distinct_attempts: two attempts produce two distinct ledger rows"
else
  fail "distinct_attempts: expected 2 rows/2 distinct attempt_ids, got lines=${n_lines} distinct=${distinct_attempts}"
fi

# --- reader returns n alongside the sums ------------------------------------
read_out="$(lv2_arm_receipt_read claude developer claude sonnet mid low)"
case "${read_out}" in
  n=2\ *) pass "reader_n: reader reports n=2 for the two close records just written" ;;
  *) fail "reader_n: expected output to start with 'n=2 ', got '${read_out}'" ;;
esac

case "${read_out}" in
  *tokens_in=150*) pass "reader_sums: tokens_in sums to 150 across both attempts" ;;
  *) fail "reader_sums: expected tokens_in=150 in '${read_out}'" ;;
esac

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
