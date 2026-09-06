#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code.sh leadv2-report-deliverable.sh
# test-lane-deliverable-advance-arm.sh — DISPATCHER-BRANCH-RESIDUE-01 (worktree-5e57c5ff
# codex r2 finding 2 + r4 finding 4): a report lane recovered via `advance-arm` must
# re-thread its deliverable declaration into spawn_product_close -- preferring the
# VALIDATED declaration persisted at spawn time (docs/handoff/dispatch-<sig8>/
# lane-deliverable, carrying the higher-precedence --lane-deliverable / row value),
# falling back to re-harvesting the mission's LANE_DELIVERABLE line. Without this, a
# recovered report lane is re-judged as a diff lane and blocks no_work despite its
# report.
#
# Method: load the real dispatcher's definitions (everything above the `# ── dispatch `
# CLI footer) as a library, stub spawn_worker + spawn_product_close + the ledger, and
# drive cmd_advance_arm directly. No provider, registry, or network call ever runs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

bash -n "$DISPATCH" || { echo "ERROR: dispatch-code.sh syntax"; exit 1; }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t leadv2-ldaa)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/handoff" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed && git add seed && git commit -qm seed)

# lib load: everything above the CLI footer marker
awk '/^# ── dispatch / { exit } { print }' "$DISPATCH" > "$ROOT/dispatch-lib.sh"

JOURNAL_CAPTURE="$ROOT/journal-capture.txt"
FAKE_JOURNAL="$ROOT/fake-journal.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$JOURNAL_CAPTURE" > "$FAKE_JOURNAL"
chmod +x "$FAKE_JOURNAL"

FAKE_PHASE_RECORD="$ROOT/fake-phase-record.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_PHASE_RECORD"
chmod +x "$FAKE_PHASE_RECORD"

CLOSE_ARGS="$ROOT/close-args.txt"

run_advance_arm() { # <sig8> <mission-file> -> close-gate 8th arg ("" if absent) in $CAPTURED_DELIVERABLE
  local sig8="$1" mission_file="$2"
  rm -f "$CLOSE_ARGS" "$JOURNAL_CAPTURE"
  (
    set -uo pipefail
    export LEADV2_PROJECT_ROOT="$REPO" CLAUDE_PROJECT_ROOT="$REPO"
    export LEADV2_JOURNAL_BIN="$FAKE_JOURNAL"
    export LEADV2_DISPATCH_E2E_GATE=1 LEADV2_DISPATCH_REVIEW_GATE=1
    export LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" LEADV2_QUOTA_LOCKOUT_DIR="$ROOT/lockouts"
    export LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off
    export LEADV2_TASK_ID="${sig8}-founder" LEADV2_PARENT_SESSION_ID=s-test
    export PHASE_RECORD_BIN="$FAKE_PHASE_RECORD"
    source "$ROOT/dispatch-lib.sh"
    # ── stubs over the loaded definitions ──
    spawn_worker() { printf 'PID=4242 LABEL=stub-arm SESSION_ID=s-stub\n'; }
    spawn_product_close() {
      # capture ALL args; arg 8 is the recovered deliverable declaration
      printf '%s\n' "${8-__ABSENT__}" > "$CLOSE_ARGS"
      return 0
    }
    _stamp_active_phase() { :; }
    dispatch_ledger_file() { printf '%s/ledger.jsonl' "$REPO"; }
    cmd_advance_arm --sig8 "$sig8" --arm sonnet --mission-file "$mission_file" \
      --task-id "${sig8}-founder" --worktree "$REPO" --writes seed >/dev/null 2>"$ROOT/adv.err"
  )
  CAPTURED_DELIVERABLE="$(cat "$CLOSE_ARGS" 2>/dev/null || printf '__NO_CLOSE__')"
}

confirm_ledger_row() { # <sig8> — a confirmed reservation row the guard accepts
  printf '{"task_sig":"%s","state":"confirmed","task_class":"Standard","founder_task_id":"%s-founder"}\n' "$1" "$1" \
    > "$REPO/ledger.jsonl"
}

# ── T1: validated lane-deliverable FILE wins -- 8th arg threads it ──────────────
SIG1=ldaa0001
confirm_ledger_row "$SIG1"
HANDOFF1="$REPO/docs/handoff/dispatch-$SIG1"
mkdir -p "$HANDOFF1"
printf 'stub mission with no deliverable line\n' > "$HANDOFF1/mission.md"
printf 'report:analysis/report.md' > "$HANDOFF1/lane-deliverable"   # the validated decl (spawn-time persistence)
run_advance_arm "$SIG1" "$HANDOFF1/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:analysis/report.md" ]]; then
  pass "T1: advance-arm threads the persisted validated declaration"
else
  fail "T1: persisted declaration" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T2: no file -> falls back to the mission's own LANE_DELIVERABLE line ────────
SIG2=ldaa0002
confirm_ledger_row "$SIG2"
HANDOFF2="$REPO/docs/handoff/dispatch-$SIG2"
mkdir -p "$HANDOFF2"
printf 'mission text\nLANE_DELIVERABLE: report:docs/other.md\nmore text\n' > "$HANDOFF2/mission.md"
run_advance_arm "$SIG2" "$HANDOFF2/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:docs/other.md" ]]; then
  pass "T2: mission-line fallback recovers the declaration"
else
  fail "T2: mission fallback" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T3: FILE beats mission line (the r4-finding-4 precedence) ──────────────────
SIG3=ldaa0003
confirm_ledger_row "$SIG3"
HANDOFF3="$REPO/docs/handoff/dispatch-$SIG3"
mkdir -p "$HANDOFF3"
printf 'LANE_DELIVERABLE: report:from-mission.md\n' > "$HANDOFF3/mission.md"
printf 'report:from-file.md' > "$HANDOFF3/lane-deliverable"
run_advance_arm "$SIG3" "$HANDOFF3/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:from-file.md" ]]; then
  pass "T3: file declaration outranks the mission line"
else
  fail "T3: precedence" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T4: UNPARSABLE decl -> ignored loudly, empty 8th arg ────────────────────────
SIG4=ldaa0004
confirm_ledger_row "$SIG4"
HANDOFF4="$REPO/docs/handoff/dispatch-$SIG4"
mkdir -p "$HANDOFF4"
printf 'mission without deliverable\n' > "$HANDOFF4/mission.md"
printf 'banana:nota/decl' > "$HANDOFF4/lane-deliverable"
run_advance_arm "$SIG4" "$HANDOFF4/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "" ]]; then
  pass "T4a: unparsable declaration threads an EMPTY deliverable"
else
  fail "T4a: unparsable decl" "8th arg='${CAPTURED_DELIVERABLE}'"
fi
if grep -q 'lane_deliverable task=ldaa0004 status=ignored reason=unknown_kind src=advance_arm' "$JOURNAL_CAPTURE" 2>/dev/null; then
  pass "T4b: the ignore is journalled (never silent)"
else
  fail "T4b: journal" "capture lacks ignored line: $(tail -2 "$JOURNAL_CAPTURE" 2>/dev/null)"
fi

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
