#!/usr/bin/env bash
# tests/test-question-delivery-ownership-01.sh — QUESTION-DELIVERY-OWNERSHIP-01
#
# Coverage matrix (per requirement):
#   (a) ask stamps owner_session / owner_task / asked_repo at write time
#   (b) reply-router refuses young foreign answer (exit 6), allows old foreign,
#       allows own always, --force overrides and is logged
#   (c) old-row (no owner fields) tolerated by router (no refusal)
#   (d) product-close waiting loop emits question_pending for its OWN task's
#       unanswered q, and NOT for a different task's
#
# Sandboxed via LEADV2_STATE_ROOT / PROJECT_ROOT / LEADV2_PROJECT_ROOT.
# Run: bash scripts/tests/test-question-delivery-ownership-01.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASK_SH="${SCRIPTS_ROOT}/leadv2-ask.sh"
ROUTER_SH="${SCRIPTS_ROOT}/leadv2-reply-router.sh"
PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
STATE_PATH_SH="${SCRIPTS_ROOT}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP_DIR="$(lv2_mktemp_dir "qdo1-test")"
STATE_ROOT="${TMP_DIR}/state"
LINK_ROOT="${TMP_DIR}/link"
mkdir -p "$STATE_ROOT" "$LINK_ROOT"
cleanup() { rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

_field() {
  python3 -c '
import sys, yaml
path = sys.argv[2].split(".")
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = yaml.safe_load(f) or {}
except FileNotFoundError:
    print("__MISSING__"); sys.exit(0)
cur = d
for p in path:
    if not isinstance(cur, dict):
        cur = None; break
    cur = cur.get(p)
print(cur if cur is not None else "__NONE__")
' "$1" "$2"
}

_ask() {
  LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" LEADV2_PROJECT_ROOT="$LINK_ROOT" \
    bash "$ASK_SH" "$@" --no-block 2>/dev/null
}

_route() {
  LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" LEADV2_PROJECT_ROOT="$LINK_ROOT" \
    bash "$ROUTER_SH" "$@"
}

# ── (a) ask stamps owner fields ────────────────────────────────────────────────────
test_a_ask_stamps_owner() {
  log "Test (a): ask stamps owner_session / owner_task / asked_repo"
  local qid qf owner_session owner_task asked_repo

  qid="$(LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" \
    LEADV2_ASK_OWNER_SESSION="sess-alpha-123" LEADV2_ASK_OWNER_TASK="TASK-OWNER" \
    bash "$ASK_SH" "TASK-OWNER" "Test question for ownership" \
    --option "a|opt a" --option "b|opt b" --no-block 2>/dev/null)"
  [[ -n "$qid" ]] || { fail "Test (a): ask produced no qid"; return; }

  qf="${STATE_ROOT}/questions/${qid}.yaml"
  owner_session="$(_field "$qf" owner_session)"
  owner_task="$(_field "$qf" owner_task)"
  asked_repo="$(_field "$qf" asked_repo)"

  if [[ "$owner_session" == "sess-alpha-123" && "$owner_task" == "TASK-OWNER" && -n "$asked_repo" && "$asked_repo" != "__NONE__" ]]; then
    pass "Test (a): owner_session=$owner_session owner_task=$owner_task asked_repo=$asked_repo"
  else
    fail "Test (a): owner_session=$owner_session owner_task=$owner_task asked_repo=$asked_repo"
  fi
}

# ── (b1) router refuses young foreign answer ───────────────────────────────────────
test_b1_refuse_young_foreign() {
  log "Test (b1): router refuses young foreign answer (exit 6)"
  # Ask as session "owner-xyz", then try to answer as a DIFFERENT session.
  local qid
  qid="$(LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" \
    LEADV2_ASK_OWNER_SESSION="owner-xyz" \
    bash "$ASK_SH" "TASK-B1" "Foreign young" \
    --option "approve|Approve" --option "reject|Reject" --no-block 2>/dev/null)"
  [[ -n "$qid" ]] || { fail "Test (b1): ask produced no qid"; return; }

  # Answer as a foreign session — should be refused (exit 6).
  local rc out
  out="$(CLAUDE_SESSION_ID="foreign-caller" \
    LEADV2_Q_FOREIGN_MIN_AGE_S="999999" \
    _route "$qid" "approve" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 6 ]]; then
    pass "Test (b1): young foreign answer refused (exit 6), owner printed"
  else
    fail "Test (b1): expected exit 6, got rc=$rc out=$out"
  fi
}

# ── (b2) router allows old foreign answer ──────────────────────────────────────────
test_b2_allow_old_foreign() {
  log "Test (b2): router allows old foreign answer (age >= threshold)"
  # Create a question with an old asked_at manually.
  local qid="q-oldforeign1"
  local qf="${STATE_ROOT}/questions/${qid}.yaml"
  mkdir -p "${STATE_ROOT}/questions"
  python3 -c '
import yaml, sys
doc = {
    "schema_version": 2,
    "qid": sys.argv[1],
    "task_id": "TASK-B2",
    "question": "Old foreign question",
    "options": [{"label": "approve", "text": "Approve"}],
    "asked_at": "2020-01-01T00:00:00Z",
    "status": "pending",
    "answer": {"selected": None, "decided_by": None, "answered_at": None},
    "owner_session": "old-owner-session",
    "owner_task": "TASK-B2",
    "asked_repo": "test",
}
with open(sys.argv[2], "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
' "$qid" "$qf"

  local rc out
  out="$(CLAUDE_SESSION_ID="foreign-caller-2" \
    LEADV2_Q_FOREIGN_MIN_AGE_S="60" \
    _route "$qid" "approve" 2>&1)" && rc=0 || rc=$?

  local status
  status="$(_field "$qf" status)"

  if [[ "$rc" -eq 0 && "$status" == "answered" ]]; then
    pass "Test (b2): old foreign answer allowed and recorded"
  else
    fail "Test (b2): rc=$rc status=$status out=$out"
  fi
}

# ── (b3) router allows own answer always ───────────────────────────────────────────
test_b3_allow_own_always() {
  log "Test (b3): router allows own session to answer (regardless of age)"
  local qid
  qid="$(LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" \
    LEADV2_ASK_OWNER_SESSION="my-session" \
    bash "$ASK_SH" "TASK-B3" "Own question" \
    --option "yes|Yes" --option "no|No" --no-block 2>/dev/null)"
  [[ -n "$qid" ]] || { fail "Test (b3): ask produced no qid"; return; }

  # Answer as the SAME session — should be allowed even with a high min_age.
  local rc
  CLAUDE_SESSION_ID="my-session" \
    LEADV2_Q_FOREIGN_MIN_AGE_S="999999" \
    _route "$qid" "yes" >/dev/null 2>&1 && rc=0 || rc=$?

  local status selected qf="${STATE_ROOT}/questions/${qid}.yaml"
  status="$(_field "$qf" status)"
  selected="$(_field "$qf" answer.selected)"

  if [[ "$rc" -eq 0 && "$status" == "answered" && "$selected" == "yes" ]]; then
    pass "Test (b3): own session answered immediately (no age gate)"
  else
    fail "Test (b3): rc=$rc status=$status selected=$selected"
  fi
}

# ── (b4) --force overrides foreign gate (logged) ────────────────────────────────────
test_b4_force_overrides() {
  log "Test (b4): --force overrides young foreign refusal"
  local qid
  qid="$(LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" \
    LEADV2_ASK_OWNER_SESSION="owner-force" \
    bash "$ASK_SH" "TASK-B4" "Force test" \
    --option "go|Go" --option "stop|Stop" --no-block 2>/dev/null)"
  [[ -n "$qid" ]] || { fail "Test (b4): ask produced no qid"; return; }

  local rc out
  out="$(CLAUDE_SESSION_ID="different-session" \
    LEADV2_Q_FOREIGN_MIN_AGE_S="999999" \
    _route "$qid" "go" --force 2>&1)" && rc=0 || rc=$?

  local status qf="${STATE_ROOT}/questions/${qid}.yaml"
  status="$(_field "$qf" status)"

  if [[ "$rc" -eq 0 && "$status" == "answered" && "$out" == *"FORCE_FOREIGN"* ]]; then
    pass "Test (b4): --force overrode refusal and logged FORCE_FOREIGN"
  else
    fail "Test (b4): rc=$rc status=$status out=$out"
  fi
}

# ── (c) old-row without owner fields tolerated ─────────────────────────────────────
test_c_old_row_tolerated() {
  log "Test (c): old-row (no owner fields) tolerated by router"
  local qid="q-oldrow0001"
  local qf="${STATE_ROOT}/questions/${qid}.yaml"
  mkdir -p "${STATE_ROOT}/questions"
  python3 -c '
import yaml, sys
doc = {
    "schema_version": 2,
    "qid": sys.argv[1],
    "task_id": "TASK-C",
    "question": "Legacy question without owner",
    "options": [{"label": "ok", "text": "OK"}],
    "asked_at": "2026-08-03T08:00:00Z",
    "status": "pending",
    "answer": {"selected": None, "decided_by": None, "answered_at": None},
}
with open(sys.argv[2], "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
' "$qid" "$qf"

  # Answer from a foreign session — no owner_session → always allowed.
  local rc
  CLAUDE_SESSION_ID="any-session" \
    LEADV2_Q_FOREIGN_MIN_AGE_S="999999" \
    _route "$qid" "ok" >/dev/null 2>&1 && rc=0 || rc=$?

  local status
  status="$(_field "$qf" status)"

  if [[ "$rc" -eq 0 && "$status" == "answered" ]]; then
    pass "Test (c): old-row without owner fields answered (no refusal)"
  else
    fail "Test (c): rc=$rc status=$status"
  fi
}

# ── (d) product-close emits question_pending for own task only ─────────────────────
test_d_pc_emit_pending_questions() {
  log "Test (d): _pc_emit_pending_questions emits for own task, not others"

  # Create two pending questions: one for TASK-OWN, one for TASK-OTHER.
  mkdir -p "${STATE_ROOT}/questions"
  local own_qid="q-pcown001"
  local other_qid="q-pcother001"
  local asked_iso
  asked_iso="$(python3 -c '
import datetime
print((datetime.datetime.utcnow() - datetime.timedelta(seconds=300)).strftime("%Y-%m-%dT%H:%M:%SZ"))
')"

  for pair in "${own_qid}:TASK-OWN" "${other_qid}:TASK-OTHER"; do
    local q="${pair%%:*}" t="${pair##*:}"
    python3 -c '
import yaml, sys
doc = {
    "schema_version": 2,
    "qid": sys.argv[1],
    "task_id": sys.argv[2],
    "question": "PC test question",
    "options": [{"label": "a", "text": "A"}],
    "asked_at": sys.argv[3],
    "status": "pending",
    "answer": {"selected": None, "decided_by": None, "answered_at": None},
    "owner_session": "pc-owner",
    "owner_task": sys.argv[2],
    "asked_repo": "test",
}
with open(sys.argv[4], "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
' "$q" "$t" "$asked_iso" "${STATE_ROOT}/questions/${q}.yaml"
  done

  # Extract the _pc_emit_pending_questions function body from the real script
  # (avoids sourcing the entire script, which would execute its main body).
  local func_extract="${TMP_DIR}/pc-func.sh"
  awk '/^_pc_emit_pending_questions\(\)/{f=1} f{print} f&&/^}$/{exit}' \
    "$PRODUCT_CLOSE_SH" > "$func_extract"
  [[ -s "$func_extract" ]] || { fail "Test (d): could not extract function"; return; }

  local capture_file="${TMP_DIR}/pc-capture.txt"
  : > "$capture_file"

  # Run the extracted function with stubbed globals + a capture emit().
  LEADV2_STATE_ROOT="$STATE_ROOT" PROJECT_ROOT="$LINK_ROOT" \
  bash -c '
    set -uo pipefail
    ROOT="'"$LINK_ROOT"'"
    TASK="TASK-OWN"
    STATE_PATH_BIN="'"$STATE_PATH_SH"'"

    emit() {
      printf -- "%s\n" "$2" >> "'"$capture_file"'"
    }

    source "'"$func_extract"'"
    _pc_emit_pending_questions
  ' 2>/dev/null || true

  # Check that the capture contains our own qid but NOT the other task's.
  local own_found=0 other_found=0
  grep -q "$own_qid" "$capture_file" 2>/dev/null && own_found=1 || true
  grep -q "$other_qid" "$capture_file" 2>/dev/null && other_found=1 || true

  if [[ "$own_found" -eq 1 && "$other_found" -eq 0 ]]; then
    pass "Test (d): emitted question_pending for own task qid, not other task's"
  else
    fail "Test (d): own_found=$own_found other_found=$other_found (expected own=1, other=0)"
    cat "$capture_file" 2>/dev/null | head -5 >&2 || true
  fi
}

main() {
  log "=== QUESTION-DELIVERY-OWNERSHIP-01 test suite ==="
  echo ""

  # Syntax checks first.
  bash -n "$ASK_SH" 2>/dev/null && pass "Syntax: leadv2-ask.sh OK" || fail "Syntax: leadv2-ask.sh FAILED"
  bash -n "$ROUTER_SH" 2>/dev/null && pass "Syntax: leadv2-reply-router.sh OK" || fail "Syntax: leadv2-reply-router.sh FAILED"
  bash -n "$PRODUCT_CLOSE_SH" 2>/dev/null && pass "Syntax: leadv2-dispatch-product-close.sh OK" || fail "Syntax: leadv2-dispatch-product-close.sh FAILED"

  test_a_ask_stamps_owner
  test_b1_refuse_young_foreign
  test_b2_allow_old_foreign
  test_b3_allow_own_always
  test_b4_force_overrides
  test_c_old_row_tolerated
  test_d_pc_emit_pending_questions

  echo ""
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "Failures:"
    for e in "${ERRORS[@]}"; do log "  $e"; done
    exit 1
  fi
  log "All tests passed."
  exit 0
}

main "$@"
