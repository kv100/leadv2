#!/usr/bin/env bash
# test-promise-guard-classified-block.sh — PROMISE-GUARD-TURN-IT-ON-01.
#
# WHY THIS TEST EXISTS: the promise-guard shipped log-only (LEADV2_PROMISE_GUARD_BLOCK
# default "0"), so 423 unkept promises were journaled and blocked zero times. The flip
# gates blocking on whether the promise kind is CLASSIFIED: a classified unkept promise
# blocks, an unclassified one is journaled (evidence for widening the taxonomy) but does
# not block unless LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1 opts in.
#
# This drives the REAL hook against synthetic transcripts in Claude Code's own JSONL
# shape, exactly like test-promise-action-binding.sh, and asserts the shipped decision —
# including the journal row's verdict/block_decision fields, not just silence/blocking.
#
# NEVER touches the real journal: HOME is sandboxed for the whole run, and a control
# fails the suite if the real ~/.claude/leadv2-promise-guard.jsonl changed size.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-classified.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# Sandbox HOME so the hook's journal and sentinel writes land here, not in the real
# ~/.claude (TESTS-POLLUTE-REAL-JOURNAL-01). Pin a control on the real journal size.
REAL_HOME="${HOME}"
REAL_JOURNAL="${REAL_HOME}/.claude/leadv2-promise-guard.jsonl"
REAL_JOURNAL_LINES_BEFORE=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_BEFORE="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
SANDBOX_HOME="${WORK}/home"
mkdir -p "${SANDBOX_HOME}/.claude"
export HOME="${SANDBOX_HOME}"
JOURNAL="${SANDBOX_HOME}/.claude/leadv2-promise-guard.jsonl"

# --- transcript builder ------------------------------------------------------
# One user turn + one assistant turn whose blocks follow $2 (space-separated):
#   disp_promise    = classified dispatch promise ("Диспатчу воркера на задачу")
#   unclass_promise = unclassified fire ("Сейчас поднимаю наблюдателя" — the
#                     COMMIT_RU_NOW "поднимаю" stem makes it a commitment shape,
#                     PROMISE_KIND_PATTERNS have no "подним" so kind stays None)
#   plain_sha       = past-tense report carrying a sha (no commitment shape)
#   disp_act        = dispatch-kind action (Agent tool_use)
#   edit_act        = write-kind action (Edit tool_use)
_transcript() { # <path> <block-script>
  local path="$1"; shift
  local spec="$1"
  PATH_OUT="${path}" SPEC="${spec}" python3 - <<'PY'
import json, os
out, spec = os.environ["PATH_OUT"], os.environ["SPEC"].split()
recs = [{"type": "user", "message": {"role": "user", "content": "давай дальше"}}]
blocks = []
for tok in spec:
    if tok == "disp_promise":
        blocks.append({"type": "text", "text": "Диспатчу воркера на задачу"})
    elif tok == "unclass_promise":
        blocks.append({"type": "text", "text": "Сейчас поднимаю наблюдателя"})
    elif tok == "plain_sha":
        blocks.append({"type": "text", "text": "Готово, коммит 1be6bcc лежит в main"})
    elif tok == "disp_act":
        blocks.append({"type": "tool_use", "name": "Agent", "input": {}})
    elif tok == "edit_act":
        blocks.append({"type": "tool_use", "name": "Edit", "input": {}})
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Run the hook once on a fresh transcript with a unique session id.
# Prints the hook's stdout; empty means silent.
_run_hook() { # <spec> [extra env as NAME=VALUE ...]
  local spec="$1"; shift
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local sid="classified-$$-${RANDOM}-${RANDOM}"
  local out
  out="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED="${LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED:-0}" \
      LEADV2_PROMISE_GUARD_BLOCK="${LEADV2_PROMISE_GUARD_BLOCK:-1}" "$@" bash "${HOOK}" 2>/dev/null)"
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
  printf '%s' "${out}"
}

_journal_field() { # <n-from-end> <json-key> -> value of that field on the row
  local n="$1" key="$2"
  tail -n "${n}" "${JOURNAL}" 2>/dev/null | head -n 1 \
    | JKEY="${key}" python3 -c '
import sys, json, os
try:
    print(json.loads(sys.stdin.read()).get(os.environ["JKEY"]) or "")
except Exception:
    print("")'
}

ok()   { PASS=$((PASS + 1)); log "PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

# --- 1. classified promise + no action of that kind => BLOCKS ---------------
out="$(_run_hook "disp_promise")"
if printf '%s' "${out}" | grep -q '"decision": "block"'; then
  ok "1 classified unkept dispatch promise blocks"
else
  bad "1 classified unkept dispatch promise blocks (got: ${out:-<silent>})"
fi

# --- 2. classified promise + matching action => silent (regression guard) ----
out="$(_run_hook "disp_promise disp_act")"
if [[ -z "${out}" ]]; then
  ok "2 classified kept dispatch promise silent"
else
  bad "2 classified kept dispatch promise silent (got: ${out})"
fi

# --- 3. UNCLASSIFIED promise + no action => silent, journal row still written -
LINES_BEFORE="$(wc -l < "${JOURNAL}" 2>/dev/null | tr -d ' ')"; LINES_BEFORE="${LINES_BEFORE:-0}"
out="$(_run_hook "unclass_promise")"
if [[ -n "${out}" ]]; then
  bad "3 unclassified promise does not block (got: ${out})"
else
  v="$(_journal_field 1 verdict)"; bd="$(_journal_field 1 block_decision)"; k="$(_journal_field 1 primary_promise_kind)"
  if [[ "$v" == "fired" && "$bd" == "no" && "$k" == "" ]]; then
    ok "3 unclassified promise silent, row journaled fired/block_decision=no/kind=None"
  else
    bad "3 unclassified journal row wrong: verdict='${v}' block_decision='${bd}' kind='${k}'"
  fi
fi

# --- 4. same unclassified promise with BLOCK_UNCLASSIFIED=1 => BLOCKS --------
out="$(_run_hook "unclass_promise" LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1)"
if printf '%s' "${out}" | grep -q '"decision": "block"'; then
  ok "4 unclassified blocks under BLOCK_UNCLASSIFIED=1"
else
  bad "4 unclassified blocks under BLOCK_UNCLASSIFIED=1 (got: ${out:-<silent>})"
fi

# --- 5. LEADV2_PROMISE_GUARD_BLOCK=0 => never blocks, whatever the kind -------
out="$(_run_hook "disp_promise" LEADV2_PROMISE_GUARD_BLOCK=0)"
if [[ -z "${out}" ]]; then
  bd="$(_journal_field 1 block_decision)"
  if [[ "$bd" == "yes" ]]; then
    ok "5 BLOCK=0: classified unkept promise silent, block_decision=yes still journaled"
  else
    bad "5 BLOCK=0: journal block_decision='${bd}' (expected yes)"
  fi
else
  bad "5 BLOCK=0 never blocks (got: ${out})"
fi

# --- 6. past-tense report with a sha => never blocks, no row -----------------
LINES_BEFORE6="$(wc -l < "${JOURNAL}" 2>/dev/null | tr -d ' ')"; LINES_BEFORE6="${LINES_BEFORE6:-0}"
out="$(_run_hook "plain_sha")"
LINES_AFTER6="$(wc -l < "${JOURNAL}" 2>/dev/null | tr -d ' ')"; LINES_AFTER6="${LINES_AFTER6:-0}"
if [[ -z "${out}" && "${LINES_AFTER6}" -eq "${LINES_BEFORE6}" ]]; then
  ok "6 past-tense sha report silent, no journal row"
else
  bad "6 past-tense sha report: out='${out:-<silent>}' rows ${LINES_BEFORE6}->${LINES_AFTER6}"
fi

# --- 7. two Stop events in one turn => blocks at most once -------------------
t="${WORK}/sentinel.jsonl"
_transcript "${t}" "disp_promise" || { bad "7 transcript build failed"; }
sid="sentinel-$$-${RANDOM}"
out1="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
  | env LEADV2_PROMISE_GUARD_BLOCK=1 bash "${HOOK}" 2>/dev/null)"
out2="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
  | env LEADV2_PROMISE_GUARD_BLOCK=1 bash "${HOOK}" 2>/dev/null)"
rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
if printf '%s' "${out1}" | grep -q '"decision": "block"' && [[ -z "${out2}" ]]; then
  ok "7 two Stops same turn: first blocks, second passes through"
else
  bad "7 sentinel: first='${out1:-<silent>}' second='${out2:-<silent>}'"
fi

# --- control: the real journal must be untouched ------------------------------
REAL_JOURNAL_LINES_AFTER="${REAL_JOURNAL_LINES_BEFORE}"
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
if [[ "${REAL_JOURNAL_LINES_AFTER}" -eq "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  ok "control: real journal untouched (${REAL_JOURNAL_LINES_BEFORE} lines)"
else
  bad "control: REAL journal changed ${REAL_JOURNAL_LINES_BEFORE} -> ${REAL_JOURNAL_LINES_AFTER}"
fi

log "classified-block: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]] || exit 1
exit 0
