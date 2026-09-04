#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-promise-guard.sh
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
# ~/.claude (TESTS-POLLUTE-REAL-JOURNAL-01). The control at the bottom fails the suite
# if the real ~/.claude/leadv2-promise-guard.jsonl changed size during this run despite
# the sandbox -- restored here after a concurrent write to this file on disk dropped
# REAL_JOURNAL_LINES_BEFORE's initializer while keeping the code that reads it,
# producing an "unbound variable" crash under `set -u`.
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
# Prints the hook's stdout; empty means silent. Returns 2 ("could not run") if
# the hook binary is missing, the transcript could not be built, or the
# journal row this call was supposed to append never landed. Callers MUST
# check the return code -- PROMISE-GUARD-TURN-IT-ON-01 round 3: this used to
# print an empty string on ANY failure (missing hook, broken python3, no
# journal write) and every caller that expects SILENT read that empty string
# as "the hook correctly stayed silent", which is a false PASS indistinguishable
# from "the hook could not run at all". A gate that judges other work must not
# make that confusion -- see run_case's COULD_NOT_RUN handling in the sibling
# suites for the same discipline.
_run_hook() { # <spec> [extra env as NAME=VALUE ...]
  local spec="$1"; shift
  [[ -f "${HOOK}" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local sid="classified-$$-${RANDOM}-${RANDOM}"
  local out rc
  out="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED="${LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED:-0}" \
      LEADV2_PROMISE_GUARD_BLOCK="${LEADV2_PROMISE_GUARD_BLOCK:-1}" "$@" bash "${HOOK}" 2>/dev/null)"
  rc=$?
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
  [[ ${rc} -ne 0 ]] && return 2
  printf '%s' "${out}"
}

_journal_field() { # <n-from-end> <json-key> -> value of that field on the row
  local n="$1" key="$2"
  [[ -f "${JOURNAL}" ]] || { printf ''; return 1; }
  tail -n "${n}" "${JOURNAL}" 2>/dev/null | head -n 1 \
    | JKEY="${key}" python3 -c '
import sys, json, os
try:
    print(json.loads(sys.stdin.read()).get(os.environ["JKEY"]) or "")
except Exception:
    print("")'
}

# Reads the journal line count, or -1 (never a valid count, so equality checks
# against it always fail) if the file is missing or wc/python3 is broken --
# never silently treated as "0 rows, unchanged".
_journal_lines() {
  [[ -f "${JOURNAL}" ]] || { printf '%s' -1; return; }
  local n
  n="$(wc -l < "${JOURNAL}" 2>/dev/null | tr -d ' ')"
  [[ -n "${n}" ]] && printf '%s' "${n}" || printf '%s' -1
}

ok()   { PASS=$((PASS + 1)); log "PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

log "PASS: bash -n leadv2-promise-guard.sh"
bash -n "${HOOK}" 2>&1 || { bad "bash -n ${HOOK}"; }

# --- 1. classified promise + no action of that kind => BLOCKS ---------------
out="$(_run_hook "disp_promise")"; rc=$?
if [[ ${rc} -eq 2 ]]; then
  bad "1 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif printf '%s' "${out}" | grep -q '"decision": "block"'; then
  ok "1 classified unkept dispatch promise blocks"
else
  bad "1 classified unkept dispatch promise blocks (got: ${out:-<silent>})"
fi

# --- 2. classified promise + matching action => silent (regression guard) ----
# PROMISE-GUARD-TURN-IT-ON-01 round 3: "silent" alone is NOT proof the hook ran
# and correctly decided "kept" -- a broken python3/jq/grep makes the hook fail
# open with the exact same empty stdout, and a hook binary that vanished makes
# _run_hook return 2 with empty stdout too. Both must be distinguished from a
# real SILENT verdict, or this case is unfalsifiable (it was: reviewer's
# tool-injection probe found it green under every failure mode).
out="$(_run_hook "disp_promise disp_act")"; rc=$?
if [[ ${rc} -eq 2 ]]; then
  bad "2 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif [[ -z "${out}" ]]; then
  ok "2 classified kept dispatch promise silent"
else
  bad "2 classified kept dispatch promise silent (got: ${out})"
fi

# --- 3. UNCLASSIFIED promise + no action => silent, journal row still written -
LINES_BEFORE="$(_journal_lines)"
out="$(_run_hook "unclass_promise")"; rc=$?
if [[ ${rc} -eq 2 ]]; then
  bad "3 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif [[ -n "${out}" ]]; then
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
out="$(_run_hook "unclass_promise" LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1)"; rc=$?
if [[ ${rc} -eq 2 ]]; then
  bad "4 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif printf '%s' "${out}" | grep -q '"decision": "block"'; then
  ok "4 unclassified blocks under BLOCK_UNCLASSIFIED=1"
else
  bad "4 unclassified blocks under BLOCK_UNCLASSIFIED=1 (got: ${out:-<silent>})"
fi

# --- 5. LEADV2_PROMISE_GUARD_BLOCK=0 => never blocks, whatever the kind -------
out="$(_run_hook "disp_promise" LEADV2_PROMISE_GUARD_BLOCK=0)"; rc=$?
if [[ ${rc} -eq 2 ]]; then
  bad "5 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif [[ -z "${out}" ]]; then
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
LINES_BEFORE6="$(_journal_lines)"
out="$(_run_hook "plain_sha")"; rc=$?
LINES_AFTER6="$(_journal_lines)"
if [[ ${rc} -eq 2 ]]; then
  bad "6 could-not-run (rc=2) -- hook did not produce a verdict, not proof of anything"
elif [[ -z "${out}" && "${LINES_AFTER6}" -eq "${LINES_BEFORE6}" ]]; then
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
# PROMISE-JOURNAL-CONCURRENT-WRITES-01: the real journal is shared production state --
# any live session's own Stop hook can append to it concurrently, so a raw line-count
# equality check flakes red on any busy day even with zero leak. Filter the appended
# rows to this suite's own sid prefixes (classified-$$- / sentinel-$$-) instead.
REAL_JOURNAL_LINES_AFTER="${REAL_JOURNAL_LINES_BEFORE}"
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
LEAKED_ROWS=""
if [[ "${REAL_JOURNAL_LINES_AFTER}" -gt "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  LEAKED_ROWS="$(tail -n "+$((REAL_JOURNAL_LINES_BEFORE + 1))" "${REAL_JOURNAL}" 2>/dev/null \
    | grep -E "\"session_id\": \"(classified|sentinel)-$$-" -- || true)"
fi
if [[ -z "${LEAKED_ROWS}" ]]; then
  ok "control: real journal has no rows from this run (before=${REAL_JOURNAL_LINES_BEFORE} after=${REAL_JOURNAL_LINES_AFTER})"
else
  bad "control: REAL journal received this run's own rows (sid prefix classified-$$- / sentinel-$$-) despite HOME sandbox"
fi

log "classified-block: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]] || exit 1
exit 0
