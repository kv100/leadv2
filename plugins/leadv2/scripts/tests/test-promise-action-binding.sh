#!/usr/bin/env bash
# test-promise-action-binding.sh — PROMISE-ACTION-BINDING-01.
#
# WHY THIS TEST EXISTS: the promise-guard suppressed itself whenever the turn
# contained ANY action tool call, because `has_action` scanned the whole turn since
# the last user message. So a turn that did work A and then promised work B went
# unreported — the guard saw an action and stayed silent.
#
# That is how a promise escaped on 2026-08-21, hours after the guard's Russian
# patterns were widened: the turn committed REVIEW-UNION-VERDICT-01 (a real action,
# real commit) and closed with "Берусь за третье — контракт prepass…", which was
# never started. The founder caught it; the guard did not. Widening the verb
# patterns had fixed only half the escape route.
#
# SUPERSEDED 2026-08-22 (PROMISE-GUARD-POSITIONAL-REVERT-01). The positional rule this
# file was written for -- an action counts only if it happened AFTER the promise -- is
# reverted: it cost five false positives in one day against zero true catches, because a
# closing recap of work launched earlier in the turn is by definition text after its own
# actions. The escape above is therefore no longer caught, deliberately; see the comment
# on case_action_then_promise for the trade and how to reverse it. What the file still
# asserts, and what still matters, is the cheap direction: a promise with NO action
# anywhere in the turn fires, and ordinary reports of finished work stay silent.
#
# This drives the REAL hook against synthetic transcripts in Claude Code's own JSONL
# shape, so it asserts the shipped decision rather than a paraphrase of it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-bind.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# PROMISE-GUARD-BIND-01 round2: _verdict below runs the REAL hook, which appends one
# journal row per evaluated case to $HOME/.claude/leadv2-promise-guard.jsonl -- with
# no override, that is the real production journal, the same file the flip
# GO-condition in docs/leadv2/scheduled-decisions.md reads. Reviewer found 84
# synthetic "fired" rows across 84 session ids already in there purely from test
# runs, which on its own satisfies the ">=20 fired, >=3 sessions" GO-condition on
# fabricated evidence. Sandbox HOME for the whole suite; the control below fails the
# suite if the real journal changes size during this run despite the sandbox.
REAL_HOME="${HOME}"
REAL_JOURNAL="${REAL_HOME}/.claude/leadv2-promise-guard.jsonl"
REAL_JOURNAL_LINES_BEFORE=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_BEFORE="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
SANDBOX_HOME="${WORK}/home"
mkdir -p "${SANDBOX_HOME}/.claude"
export HOME="${SANDBOX_HOME}"

# PROMISE-GUARD-BIND-01 round2: the pre-image used to be `git show HEAD:...`, which
# self-destructs the moment this task's own fix is committed -- HEAD then IS the fix,
# so the "pre-fix" arm diffs the fix against itself (reviewer observed
# "0 passed(red->green), 8 green-pre-fix" post-commit). Pinned instead to a checked-in
# fixture snapshot of the hook as it stood immediately before this task
# (commit e994f07, parent of fc080bf) -- fixed content, never shifts, never re-derived
# from a ref that this task itself moves. An unresolvable pre-image is a HARD FAILURE
# (exit 1 below), never a silent fall-through that gets reported as a pass.
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_HOOK="${REPO}/docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh"
if [[ -z "${REPO}" || ! -s "${PRE_HOOK}" ]]; then
  log "FATAL: pre-fix fixture unresolvable (repo='${REPO}' fixture='${PRE_HOOK}') -- refusing to report a fake RED-then-GREEN proof"
  exit 1
fi

# Build a transcript: one real user turn, then an assistant turn whose blocks are
# described by $2 — a space-separated script of:
#   act   = an action tool_use (Bash: git commit)
#   text  = an assistant text block carrying a commitment
#   plain = an assistant text block with no commitment
_transcript() { # <path> <block-script>
  local path="$1"; shift
  local spec="$1"
  PATH_OUT="${path}" SPEC="${spec}" python3 - <<'PY'
import json, os
out, spec = os.environ["PATH_OUT"], os.environ["SPEC"].split()
recs = [{"type": "user", "message": {"role": "user", "content": "давай дальше"}}]
blocks = []
for tok in spec:
    if tok == "act":
        blocks.append({"type": "tool_use", "name": "Bash",
                       "input": {"command": "git commit -m 'real work'"}})
    elif tok == "text":
        blocks.append({"type": "text", "text": "Берусь за третье — контракт prepass"})
    elif tok == "plain":
        blocks.append({"type": "text", "text": "Готово, коммит 1be6bcc лежит в main"})
    elif tok == "recap":
        # PROMISE-GUARD-3PL-COLLISION-01: the exact founder sentence that fired
        # falsely on 2026-08-22 — a recap of two jobs already launched earlier in
        # this same turn, not a new commitment. "идут" (3rd-person-plural) collides
        # with the bare 1sg stem "иду" in an unanchored COMMIT_RU.
        blocks.append({"type": "text", "text": "Они идут параллельно и независимо"})
    elif tok == "dispatch_promise":
        # PROMISE-GUARD-BIND-01: a promise whose kind IS classifiable
        # (dispatch) via classify_promise_kind — "диспатчу" is already a
        # COMMIT_RU_VERBS entry, so this triggers a commitment on its own.
        blocks.append({"type": "text", "text": "Диспатчу воркера на задачу"})
    elif tok == "commit_promise":
        blocks.append({"type": "text", "text": "I'll commit the fix now"})
    elif tok == "write_act":
        # write-kind action: unrelated to a dispatch or commit promise.
        blocks.append({"type": "tool_use", "name": "Edit", "input": {}})
    elif tok == "dispatch_act":
        blocks.append({"type": "tool_use", "name": "Agent", "input": {}})
    elif tok == "write_promise":
        # PROMISE-GUARD-BIND-01 round2: "поправлю" only became extractable /
        # classify_promise_kind='write' this round -- see the hook's
        # COMMIT_RU_VERBS comment and PROMISE_KIND_PATTERNS 'write' entry.
        blocks.append({"type": "text", "text": "Сейчас поправлю конфиг"})
    elif tok == "devnull_act":
        # round2: ACTION_BASH_RE's old `>>?\s*\S` alternative read a stderr-to-
        # /dev/null redirect as "a write happened" -- this writes NOTHING a promise
        # could point to and must NOT be classified as the 'write' kind.
        blocks.append({"type": "tool_use", "name": "Bash",
                       "input": {"command": "grep -n foo bar.txt 2>/dev/null"}})
    elif tok == "realwrite_act":
        # a genuine file write must still classify as 'write' after the tightening.
        blocks.append({"type": "tool_use", "name": "Bash",
                       "input": {"command": "echo done > /tmp/promise-bind-out.txt"}})
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Sets GOT_OUT/GOT_RC from the hook's real run; returns 2 if the case cannot
# run at all (hook missing, transcript unbuildable) -- which run_case turns
# into a FAIL, never a skip.
#
# SENTINEL-ISOLATION-01: the hook's once-per-turn sentinel lives at a path keyed
# ONLY by session_id ($HOME/.claude/leadv2-promise-retry-<SESSION_ID>.txt). Every
# call that omits session_id falls back to the literal string "unknown", so without
# a unique id here every _verdict call in a run — across different cases, and across
# the PRE_HOOK vs. HOOK run of the SAME case — shares one sentinel file. A call that
# fires leaves the sentinel behind; the NEXT unrelated call that also fires then
# reads it as "second Stop this turn", silently consumes it, and returns SILENT for
# a reason that has nothing to do with its own commitment/action shape. That false
# contamination was verified live: with a shared session id, "промise-only-fires"
# was reported FAIL and the new recap case's SILENT verdict was unfalsifiable (it
# would have read SILENT even with no morphology fix at all, purely from a leftover
# sentinel written by the immediately-preceding PRE_HOOK call). A unique session_id
# per call gives every call its own sentinel path, so each verdict reflects only
# that call's own transcript.
GOT_OUT=""; GOT_RC=""
_verdict() { # <hook> <block-script>
  local hook="$1" spec="$2"
  [[ -f "$hook" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local sid="test-$$-${RANDOM}-${RANDOM}"
  GOT_OUT="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK=1 bash "${hook}" 2>/dev/null)"
  GOT_RC=$?
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
}

_expect() { # <hook> <spec> <FIRED|SILENT>
  GOT_OUT=""; GOT_RC=""
  _verdict "$1" "$2" || return 2
  if [[ "$3" == "FIRED" ]]; then
    # PROMISE-GUARD-TURN-IT-ON-01 r3: FIRED is the hook's REAL block shape --
    # {"decision": "block", ...} on stdout with exit 0 under
    # LEADV2_PROMISE_GUARD_BLOCK=1 -- not "printed anything". Judging any
    # non-empty output as FIRED let a hook that fails open with a stray
    # warning (or dies loudly onto stdout) count as fired. An assertion tool
    # that cannot run (grep failing) must turn the case RED, never skip it.
    [[ "${GOT_RC}" -eq 0 ]] || return 1
    printf '%s' "${GOT_OUT}" | grep -q '"decision": "block"'
  else
    # SILENT is likewise exact: the hook passed through with no output and
    # a clean exit. A crashing hook that happens to print nothing is not SILENT.
    [[ -z "${GOT_OUT}" && "${GOT_RC}" -eq 0 ]]
  fi
}

# DELIBERATELY GIVEN UP 2026-08-22 (PROMISE-GUARD-POSITIONAL-REVERT-01).
#
# This case used to assert FIRED: work happened, then an unrelated promise was made, and
# the positional binding caught it. That binding is reverted, so this shape now passes
# silently — and the assertion is inverted rather than deleted so the trade stays visible
# and reversible.
#
# WHY THE TRADE: the positional rule ("only actions AFTER the last text keep a promise")
# produced FIVE false positives against ZERO true catches in its first full day, because a
# closing recap of work launched earlier in the same turn is by definition text after its
# own actions. Every turn ending in a summary tripped it. This act-then-unrelated-promise
# shape, meanwhile, has never once been observed in a real transcript.
#
# A guard that fires on every status report gets ignored, and an ignored guard catches
# nothing at all — so we keep the cheap, reliable check (promise with NO work anywhere in
# the turn, case_promise_only below) and drop the expensive, noisy one.
#
# TO REVERT THE TRADE: restore the positional binding in the hook and flip this back to
# FIRED. Both must move together.
# TURN-IT-ON-01: the promise side is now a CLASSIFIED write promise ("Берусь за..."),
# so the action that keeps it must be write-kind — the old bare `act` (git commit,
# commit-kind) no longer keeps it, and the kind-scoped binding firing there is the
# 2026-08-21 escape being caught, not a regression. write_act (Edit) keeps it.
case_action_then_promise() { _expect "$1" "write_act text" SILENT; }

# A promise made and then actually acted on (same kind — write). Must stay silent.
case_promise_then_action() { _expect "$1" "text write_act" SILENT; }

# A bare promise with no work at all. Must fire: "Берусь за..." classifies as a
# write-kind promise (TURN-IT-ON-01 taxonomy) and no write action exists.
case_promise_only()        { _expect "$1" "text" FIRED; }

# Work with no promise at all. Must stay silent — the guard must not punish a turn
# that simply reported what it did.
case_action_then_report()  { _expect "$1" "act plain" SILENT; }

# Two jobs already launched, then a plain recap describing them in the 3rd person
# plural ("идут" = "[they] are going/running"). This is the live 2026-08-22 false
# positive: "иду" (1sg) is a bare substring of "идут" (3pl) in an unanchored
# COMMIT_RU, so a report of already-launched parallel work misread as a fresh
# commitment. Must stay silent — this is the direct falsifier for a naive \b(...)\b
# fix. (It used to double as the falsifier for un-matching "берусь"; since the
# positional revert, case_action_then_promise no longer pins that direction.)
case_action_then_recap()   { _expect "$1" "act act recap" SILENT; }

# PROMISE-GUARD-BIND-01 pair — the whole point of this task. The guard used to
# suppress on ANY action tool call; these two cases are the direct falsifier
# for that: a promise of a classifiable kind (dispatch) must be bound to an
# action of the SAME kind, not just any action.
#
# Matching kind: promise = dispatch, action = Agent (dispatch-kind) -> kept, SILENT.
# This is already correct pre-fix too (pre-fix suppresses on ANY action), so
# expect GREEN-PRE-FIX here — it locks the "must still pass" half of the pair.
case_dispatch_promise_matching_action()   { _expect "$1" "dispatch_promise dispatch_act" SILENT; }

# Mismatched kind: promise = dispatch, action = Edit (write-kind, unrelated) ->
# NOT kept, must FIRE. Pre-fix this reads SILENT (any action suppresses), so
# this is the RED-then-GREEN control that proves the binding fix actually
# rejects an unrelated tool call rather than accepting it.
case_dispatch_promise_unrelated_action()  { _expect "$1" "dispatch_promise write_act" FIRED; }

# Sanity companion: a classifiable commit-kind promise kept by its own kind.
case_commit_promise_matching_action()     { _expect "$1" "commit_promise act" SILENT; }

# PROMISE-GUARD-BIND-01 round2: a write-kind promise (new extractor form,
# "поправлю") followed ONLY by a `2>/dev/null` redirect must still FIRE -- that
# redirect writes nothing, so a write promise is not kept. This is a genuine
# RED-then-GREEN against the round1 pre-fix fixture too, since e994f07's
# ACTION_BASH_RE catch-all suppressed on ANY bash call regardless of kind.
case_write_promise_devnull_unrelated()    { _expect "$1" "write_promise devnull_act" FIRED; }

# Companion: a REAL write (`> /tmp/...`) after the same promise must keep it,
# proving the tightened regex didn't also blind the write kind to genuine writes.
case_write_promise_real_write_matches()   { _expect "$1" "write_promise realwrite_act" SILENT; }

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  "${fn}" "${PRE_HOOK}" >/dev/null 2>&1; pre_rc=$?
  "${fn}" "${HOOK}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix could-not-run (rc=2)")
    log "FAIL: ${name} -- post-fix could-not-run (rc=2)"; return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  # PROMISE-GUARD-BIND-01 round2: pre_rc=2 (pre-fix arm could not run at all) used to
  # fall through to the PASS/RED-then-GREEN branch below -- a pre-image that never ran
  # is not proof of anything, and reporting it as "passed(red->green)" is exactly the
  # fabricated-evidence shape the reviewer caught (a non-git dir printed
  # "8 passed(red->green)" with the pre-image never resolved). Now a hard failure.
  if [[ ${pre_rc} -eq 2 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: pre-fix could-not-run (rc=2) -- RED-then-GREEN proof invalid")
    log "FAIL: ${name} -- pre-fix arm could not run; proof is invalid, not a pass"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the pre-fix hook too (pre_rc=0)"; return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n leadv2-promise-guard.sh"
bash -n "${HOOK}" || { log "FAIL: bash -n"; exit 1; }

run_case "action-then-promise-now-silent" case_action_then_promise
run_case "promise-then-action-silent" case_promise_then_action
run_case "promise-only-fires"         case_promise_only
run_case "action-then-report-silent"  case_action_then_report
run_case "action-then-recap-silent"   case_action_then_recap
run_case "dispatch-promise-matching-action-silent"  case_dispatch_promise_matching_action
run_case "dispatch-promise-unrelated-action-fires"  case_dispatch_promise_unrelated_action
run_case "commit-promise-matching-action-silent"    case_commit_promise_matching_action
run_case "write-promise-devnull-unrelated-fires"    case_write_promise_devnull_unrelated
run_case "write-promise-real-write-matches-silent"  case_write_promise_real_write_matches

# --- sandbox control: this suite must never write the real journal ---------------
REAL_JOURNAL_LINES_AFTER=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
if [[ "${REAL_JOURNAL_LINES_AFTER}" != "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  FAIL=$((FAIL + 1))
  ERRORS+=("sandbox-escape: ${REAL_JOURNAL} grew from ${REAL_JOURNAL_LINES_BEFORE} to ${REAL_JOURNAL_LINES_AFTER} lines during this run despite HOME sandbox")
  log "FAIL: sandbox-escape -- real journal changed during test run"
else
  log "PASS: sandbox-control -- real journal ${REAL_JOURNAL} unchanged (${REAL_JOURNAL_LINES_BEFORE} lines)"
fi

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
