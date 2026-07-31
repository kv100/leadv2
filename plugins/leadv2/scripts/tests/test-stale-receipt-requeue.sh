#!/usr/bin/env bash
# tests/test-stale-receipt-requeue.sh — SESSION-CLOSE-FIXES-01 fix 2 tests for
# lib/leadv2-receipt-freshness.sh (the shared receipt-freshness guard sourced
# identically by kimi/glm/session-runner).
#
# Before fix 2, a task re-filed after a prior close was refused by all three
# runners because a stale phase8_passed receipt still sat at
# completions/<id>.json. The guard now treats a receipt as STALE (rename +
# proceed) only when the task is open (status queued|pending) in tasks.yaml;
# every other case HONOURS the receipt (fail-closed, today's behaviour).
#
# Cases (assert on the rename, not only the exit code):
#   1. receipt + queued  -> STALE: rc 0, original gone, *.stale-* present, log.
#   2. receipt + pending -> STALE (rc 0, renamed).
#   3. receipt + claimed_done (other status) -> HONOUR (rc 1, untouched).
#   4. receipt + task absent -> HONOUR (rc 1, untouched).
#   5. receipt + no tasks.yaml -> HONOUR (rc 1, untouched).
#   6. mapping-shape tasks.yaml ({tasks:[...]}) + queued -> STALE (both shapes).
#   7. kill-switch LEADV2_RECEIPT_REQUEUE_GUARD=0 + queued -> HONOUR.
#
# Also verifies each of the three runners sources the lib (so the shared
# behaviour is wired, not just standalone). Run: bash scripts/tests/test-stale-receipt-requeue.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/leadv2-receipt-freshness.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${LIB}" 2>/dev/null; then pass "bash -n receipt-freshness lib"; else fail "bash -n receipt-freshness lib"; fi
[[ -f "$LIB" ]] || { fail "lib missing — cannot source"; log "=== ${PASS} passed, ${FAIL} failed ==="; exit 1; }
# Isolation: scrub ambient repo roots so ONLY the positional tasks.yaml arg is
# consulted (the lib's resolution order is positional > $LEADV2_TASKS_YAML >
# $LEADV2_PROJECT_ROOT/docs/tasks.yaml — an ambient LEADV2_PROJECT_ROOT leaking
# from the harness would otherwise point at a real repo's tasks.yaml).
unset LEADV2_PROJECT_ROOT PROJECT_ROOT LEADV2_TASKS_YAML
# shellcheck source=../lib/leadv2-receipt-freshness.sh
source "$LIB"

SANDBOX="$(lv2_mktemp_dir receipt-fresh)"
RECEIPTS="${SANDBOX}/completions"
LOGF="${SANDBOX}/runner.log"
mkdir -p "$RECEIPTS"
TID="e7ba6ad19f2c"

# A valid-looking phase8_passed receipt (content does not matter to the guard;
# only its existence does — validity is the runner's sentinel_present job).
write_receipt() {
  python3 -c "
import json,sys
path=sys.argv[1]
json.dump({'schema_version':1,'task_id':'e7ba6ad19f2c','status':'phase8_passed','assertions':'7/7'}, open(path,'w'))
" "$RECEIPTS/${TID}.json"
}

RECEIPT="${RECEIPTS}/${TID}.json"
receipt_exists() { [ -f "$RECEIPT" ]; }
stale_exists()   { ls "$RECEIPTS"/${TID}.json.stale-* >/dev/null 2>&1; }

# ── Case 1: receipt + queued -> STALE, renamed ─────────────────────────────
TY1="$(lv2_mktemp_dir ty)/tasks.yaml"
cat > "$TY1" <<YML
- id: ${TID}
  status: queued
YML
write_receipt
rm -f "$LOGF"
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY1" "$LOGF"; then
  pass "case1: queued -> rc 0 (stale)"
else
  fail "case1: queued -> rc != 0 (want stale)"
fi
if receipt_exists; then fail "case1: original receipt still present (should be renamed)"; else pass "case1: original receipt gone"; fi
if stale_exists; then pass "case1: *.stale-* artifact present"; else fail "case1: no *.stale-* artifact"; fi
if grep -q "stale receipt (task re-queued) — ignoring + renaming to ${TID}.json.stale-" "$LOGF" 2>/dev/null; then
  pass "case1: rename line in log"
else fail "case1: rename line missing from log"; fi

# ── Case 2: receipt + pending -> STALE ─────────────────────────────────────
TY2="$(lv2_mktemp_dir ty)/tasks.yaml"
cat > "$TY2" <<YML
- id: ${TID}
  status: pending
YML
write_receipt
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY2" "$LOGF"; then
  pass "case2: pending -> rc 0 (stale)"
else
  fail "case2: pending -> rc != 0 (want stale)"
fi
if receipt_exists; then fail "case2: original still present"; else pass "case2: original renamed"; fi

# ── Case 3: receipt + other status -> HONOUR ───────────────────────────────
TY3="$(lv2_mktemp_dir ty)/tasks.yaml"
cat > "$TY3" <<YML
- id: ${TID}
  status: claimed_done
YML
write_receipt
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY3" "$LOGF"; then
  fail "case3: claimed_done -> rc 0 (want honour)"
else
  pass "case3: claimed_done -> rc 1 (honour)"
fi
if receipt_exists; then pass "case3: receipt untouched"; else fail "case3: receipt wrongly renamed"; fi

# ── Case 4: receipt + task absent -> HONOUR ────────────────────────────────
TY4="$(lv2_mktemp_dir ty)/tasks.yaml"
cat > "$TY4" <<YML
- id: some-other-task
  status: queued
YML
write_receipt
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY4" "$LOGF"; then
  fail "case4: task absent -> rc 0 (want honour)"
else
  pass "case4: task absent -> rc 1 (honour)"
fi
if receipt_exists; then pass "case4: receipt untouched"; else fail "case4: receipt wrongly renamed"; fi

# ── Case 5: receipt + no tasks.yaml -> HONOUR ──────────────────────────────
NOPE="$(lv2_mktemp_dir ty)/does-not-exist.yaml"
write_receipt
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$NOPE" "$LOGF"; then
  fail "case5: no tasks.yaml -> rc 0 (want honour)"
else
  pass "case5: no tasks.yaml -> rc 1 (honour)"
fi
if receipt_exists; then pass "case5: receipt untouched"; else fail "case5: receipt wrongly renamed"; fi

# ── Case 6: mapping-shape tasks.yaml ({tasks:[...]}) + queued -> STALE ──────
TY6="$(lv2_mktemp_dir ty)/tasks.yaml"
cat > "$TY6" <<YML
total_open: 1
tasks:
  - id: ${TID}
    status: queued
YML
write_receipt
if leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY6" "$LOGF"; then
  pass "case6: mapping-shape + queued -> rc 0 (stale)"
else
  fail "case6: mapping-shape + queued -> rc != 0 (want stale)"
fi
if receipt_exists; then fail "case6: original still present"; else pass "case6: original renamed"; fi

# ── Case 7: kill-switch off + queued -> HONOUR ─────────────────────────────
write_receipt
if LEADV2_RECEIPT_REQUEUE_GUARD=0 leadv2_receipt_is_stale "$TID" "$RECEIPT" "$TY1" "$LOGF"; then
  fail "case7: kill-switch=0 -> rc 0 (want honour)"
else
  pass "case7: kill-switch=0 -> rc 1 (honour)"
fi
if receipt_exists; then pass "case7: receipt untouched under kill-switch"; else fail "case7: receipt renamed despite kill-switch"; fi

# ── Wiring: all three runners source the shared lib ────────────────────────
for r in leadv2-kimi-session-runner.sh leadv2-glm-session-runner.sh leadv2-session-runner.sh; do
  if grep -q "leadv2-receipt-freshness.sh" "${SCRIPT_DIR}/${r}"; then
    pass "wiring: ${r} sources receipt-freshness lib"
  else
    fail "wiring: ${r} does NOT source receipt-freshness lib"
  fi
done

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" = "0" ]
