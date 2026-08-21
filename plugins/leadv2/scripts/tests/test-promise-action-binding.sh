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
# The rule under test is positional: an action counts as keeping a promise only if it
# happened AFTER the promise. A promise lives in the final assistant text block, and
# nothing follows it in this harness, so an unfulfilled promise has zero actions
# after it no matter how much work the turn did earlier.
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
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Returns FIRED if the hook produced any output (it reports/blocks), SILENT otherwise.
_verdict() { # <hook> <block-script>
  local hook="$1" spec="$2"
  [[ -f "$hook" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local out
  out="$(printf '{"transcript_path":"%s"}' "${t}" | bash "${hook}" 2>/dev/null)"
  rm -f "${t}"
  [[ -n "${out}" ]] && printf 'FIRED' || printf 'SILENT'
}

_expect() { # <hook> <spec> <FIRED|SILENT>
  local got; got="$(_verdict "$1" "$2")" || return 2
  [[ -z "${got}" ]] && return 2
  [[ "${got}" == "$3" ]] && return 0
  return 1
}

# THE ESCAPE: work happened, THEN a promise was made. Must fire.
case_action_then_promise() { _expect "$1" "act text" FIRED; }

# A promise made and then actually acted on. Must stay silent.
case_promise_then_action() { _expect "$1" "text act" SILENT; }

# A bare promise with no work at all. Must fire (already worked pre-fix).
case_promise_only()        { _expect "$1" "text" FIRED; }

# Work with no promise at all. Must stay silent — the guard must not punish a turn
# that simply reported what it did.
case_action_then_report()  { _expect "$1" "act plain" SILENT; }

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

run_case "action-then-promise-fires"  case_action_then_promise
run_case "promise-then-action-silent" case_promise_then_action
run_case "promise-only-fires"         case_promise_only
run_case "action-then-report-silent"  case_action_then_report

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
