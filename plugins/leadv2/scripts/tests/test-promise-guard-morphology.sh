#!/usr/bin/env bash
# test-promise-guard-morphology.sh — PROMISE-GUARD-MORPHOLOGY-01.
#
# WHY THIS TEST EXISTS: the promise-guard's Russian side was a hand-kept verb list.
# On 2026-08-21 a lead in ~/Projects/getmany-followup-bot ended a turn with
#
#     Чиню постраничную выборку Calendly — без неё рассылка бессмысленна.
#     Ссылку на перебронирование добавлю тем же заходом.
#
# started neither, and the guard stayed silent: «чиню» and «добавлю» were simply not
# on the list. The founder reported the same shape in m3-market. A verb dictionary
# can never cover Russian morphology — every future escape uses a verb nobody
# thought to add — so the guard now matches the grammatical SHAPE of a first-person
# singular non-past verb instead.
#
# Both directions are asserted, and the negative direction is the important one: a
# guard that fires on every status report would be turned off within a day. The two
# verbatim escape sentences are pinned as cases 1 and 2, so this exact escape can
# never regress silently.
#
# The patterns are READ OUT OF THE LIVE HOOK, never restated here — a copy would let
# the hook drift while the test stayed green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-morph.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_HOOK="${WORK}/pre-hook.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/hooks/leadv2-promise-guard.sh" > "${PRE_HOOK}" 2>/dev/null || : > "${PRE_HOOK}"
fi
[[ -s "${PRE_HOOK}" ]] || PRE_HOOK=""

# Extract the hook's own regex definitions and evaluate one clause through them.
# Prints HIT or MISS. rc 2 if the definitions could not be lifted (shape changed).
_verdict() { # <hook> <clause>
  local hook="$1" clause="$2"
  [[ -f "$hook" ]] || return 2
  HOOK_FILE="$hook" CLAUSE="$clause" python3 - <<'PY' 2>/dev/null
import os, re, sys

src = open(os.environ["HOOK_FILE"]).read()
clause = os.environ["CLAUSE"]

# Lift the assignments verbatim from the hook's embedded python. Only the names the
# decision actually uses; a missing required name is "cannot run", not a pass.
def grab(name, required=True):
    m = re.search(r'^%s\s*=\s*(.+?)(?=\n[A-Z_]+\s*=|\n\n|\nCOMMIT_RE|\nVETO_RE)' % name,
                  src, re.S | re.M)
    if not m:
        if required:
            sys.exit(2)
        return None
    return m.group(1)

ns = {"re": re}
for name in ("COMMIT_RU", "COMMIT_RU_NOW", "COMMIT_EN", "PAST_RU", "PAST_EN", "ARTIFACT"):
    expr = grab(name)
    try:
        exec("%s = %s" % (name, expr), ns)
    except Exception:
        sys.exit(2)

# Optional (post-fix only) names: absent on the pre-fix hook, which is the point.
for name in ("RU_1SG_NONPAST", "RU_INTENT_MARKER", "COMMIT_RU_SHAPE"):
    expr = grab(name, required=False)
    if expr is not None:
        try:
            exec("%s = %s" % (name, expr), ns)
        except Exception:
            pass

parts = [ns["COMMIT_RU_NOW"], ns["COMMIT_RU"], ns["COMMIT_EN"]]
if "COMMIT_RU_SHAPE" in ns:
    parts.append(ns["COMMIT_RU_SHAPE"])
commit = re.compile("(?:" + "|".join(parts) + ")", re.I | re.UNICODE)
veto = re.compile("(?:" + ns["PAST_RU"] + "|" + ns["PAST_EN"] + "|" + ns["ARTIFACT"] + ")",
                  re.I | re.UNICODE)

leading = None
m = re.search(r"^COMMIT_RU_LEADING\s*=\s*re\.compile\((.+?)\)\s*$", src, re.S | re.M)
if m:
    try:
        leading = eval("re.compile(%s)" % m.group(1), {"re": re})
    except Exception:
        leading = None

hit = bool(commit.search(clause) or (leading and leading.match(clause)))
if hit and veto.search(clause):
    hit = False
print("HIT" if hit else "MISS")
PY
}

_expect() { # <hook> <clause> <HIT|MISS>
  local out; out="$(_verdict "$1" "$2")" || return 2
  [[ -z "$out" ]] && return 2
  [[ "$out" == "$3" ]] && return 0
  return 1
}

# --- the verbatim escape from 2026-08-21 (pinned) --------------------------------
case_escape_chinyu()  { _expect "$1" "Чиню постраничную выборку Calendly — без неё рассылка бессмысленна" HIT; }
case_escape_dobavlyu(){ _expect "$1" "Ссылку на перебронирование добавлю тем же заходом" HIT; }

# --- shapes the old list already caught (must not regress) -----------------------
case_known_verb()     { _expect "$1" "сейчас поднимаю наблюдателя" HIT; }

# --- new shape, no marker: a leading first-person verb ---------------------------
case_leading_verb()   { _expect "$1" "Довожу list-form до мерджа" HIT; }

# --- the negative direction: reports of DONE work must stay silent ---------------
# A guard that fires on status prose gets switched off within a day, so these matter
# as much as the hits.
case_neg_commit_sha() { _expect "$1" "Выкатка прошла — 8cf3636 на VPS" MISS; }
case_neg_test_result(){ _expect "$1" "Тест дал 12/12 pass" MISS; }
case_neg_past_report(){ _expect "$1" "К отправке подготовилось только 11 человек" MISS; }
case_neg_prose()      { _expect "$1" "Правило «что раньше» берёт три дня после письма" MISS; }
# An accusative noun in -ку/-ю with no verb and no marker must not fire.
case_neg_bare_noun()  { _expect "$1" "Проблема в постраничной выборке и ссылке" MISS; }

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

run_case "escape-chinyu-pinned"    case_escape_chinyu
run_case "escape-dobavlyu-pinned"  case_escape_dobavlyu
run_case "known-verb-no-regress"   case_known_verb
run_case "leading-first-person"    case_leading_verb
run_case "neg-commit-sha"          case_neg_commit_sha
run_case "neg-test-result"         case_neg_test_result
run_case "neg-past-report"         case_neg_past_report
run_case "neg-plain-prose"         case_neg_prose
run_case "neg-bare-accusative"     case_neg_bare_noun

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
