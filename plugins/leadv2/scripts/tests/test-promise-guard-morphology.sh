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

# PROMISE-GUARD-BIND-01 round2: pinned to the same checked-in fixture as
# test-promise-action-binding.sh, not `git show HEAD:...` -- see that file's comment
# for why HEAD self-destructs the pre-fix arm once this task's own commit lands. An
# unresolvable pre-image is a HARD FAILURE, never a silent fall-through reported as a
# pass.
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_HOOK="${REPO}/docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh"
if [[ -z "${REPO}" || ! -s "${PRE_HOOK}" ]]; then
  log "FATAL: pre-fix fixture unresolvable (repo='${REPO}' fixture='${PRE_HOOK}') -- refusing to report a fake RED-then-GREEN proof"
  exit 1
fi

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

# PROMISE-GUARD-3PL-COLLISION-01: COMMIT_RU is now built as a `'|'.join(...)`
# comprehension over COMMIT_RU_VERBS instead of a self-contained alternation
# string, so exec'ing the COMMIT_RU expression needs COMMIT_RU_VERBS already in
# `ns` — grab it FIRST, but OPTIONALLY: the pre-fix hook has no such name (its
# COMMIT_RU is a bare literal, self-contained), and that absence is the entire
# point of a pre/post comparison. Treating it as required would sys.exit(2) on
# every case run against the pre-fix hook, collapsing the RED/GREEN-PRE-FIX
# distinction for the WHOLE suite into an undifferentiated "could not run".
expr = grab("COMMIT_RU_VERBS", required=False)
if expr is not None:
    try:
        exec("COMMIT_RU_VERBS = %s" % expr, ns)
    except Exception:
        pass

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
        # Evaluate in the SAME namespace the other patterns were exec'd into: the
        # leading rule is composed from RU_1SG_NONPAST, and a bare {"re": re} scope
        # silently raised NameError and dropped the rule entirely — the test then
        # reported failures that were its own, not the hook's.
        _scope = dict(ns); _scope["re"] = re
        leading = eval("re.compile(%s)" % m.group(1), _scope)
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

# --- PROMISE-GUARD-BIND-01 round2: the extractor itself, not just the binder ------
# Round-1 fixed binding (a promise is only "kept" by an action of its own kind) but
# never touched the extractor -- the round-2 review ran twelve realistic promise
# sentences (the shapes actually used by this lead, RU + EN, across all four
# classify_promise_kind kinds) through the shipped hook and found five produced NO
# journal row at all: COMMIT_RE never matched, so there was nothing for the binder to
# bind. The exact repo-history set of twelve was not committed anywhere this task
# could find (see report.md); this is a reconstructed twelve covering the same
# grammar shapes and all four kinds, anchored by the three sentences the review
# quoted verbatim. All twelve must HIT; the three quoted ones are RED against the
# pinned pre-round2 fixture (the verbs are not in ANY committed version of
# COMMIT_RU_VERBS before this task) and GREEN against the shipped hook -- a genuine
# RED-then-GREEN, not a restatement.
case_r2_01_popravlyu()   { _expect "$1" "Сейчас поправлю…" HIT; }              # write  (quoted verbatim by review)
case_r2_02_progonyu()    { _expect "$1" "Сейчас прогоню тесты" HIT; }          # test   (quoted verbatim by review)
case_r2_03_zakommichu()  { _expect "$1" "Сейчас закоммичу фикс" HIT; }         # commit (quoted verbatim by review)
case_r2_04_dispatchu()   { _expect "$1" "Сейчас диспатчу воркера на задачу" HIT; }   # dispatch
case_r2_05_podnimu()     { _expect "$1" "Сейчас подниму лейн заново" HIT; }          # dispatch/write
case_r2_06_ill_commit()  { _expect "$1" "I'll commit the fix now" HIT; }             # commit, EN
case_r2_07_ill_run()     { _expect "$1" "I'll run the test suite next" HIT; }        # test, EN
case_r2_08_zapushu()     { _expect "$1" "Сейчас запущу линт" HIT; }                  # test/write
case_r2_09_otpravlyu()   { _expect "$1" "Сейчас отправлю фикс на ревью" HIT; }       # dispatch/write
case_r2_10_sdelayu()     { _expect "$1" "Сейчас сделаю патч" HIT; }                  # write
case_r2_11_shape_marker(){ _expect "$1" "Допишу тесты этим же заходом" HIT; }        # COMMIT_RU_SHAPE
case_r2_12_bare_verb()   { _expect "$1" "Ещё раз проверю логи" HIT; }                # bare COMMIT_RU, no сейчас

# --- the negative direction: reports of DONE work must stay silent ---------------
# A guard that fires on status prose gets switched off within a day, so these matter
# as much as the hits.
case_neg_commit_sha() { _expect "$1" "Выкатка прошла — 8cf3636 на VPS" MISS; }
case_neg_test_result(){ _expect "$1" "Тест дал 12/12 pass" MISS; }
case_neg_past_report(){ _expect "$1" "К отправке подготовилось только 11 человек" MISS; }
case_neg_prose()      { _expect "$1" "Правило «что раньше» берёт три дня после письма" MISS; }
# An accusative noun in -ку/-ю with no verb and no marker must not fire.
case_neg_bare_noun()  { _expect "$1" "Проблема в постраничной выборке и ссылке" MISS; }

# PROMISE-GUARD-3PL-COLLISION-01 (2026-08-22): a recap of already-launched parallel
# work, in the 3rd-person-plural. Live escape — the founder's own words after an
# Agent call and a Workflow call both preceded this text in the same turn. Bare
# 1st-conjugation 1sg stems collide with their own 3pl form (1sg + "т" = 3pl for
# almost every verb in COMMIT_RU: иду/идут, беру/берут, поднимаю/поднимают,
# запускаю/запускают, начинаю/начинают, приземляю/приземляют, пойду/пойдут,
# сделаю/сделают). Confirmed by direct extraction against the live (pre-fix) hook:
# COMMIT_RE.search matched "иду" as a bare substring inside "идут", span (4,7).
case_neg_idut()       { _expect "$1" "Они идут параллельно и независимо" MISS; }

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

run_case "escape-chinyu-pinned"    case_escape_chinyu
run_case "escape-dobavlyu-pinned"  case_escape_dobavlyu
run_case "known-verb-no-regress"   case_known_verb
run_case "leading-first-person"    case_leading_verb

run_case "r2-01-popravlyu-write"     case_r2_01_popravlyu
run_case "r2-02-progonyu-test"       case_r2_02_progonyu
run_case "r2-03-zakommichu-commit"   case_r2_03_zakommichu
run_case "r2-04-dispatchu-dispatch"  case_r2_04_dispatchu
run_case "r2-05-podnimu-dispatch"    case_r2_05_podnimu
run_case "r2-06-ill-commit-en"       case_r2_06_ill_commit
run_case "r2-07-ill-run-en"          case_r2_07_ill_run
run_case "r2-08-zapushu"             case_r2_08_zapushu
run_case "r2-09-otpravlyu"           case_r2_09_otpravlyu
run_case "r2-10-sdelayu"             case_r2_10_sdelayu
run_case "r2-11-shape-marker"        case_r2_11_shape_marker
run_case "r2-12-bare-verb"           case_r2_12_bare_verb
run_case "neg-commit-sha"          case_neg_commit_sha
run_case "neg-test-result"         case_neg_test_result
run_case "neg-past-report"         case_neg_past_report
run_case "neg-plain-prose"         case_neg_prose
run_case "neg-bare-accusative"     case_neg_bare_noun
run_case "neg-3pl-idut-collision"  case_neg_idut

# --- the false positive this rule produced on its first live day ------------------
# Within an hour of shipping the leading-verb rule it fired on the lead's own REPORT
# of finished work — «Поэтому контракт теперь требует…» — because «поэтому» ends in
# -у and opens the clause. Same for «потому», «посему», and the dative of any
# adjective. Pinned because a guard that cries wolf on status prose gets switched off
# within a day, which costs more than the escape it was built to catch.
case_neg_poetomu()    { _expect "$1" "Поэтому контракт теперь требует переписи вызывающих" MISS; }
case_neg_potomu()     { _expect "$1" "Потому что так короче" MISS; }
case_neg_dative_adj() { _expect "$1" "Новому клиенту это ничего не сломает" MISS; }

run_case "neg-poetomu-adverb"      case_neg_poetomu
run_case "neg-potomu-adverb"       case_neg_potomu
run_case "neg-dative-adjective"    case_neg_dative_adj

# The SHAPE rule needs the same guard as the LEADING rule. When the -ому/-ему
# exclusion was written into COMMIT_RU_LEADING alone, this clause fired within the
# hour: «твоему» is a dative adjective and «дальше» is an intent marker, so the pair
# read as a commitment. One definition widened, its twin left behind — the same
# copy-drift shape fixed in the scope gate the same day.
case_neg_shape_dative()  { _expect "$1" "дальше по твоему порядку: бриф, чистка, компакт" MISS; }
case_neg_shape_adverb()  { _expect "$1" "сейчас по этому делу решения нет" MISS; }
# ...while the shape rule must still catch a real deferred commitment.
case_pos_shape_real()    { _expect "$1" "Ссылку на перебронирование добавлю тем же заходом" HIT; }

run_case "neg-shape-dative-adj"    case_neg_shape_dative
run_case "neg-shape-adverb"        case_neg_shape_adverb
run_case "pos-shape-still-fires"   case_pos_shape_real

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
