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

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_HOOK="${WORK}/pre-hook.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/hooks/leadv2-promise-guard.sh" > "${PRE_HOOK}" 2>/dev/null || : > "${PRE_HOOK}"
fi
[[ -s "${PRE_HOOK}" ]] || PRE_HOOK=""

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
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Returns FIRED if the hook produced any output (it reports/blocks), SILENT otherwise.
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
_verdict() { # <hook> <block-script>
  local hook="$1" spec="$2"
  [[ -f "$hook" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local sid="test-$$-${RANDOM}-${RANDOM}"
  local out
  out="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" | bash "${hook}" 2>/dev/null)"
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
  [[ -n "${out}" ]] && printf 'FIRED' || printf 'SILENT'
}

_expect() { # <hook> <spec> <FIRED|SILENT>
  local got; got="$(_verdict "$1" "$2")" || return 2
  [[ -z "${got}" ]] && return 2
  [[ "${got}" == "$3" ]] && return 0
  return 1
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
case_action_then_promise() { _expect "$1" "act text" SILENT; }

# A promise made and then actually acted on. Must stay silent.
case_promise_then_action() { _expect "$1" "text act" SILENT; }

# A bare promise with no work at all. Must fire (already worked pre-fix).
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

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_HOOK}" ]]; then "${fn}" "${PRE_HOOK}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${HOOK}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1)); log "COULD-NOT-RUN: ${name}"; return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
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

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
