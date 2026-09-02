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
# PROMISE-GUARD-BIND-01 round4: this suite used to lift the hook's regex
# assignments out with a source-level `grab()` and re-exec them in a bare Python
# namespace — a PARAPHRASE of the decision, not the decision itself. The parser
# broke silently the moment COMMIT_RU_SHAPE grew a third name (RU_OTHER_FINITE_VERB)
# it didn't know to lift, and the suite would have stayed green forever measuring a
# stale copy while the real hook did something else entirely (review-r3.md, second
# High finding). It now drives the REAL hook end-to-end exactly the way
# test-promise-action-binding.sh does: a synthetic Stop-hook transcript, a sandboxed
# HOME so this suite never touches the production journal, and FIRED/SILENT read
# off the hook's own stdout — never a restated regex.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/leadv2-promise-guard.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/promise-morph.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# PROMISE-GUARD-BIND-01 round2: _verdict below runs the REAL hook, which appends one
# journal row per evaluated case to $HOME/.claude/leadv2-promise-guard.jsonl -- with
# no override, that is the real production journal, the same file the flip
# GO-condition in docs/leadv2/scheduled-decisions.md reads. Sandbox HOME for the
# whole suite; the control at the bottom fails the suite if the real journal
# changes size during this run despite the sandbox.
REAL_HOME="${HOME}"
REAL_JOURNAL="${REAL_HOME}/.claude/leadv2-promise-guard.jsonl"
REAL_JOURNAL_LINES_BEFORE=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_BEFORE="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
SANDBOX_HOME="${WORK}/home"
mkdir -p "${SANDBOX_HOME}/.claude"
export HOME="${SANDBOX_HOME}"

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

# Build a transcript carrying exactly one assistant turn: a single text block with
# the clause under test and NO tool calls at all, so the verdict is the extractor's
# alone, never contaminated by the action-binding suppression this file doesn't test.
_transcript() { # <path> <clause>
  local path="$1" clause="$2"
  PATH_OUT="${path}" CLAUSE="${clause}" python3 - <<'PY'
import json, os
out, clause = os.environ["PATH_OUT"], os.environ["CLAUSE"]
recs = [
    {"type": "user", "message": {"role": "user", "content": "давай дальше"}},
    {"type": "assistant", "message": {"role": "assistant",
        "content": [{"type": "text", "text": clause}]}},
]
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# PROMISE-GUARD-BIND-01 round2 (SENTINEL-ISOLATION-01): a unique session_id per call
# gives every call its own once-per-turn sentinel path, so no call's verdict is
# contaminated by a sentinel a PRIOR call in this same run left behind.
#
# PROMISE-GUARD-TURN-IT-ON-01 r3: _verdict no longer returns a verdict word. It
# records the hook's real stdout (GOT_OUT) and exit code (GOT_RC); _expect asserts
# the honest shape below -- FIRED means the hook's actual {"decision": "block"}
# emission with exit 0, SILENT means no output with exit 0. The old "any output =
# FIRED" let a hook failing open with a stray warning count as fired, and the
# suite used no assertion tool whose breakage could turn it red.
GOT_OUT=""; GOT_RC=""
_verdict() { # <hook> <clause>
  local hook="$1" clause="$2"
  [[ -f "$hook" ]] || return 2
  local t="${WORK}/t.$$.jsonl"
  _transcript "${t}" "${clause}" || return 2
  local sid="test-$$-${RANDOM}-${RANDOM}"
  GOT_OUT="$(printf '{"transcript_path":"%s","session_id":"%s"}' "${t}" "${sid}" \
    | env LEADV2_PROMISE_GUARD_BLOCK=1 bash "${hook}" 2>/dev/null)"
  GOT_RC=$?
  rm -f "${t}" "${HOME}/.claude/leadv2-promise-retry-${sid}.txt"
}

_expect() { # <hook> <clause> <FIRED|SILENT>
  GOT_OUT=""; GOT_RC=""
  _verdict "$1" "$2" || return 2
  if [[ "$3" == "FIRED" ]]; then
    [[ "${GOT_RC}" -eq 0 ]] || return 1
    printf '%s' "${GOT_OUT}" | grep -q '"decision": "block"'
  else
    [[ -z "${GOT_OUT}" && "${GOT_RC}" -eq 0 ]]
  fi
}

# --- the verbatim escape from 2026-08-21 (pinned) --------------------------------
case_escape_chinyu()  { _expect "$1" "Чиню постраничную выборку Calendly — без неё рассылка бессмысленна" FIRED; }
case_escape_dobavlyu(){ _expect "$1" "Ссылку на перебронирование добавлю тем же заходом" FIRED; }

# --- shapes the old list already caught (must not regress) -----------------------
case_known_verb()     { _expect "$1" "сейчас поднимаю наблюдателя" SILENT; }

# --- new shape, no marker: a leading first-person verb ---------------------------
case_leading_verb()   { _expect "$1" "Довожу list-form до мерджа" FIRED; }

# --- PROMISE-GUARD-BIND-01 round3: the ORIGINAL review-r1.md:88-98 eleven --------
# Round-1 fixed binding (a promise is only "kept" by an action of its own kind) but
# never touched the extractor. The round-2 review (review-r1.md:88-98) ran these
# eleven realistic promise sentences (the shapes actually used by this lead, RU + EN)
# through the shipped hook and reported "5 of 12 textbook lead promises produce no
# journal row at all" -- COMMIT_RE never matched, so there was nothing for the binder
# to bind. Round 3 restores the reviewer's own set verbatim, from this lane's own
# handoff directory. The two hardest ones -- "Сейчас напишу отчёт" and "Сейчас
# исправлю биндинг" -- use 1sg verbs that are not in COMMIT_RU_VERBS and open with
# the marker "сейчас" BEFORE the verb, which COMMIT_RU_SHAPE (verb-then-marker only)
# could not match at all pre-round-3.
case_r1_01_popravlyu()  { _expect "$1" "Сейчас поправлю регэксп в хуке" FIRED; }
case_r1_02_progonyu()   { _expect "$1" "Сейчас прогоню тесты" FIRED; }
case_r1_03_zakommichu() { _expect "$1" "Сейчас закоммичу фикс" FIRED; }
case_r1_04_napishu()    { _expect "$1" "Сейчас напишу отчёт" FIRED; }             # marker-before-verb, no listed verb
case_r1_05_ispravlyu()  { _expect "$1" "Сейчас исправлю биндинг" FIRED; }         # marker-before-verb, no listed verb
case_r1_06_dispatchu()  { _expect "$1" "Сейчас диспатчу воркера" FIRED; }
case_r1_07_podnimu()    { _expect "$1" "Сейчас подниму лейн" FIRED; }
case_r1_08_beru()       { _expect "$1" "Дальше беру третий таск" FIRED; }
case_r1_09_ill_dispatch(){ _expect "$1" "I'll dispatch the lane now" FIRED; }
case_r1_10_going_to_run(){ _expect "$1" "Now I'm going to run the suite" FIRED; }
case_r1_11_podnimayu()  { _expect "$1" "Сейчас поднимаю наблюдателя" SILENT; }

# --- marker-before-verb order, whole допишу/перепишу/обновлю/смерджу/добавлю family --
# The review named this exact family as dead the same way: a leading «сейчас» disables
# COMMIT_RU_SHAPE's verb-then-marker order and the sentence falls through to the
# COMMIT_RU_VERBS whitelist, which none of these five are on.
case_r3_dopishu()   { _expect "$1" "Сейчас допишу тесты" FIRED; }
case_r3_perepishu() { _expect "$1" "Сейчас перепишу регэксп" FIRED; }
case_r3_obnovlyu()  { _expect "$1" "Сейчас обновлю фикстуры" FIRED; }
case_r3_smerdzhu()  { _expect "$1" "Сейчас смерджу ветку" FIRED; }
case_r3_dobavlyu()  { _expect "$1" "Сейчас добавлю кейс" FIRED; }

# --- the negative direction: reports of DONE work must stay silent ---------------
# A guard that fires on status prose gets switched off within a day, so these matter
# as much as the hits.
case_neg_commit_sha() { _expect "$1" "Выкатка прошла — 8cf3636 на VPS" SILENT; }
case_neg_test_result(){ _expect "$1" "Тест дал 12/12 pass" SILENT; }
case_neg_past_report(){ _expect "$1" "К отправке подготовилось только 11 человек" SILENT; }
case_neg_prose()      { _expect "$1" "Правило «что раньше» берёт три дня после письма" SILENT; }
# An accusative noun in -ку/-ю with no verb and no marker must not fire.
case_neg_bare_noun()  { _expect "$1" "Проблема в постраничной выборке и ссылке" SILENT; }

# PROMISE-GUARD-3PL-COLLISION-01 (2026-08-22): a recap of already-launched parallel
# work, in the 3rd-person-plural. Live escape — the founder's own words after an
# Agent call and a Workflow call both preceded this text in the same turn. Bare
# 1st-conjugation 1sg stems collide with their own 3pl form (1sg + "т" = 3pl for
# almost every verb in COMMIT_RU: иду/идут, беру/берут, поднимаю/поднимают,
# запускаю/запускают, начинаю/начинают, приземляю/приземляют, пойду/пойдут,
# сделаю/сделают).
case_neg_idut()       { _expect "$1" "Они идут параллельно и независимо" SILENT; }

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

run_case "r1-01-popravlyu"    case_r1_01_popravlyu
run_case "r1-02-progonyu"     case_r1_02_progonyu
run_case "r1-03-zakommichu"   case_r1_03_zakommichu
run_case "r1-04-napishu"      case_r1_04_napishu
run_case "r1-05-ispravlyu"    case_r1_05_ispravlyu
run_case "r1-06-dispatchu"    case_r1_06_dispatchu
run_case "r1-07-podnimu"      case_r1_07_podnimu
run_case "r1-08-beru"         case_r1_08_beru
run_case "r1-09-ill-dispatch" case_r1_09_ill_dispatch
run_case "r1-10-going-to-run" case_r1_10_going_to_run
run_case "r1-11-podnimayu"    case_r1_11_podnimayu

run_case "r3-dopishu"    case_r3_dopishu
run_case "r3-perepishu"  case_r3_perepishu
run_case "r3-obnovlyu"   case_r3_obnovlyu
run_case "r3-smerdzhu"   case_r3_smerdzhu
run_case "r3-dobavlyu"   case_r3_dobavlyu

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
case_neg_poetomu()    { _expect "$1" "Поэтому контракт теперь требует переписи вызывающих" SILENT; }
case_neg_potomu()     { _expect "$1" "Потому что так короче" SILENT; }
case_neg_dative_adj() { _expect "$1" "Новому клиенту это ничего не сломает" SILENT; }

run_case "neg-poetomu-adverb"      case_neg_poetomu
run_case "neg-potomu-adverb"       case_neg_potomu
run_case "neg-dative-adjective"    case_neg_dative_adj

# The SHAPE rule needs the same guard as the LEADING rule. When the -ому/-ему
# exclusion was written into COMMIT_RU_LEADING alone, this clause fired within the
# hour: «твоему» is a dative adjective and «дальше» is an intent marker, so the pair
# read as a commitment. One definition widened, its twin left behind — the same
# copy-drift shape fixed in the scope gate the same day.
case_neg_shape_dative()  { _expect "$1" "дальше по твоему порядку: бриф, чистка, компакт" SILENT; }
# ...while the shape rule must still catch a real deferred commitment.
case_pos_shape_real()    { _expect "$1" "Ссылку на перебронирование добавлю тем же заходом" FIRED; }

run_case "neg-shape-dative-adj"    case_neg_shape_dative
run_case "pos-shape-still-fires"   case_pos_shape_real

# PROMISE-GUARD-BIND-01 round4: review-r3.md's second High finding — the pinned
# negative that used to stand here, «сейчас по этому делу решения нет», is blocked
# by the PREPOSITION sub-case of adjacency (the marker's next word is "по", too
# short and not verb-shaped) and proves nothing about the sub-case that actually
# broke round 3: a marker followed DIRECTLY by an accusative-case noun that happens
# to share the -у/-ю ending with a first-person verb. Ten hand-written status
# clauses, measured through the real (round-3) hook before this fix, six of them
# false-positive `fired` (review-r3.md:105-118). All ten pinned here as SILENT;
# round4-red/marker-shape-mutation.log proves they go RED against a revert of the
# RU_OTHER_FINITE_VERB guard.
case_r4_neg_rabotu()     { _expect "$1" "Сейчас работу делают два воркера" SILENT; }
case_r4_neg_zadachu()    { _expect "$1" "Сейчас задачу держит лейн A" SILENT; }
case_r4_neg_komandu()    { _expect "$1" "Сейчас команду не трогаем" SILENT; }
case_r4_neg_kartinu()    { _expect "$1" "Дальше картину покажет соак" SILENT; }
case_r4_neg_versiyu()    { _expect "$1" "Сейчас версию 5.2 использует прод" SILENT; }
case_r4_neg_situaciyu()  { _expect "$1" "Потом ситуацию посмотрим вместе" SILENT; }
case_r4_neg_bazu()       { _expect "$1" "Сейчас базу мигрировали вручную" SILENT; }
case_r4_neg_tablicu()    { _expect "$1" "Затем таблицу привёл к виду выше" SILENT; }
case_r4_neg_ochered()    { _expect "$1" "Сейчас очередь пустая" SILENT; }
case_r4_neg_statistiku() { _expect "$1" "Сейчас статистику собирает джоба" SILENT; }

run_case "r4-neg-rabotu-delayut"      case_r4_neg_rabotu
run_case "r4-neg-zadachu-derzhit"     case_r4_neg_zadachu
run_case "r4-neg-komandu-trogaem"     case_r4_neg_komandu
run_case "r4-neg-kartinu-pokazhet"    case_r4_neg_kartinu
run_case "r4-neg-versiyu-ispolzuet"   case_r4_neg_versiyu
run_case "r4-neg-situaciyu-posmotrim" case_r4_neg_situaciyu
run_case "r4-neg-bazu-past-veto"      case_r4_neg_bazu
run_case "r4-neg-tablicu-past-veto"   case_r4_neg_tablicu
run_case "r4-neg-ochered-no-candidate" case_r4_neg_ochered
run_case "r4-neg-statistiku-excluded-ending" case_r4_neg_statistiku

# --- TURN-IT-ON-01 round 4: word-start anchors on the new stems -------------------
# Judge verdict HIGH: the r3 additions "чин\w*" and "обнов\w*" were UNANCHORED
# substrings. Blocking only reaches a sentence that is promise-DETECTED, and the
# judge's verbatim probe («Сейчас посмотрю, в чём причина») is not one — but the
# mechanism is real end-to-end: a DETECTED promise whose only kind signal is the
# substring («Сделаю разбор причины», «Запущу обновление кэша») gets classified
# write and BLOCKED with no keeping write action. Pinned both layers:
#   - the judge's sentence and the bare noun forms (regex layer, SILENT), and
#   - detected promises whose only kind match was the unanchored stem (the
#     mutation-control negatives: strip the \b anchors and these four go RED —
#     measured, see report.md round 4).
# Every TURN-IT-ON-01 stem now carries \b; чин- additionally requires verb endings
# because the noun «починка» shares the word-start «почин» with the verb «починю»
# (\b alone cannot separate them).
# PROMISE-GUARD-UNKNOWN-KIND-01 (2026-09-02 escape): this pin FLIPPED from
# SILENT to FIRED. It was written when «посмотрю» had no kind — the sentence
# was detected but unclassified, and the flip gate kept unclassified rows
# log-only. UNKNOWN-KIND-01 added the `diagnose` kind for exactly this family
# (посмотрю/разбираю/выясняю/…), so the clause now classifies diagnose, and a
# diagnose promise is kept only by a state-changing action (or a test run) —
# never by a read. With zero actions this is the same escape shape as the
# 2026-09-02 «сейчас разбираю все три» and must block. The \b-anchor mutation
# control below is unaffected: the stems it guards (разбор/обновление nouns)
# classify write via «сделаю/запущу», not diagnose.
case_r4b_neg_prichina()    { _expect "$1" "Сейчас посмотрю, в чём причина" FIRED; }
case_r4b_neg_obnovlenie()  { _expect "$1" "обновление пришло" SILENT; }
case_r4b_neg_pochinka()    { _expect "$1" "починка была вчера" SILENT; }
case_r4b_neg_razbor()      { _expect "$1" "Сделаю разбор причины" SILENT; }
case_r4b_neg_kesh()        { _expect "$1" "Запущу обновление кэша" SILENT; }
case_r4b_neg_reestr()      { _expect "$1" "Сейчас сделаю обновление реестра" SILENT; }
case_r4b_neg_nachnu()      { _expect "$1" "Начну с разбора причины" SILENT; }
case_r4b_pos_chinyu()      { _expect "$1" "чиню конфиг" FIRED; }
case_r4b_pos_pochinyu()    { _expect "$1" "починю конфиг" FIRED; }
case_r4b_pos_obnovlyu()    { _expect "$1" "сейчас обновлю yaml" FIRED; }
# Control that the flip negatives stay honest: a detected promise with a REAL kind
# signal (прогоню тест → test kind) must still block even though "обновление" is
# also present — proves the SILENTs above come from de-classification, not from
# something muting the hook wholesale.
case_r4b_pos_test_kind()   { _expect "$1" "Прогоню тест на обновление схемы" FIRED; }

run_case "r4b-neg-prichina-substring"   case_r4b_neg_prichina
run_case "r4b-neg-obnovlenie-noun"      case_r4b_neg_obnovlenie
run_case "r4b-neg-pochinka-noun"        case_r4b_neg_pochinka
run_case "r4b-neg-razbor-prichiny"      case_r4b_neg_razbor
run_case "r4b-neg-obnovlenie-kesha"     case_r4b_neg_kesh
run_case "r4b-neg-obnovlenie-reestra"   case_r4b_neg_reestr
run_case "r4b-neg-nachnu-prichiny"      case_r4b_neg_nachnu
run_case "r4b-pos-chinyu"               case_r4b_pos_chinyu
run_case "r4b-pos-pochinyu"             case_r4b_pos_pochinyu
run_case "r4b-pos-obnovlyu-yaml"        case_r4b_pos_obnovlyu
run_case "r4b-pos-test-kind-still-blocks" case_r4b_pos_test_kind

# --- sandbox control: this suite must never write the real journal ---------------
# PROMISE-JOURNAL-CONCURRENT-WRITES-01: the real journal is shared production state --
# every live Claude session's own Stop hook appends to it, so a raw before/after LINE
# COUNT is a concurrency false-positive that flakes red on any busy day (measured
# 2026-09-01: a foreign real-UUID session_id appended mid-run, no leak occurred). The
# only thing this suite can actually prove is that ITS OWN calls (sid prefix
# "test-${$}-...", unique per PID) never landed in the real file -- so filter the
# appended rows to that prefix instead of trusting total count.
REAL_JOURNAL_LINES_AFTER=0
[[ -f "${REAL_JOURNAL}" ]] && REAL_JOURNAL_LINES_AFTER="$(wc -l < "${REAL_JOURNAL}" 2>/dev/null | tr -d ' ')"
LEAKED_ROWS=""
if [[ "${REAL_JOURNAL_LINES_AFTER}" -gt "${REAL_JOURNAL_LINES_BEFORE}" ]]; then
  LEAKED_ROWS="$(tail -n "+$((REAL_JOURNAL_LINES_BEFORE + 1))" "${REAL_JOURNAL}" 2>/dev/null \
    | grep -F "\"session_id\": \"test-$$-" -- || true)"
fi
if [[ -n "${LEAKED_ROWS}" ]]; then
  FAIL=$((FAIL + 1))
  ERRORS+=("sandbox-escape: ${REAL_JOURNAL} received this run's own rows despite HOME sandbox")
  log "FAIL: sandbox-escape -- real journal contains this run's own sid prefix (test-$$-)"
else
  log "PASS: sandbox-control -- real journal ${REAL_JOURNAL} has no rows from this run (before=${REAL_JOURNAL_LINES_BEFORE} after=${REAL_JOURNAL_LINES_AFTER})"
fi

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
