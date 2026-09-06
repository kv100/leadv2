#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-product-close.sh leadv2-dispatch-code.sh leadv2-worker-reason.sh
# (BASENAMES only — a token containing "/" is FATAL for the whole run.)
#
# tests/test-worker-ended-on-wait.sh — WORKER-ENDS-TURN-ON-WAIT-01.
#
# A dispatched worker has exactly one turn-chain and nothing that wakes it. A final
# message of the shape "I'll wait for the background job" is therefore not a pause,
# it is the end of the lane — with the work still uncommitted in the worktree, which
# is precisely how finished work has been lost at the last inch.
#
# What is REAL here and what is faked (E2E-KILLRATE-01 rule 1): the three production
# functions under claim — `_pc_wait_phrase_hit`, `_pc_commit_lane_on_wait` and the
# `_dl_note` funnel they hang on — are LIFTED OUT OF THE SHIPPED FILE at run time and
# executed. Nothing restates their rules. Faked one level lower: the worker's last
# words (`_pc_worker_reason`), the journal sink (`emit`), and the ledger (TERMINAL_LEDGER=0).
# The git repository the salvage commit runs against is a real one.
#
# DECLARED MUTATION (the negative control this suite is measured by):
#   in leadv2-dispatch-product-close.sh, invert the `_pc_wait_phrase_hit` call inside
#   _dl_note (or empty _PC_WAIT_PHRASE_RE) so the wait shape never matches.
#   Must go RED: (g) — a wait-shaped last message journals `worker_ended_on_wait` and
#   commits the lane. Must stay GREEN under that same mutation: (h) — a normal
#   completion sentence never fires. (h) is the control that keeps this from becoming
#   a rule that fires on everything.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
PC_FILE="${SCRIPTS_DIR}/leadv2-dispatch-product-close.sh"
DC_FILE="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf -- '[TEST] PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf -- '[TEST] FAIL %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lv2-weow.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

[[ -f "${PC_FILE}" ]] || { printf 'no product-close script at %s\n' "${PC_FILE}" >&2; exit 2; }

# ── lift the production functions out of the shipped file ──────────────────────
# Byte-exact slices, located by their own opening lines. A rename upstream makes the
# extraction fail loudly here rather than silently testing a stale copy.
LIFTED="${WORK}/lifted.sh"
python3 - "${PC_FILE}" "${LIFTED}" <<'PY' || { printf 'extraction failed\n' >&2; exit 2; }
import io, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
out = []
def take(head, end="\n}\n"):
    i = src.index(head)
    j = src.index(end, i) + len(end)
    out.append(src[i:j])
i = src.index("_PC_WAIT_PHRASE_RE='")
out.append(src[i:src.index("\n", i) + 1])
take("_pc_wait_phrase_hit() {")
take("_pc_commit_lane_on_wait() {")
take("_dl_note() {")
io.open(sys.argv[2], "w", encoding="utf-8").write("".join(out))
PY

# ── harness: everything one level below the functions under claim ──────────────
EMITTED="${WORK}/emitted.log"
: > "${EMITTED}"
emit() { printf '%s\n' "$*" >> "${EMITTED}"; }          # the journal sink
_PC_WORKER_REASON_TEXT=""
_pc_worker_reason() { printf '%s' "${_PC_WORKER_REASON_TEXT}"; }
_OWN_WORKTREE=1
lv2_lane_root_is_own_worktree() { [[ "${_OWN_WORKTREE}" == "1" ]]; }
TERMINAL_LEDGER=0                                        # never reach the ledger
TASK="weow1234"; AUTHOR="sonnet"; FOUNDER_TASK_ID="WORKER-ENDS-TURN-ON-WAIT-01"
LANE_NAME="${FOUNDER_TASK_ID}"; _PC_ATTEMPT="weow1234-0-0"
_PC_TERMINAL_COMMIT=""; _PC_TERMINAL_DELIVERABLE=""
# shellcheck disable=SC1090
source "${LIFTED}"

new_lane_repo() { # -> prints a fresh git repo with one commit
  local r; r="$(mktemp -d "${WORK}/lane.XXXXXX")"
  git -C "${r}" init -q 2>/dev/null
  git -C "${r}" config user.email t@t; git -C "${r}" config user.name t
  mkdir -p "${r}/src"; printf 'base\n' > "${r}/src/keep.txt"
  git -C "${r}" add -- src/keep.txt >/dev/null 2>&1
  git -C "${r}" -c commit.gpgsign=false commit -qm base >/dev/null 2>&1
  printf '%s' "${r}"
}

# ── (a)(b) the phrase predicate itself, both directions ────────────────────────
for phrase in "I'll wait for the background job to finish" \
              "Waiting for the review to come back before continuing." \
              "I will wait — before proceeding I need the lead's answer"; do
  if _pc_wait_phrase_hit "${phrase}" >/dev/null; then
    ok "(a) wait shape recognised: ${phrase:0:34}…"
  else
    bad "(a) wait shape MISSED: ${phrase}"
  fi
done
for plain in "Landed the fix and committed it as 1a2b3c4." \
             "Suite is 12/0; report written to docs/handoff/X/report.md." \
             "BLOCKED: the API key is missing — committed what I have."; do
  if _pc_wait_phrase_hit "${plain}" >/dev/null; then
    bad "(b) NEG-CTL: normal completion misread as a wait: ${plain}"
  else
    ok "(b) NEG-CTL: normal completion is not a wait: ${plain:0:34}…"
  fi
done

# ── (c) the salvage commit lands the DECLARED paths, by name ───────────────────
_lane_root="$(new_lane_repo)"
printf 'work\n' > "${_lane_root}/src/done.txt"
printf 'someone else\n' > "${_lane_root}/src/foreign.txt"
WRITES_CSV="src/done.txt"
_PC_WAIT_COMMIT_DONE=0
act="$(_pc_commit_lane_on_wait)"
if [[ "${act}" == "committed" ]] \
   && git -C "${_lane_root}" show --stat --name-only HEAD 2>/dev/null | grep -q '^src/done.txt$'; then
  ok "(c) uncommitted lane work is salvaged into a commit"
else
  bad "(c) act=${act} head=[$(git -C "${_lane_root}" show --name-only --format= HEAD 2>/dev/null | tr '\n' ' ')]"
fi
# (c2) NEVER `git add -A`: an undeclared file in the same tree must be left alone.
if git -C "${_lane_root}" status --porcelain -- src/foreign.txt 2>/dev/null | grep -q '^??'; then
  ok "(c2) a file outside the write set is left uncommitted (no add -A)"
else
  bad "(c2) an undeclared file was swept into the salvage commit"
fi

# ── (d)(e)(f) the three refusals, each named rather than silent ────────────────
_PC_WAIT_COMMIT_DONE=0
act="$(_pc_commit_lane_on_wait)"
[[ "${act}" == "nothing_to_commit" ]] \
  && ok "(d) a clean lane reports nothing_to_commit" \
  || bad "(d) clean lane -> ${act}"

_OWN_WORKTREE=0; _PC_WAIT_COMMIT_DONE=0
act="$(_pc_commit_lane_on_wait)"
[[ "${act}" == "not_own_worktree" ]] \
  && ok "(e) an unidentified tree is never committed into" \
  || bad "(e) unidentified tree -> ${act}"
_OWN_WORKTREE=1

printf 'more\n' > "${_lane_root}/src/done.txt"
WRITES_CSV=""; _PC_WAIT_COMMIT_DONE=0
act="$(_pc_commit_lane_on_wait)"
if [[ "${act}" == "no_write_set" ]] \
   && git -C "${_lane_root}" status --porcelain -- src/done.txt | grep -q .; then
  ok "(f) no declared write set -> refuses, and commits nothing"
else
  bad "(f) empty write set -> ${act} (tree may have been committed blind)"
fi
WRITES_CSV="src/done.txt"

# ── (g) the funnel: a wait-shaped stop journals AND salvages ───────────────────
: > "${EMITTED}"
_lane_root="$(new_lane_repo)"
printf 'unsaved\n' > "${_lane_root}/src/done.txt"
_PC_WAIT_COMMIT_DONE=0
_PC_WORKER_REASON_SET=0; _PC_WORKER_REASON=""
_PC_WORKER_REASON_TEXT="I'll wait for the background suite to finish and then commit."
_PC_TERMINAL_EVIDENCE=""
_dl_note no_work arm_produced_nothing "diff=none"
if grep -q "worker_ended_on_wait task=${TASK} arm=${AUTHOR} phrase=" "${EMITTED}" \
   && grep -q 'action=committed' "${EMITTED}" \
   && [[ "${_PC_TERMINAL_EVIDENCE}" == *'ended_on_wait=committed'* ]] \
   && git -C "${_lane_root}" log --oneline -1 2>/dev/null | grep -q .; then
  ok "(g) a wait-shaped stop is journaled and the lane is committed"
else
  bad "(g) emitted=[$(tr '\n' '|' < "${EMITTED}")] evidence=[${_PC_TERMINAL_EVIDENCE}]"
fi

# ── (h) NEG-CTL: a normal stop must be untouched — mutation or not ─────────────
: > "${EMITTED}"
_lane_root="$(new_lane_repo)"
printf 'unsaved\n' > "${_lane_root}/src/done.txt"
_PC_WAIT_COMMIT_DONE=0
_PC_WORKER_REASON_SET=0; _PC_WORKER_REASON=""
_PC_WORKER_REASON_TEXT="Landed the fix; suite 12/0; nothing outstanding."
_PC_TERMINAL_EVIDENCE=""
_dl_note no_work arm_produced_nothing "diff=none"
if grep -q 'worker_ended_on_wait' "${EMITTED}" \
   || [[ "${_PC_TERMINAL_EVIDENCE}" == *'ended_on_wait='* ]]; then
  bad "(h) NEG-CTL: a normal stop fired the wait path"
elif git -C "${_lane_root}" status --porcelain -- src/done.txt | grep -q .; then
  ok "(h) NEG-CTL: a normal stop journals nothing and commits nothing"
else
  bad "(h) NEG-CTL: a normal stop committed the lane anyway"
fi

# ── (i) the kill switch is real ────────────────────────────────────────────────
: > "${EMITTED}"
_lane_root="$(new_lane_repo)"
printf 'unsaved\n' > "${_lane_root}/src/done.txt"
_PC_WAIT_COMMIT_DONE=0
_PC_WORKER_REASON_SET=0; _PC_WORKER_REASON=""
_PC_WORKER_REASON_TEXT="I'll wait for the background suite."
_PC_TERMINAL_EVIDENCE=""
LEADV2_WORKER_ENDED_ON_WAIT=0 _dl_note no_work arm_produced_nothing "diff=none"
grep -q 'worker_ended_on_wait' "${EMITTED}" \
  && bad "(i) kill switch did not stop the wait path" \
  || ok "(i) LEADV2_WORKER_ENDED_ON_WAIT=0 stops it"

# ── (j) the mission actually CARRIES the contract the detector polices ─────────
# The preamble and the detector are two halves of one row: a contract the worker is
# never shown, and a detector for a rule nobody stated, are each worth nothing.
if [[ -f "${DC_FILE}" ]] && grep -q '^## Waiting (you have no next turn)' "${DC_FILE}" \
   && grep -q 'BLOCKED: <what you are blocked on>' "${DC_FILE}"; then
  ok "(j) the dispatched mission carries the ## Waiting contract"
else
  bad "(j) the wait contract is absent from the mission preamble"
fi

printf -- '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
