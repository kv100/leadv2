#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-promise-guard.sh
# test-promise-guard-closing-promise.sh — PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01.
#
# WHY THIS TEST EXISTS: on 2026-09-13 the lead ended a turn with «Начинаю с
# пункта 1 прямо сейчас», did not start, and the guard stayed silent. The
# clause WAS detected («начинаю» is in COMMIT_RU_VERBS) but classified
# kind=None, and the None path bound "kept" to any state-changing action —
# which a Write of a scratch analysis file into the session scratchpad
# satisfied. A scratch write and a repo write were the same evidence. This
# suite pins the fix:
#   - a `start` kind exists for the begin-family (начинаю/начну/приступаю/
#     приступлю/стартую/принимаюсь), appended LAST so a concrete kind always
#     wins («Начинаю с мержа…» stays commit, «стартую фоновый воркер» stays
#     dispatch);
#   - a start- or unknown-kind promise is kept only by a state-changing
#     action on a DURABLE target — commit/dispatch by construction, a write
#     only when its target is outside the scratch prefixes (derived from
#     TMPDIR/TMP + the POSIX roots, both /private spellings, textual only);
#   - the correction names the scratch write when the turn's only write went
#     to a scratch path (the rendered acceptance surface);
#   - the five reverted false positives from 2026-08-22 stay non-blocking.
#
# CENSUS CORRECTION (implementer, 2026-09-13, probe-evidenced — the architect
# prepass claimed all five are silent AT DETECTION): N4 «...ту болотовню,
# которую контракт запрещает» and N5 «...историю, которую они рассказывают»
# ARE detected by the shipped hook — their second comma-clause opens on
# «которую», which matches COMMIT_RU_LEADING — and land in the log-only
# state (verdict=fired, kind=null, block_decision=no,
# LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=0). Nothing in this lane touches
# detection, so that pre-existing row is pinned HERE as "never blocks, kind
# stays null" instead of "no journal row". N1/N2/N3/N9 are pinned fully
# silent, as the prepass claimed for all five.
#
# Drives the REAL hook against synthetic transcripts in Claude Code's own JSONL
# shape, exactly like test-promise-guard-unknown-kind.sh. NEVER touches the
# real journal: HOME is sandboxed for the whole run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-closing.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REAL_HOME="${HOME}"
REAL_JOURNAL="${REAL_HOME}/.claude/leadv2-promise-guard.jsonl"
REAL_JOURNAL_LINES_BEFORE=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_BEFORE="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
SANDBOX_HOME="${WORK}/home"
mkdir -p "${SANDBOX_HOME}/.claude"
export HOME="${SANDBOX_HOME}"
JOURNAL="${SANDBOX_HOME}/.claude/leadv2-promise-guard.jsonl"

# The verbatim 2026-09-13 escape clauses (mission ground truth).
ESCAPE1="Начинаю с пункта 1 прямо сейчас"
ESCAPE2="Приступаю ко второму пункту"

# Scratch roots, built at runtime — never a literal machine path (the suite
# must prove the hook's DERIVATION, not a hard-coded prefix):
#   ROOT_A  the live $TMPDIR spelling (on macOS /var/folders/.../T);
#   ROOT_B  its /private twin — the spelling the hook must DERIVE from ROOT_A
#           via the twin rule; neither is a literal POSIX root on macOS.
ROOT_A="${TMPDIR:-/tmp}"
if [[ "${ROOT_A}" == /private/* ]]; then
  ROOT_B="${ROOT_A#/private}"
else
  ROOT_B="/private${ROOT_A}"
fi

# --- transcript builder ------------------------------------------------------
# Spec tokens, `||`-separated:
#   T:<text>     assistant text block
#   B:<cmd>      Bash tool_use with that command
#   TOOL:<name>  other tool_use with empty input (Write/Edit/Agent/...)
#   W:<path>     Write tool_use with an explicit file_path (this suite's
#                addition: the target is the whole point of the fix)
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
    elif tok.startswith("W:"):
        blocks.append({"type": "tool_use", "name": "Write",
                       "input": {"file_path": tok[2:]}})
    elif tok.startswith("TOOL:"):
        blocks.append({"type": "tool_use", "name": tok[5:], "input": {}})
recs.append({"type": "assistant", "message": {"role": "assistant", "content": blocks}})
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# Run the hook once on a fresh transcript. SID (exported by the caller) both
# lands in the hook's stdin AND is embedded in the scratch fixture paths, so
# the session-scoped clause is exercised with the id the hook actually holds.
# HOOK_OVERRIDE (exported by the mutation controls) swaps in a scratch COPY of
# the hook — without it the mutants below would be built and never run, and
# "control still fires" would be indistinguishable from "control disarmed".
# Prints the hook's stdout; empty means silent. Returns 2 ("could not run")
# if the hook is missing, the transcript could not be built, or the run
# exited non-zero — a broken hook and a correct silence are indistinguishable
# otherwise.
_run_hook() { # <spec> [extra env as NAME=VALUE ...]
  local spec="$1"; shift
  local hook="${HOOK_OVERRIDE:-${HOOK}}"
  [[ -f "${hook}" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${spec}" || return 2
  [[ -s "${t}" ]] || return 2
  local sid="${SID:-closing-$$-${RANDOM}-${RANDOM}}"
  local out rc
  out="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED="${LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED:-0}" \
      LEADV2_PROMISE_GUARD_BLOCK="${LEADV2_PROMISE_GUARD_BLOCK:-1}" \
      "$@" bash "${hook}" 2>/dev/null)"
  rc=$?
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
  [[ ${rc} -ne 0 ]] && return 2
  printf '%s' "${out}"
}

_journal_field() { # <n-from-end> <json-key> -> value (lists rendered as JSON)
  local n="$1" key="$2"
  [[ -f "${JOURNAL}" ]] || { printf ''; return 1; }
  tail -n "${n}" "${JOURNAL}" 2>/dev/null | head -n 1 \
    | JKEY="${key}" python3 -c '
import sys, json, os
try:
    d = json.loads(sys.stdin.read())
    v = d.get(os.environ["JKEY"])
    print(json.dumps(v, ensure_ascii=False) if isinstance(v, list) else (v if v is not None else ""))
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

# expect_fires_row <name> <spec> <want_kind> <want_durable-json> [env...]
#   block stdout AND the last journal row is verdict=fired with exactly this
#   kind and durable_kinds_seen — state 13 of the design, measurable.
expect_fires_row() {
  local name="$1" spec="$2" want_kind="$3" want_durable="$4"; shift 4
  local out rc v k d
  out="$(_run_hook "${spec}" "$@")"; rc=$?
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"; return
  fi
  if ! printf '%s' "${out}" | grep -q '"decision": "block"'; then
    bad "${name} fires (got: ${out:-<silent>})"; return
  fi
  v="$(_journal_field 1 verdict)"; k="$(_journal_field 1 primary_promise_kind)"
  d="$(_journal_field 1 durable_kinds_seen)"
  if [[ "$v" == "fired" && "$k" == "${want_kind}" && "$d" == "${want_durable}" ]]; then
    ok "${name} fires, row kind=${want_kind} durable=${want_durable}"
  else
    bad "${name} row wrong: verdict='${v}' kind='${k}' durable='${d}' (want fired/${want_kind}/${want_durable})"
  fi
}

# expect_silent_row <name> <spec> <verdict> <kind> <want_durable-json> [env...]
#   silent stdout AND the journal row carries exactly this verdict/kind/durable,
#   so "silent" is distinguishable from "not even detected".
expect_silent_row() {
  local name="$1" spec="$2" want_verdict="$3" want_kind="$4" want_durable="$5"; shift 5
  local out rc v k d
  out="$(_run_hook "${spec}" "$@")"; rc=$?
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"; return
  fi
  if [[ -n "${out}" ]]; then
    bad "${name} silent (got: ${out})"; return
  fi
  v="$(_journal_field 1 verdict)"; k="$(_journal_field 1 primary_promise_kind)"
  d="$(_journal_field 1 durable_kinds_seen)"
  if [[ "$v" == "${want_verdict}" && "$k" == "${want_kind}" && "$d" == "${want_durable}" ]]; then
    ok "${name} silent, row verdict=${want_verdict} kind=${want_kind} durable=${want_durable}"
  else
    bad "${name} journal row wrong: verdict='${v}' kind='${k}' durable='${d}' (want ${want_verdict}/${want_kind}/${want_durable})"
  fi
}

# expect_fully_silent <name> <spec> — silent stdout AND no journal row at all
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

# expect_no_block_null <name> <spec> — the CENSUS-CORRECTION pin for the two
# controls the shipped hook already DETECTS (see header): they must never
# BLOCK (nothing is rendered to the lead), and any row they append must stay
# kind=null, block_decision=no — log-only taxonomy evidence, exactly as
# before this fix. A row with a kind or a block here would mean this diff
# widened detection, which it must not.
expect_no_block_null() {
  local name="$1" spec="$2"
  local before after out rc k bd v
  before="$(_journal_lines)"
  out="$(_run_hook "${spec}")"; rc=$?
  after="$(_journal_lines)"
  if [[ ${rc} -eq 2 ]]; then
    bad "${name}: could-not-run (rc=2) -- not proof of anything"; return
  fi
  if [[ -n "${out}" ]]; then
    bad "${name} must not block (got: ${out})"; return
  fi
  if [[ "${after}" -eq "${before}" ]]; then
    ok "${name} no block, no row (stronger than required)"
    return
  fi
  k="$(_journal_field 1 primary_promise_kind)"; bd="$(_journal_field 1 block_decision)"
  v="$(_journal_field 1 verdict)"
  if [[ "$k" == "" && "$bd" == "no" && "$v" == "fired" ]]; then
    ok "${name} no block; log-only row kind=null (pre-existing detection, unchanged)"
  else
    bad "${name} row changed shape: verdict='${v}' kind='${k}' block='${bd}' (want fired//no)"
  fi
}

log "PASS: bash -n leadv2-promise-guard.sh"
bash -n "${HOOK}" 2>&1 || { bad "bash -n ${HOOK}"; }

# --- TP1. THE REAL ESCAPE: start promise, turn = scratch Write + reads only --
# The scratch path carries the session id the hook is handed and lives under
# the live $TMPDIR spelling — the measured 2026-09-13 shape. The guard MUST
# fire, the row must say kind=start with an EMPTY durable set, and the
# correction must name the scratch write (rendered acceptance surface).
SID="closing-tp1-$$-${RANDOM}-a1"
export SID
expect_fires_row "TP1 real 2026-09-13 escape (scratch write + reads) blocks" \
  "T:${ESCAPE1} || W:${ROOT_A%/}/${SID}/scratchpad/plan.md || B:grep -n x f || B:git status --short || B:wc -l f" \
  start "[]"
unset SID
out_tp1="$(_run_hook "T:${ESCAPE1} || W:${ROOT_A%/}/closing-tp1b-$$-${RANDOM}-b2/scratchpad/plan.md || B:grep -n x f")"
if printf '%s' "${out_tp1}" | grep -q 'scratch path'; then
  ok "TP1b correction names the scratch write (rendered surface)"
else
  bad "TP1b correction does not name the scratch write (got: ${out_tp1:-<silent>})"
fi

# --- TP2. second escape clause; scratch path in the /private TWIN spelling,
# session id NOT embedded — ONLY the derived twin prefix can judge it scratch.
SID="closing-tp2-$$-${RANDOM}-c3"
export SID
expect_fires_row "TP2 приступаю + /private-twin scratch write blocks" \
  "T:${ESCAPE2} || W:${ROOT_B%/}/claude-503/some-project/scratchpad/plan.md || B:grep -n x f || B:git status --short || B:wc -l f" \
  start "[]"
unset SID

# --- N1..N3. reverted 2026-08-22 controls, verbatim (fully silent) -----------
expect_fully_silent "N1 3pl recap of launched jobs" "T:Они идут параллельно и независимо"
expect_fully_silent "N2 поэтому-adverb report"      "T:Поэтому контракт теперь требует переписи вызывающих"
expect_fully_silent "N3 founder-dictated plan"      "T:дальше по твоему порядку: сначала ревью"

# --- N4..N5. reverted controls the shipped hook already detects (census
# correction, see header): never block, log-only kind=null rows.
expect_no_block_null "N4 accusative relative clause" "T:ту болтовню, которую контракт запрещает"
expect_no_block_null "N5 accusative recap clause"    "T:историю, которую они рассказывают"

# --- N6. start promise + real commit: SILENT — the work demonstrably began,
# even though the turn also wrote to scratch (commit is durable by construction).
SID="closing-n6-$$-${RANDOM}-d4"
export SID
expect_silent_row "N6 start + git commit stays silent" \
  "T:Начинаю с пункта 1 || B:git commit -m \"fix\" || W:${ROOT_A%/}/${SID}/scratchpad/x.md" \
  suppressed_action start '["commit"]'
unset SID

# --- N7. the durable-write twin of TP1: same promise, same Write TOOL, only
# the TARGET differs — proves the rule discriminates by target, not by tool.
expect_silent_row "N7 start + durable Write stays silent" \
  "T:Начинаю с пункта 1 || W:/Users/worker/Projects/leadv2/docs/x.md" \
  suppressed_action start '["write"]'

# --- N8. Write with EMPTY input must stay durable (fail-open): every
# pre-existing promise-guard fixture emits input {} — this is the regression
# pin that keeps the three older suites green.
expect_silent_row "N8 start + Write(input={}) stays silent (fail-open)" \
  "T:Начинаю с пункта 1 || TOOL:Write" \
  suppressed_action start '["write"]'

# --- N9. the noun guard: «начальник»/«начало» share the stem and must never
# classify (nor even detect).
expect_fully_silent "N9 начальник/начало nouns stay silent" "T:начальник дал добро на начало"

# --- N10. concrete kinds keep their classification (start appended LAST):
# «Начинаю с мержа…» must stay commit — and a commit keeps it.
expect_silent_row "N10 «Начинаю с мержа» keeps commit kind" \
  "T:Начинаю с мержа fix/abc || B:git merge --no-ff fix/abc" \
  suppressed_action commit '["commit"]'

# --- N11. a start promise kept ONLY by a Bash write to scratch is still
# suppressed by design (Bash writes are durable; shell parsing is out of
# scope — the design's §5(b) residual, pinned here so a future change is a
# deliberate re-verdict, not a silent drift).
expect_silent_row "N11 start + Bash scratch write stays suppressed (documented residual)" \
  "T:Начинаю с пункта 1 || B:echo notes > /tmp/leadv2-pg-notes.md" \
  suppressed_action start '["write"]'

# --- N12 (second-model review, codex 2026-09-13): the None branch must ALSO
# bind to durable evidence — every durability case above is start-kind, so a
# regression reverting ONLY the None arm to action_kinds_seen (scratch write
# counts again) would pass this suite without this pin. «доведу» is a DETECTED
# unclassified commitment (probe-verified kind=null), so blocking needs the
# BLOCK_UNCLASSIFIED opt-in; the proof is that the scratch write does NOT
# suppress the verdict — row stays fired with durable_kinds_seen=[] even
# though an action write is present in the turn.
SID="closing-n12-$$-${RANDOM}-g7"
export SID
expect_fires_row "N12 None-kind + scratch write binds to durable (opt-in block)" \
  "T:Сейчас доведу до ума || W:${ROOT_A%/}/${SID}/scratchpad/notes.md" \
  "" "[]" "LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1"
unset SID

# --- M1. NEGATIVE CONTROL: mutate is_durable_target INSIDE the function body
# (scratch hit returns True instead of False) in a scratch COPY of the real
# hook — TP1's spec must STOP firing. A suite that could not redden by
# breaking its own guarded rule would be theater, not a control.
MUTANT="${WORK}/leadv2-promise-guard.mutant1.sh"
python3 - "${HOOK}" "${MUTANT}" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = (
    "    for pre in SCRATCH_PREFIXES:\n"
    "        if path == pre or path.startswith(pre + '/'):\n"
    "            return False\n"
)
if needle not in text:
    sys.exit(3)  # anchor text moved -- refuse to fabricate a mutant
open(dst, "w").write(text.replace(needle, needle.replace("return False", "return True"), 1))
PY
if [[ $? -ne 0 ]]; then
  bad "M1 negative control: mutation anchor not found in ${HOOK} -- cannot prove the control"
else
  chmod +x "${MUTANT}"
  bash -n "${MUTANT}" 2>&1 || bad "M1 negative control: mutant fails bash -n"
  SID="closing-m1-$$-${RANDOM}-e5"
  export SID
  HOOK_OVERRIDE="${MUTANT}"
  out_m1="$(_run_hook "T:${ESCAPE1} || W:${ROOT_A%/}/${SID}/scratchpad/plan.md || B:grep -n x f")"; rc_m1=$?
  unset SID HOOK_OVERRIDE
  if [[ ${rc_m1} -eq 2 ]]; then
    bad "M1 negative control: mutant could-not-run (rc=2)"
  elif [[ -z "${out_m1}" ]]; then
    ok "M1 negative control: durability mutant reddens (TP1 goes silent when scratch counts as durable)"
  else
    bad "M1 negative control: mutant still fires -- control is disarmed (out='${out_m1}')"
  fi
fi

# --- M2. NEGATIVE CONTROL: delete the start arm from the binding condition
# (start falls to the concrete-kind branch, which no action can ever satisfy)
# — N6's spec must START firing. Proves the binding, not just the classifier.
MUTANT2="${WORK}/leadv2-promise-guard.mutant2.sh"
python3 - "${HOOK}" "${MUTANT2}" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = "if primary_kind is None or primary_kind == 'start':\n"
if needle not in text:
    sys.exit(3)  # anchor text moved -- refuse to fabricate a mutant
open(dst, "w").write(text.replace(needle, "if primary_kind is None:\n", 1))
PY
if [[ $? -ne 0 ]]; then
  bad "M2 negative control: mutation anchor not found in ${HOOK} -- cannot prove the control"
else
  chmod +x "${MUTANT2}"
  bash -n "${MUTANT2}" 2>&1 || bad "M2 negative control: mutant fails bash -n"
  SID="closing-m2-$$-${RANDOM}-f6"
  export SID
  HOOK_OVERRIDE="${MUTANT2}"
  out_m2="$(_run_hook "T:Начинаю с пункта 1 || B:git commit -m \"fix\" || W:${ROOT_A%/}/${SID}/scratchpad/x.md")"; rc_m2=$?
  unset SID HOOK_OVERRIDE
  if [[ ${rc_m2} -eq 2 ]]; then
    bad "M2 negative control: mutant could-not-run (rc=2)"
  elif printf '%s' "${out_m2}" | grep -q '"decision": "block"'; then
    ok "M2 negative control: binding mutant reddens (N6 fires when start loses its branch)"
  else
    bad "M2 negative control: mutant stayed silent -- control is disarmed (out='${out_m2:-<silent>}')"
  fi
fi

# --- control: the real journal must be untouched ------------------------------
REAL_JOURNAL_LINES_AFTER="${REAL_JOURNAL_LINES_BEFORE}"
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
LEAKED_ROWS=""
if [[ "${REAL_JOURNAL_LINES_AFTER}" -gt "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  LEAKED_ROWS="$(tail -n "+$((REAL_JOURNAL_LINES_BEFORE + 1))" "${REAL_JOURNAL}" 2>/dev/null \
    | grep -E "\"session_id\": \"closing-" -- || true)"
fi
if [[ -z "${LEAKED_ROWS}" ]]; then
  ok "control: real journal has no rows from this run (before=${REAL_JOURNAL_LINES_BEFORE} after=${REAL_JOURNAL_LINES_AFTER})"
else
  bad "control: REAL journal received this run's own rows (sid prefix closing-) despite HOME sandbox"
fi

log "closing-promise: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]] || exit 1
exit 0
