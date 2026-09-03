#!/usr/bin/env bash
# test-promise-guard-unknown-kind.sh — PROMISE-GUARD-UNKNOWN-KIND-01.
#
# WHY THIS TEST EXISTS: on 2026-09-02 the lead ended a turn with «так что сейчас
# разбираю все три», did nothing, and the guard stayed silent. Detection worked;
# the clause classified kind=None («разбираю» was in no PROMISE_KIND_PATTERNS
# entry), and the None path bound "kept" to ANY action — a turn of pure reads
# (grep, head) satisfied it in spirit. This suite pins the fix:
#   - a `diagnose` kind exists for the look-into-it family (разбираю/смотрю/
#     выясняю/изучаю/гляну/копаю…), and a diagnose promise is kept only by a
#     state-changing action (write/commit/dispatch) or a test run — never a read;
#   - the unknown-kind path no longer accepts "any action": reads keep nothing;
#   - real status prose (past tense, artifacts, shas — verbatim sentences pinned
#     by earlier promise-guard lanes from real lead messages) stays silent.
#
# Drives the REAL hook against synthetic transcripts in Claude Code's own JSONL
# shape, exactly like test-promise-guard-classified-block.sh. NEVER touches the
# real journal: HOME is sandboxed for the whole run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-unknown-kind.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REAL_HOME="${HOME}"
REAL_JOURNAL="${REAL_HOME}/.claude/leadv2-promise-guard.jsonl"
REAL_JOURNAL_LINES_BEFORE=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_BEFORE="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
SANDBOX_HOME="${WORK}/home"
mkdir -p "${SANDBOX_HOME}/.claude"
export HOME="${SANDBOX_HOME}"
JOURNAL="${SANDBOX_HOME}/.claude/leadv2-promise-guard.jsonl"

# The verbatim 2026-09-02 escape clause (mission ground truth).
ESCAPE="Ни одну из трёх причин нельзя починить ожиданием, так что сейчас разбираю все три"

# --- transcript builder ------------------------------------------------------
# Spec tokens, `||`-separated:
#   T:<text>     assistant text block
#   B:<cmd>      Bash tool_use with that command
#   TOOL:<name>  other tool_use (Write / Edit / Agent / ...)
_transcript() { # <path> <spec>
  local path="$1" spec="$2"
  PATH_OUT="${path}" SPEC="${spec}" python3 - <<'PY'
import json, os
out, spec = os.environ["PATH_OUT"], os.environ["SPEC"]
recs = [{"type": "user", "message": {"role": "user", "content": "давай дальше"}}]
blocks = []
for tok in spec.split("||"):
    tok = tok.strip()
    if tok.startswith("T:"):
        blocks.append({"type": "text", "text": tok[2:]})
    elif tok.startswith("B:"):
        blocks.append({"type": "tool_use", "name": "Bash", "input": {"command": tok[2:]}})
    elif tok.startswith("TOOL:"):
        blocks.append({"type": "tool_use", "name": tok[5:], "input": {}})
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Run the hook once on a fresh transcript with a unique session id.
# Prints the hook's stdout; empty means silent. Returns 2 ("could not run") if
# the hook is missing, the transcript could not be built, or the journal row
# this call was supposed to append never landed. Callers MUST check the return
# code — the same discipline as test-promise-guard-classified-block.sh: a broken
# hook and a correct silence are indistinguishable otherwise.
_run_hook() { # <spec> [extra env as NAME=VALUE ...]
  local spec="$1"; shift
  [[ -f "${HOOK}" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  local sid="unknown-kind-$$-${RANDOM}-${RANDOM}"
  local out rc
  out="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED="${LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED:-0}" \
      LEADV2_PROMISE_GUARD_BLOCK="${LEADV2_PROMISE_GUARD_BLOCK:-1}" \
      "$@" bash "${HOOK}" 2>/dev/null)"
  rc=$?
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
  [[ ${rc} -ne 0 ]] && return 2
  printf '%s' "${out}"
}

_journal_field() { # <n-from-end> <json-key> -> value
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

_journal_lines() {
  [[ -f "${JOURNAL}" ]] || { printf '%s' -1; return; }
  local n
  n="$(wc -l < "${JOURNAL}" 2>/dev/null | tr -d ' ')"
  [[ -n "${n}" ]] && printf '%s' "${n}" || printf '%s' -1
}

ok()   { PASS=$((PASS + 1)); log "PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

# expect_fires <name> <spec> [env...]
expect_fires() {
  local name="$1" spec="$2"; shift 2
  local out rc
  out="$(_run_hook "${spec}" "$@")"; rc=$?
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"
  elif printf '%s' "${out}" | grep -q '"decision": "block"'; then
    ok "${name} fires"
  else
    bad "${name} fires (got: ${out:-<silent>})"
  fi
}

# expect_silent_row <name> <spec> <verdict> <kind> [env...]
#   silent stdout AND the journal row carries exactly this verdict/kind, so
#   "silent" is distinguishable from "not even detected".
expect_silent_row() {
  local name="$1" spec="$2" want_verdict="$3" want_kind="$4"; shift 4
  local out rc v k
  out="$(_run_hook "${spec}" "$@")"; rc=$?
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"; return
  fi
  if [[ -n "${out}" ]]; then
    bad "${name} silent (got: ${out})"; return
  fi
  v="$(_journal_field 1 verdict)"; k="$(_journal_field 1 primary_promise_kind)"
  if [[ "$v" == "${want_verdict}" && "$k" == "${want_kind}" ]]; then
    ok "${name} silent, row verdict=${want_verdict} kind=${want_kind}"
  else
    bad "${name} journal row wrong: verdict='${v}' kind='${k}' (want ${want_verdict}/${want_kind})"
  fi
}

# expect_fully_silent <name> <spec>  — silent stdout AND no journal row at all
# (not detected / vetoed — the DESIRED shape for finished-work prose).
expect_fully_silent() {
  local name="$1" spec="$2"
  local before out rc after
  before="$(_journal_lines)"
  out="$(_run_hook "${spec}")"; rc=$?
  after="$(_journal_lines)"
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"
  elif [[ -z "${out}" && "${after}" -eq "${before}" ]]; then
    ok "${name} silent, no journal row"
  else
    bad "${name}: out='${out:-<silent>}' rows ${before}->${after}"
  fi
}

log "PASS: bash -n leadv2-promise-guard.sh"
bash -n "${HOOK}" 2>&1 || { bad "bash -n ${HOOK}"; }

# --- 1. THE REAL ESCAPE: diagnose clause, turn = grep + head only ------------
expect_fires "1 real 2026-09-02 escape (reads only) blocks" \
  "T:${ESCAPE} || B:grep -rn foo . || B:head -30 file.sh"

# --- 2-5. same clause kept by a state-changing action, or a test run ---------
expect_silent_row "2 escape + Write stays silent" \
  "T:${ESCAPE} || TOOL:Write" suppressed_action diagnose
expect_silent_row "3 escape + Agent dispatch stays silent" \
  "T:${ESCAPE} || TOOL:Agent" suppressed_action diagnose
expect_silent_row "4 escape + git commit stays silent" \
  "T:${ESCAPE} || B:git commit -m wip" suppressed_action diagnose
expect_silent_row "5 escape + test run stays silent (a test IS digging in)" \
  "T:${ESCAPE} || B:bash tests/run-all.sh --scope changed" suppressed_action diagnose

# --- 6-8. other diagnose verbs, zero actions: the escape shape ---------------
expect_fires "6 посмотрю look-promise with no action blocks" \
  "T:Сейчас посмотрю, в чём причина"
expect_fires "7 изучаю look-promise with no action blocks" \
  "T:Изучаю fallback в supervise"
expect_fires "8 гляну look-promise with no action blocks" \
  "T:Сейчас гляну в логи"

# --- 9. truly unclassified promise + reads only: silent, fired evidence row --
expect_silent_row "9 unclassified + reads only: silent evidence row" \
  "T:Сейчас поднимаю наблюдателя || B:grep -rn x ." fired ""

# --- 10. unclassified + BLOCK_UNCLASSIFIED=1 + test-only action: FIRES -------
# The driver's unclassified verdict now follows the narrowed binding (kept only
# by state-changing action), so a test run no longer suppresses a vague
# promise. Without the opt-in this stays log-only (case 9 semantics).
expect_fires "10 unclassified + opt-in + test-only action blocks" \
  "T:Сейчас поднимаю наблюдателя || B:bash tests/run-all.sh --scope changed" \
  LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1

# --- 11-17. real status prose stays silent (verbatim lead sentences) ---------
# Provenance: each sentence is pinned verbatim by an earlier promise-guard lane
# from a real lead message (test-promise-guard-morphology.sh, suites of
# PROMISE-GUARD-BIND-01 / -MORPHOLOGY-01 / -3PL-COLLISION-01 / review-r3.md).
# A guard that fires on these gets switched off within a day.
expect_fully_silent "11 commit-sha report"   "T:Готово, коммит 1be6bcc лежит в main"
expect_fully_silent "12 deploy report"       "T:Выкатка прошла — 8cf3636 на VPS"
expect_fully_silent "13 test-pass report"    "T:Тест дал 12/12 pass"
expect_fully_silent "14 past-tense report"   "T:К отправке подготовилось только 11 человек"
expect_fully_silent "15 3pl recap of launched jobs" "T:Они идут параллельно и независимо"
expect_fully_silent "16 past-veto мигрировали" "T:Сейчас базу мигрировали вручную"
expect_fully_silent "17 поэтому-adverb report" "T:Поэтому контракт теперь требует переписи вызывающих"

# --- 18. diagnose NOUNS must not classify (kept-by-mistake guard) ------------
# «Сделаю разбор причины» is DETECTED («сделаю») but its kind must NOT become
# diagnose — «разбор» is a noun. Pinning kind=None via the journal row proves
# the diagnose dictionary only matches verb forms: a diagnose label here would
# hand the clause to the diagnose binding and change which actions keep it.
# (TURN-IT-ON-01 round 4 already fixed the unanchored-«чин»-inside-«причины»
# mislabel to write; diagnose must not re-steal it.)
expect_silent_row "18a «разбор» noun clause stays kind=None (not diagnose)" \
  "T:Сделаю разбор причины" fired ""
expect_fully_silent "18b bare noun «разбор причин» is vetoed prose" \
  "T:Разбор причин закончен, отчёт ниже"

# --- control: the real journal must be untouched ------------------------------
REAL_JOURNAL_LINES_AFTER="${REAL_JOURNAL_LINES_BEFORE}"
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
LEAKED_ROWS=""
if [[ "${REAL_JOURNAL_LINES_AFTER}" -gt "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  LEAKED_ROWS="$(tail -n "+$((REAL_JOURNAL_LINES_BEFORE + 1))" "${REAL_JOURNAL}" 2>/dev/null \
    | grep -E "\"session_id\": \"unknown-kind-$$-" -- || true)"
fi
if [[ -z "${LEAKED_ROWS}" ]]; then
  ok "control: real journal has no rows from this run (before=${REAL_JOURNAL_LINES_BEFORE} after=${REAL_JOURNAL_LINES_AFTER})"
else
  bad "control: REAL journal received this run's own rows (sid prefix unknown-kind-$$-) despite HOME sandbox"
fi

log "unknown-kind: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]] || exit 1
exit 0
