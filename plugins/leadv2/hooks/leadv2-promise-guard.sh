#!/usr/bin/env bash
# Stop hook — PROMISE-GUARD-01: a promise in chat must not count as work.
#
# Reads the turn's final assistant text; if it ends on a forward-tense
# commitment («сейчас поднимаю наблюдателя», "I'll dispatch…") AND that same
# turn made ZERO tool calls of the PROMISED KIND, blocks once with a correction
# that quotes the unkept sentence, and appends a durable JSONL row so the rate
# is measurable. Past-tense reports carrying artifacts (sha / path / probe) are
# the DESIRED output and are never fired on.
#
# PROMISE-GUARD-BIND-01 (2026-08-30): before this fix, ANY action-tool call in
# the turn suppressed the guard, regardless of what was promised — a turn that
# promised a dispatch and then only read a file looked identical, to the
# guard, to a turn that actually dispatched. `classify_promise_kind` /
# `classify_action_kind` below bind the two: a promise of a KNOWN kind
# (dispatch / commit / write / test-run) is only "kept" by an action of that
# same kind. A promise whose kind cannot be classified falls back to the
# legacy behaviour (any action suppresses) — we don't yet have enough journal
# evidence to bind kinds we haven't modeled, and a guard that fires on
# unmodeled shapes trains itself off on day one.
#
# BLOCKING ROLLOUT: LEADV2_PROMISE_GUARD_BLOCK (default "1" since
# PROMISE-GUARD-TURN-IT-ON-01, 2026-09-01; was "0" log-only) gates the actual
# `decision:block` emission. The journal row (verdict=fired/suppressed_action)
# is written unconditionally, so "fired" in log-only mode means "would have
# blocked" — that is the evidence the flip decision needs. See
# docs/leadv2/scheduled-decisions.md for the GO-condition.
#
# Unlike lead-prose-guard, this fires regardless of LEADV2_LEAD_GUARD,
# LEADV2_SUPERVISOR_MODE, or live-session count — the defect happens in plain
# chat turns too. Gating is: kill switch, stop_hook_active, once-per-turn
# sentinel. Nothing else. A guard that crashes must never wedge a session, so
# the ERR trap exits 0 (fail-open).
#
# PROMISE-GUARD-TURN-IT-ON-01: block on classified promises, keep unclassified
# log-only. Set LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1 to opt-in to the
# old behaviour (block on unclassified promises).

set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

# --- kill switch -------------------------------------------------------------
[[ "${LEADV2_PROMISE_GUARD:-1}" == "1" ]] || exit 0

# --- read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Parse the bits of the Stop-hook stdin JSON we need (python, fail-open).
META="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    r = {}
print(r.get("session_id", "") or "")
print("yes" if r.get("stop_hook_active") else "no")
print(r.get("cwd", "") or "")
print(r.get("transcript_path", "") or "")
' 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$META" | sed -n '1p')"
STOP_ACTIVE="$(printf '%s' "$META" | sed -n '2p')"
CWD="$(printf '%s' "$META" | sed -n '3p')"
STDIN_TRANSCRIPT="$(printf '%s' "$META" | sed -n '4p')"

# --- anti-loop: canonical field ---------------------------------------------
[[ "$STOP_ACTIVE" == "yes" ]] && exit 0

# --- transcript resolution (env override > stdin > glob by session_id) ------
TRANSCRIPT="${LEADV2_PROMISE_GUARD_TRANSCRIPT:-}"
if [[ -z "$TRANSCRIPT" ]]; then
  TRANSCRIPT="$STDIN_TRANSCRIPT"
fi
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  if [[ -n "$SESSION_ID" ]]; then
    TRANSCRIPT="$(python3 -c "
import os, glob, sys
for p in glob.glob(os.path.expanduser('~/.claude/projects/*/' + sys.argv[1] + '.jsonl')):
    print(p); break
" "$SESSION_ID" 2>/dev/null || true)"
  fi
fi
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

[[ -z "$SESSION_ID" ]] && SESSION_ID="unknown"
[[ -z "$CWD" ]] && CWD="$PWD"

# --- parse + detect (one python heredoc, stdlib only) -----------------------
# Reconciliation note: design §4b says split on [.!?\n;], but §4d note + test
# case 10 require «закоммитил 4eb4c304, сейчас поднимаю наблюдателя» to FIRE
# with quote = only the promise clause. A pure sentence split treats that as one
# sentence and the past-tense clause vetoes the whole thing (miss). We therefore
# evaluate at CLAUSE level (split sentences on [.!?\n;], then clauses on comma),
# so the past+artifact clause and the forward-promise clause are judged
# independently. The test assertion (case 10 fires) is ground truth.
VERDICT="$(python3 - "$TRANSCRIPT" "$SESSION_ID" <<'PYEOF' 2>/dev/null || true
import sys, os, json, re, shlex   # os: T16 §6 tail-window fast path

jsonl_path = sys.argv[1]

# --- commitment shapes (one named block, editable) -------------------------
# PROMISE-GUARD-3PL-COLLISION-01 (2026-08-22): bare 1st-conjugation 1sg stems collide
# with their own 3rd-person-plural — 1sg + "т" = 3pl for almost every verb in this
# list (иду/идут, беру/берут, поднимаю/поднимают, запускаю/запускают, начинаю/
# начинают, приземляю/приземляют, пойду/пойдут, сделаю/сделают). Unanchored, the
# bare alternation matched "иду" as a substring inside the unrelated "идут", so a
# recap of two jobs already launched earlier in the turn — «Они идут параллельно и
# независимо» — was misread as a fresh 1st-person commitment and fired the guard on
# a completed report, not an unkept promise.
#
# A blanket \b(...)\b anchor is the obvious fix and it is wrong: it breaks a REAL
# commitment. "берусь" ("I take on", reflexive) is "беру"+"сь", and no \b occurs
# between "беру" and "сь" since "сь" is word characters throughout — anchoring both
# sides silently un-matches "Берусь за третье — контракт prepass", which
# test-promise-action-binding.sh:case_action_then_promise requires to FIRE.
#
# The fix is a RIGHT-SIDE-ONLY negative lookahead per alternative: forbid the stem
# from being immediately followed by the 3rd-person-plural ending — "т" alone, or
# "т"+"ся" for the reflexive 3pl ("берутся") — when that ending is itself followed by
# a word boundary. This keeps "беру" matching inside "берусь" (next char "с", the
# lookahead does not fire) while rejecting it inside "берут" ("т" then boundary) and
# "берутся" ("т"+"ся" then boundary).
#
# KNOWN RESIDUAL GAP (documented, not solved — same posture as the -су/-ту/-ду nominal
# collision already noted below for RU_1SG_NONPAST): this lookahead only models the
# exact т / тся-then-boundary collision observed live. A 3pl reflexive whose ending is
# followed by more word characters, or a derivational suffix that happens to start
# with "т" for an unrelated reason, is not covered.
# PROMISE-GUARD-BIND-01 round2: 'поправлю'/'прогоню'/'закоммичу' added -- the
# extractor never matched these real lead phrasings at all (zero commitments
# detected, not a binding/kind problem), so the guard could never fire on
# «Сейчас поправлю…», «Сейчас прогоню тесты», «Сейчас закоммичу фикс». None of the
# three collide with their own 3rd-person-plural the way the PROMISE-GUARD-3PL-
# COLLISION-01 verbs do (поправят/прогонят/закоммитят are not stem+"т"), so the
# right-side lookahead guard is inert for them but harmless to share.
COMMIT_RU_VERBS = ['приземляю', 'запускаю', 'поднимаю', 'диспатчу', 'начинаю', 'иду',
                    'сделаю', 'проверю', 'подниму', 'запущу', 'отправлю', 'дам',
                    'пойду', 'беру', 'поправлю', 'прогоню', 'закоммичу']
COMMIT_RU = '|'.join(v + r'(?!т(?:ся)?\b)' for v in COMMIT_RU_VERBS)
COMMIT_RU_NOW = r'сейчас\s+(?:же\s+)?(?:' + COMMIT_RU + r')'
COMMIT_EN = r"\bI'?ll\b|\bI will\b|\blet me\b|\bgoing to\b|\bnext I\b|\bnow I'?m\b|\bI'?m about to\b|\bwill now\b"

# PROMISE-GUARD-MORPHOLOGY-01: match the GRAMMATICAL SHAPE, not a verb dictionary.
#
# The hand-kept list above cannot work, and 2026-08-21 proved it on a real escape in
# ~/Projects/getmany-followup-bot: the lead ended a turn with "Чиню постраничную
# выборку Calendly" and "Ссылку на перебронирование добавлю тем же заходом", started
# neither, and the guard stayed silent — «чиню» and «добавлю» are simply not on the
# list. Russian verb morphology has no finite enumeration; every future escape will
# use a verb nobody thought to add. The founder reported the same shape in m3-market.
#
# The shape that actually carries a commitment is a FIRST-PERSON SINGULAR NON-PAST
# verb: in Russian that is a -ю/-у ending (present and future are identical in form
# — «чиню» and «добавлю» are both caught by one rule). Bare -ю/-у over-matches nouns
# in the accusative («выборку», «ссылку»), so the verb candidate must ALSO sit in a
# clause carrying a commitment marker — an intention adverbial («сейчас», «дальше»,
# «тем же заходом», «отдельно») — or be one of the known verbs above. That pairing is
# what keeps «Ссылку на перебронирование добавлю тем же заходом» a hit while
# «правлю выборку и вот результат 12/12» is not (the artifact vetoes it downstream).
# The -ому/-ему exclusion lives HERE, in the morphological unit, so every rule that
# uses it inherits the guard. It was first written into COMMIT_RU_LEADING alone, and
# within the hour the SHAPE rule fired on "дальше по твоему порядку" — «твоему» is a
# dative adjective, «дальше» is an intent marker, and the pair read as a commitment.
# Exactly the copy-drift shape fixed in the scope gate the same day: one definition
# widened, its twin left behind. One definition, two consumers, no drift.
#
# The exclusion list is nominal endings, not a word list: Russian dative and
# accusative nouns share the -у/-ю ending with first-person verbs («порядку»,
# «выборку», «ссылку» look exactly like «чиню» to a bare pattern). Excluding
# -ому/-ему (dative adjectives, «поэтому»/«потому») and -ку/-гу/-ху/-це/-ре/-ле
# (the common nominal endings) removes the families that actually bit us.
#
# KNOWN LIMIT, stated rather than hidden: -су/-ту/-ду still collide — «по этому
# вопросу» is nominal, «несу»/«веду» are verbs, and no ending distinguishes them.
# Those slip through the SHAPE rule when an intent marker is also present. That is
# accepted: the alternative is a morphological analyser, and the LEADING rule plus
# the explicit verb list carry most real commitments anyway.
RU_1SG_NONPAST = r'\b(?![а-яё]*(?:[ое]му|ку|гу|ху|це|ре|ле)\b)[а-яё]{3,}[юу]\b'
# Word-boundary anchored: without \b, «потом» matches inside «потому», so
# «Потому что так короче» — plain reasoning prose — was read as an intention marker
# and, paired with any -ю/-у word, became a false commitment. Every marker here is a
# whole word or phrase, never a stem.
RU_INTENT_MARKER = (
    r'\bтем\s+же\s+заходом\b|\bследующим\s+заходом\b|\bэтим\s+же\s+заходом\b'
    r'|\bсейчас\b|\bсразу\b|\bдальше\b|\bзатем\b|\bпотом\b|\bпозже\b'
    r'|\bпосле\s+этого\b|\bв\s+конце\b'
    r'|\bотдельно\b|\bзаодно\b|\bпопутно\b|\bпо\s+ходу\b|\bещё\s+раз\b|\bнапоследок\b'
)
# ORDER IS THE DISCRIMINATOR. The rule used to be "an intent marker somewhere AND a
# -ю/-у word somewhere", which fired on ordinary prose because Russian dative and
# accusative nouns end in -у/-ю too: "дальше по твоему порядку" and "сейчас по этому
# делу" both matched. Excluding nominal endings turned into whack-a-mole (-ку, then
# -лу, then -су…) and would never have terminated.
#
# In a real deferred commitment the VERB PRECEDES the marker — «добавлю тем же
# заходом», «допишу потом». In the false positives the marker opens the clause and
# the -у word after it is a noun. Requiring verb-then-marker within a short window
# keeps the real shape and drops the prose, without enumerating endings.
# PROMISE-GUARD-BIND-01 round3: the first alternative below is the original rule
# (verb, then a marker within 40 chars -- "TRAILING"). The second is new: marker-
# BEFORE-verb, the order a lead actually opens a turn with -- «Сейчас напишу отчёт»,
# «Сейчас исправлю биндинг». TRAILING only ever matched verb-then-marker, so any
# sentence that opens with «сейчас» fell through to the COMMIT_RU_VERBS whitelist and
# was silent for every verb not on that hand-kept list (review-r1.md:88-98, «Сейчас
# напишу отчёт» / «Сейчас исправлю биндинг» measured SILENT no-journal-row on the
# shipped hook).
#
# The new alternative is NOT symmetric with TRAILING's `.{0,40}?` gap: TRAILING scans
# forward from a verb looking for a marker anywhere nearby, but doing the same thing
# backward from a marker (marker, then ANY 40 chars, then a verb-shaped word) reopens
# the exact bug ORDER IS THE DISCRIMINATOR fixed -- «сейчас по этому делу» has a
# marker, then a preposition and an adjective, then the nominal «делу» (dative, -у
# ending, not excluded by RU_1SG_NONPAST's suffix list) chars later, which would read
# as a commitment. Pinned as case_neg_shape_adverb below.
#
# The fix is adjacency, not scope: require the verb-shaped word to be the marker's
# very next word (optionally through a bare "же", as in «сейчас же исправлю»). A
# preposition or adjective between marker and candidate is real prose, not a deferred
# commitment, and blocks the match because the immediately-following word fails
# RU_1SG_NONPAST (too short, or a nominal ending already excluded there).
#
# PROMISE-GUARD-BIND-01 round4: adjacency alone is not enough. Russian accusative
# singular nouns end in -у/-ю too, and the exclusion list on RU_1SG_NONPAST only
# covers a handful of nominal endings, so the marker's next word being an accusative
# object reads as a commitment: «Сейчас работу делают два воркера», «Сейчас задачу
# держит лейн A» both matched (review-r3.md, ten hand-written status clauses, six
# false positives). Enumerating every nominal -у/-ю ending is the whack-a-mole the
# KNOWN LIMIT comment on RU_1SG_NONPAST already warns never terminates.
#
# The actual discriminator is not the candidate's shape, it's the REST OF THE
# CLAUSE: a real promise clause has exactly one finite verb (the candidate itself)
# — «Сейчас поправлю регэксп в хуке» ends there. Every measured false positive has
# a SECOND, genuinely finite verb later in the clause carrying the real subject —
# «делают», «держит», «использует», «покажет», «трогаем», «посмотрим» — because the
# marker-adjacent word was never the verb; it was the fronted object of that later
# verb. RU_OTHER_FINITE_VERB names that later-verb shape (3rd-person / 1st-2nd
# plural present-tense endings, which never coincide with the 1sg -у/-ю candidate
# shape) and the marker-before-verb arm now requires its absence for the rest of
# the clause. This does not touch the TRAILING arm (verb-then-marker) at all, and a
# genuine promise clause that happens to name a second finite verb after the
# candidate is not attested in any fixture — if one shows up, it is a new case to
# pin, not a reason to revert this guard.
# "ет" (not "ёт") deliberately: "ёт" collides with report nouns like «отчёт»,
# «полёт» that end the very promise clauses this guard must keep firing on, while
# genuine 3sg -ет verbs («покажет», «использует») never carry ё. "ует" folds into
# bare "ет" (its own last two letters), so it is not listed separately.
RU_OTHER_FINITE_VERB = r'\b[а-яё]{2,}(?:ет|ают|ят|ат|им|ешь|ишь|ем|ит|ют)\b'
COMMIT_RU_SHAPE = (
    RU_1SG_NONPAST + r'.{0,40}?(?:' + RU_INTENT_MARKER + r')'
    + r'|(?:' + RU_INTENT_MARKER + r')\s+(?:же\s+)?' + RU_1SG_NONPAST
    + r'(?!.*' + RU_OTHER_FINITE_VERB + r')'
)

COMMIT_RE = re.compile(
    '(?:' + COMMIT_RU_NOW + r'|' + COMMIT_RU + r'|' + COMMIT_EN + r'|' + COMMIT_RU_SHAPE + r')',
    re.I | re.UNICODE)

# A clause that is a bare first-person non-past verb with no marker at all is still a
# commitment when it OPENS the clause — «Чиню выборку…», «Довожу list-form…». Checked
# separately so the marker rule above stays strict.
#
# The `(?![а-яё]*[ое]му\b)` guard is not decoration: within an hour of shipping this
# rule it fired on the lead's own REPORT of finished work — «Поэтому контракт теперь
# требует…» — because «поэтому» ends in -у and opens the clause. «Потому», «посему»
# and the dative of any adjective («новому», «первому») do the same. Russian
# first-person singular verbs do not end in -ому/-ему, so excluding that ending kills
# the whole family without touching a single real verb. A guard that cries wolf on
# status prose gets switched off within a day, which would cost more than the escape
# it was built to catch.
COMMIT_RU_LEADING = re.compile(r'^\s*[«"\-—*]*\s*' + RU_1SG_NONPAST, re.I | re.UNICODE)

# --- past-tense / artifact veto --------------------------------------------
PAST_RU = r'\b\w+(?:л|ла|ло|ли)\b'
PAST_EN = r'\b(?:committed|shipped|pushed|landed|ran|wrote|fixed|added|done|merged|deployed|\w+ed)\b'
ARTIFACT = r'\b[0-9a-f]{7,40}\b|\b\d+/\d+\s+pass\b|^\s*(?:PASS|FAIL):|https?://|DELIVERABLE_COMPLETE|\S+\.(?:sh|py|ts|tsx|json|md|yaml):\d+'
VETO_RE = re.compile('(?:' + PAST_RU + r'|' + PAST_EN + r'|' + ARTIFACT + r')', re.I | re.UNICODE)

# --- negation, engine-wide (PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01 r2) ---
# A commitment clause carrying a negation of its own verb is not a commitment.
# «Не начинаю новую линию, пока не закрою эту — работаю по плану.» is a REPORT
# that the lead is NOT starting something, and «не закоммичу» / «не буду»
# fire on the pre-existing (pre-`start`) engine too -- this is a class fix,
# not a `start`-only patch. Double negation («не могу не начать») IS a
# commitment and is checked FIRST, before the plain-negation veto, so it is
# never accidentally vetoed by its own inner «не».
RU_NEG_AUX = r'(?:буду|стану|собираюсь|планирую|хочу|намерен|намерена|могу|смогу)'
# One optional adverb between the negation particle and the verb: «не сразу
# начну», «пока не закрою», «ещё не начинаю».
NEG_VERB_RE = re.compile(
    r'\b(?:не|ни)\s+(?:(?:пока|ещё|еще|уже|же|сразу|сейчас|точно)\s+)?([а-яё]{3,})\b',
    re.I | re.UNICODE)
DOUBLE_NEG_RE = re.compile(
    r'\bне\s+(?:могу|смогу|вправе|в\s+состоянии)\s+не\s+([а-яё]{3,}(?:ть|ти|чь)(?:ся)?)\b',
    re.I | re.UNICODE)
EN_NEG_RE = re.compile(
    r"\b(?:I\s+won'?t|I\s+will\s+not|will\s+not|I'?m\s+not\s+(?:going|about)"
    r"|not\s+going\s+to|let\s+me\s+not)\b", re.I)

def negated_commitment(clause):
    """True when the clause's leftmost commitment-verb candidate is governed
    by a negation particle. Double negation is a commitment, not a negation,
    and is excluded here (checked separately, first, by the caller)."""
    if EN_NEG_RE.search(clause):
        return True
    m = NEG_VERB_RE.search(clause)
    if not m:
        return False
    word = m.group(1)
    # the negated word must itself look like the commitment candidate (a verb
    # or the RU_NEG_AUX modal), not an unrelated noun sitting after "не"/"ни"
    if re.match(r'^' + RU_NEG_AUX + r'$', word, re.I | re.UNICODE):
        return True
    if word.lower() in COMMIT_RU_VERBS:
        return True
    if re.match(r'^[а-яё]{3,}[юу]$', word, re.I | re.UNICODE):
        return True
    return False

# --- action detection --------------------------------------------------------
# PROMISE-GUARD-BIND-01: every action is tagged with a KIND, not just a bare
# yes/no. The old ACTION_BASH_RE had one catch-all alternative — `leadv2-.*\.sh`
# — that matched almost every script in this repo, including read-only status
# and audit scripts, which is most of why "any tool call" suppressed the guard
# in practice: nearly any Bash call in this codebase invokes a `leadv2-*.sh`
# script of SOME kind. That blanket alternative is removed; each kind below is
# named by the specific commands that actually perform it.
ACTION_KIND_BASH = [
    ('test', re.compile(
        r'run-all\.sh|test-[\w.-]*\.sh|\bpytest\b|npm\s+(?:run\s+)?test|\bctest\b',
        re.UNICODE)),
    # TURN-IT-ON-01: merge joins commit — sampled from the journal's unclassified
    # bucket ("мержу в develop", "Начинаю с мержа fix/..."); a merge promise is
    # kept by the git merge that performs it.
    ('commit', re.compile(r'git\s+(?:commit|push|add|tag|merge)', re.UNICODE)),
    ('dispatch', re.compile(
        r'leadv2-dispatch-code|leadv2-fanout|[A-Za-z0-9_-]*-task\.sh|glm-coder\.sh',
        re.UNICODE)),
    # PROMISE-GUARD-BIND-01 round2: the bare `>>?\s*\S` alternative matched shell
    # redirection that writes NOTHING a promise could point to -- `2>/dev/null` (the
    # near-universal noise-suppression idiom in this repo's own test suites) and
    # `2>&1` (fd duplication) both satisfied a "write" promise just by appearing in
    # an unrelated command. Excluding a `/dev/null` target and an `&`-fd target
    # removes both without touching a real file write (`> out.txt`, `>> log`).
    ('write', re.compile(
        r'sed\s+-i|\b(?:mv|cp|tee|touch|mkdir|install)\b'
        r'|>>?\s*(?!/dev/null\b)(?!&)\S'
        r'|systemctl\s+(?:restart|start|enable)',
        re.UNICODE)),
]
# Back-compat single pattern (telemetry / callers that only need "was this
# Bash call an action at all", not its kind).
ACTION_BASH_RE = re.compile(
    '(?:' + '|'.join(p.pattern for _, p in ACTION_KIND_BASH) + ')', re.UNICODE)

ACTION_TOOL_KIND = {
    'Edit': 'write', 'MultiEdit': 'write', 'Write': 'write', 'NotebookEdit': 'write',
    'Agent': 'dispatch', 'Workflow': 'dispatch', 'SendMessage': 'dispatch',
}

# PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: a write's TARGET decides whether
# it is evidence that promised work began. Prefixes are derived from the
# environment the hook already sees — never a hard-coded machine path. An
# empty or "/" entry is DROPPED: an empty prefix makes startswith() true for
# every path, which would judge every write scratch and fire the guard on
# every write-kept promise. Derivation is textual only — no realpath(), no
# stat(): a Stop hook that touches the filesystem can block on a dead mount,
# and the target may already be gone by the time the hook runs. The /private
# twin of every entry is added (and the stripped twin of every /private
# entry) because both spellings are live on macOS: $TMPDIR is
# /var/folders/.../T while the scratchpad paths it fronts resolve through
# /private/var/folders/...
def _scratch_prefixes():
    out = set()
    for raw in ('/tmp', '/private/tmp', '/var/tmp', '/private/var/tmp',
                os.environ.get('TMPDIR') or '', os.environ.get('TMP') or ''):
        p = (raw or '').strip().rstrip('/')
        if not p or p == '/':
            continue
        out.add(p)
        out.add(p[len('/private'):] if p.startswith('/private/') else '/private' + p)
    return sorted(x for x in out if x and x != '/')

SCRATCH_PREFIXES = _scratch_prefixes()
# argv[2] of this heredoc is the hook's SESSION_ID (the bash driver passes
# it). A short or absent id keeps the session clause below inert — the bash
# layer's `unknown` fallback is 7 chars, under the floor, so it can never
# mark a path scratch by accident.
SESSION_ID = sys.argv[2] if len(sys.argv) > 2 else ''

WRITE_PATH_KEYS = ('file_path', 'notebook_path', 'path')

def write_target(inp):
    if not isinstance(inp, dict):
        return ''
    for k in WRITE_PATH_KEYS:
        v = inp.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ''

def is_durable_target(path):
    """FAIL-OPEN: absent / empty / relative / unparseable -> DURABLE. Every
    pre-existing promise-guard fixture emits Write/Edit with input {}, and
    those suites must keep their suppressed_action verdicts."""
    if not path:
        return True
    if not path.startswith('/'):
        return True
    for pre in SCRATCH_PREFIXES:
        if path == pre or path.startswith(pre + '/'):
            return False
    if len(SESSION_ID) >= 16 and ('/' + SESSION_ID + '/') in path:
        return False
    return True

# --- Bash write targets (PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01 r2) -----
# `name == 'Bash'` used to exempt EVERY Bash write from the durability check
# above -- `echo x > /tmp/y` kept a start-promise the same way a scratch
# `Write` used to, because the target was never examined. This extracts the
# target(s) of a write-kind Bash command so they can be run through
# is_durable_target() like any other write. Textual only -- no realpath(), no
# stat(): same rule as _scratch_prefixes, for the same reason (a Stop hook
# must never touch a dead mount, and the target may already be gone).
BASH_UNRESOLVABLE_RE = re.compile(r'\$\(|`|\$\{[^}]*[:#%/][^}]*\}')
BASH_VAR_RE = re.compile(r'\$(?:\{(\w+)\}|(\w+))')
BASH_DEST_LAST = ('cp', 'mv', 'install')
BASH_DEST_ALL = ('tee', 'touch', 'mkdir')
BASH_EXPANDABLE_VARS = ('TMPDIR', 'TMP', 'HOME')
_UNRESOLVED_SENTINEL = '\x00UNRESOLVED\x00'

def _bash_expand_known_vars(token):
    """Textually expand $TMPDIR/${TMPDIR}/$TMP/$HOME/~ from the hook's own
    environ (the session's own env, same source _scratch_prefixes reads).
    Any other $VAR, or a known var absent from the environ, marks the token
    unresolved -- never expanded to empty, which would misread `$TMPDIR/x` as
    an absolute non-scratch path when TMPDIR is simply unset."""
    def repl(m):
        name = m.group(1) or m.group(2)
        if name in BASH_EXPANDABLE_VARS:
            val = os.environ.get(name)
            if val:
                return val
        return _UNRESOLVED_SENTINEL
    out = BASH_VAR_RE.sub(repl, token)
    if out.startswith('~/') or out == '~':
        home = os.environ.get('HOME')
        out = (home + out[1:]) if home else _UNRESOLVED_SENTINEL + out[1:]
    return out

def bash_write_targets(cmd):
    """Returns (targets, resolved). resolved=False means: this write-kind
    Bash call has a target the guard could not determine -- caller must treat
    that conservatively (not durable), never guess."""
    if BASH_UNRESOLVABLE_RE.search(cmd):
        return [], False
    try:
        tokens = shlex.split(cmd, posix=True)
    except ValueError:
        # unbalanced quotes -- fall back to a raw regex pass for redirection
        # targets only; anything more structured (cp/tee/sed -i) is unresolved.
        raw = re.findall(r'(?:^|[\s;&|(])(?:\d?>>?|&>>?)\s*(\S+)', cmd)
        raw = [t for t in raw if t != '/dev/null' and not t.startswith('&')]
        return (raw, True) if raw else ([], False)

    simple_cmds = []
    current = []
    for tok in tokens:
        if tok in (';', '&&', '||', '|'):
            if current:
                simple_cmds.append(current)
            current = []
        else:
            current.append(tok)
    if current:
        simple_cmds.append(current)

    saw_cd = any(os.path.basename(parts[0]) in ('cd', 'pushd')
                 for parts in simple_cmds if parts)
    raw_targets = []
    for parts in simple_cmds:
        if not parts:
            continue
        prog = os.path.basename(parts[0])
        if prog in ('cd', 'pushd'):
            continue
        if prog == 'systemctl' and len(parts) > 1 and parts[1] in ('restart', 'start', 'enable'):
            raw_targets.append('<systemctl>')
            continue
        operands = [p for p in parts[1:] if not p.startswith('-')]
        if prog == 'sed' and any(p == '-i' or p.startswith('-i') or p == '--in-place' for p in parts):
            # BSD sed's bare `-i` consumes the NEXT token as a backup suffix,
            # even when that suffix is an empty string (`-i ''`) -- shlex does
            # NOT drop the empty token (verified: shlex.split("sed -i '' x")
            # keeps a bare '' element), so a naive "skip flags, keep the rest"
            # pass would misread the sed SCRIPT itself as a target. Walk the
            # tokens explicitly: `-i`/`--in-place` bare consumes one following
            # token (the suffix, whatever it is); `-iSUFFIX`/`-e script` are
            # glued/consumed inline. Whatever survives: first is the script,
            # the rest are files.
            rest = parts[1:]
            consumed = set()
            script_already_taken = False
            i = 0
            while i < len(rest):
                p = rest[i]
                if i in consumed:
                    i += 1
                    continue
                if p in ('-i', '--in-place'):
                    consumed.add(i)
                    if i + 1 < len(rest):
                        consumed.add(i + 1)  # the (possibly empty) suffix
                    i += 2
                    continue
                if p.startswith('-i') and len(p) > 2:
                    consumed.add(i)  # glued suffix, e.g. -i.bak
                    i += 1
                    continue
                if p == '-e':
                    consumed.add(i)
                    if i + 1 < len(rest):
                        consumed.add(i + 1)
                        script_already_taken = True
                    i += 2
                    continue
                i += 1
            remaining = [p for j, p in enumerate(rest)
                         if j not in consumed and not p.startswith('-')]
            raw_targets.extend(remaining if script_already_taken else remaining[1:])
        elif prog in BASH_DEST_LAST and operands:
            raw_targets.append(operands[-1])
        elif prog in BASH_DEST_ALL:
            raw_targets.extend(operands)
        for m in re.finditer(r'(?:^|\s)(?:\d?>>?|&>>?)\s*(\S+)', ' '.join(parts)):
            t = m.group(1)
            if t == '/dev/null' or t.startswith('&'):
                continue
            raw_targets.append(t)

    if not raw_targets:
        return [], False

    targets = []
    for t in raw_targets:
        if t == '<systemctl>':
            targets.append(t)
            continue
        expanded = _bash_expand_known_vars(t)
        if _UNRESOLVED_SENTINEL in expanded:
            return [], False
        if not expanded.startswith('/') and saw_cd:
            # a relative target after cd/pushd resolves against an unknown cwd
            return [], False
        targets.append(expanded)
    return targets, True

def classify_action_kind(name, bash_cmd=None):
    """Returns the action kind ('test'|'commit'|'dispatch'|'write') or None."""
    if name.startswith('Task'):
        return 'dispatch'
    if name in ACTION_TOOL_KIND:
        return ACTION_TOOL_KIND[name]
    if name == 'Bash' and bash_cmd:
        for kind, pat in ACTION_KIND_BASH:
            if pat.search(bash_cmd):
                return kind
    return None

def is_action_tool(name, bash_cmd=None):
    return classify_action_kind(name, bash_cmd) is not None

# PROMISE-GUARD-BIND-01: the promise EXTRACTOR previously captured only the
# raw clause text — it never derived WHAT was promised, so binding an action
# to it was impossible; "has_action" could only ever mean "any action
# happened anywhere". classify_promise_kind names the same small kind space
# as the action side, read off the commitment clause itself.
PROMISE_KIND_PATTERNS = [
    ('test', re.compile(
        r'тест\w*|suite\b|прогон\w*|pytest|test[-_]all', re.I | re.UNICODE)),
    ('commit', re.compile(
        r'коммич\w*|закоммич\w*|\bcommit\b'
        # TURN-IT-ON-01: merge shapes, sampled from the unclassified journal
        # bucket ("смерджу ветку", "мержу в develop", "мержа fix/...").
        r'|мерж\w*|мердж\w*|\bmerge\b', re.I | re.UNICODE)),
    # (write keeps its original entries plus the TURN-IT-ON-01 additions below.)
    ('dispatch', re.compile(
        r'диспатч\w*|диспетч\w*|\bdispatch\b|\bлейн\w*|\bворкер\w*|\bworker\b'
        r'|\bspawn\b|субагент\w*|\bsubagent\b', re.I | re.UNICODE)),
    ('write', re.compile(
        r'напиш\w*|запиш\w*|патч\w*|\bpatch\b|исправ\w*|\bfix\b|поправ\w*'
        r'|допиш\w*|добавлю\b'
        # TURN-IT-ON-01 additions, each sampled from the unclassified journal
        # bucket and each kept by an already-modelled write action (Edit/Write/
        # sed -i/> file):
        #  - "перепишу" — the писать family already here (напиш/запиш/допиш)
        #  - "чиню/починю" — synonym of исправ, the pinned 2026-08-21 escape:
        #    \b-anchored — unanchored "чин" is a substring of "причина"
        #    ("в чём причина" classified WRITE, judge round-4 HIGH). Verb
        #    endings are required for the почин- family too: the noun
        #    "починка" shares the word-start "почин" with the verb "починю",
        #    so \b alone cannot separate them ("починка была вчера" stays
        #    SILENT, "починю конфиг" fires).
        #  - "обновлю" — "Сейчас обновлю фикстуры". \b + verb-forms only:
        #    the noun "обновление" ("обновление пришло") must stay SILENT.
        #  - "беру/берусь" — "Берусь за третье — контракт prepass" is the single
        #    most-fired unclassified quote (96 rows); taking on a task is kept
        #    by the state-changing work on it (a write-class action).
        #
        # Every stem added by TURN-IT-ON-01 carries a word-start anchor (\b works
        # here: the engine is Python re with re.UNICODE, so Cyrillic letters are
        # word chars); unanchored stems matched mid-word nouns.
        r'|перепиш\w*|\b(?:по)?чин(?:ю|ишь|ит|им|ите|ат|ить)\b'
        r'|\bобнов(?:лю|им|ляю)\b|\b(?:беру|берусь)\b', re.I | re.UNICODE)),
    # PROMISE-GUARD-UNKNOWN-KIND-01 (2026-09-02 escape): the lead ended a turn
    # with «так что сейчас разбираю все три», did nothing, and the guard stayed
    # silent — detection worked but the clause classified None, and None bound to
    # "any action", which a turn of pure reads satisfies in spirit. «разбираю» is
    # the commonest promise a lead makes and it had NO kind. `diagnose` names the
    # look-into-it family. LAST on purpose: a clause naming a concrete kind
    # («разбираюсь с упавшими тестами») keeps its sharper classification and the
    # keeping action that comes with it; diagnose is the residue.
    #
    # Anchoring discipline is the TURN-IT-ON-01 one — every stem \b-anchored and
    # verb-formed, because only DETECTED commitments ever reach this classifier
    # (the past-tense veto has already removed reports), but the nouns must still
    # not steal the label from a real kind: «Сделаю разбор причины» has its own
    # write signal («сделаю») and must classify write, not diagnose; «разбор»,
    # «изучение», «копия», «осмотр» are nouns sharing these stems. 1sg present and
    # 1sg future forms are listed explicitly (разбираю/разберусь, выясняю/выясню,
    # изучаю/изучу) — no bare stem match, so 3rd-person shapes («воркер
    # разбирается», «джоба изучает») and 1pl («посмотрим») never classify.
    # Kept by: any state-changing action, plus a test run — running the suite IS
    # digging in (see the binding below). Never by a read.
    ('diagnose', re.compile(
        r'\bразбира(?:юсь|ю)\b|\bразбер(?:усь|у)\b'
        r'|\b(?:по|о)?смотрю\b|\b(?:вз)?гляну\b'
        r'|\bвыясняю\b|\bвыясню\b'
        r'|\b(?:по)?копаю(?:сь)?\b'
        r'|\bизучаю\b|\bизучу\b'
        r'|\bзаймусь\b|\bознакомлюсь\b', re.I | re.UNICODE)),
    # PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01 (2026-09-13 escape): «Начинаю с
    # пункта 1 прямо сейчас» was DETECTED («начинаю» is in COMMIT_RU_VERBS)
    # and classified None, and None bound to any state-changing action — a
    # scratch Write kept it. The start-family names an intention to BEGIN and
    # carries no object, so it can never classify sharper than this. LAST on
    # purpose, after every concrete kind: «Начинаю с мержа fix/…» keeps its
    # `commit` classification and «стартую фоновый воркер» its `dispatch` one
    # (both verified) — start is the residue, never the label that steals a
    # concrete kind. («начинаю разбираться» also lands here on `start`: the
    # infinitive «разбираться» never matched `diagnose` even before this
    # entry — census note from the implementer, pinned by the closing-promise
    # suite.)
    #
    # Anchoring is the TURN-IT-ON-01 discipline: \b both sides, verb-formed,
    # 1sg only. The nouns «начало», «начальник», «начинание», «начинка»,
    # «приступ», «стартап» share these stems and must never classify; the
    # right-hand \b also rejects the 3pl («начинают», «приступают»,
    # «стартуют») without needing the COMMIT_RU_VERBS lookahead, because
    # these stems are only ever matched fully anchored. «берусь» stays in
    # `write` — the move is not made.
    ('start', re.compile(
        # "ать"/"ить" infinitives added (round 2, MISSES-A-CLOSING-PROMISE-01):
        # these forms only ever reach this classifier through DOUBLE_NEG_RE
        # («не могу не начать») -- nothing else detects a bare infinitive, so
        # this is not a widening of what commits, only of what a double
        # negative's captured verb can classify as.
        r'\bнач(?:инаю|ну|ать)\b'
        r'|\bприступ(?:аю|лю|ить)\b'
        r'|\bстартую\b'
        r'|\bпринимаюсь\b', re.I | re.UNICODE)),
]

def classify_promise_kind(clause):
    """Returns the promised action kind, or None if the clause's kind cannot
    be classified. PROMISE-GUARD-UNKNOWN-KIND-01: an unknown kind no longer
    falls back to legacy any-action binding — it is kept only by a
    state-changing action (write / commit / dispatch), never by a read."""
    for kind, pat in PROMISE_KIND_PATTERNS:
        if pat.search(clause):
            return kind
    return None

# --- turn reconstruction ---------------------------------------------------
# The turn = every assistant record since the last REAL user record.
turn_tools = []          # list of labels, e.g. "Bash:grep", "Edit", "Read"
has_action = False

# PROMISE-ACTION-BINDING-01 (2026-08-21): an action is only evidence that a promise
# was kept if it happened AFTER the promise was made.
#
# `has_action` scans the whole turn since the last user message, so a turn that does
# work A and then promises work B was silently suppressed: the guard saw an action
# and stayed quiet. That is exactly how a promise escaped today — the turn committed
# REVIEW-UNION-VERDICT-01 (a real action) and closed with "берусь за третье", which
# was never started. The founder caught it, not the guard.
#
# The binding rule is positional: count only actions that occur after the last
# non-empty assistant text block. A promise lives in that final text, and in this
# harness nothing follows it, so an unfulfilled promise has zero actions after it no
# matter how much work the turn did earlier.
action_positions = []
action_kinds_seen = set()   # PROMISE-GUARD-BIND-01: kinds of action, turn-wide
durable_kinds_seen = set()  # PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: kinds
                            # of action whose state change hit a DURABLE target
write_target_states = set()  # r2: 'durable' | 'scratch' | 'unresolved' per write seen
last_text_pos = -1
block_pos = 0
final_text_parts = []    # text blocks of the LAST assistant record

records = []

# T16 §6 (LEAD-FINAL-FIXES-01) fast path: the verdict only evaluates records
# after the last real user turn, but this loader used to parse the ENTIRE
# transcript on every Stop of every session in a repo with an active task.
# Load a bounded TAIL window first; only when the file was truncated AND the
# window contains no real user turn (one turn larger than the window) fall
# back to the full parse. The evaluated records are identical either way.
def is_real_user_turn(rec):
    if rec.get('type') != 'user':
        return False
    msg = rec.get('message', {}) or {}
    content = msg.get('content')
    if isinstance(content, str):
        return bool(content.strip())
    if isinstance(content, list):
        # real only if at least one block is not a tool_result
        return any((not isinstance(b, dict)) or b.get('type') != 'tool_result'
                   for b in content)
    return False

TAIL_WINDOW_BYTES = 262144

def _load_tail(path):
    """Tail-bounded JSONL load; returns (records, truncated) or (None, False)."""
    out = []
    truncated = False
    try:
        size = os.path.getsize(path)
        truncated = size > TAIL_WINDOW_BYTES
        with open(path, encoding='utf-8') as f:
            if truncated:
                f.seek(size - TAIL_WINDOW_BYTES)
                f.readline()  # drop the partial line the seek landed in
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        return None, False
    return out, truncated

records, _truncated = _load_tail(jsonl_path)
if records is None:
    # fail-open: cannot read transcript -> never block
    print(json.dumps({'final_text_found': False, 'commitments': [],
                      'has_action': False, 'tools': []}))
    sys.exit(0)
if _truncated and not any(is_real_user_turn(r) for r in records):
    # the whole current turn sits above the window — re-read the full file
    records = []
    try:
        with open(jsonl_path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        records = []

# find index of last real user turn
boundary = -1
for i in range(len(records) - 1, -1, -1):
    if is_real_user_turn(records[i]):
        boundary = i
        break

turn_records = [r for r in records[boundary + 1:] if r.get('type') == 'assistant']

for rec in turn_records:
    content = (rec.get('message', {}) or {}).get('content', [])
    if not isinstance(content, list):
        continue
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get('type')
        if btype == 'tool_use':
            name = block.get('name', '') or ''
            inp = block.get('input', {}) or {}
            cmd = inp.get('command', '') if isinstance(inp, dict) else ''
            if name == 'Bash' and isinstance(cmd, str) and cmd:
                first = cmd.strip().split()[0] if cmd.strip() else 'bash'
                turn_tools.append('Bash:' + first)
            else:
                turn_tools.append(name)
            action_kind = classify_action_kind(name, cmd if isinstance(cmd, str) else None)
            if action_kind is not None:
                has_action = True
                # PROMISE-ACTION-BINDING-01: remember WHERE the action happened.
                action_positions.append(block_pos)
                # PROMISE-GUARD-BIND-01: remember WHAT KIND it was.
                action_kinds_seen.add(action_kind)
                # PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: remember whether it
                # was DURABLE. commit and dispatch are durable by construction
                # (a git operation writes the repo, a spawn starts a real lane).
                # round 2: a Bash write is NO LONGER exempt -- `name == 'Bash'`
                # used to skip the check entirely, which reopened the exact
                # scratch-write escape one tool over (`echo x > /tmp/y` kept a
                # start-promise the same way a scratch `Write` used to).
                if action_kind != 'write':
                    durable_kinds_seen.add(action_kind)
                elif name == 'Bash':
                    bash_targets, bash_resolved = bash_write_targets(cmd)
                    if not bash_resolved:
                        write_target_states.add('unresolved')
                    elif any(is_durable_target(t) for t in bash_targets):
                        durable_kinds_seen.add(action_kind)
                        write_target_states.add('durable')
                    else:
                        write_target_states.add('scratch')
                elif is_durable_target(write_target(inp)):
                    durable_kinds_seen.add(action_kind)
                    write_target_states.add('durable')
                else:
                    write_target_states.add('scratch')
        if btype == 'text' and (block.get('text') or '').strip():
            last_text_pos = block_pos
        block_pos += 1

# final_text = text blocks of the LAST assistant record
if turn_records:
    last_content = (turn_records[-1].get('message', {}) or {}).get('content', [])
    if isinstance(last_content, list):
        final_text_parts = [b.get('text', '') for b in last_content
                            if isinstance(b, dict) and b.get('type') == 'text']

final_text = '\n'.join(final_text_parts).strip()

commitments = []
commitment_kinds = []
if final_text:
    # sentence split, then comma-clause split (see reconciliation note above)
    raw_clauses = []
    # PROMISE-GUARD-BIND-01 round4: a bare `.` alternative split a version number
    # in half -- "Сейчас версию 5.2 использует прод" became sentences "Сейчас
    # версию 5" and "2 использует прод", and the first of those has no second
    # finite verb to trip RU_OTHER_FINITE_VERB, so it read as a fresh commitment
    # (review-r3.md's ten status clauses, measured through the real hook). A `.`
    # between two digits is a decimal point, not a sentence boundary; `!?\n;`
    # still split unconditionally.
    for sent in re.split(r'(?<!\d)\.(?!\d)|[!?\n;]', final_text):
        sent = sent.strip()
        if not sent:
            continue
        for clause in sent.split(','):
            clause = clause.strip()
            if clause:
                raw_clauses.append(clause)
    for clause in raw_clauses:
        if DOUBLE_NEG_RE.search(clause) and not VETO_RE.search(clause):
            # «не могу не начать» IS a commitment -- checked first so it is
            # never vetoed by its own inner «не» below.
            commitments.append(clause)
            commitment_kinds.append(classify_promise_kind(clause))
            continue
        if (COMMIT_RE.search(clause) or COMMIT_RU_LEADING.match(clause)) \
                and not VETO_RE.search(clause) \
                and not negated_commitment(clause):
            commitments.append(clause)
            commitment_kinds.append(classify_promise_kind(clause))

# The QUOTE reported downstream is always commitments[0] (see bash driver
# below), so the PRIMARY promise — the one this verdict is actually about —
# is bound by its kind, not by the turn's kind set as a whole.
primary_kind = commitment_kinds[0] if commitment_kinds else None

# REVERTED 2026-08-22 (PROMISE-GUARD-POSITIONAL-REVERT-01) to turn-wide binding.
#
# The positional rule below — only actions AFTER the last text block keep a promise —
# shipped 2026-08-21 to catch "did X, then promised unrelated Y". In its first full day
# it produced FIVE false positives against ZERO true catches, and it cannot be fixed by
# widening the verb patterns, because the defect is structural: a closing recap of work
# already launched in this turn is BY DEFINITION text that comes after its own actions.
# Every turn that ends with a summary is a false positive. Observed live, all five on
# ordinary lead prose:
#   «они идут параллельно и независимо»   (two jobs launched earlier in the same turn)
#   «Поэтому контракт теперь требует…»    (a report of a finished change)
#   «дальше по твоему порядку: …»         (a plan the founder himself dictated)
#   «...ту болтовню, которую контракт запрещает»  (accusative noun, no verb at all)
#   «...историю, которую они рассказывают»        (same, confirmed twice)
#
# Three adversarial reviewers then reproduced the SAME defect class against the
# regex-level patch with fresh phrasings («слежу за прогрессом обеих», «Поднимаю фоновый
# воркер…», «Сразу документирую результат…»), which is the proof that patching trigger
# strings never reaches this cause.
#
# What we give up: a turn that does real work AND makes an unrelated unkept promise now
# passes. That is a deliberate trade — that shape has never once been observed, while the
# false-positive shape fires several times a day and trains the lead to ignore the guard.
# A guard that cries wolf on every status report is worse than no guard.
#
# The guard's actual purpose is unchanged and still enforced: a turn that promises
# something and does NOTHING still fires, which is every real escape we have caught.
#
# PROMISE-GUARD-BIND-01: when the primary promise's kind IS known, only an
# action of that same kind keeps it. This is the fix for
# PROMISE-GUARD-SUPPRESSED-BY-ANY-TOOL-CALL-01: a turn that promises a dispatch
# and then only Edits a file no longer reads as "kept" just because Edit is
# *an* action.
#
# PROMISE-GUARD-UNKNOWN-KIND-01 (2026-09-02 escape): the old fallback for an
# UNKNOWN kind — `action_after_promise = has_action` — is REMOVED, not kept. It
# let the escape through («так что сейчас разбираю все три», turn = grep + head
# only) and no case needs it: a promise kept by "any action anywhere" is a
# promise kept by a read, and reads are how you look, not how you do. When the
# kind is unknown the promise is kept only by a state-changing action (write /
# commit / dispatch); a `diagnose` promise is additionally kept by a test run,
# because running the suite IS digging in. A 'test' action does NOT keep an
# unknown-kind promise — a vague promise bound by a test run binds to nothing
# checkable, which is the defect being fixed here. The unclassified BLOCK gate
# downstream (BLOCK_UNCLASSIFIED opt-in) is unchanged, so this hardening
# widens evidence, not shouting.
STATE_KINDS = {'write', 'commit', 'dispatch'}
if primary_kind is None or primary_kind == 'start':
    # PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: an unknown- or start-kind
    # promise names no object, so the only honest evidence it began is a state
    # change on a DURABLE target. A scratch write and a repo write are no
    # longer the same evidence.
    action_after_promise = bool(durable_kinds_seen & STATE_KINDS)
elif primary_kind == 'diagnose':
    action_after_promise = bool(action_kinds_seen & (STATE_KINDS | {'test'}))
else:
    action_after_promise = primary_kind in action_kinds_seen

# r2: single reported write-target state, priority durable > scratch >
# unresolved > none -- a durable write anywhere keeps the promise, so the
# message must never claim "scratch only" when one write was durable.
if 'durable' in write_target_states:
    write_target_state = 'durable'
elif 'scratch' in write_target_states:
    write_target_state = 'scratch'
elif 'unresolved' in write_target_states:
    write_target_state = 'unresolved'
else:
    write_target_state = 'none'

print(json.dumps({
    'final_text_found': bool(final_text),
    'commitments': commitments,
    'has_action': action_after_promise,
    'has_action_anywhere_in_turn': has_action,
    'primary_promise_kind': primary_kind,
    'action_kinds_seen': sorted(action_kinds_seen),
    'durable_kinds_seen': sorted(durable_kinds_seen),
    'write_target_state': write_target_state,
    'tools': turn_tools,
}, ensure_ascii=False))
PYEOF
)"

[[ -z "$VERDICT" ]] && exit 0

# Pull fields out of the verdict JSON (fail-open on any parse error).
VF="$(printf '%s' "$VERDICT" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    d = {}
print("yes" if d.get("final_text_found") else "no")
print("yes" if d.get("has_action") else "no")
print("|".join(d.get("tools", []) or []))
import json as _j
print(_j.dumps(d.get("commitments", []) or [], ensure_ascii=False))
print(d.get("primary_promise_kind") or "")
print(",".join(d.get("action_kinds_seen", []) or []))
print("yes" if d.get("has_action_anywhere_in_turn") else "no")
# PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: APPENDED as line 8, never
# inserted — the bash driver reads the fields above positionally with
# sed -n 'Np', so a shift would silently mislabel every journal row.
print(",".join(d.get("durable_kinds_seen", []) or []))
# r2: APPENDED as line 9, same append-only discipline.
print(d.get("write_target_state") or "none")
' 2>/dev/null || true)"

FINAL_FOUND="$(printf '%s' "$VF" | sed -n '1p')"
HAS_ACTION="$(printf '%s' "$VF" | sed -n '2p')"
TOOLSJoined="$(printf '%s' "$VF" | sed -n '3p')"
COMMITMENTS_JSON="$(printf '%s' "$VF" | sed -n '4p')"
PRIMARY_KIND="$(printf '%s' "$VF" | sed -n '5p')"
ACTION_KINDS_SEEN="$(printf '%s' "$VF" | sed -n '6p')"
HAS_ACTION_ANYWHERE_IN_TURN="$(printf '%s' "$VF" | sed -n '7p')"
DURABLE_KINDS_SEEN="$(printf '%s' "$VF" | sed -n '8p')"
WRITE_TARGET_STATE="$(printf '%s' "$VF" | sed -n '9p')"

# PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: the turn DID write files, but no
# write landed on a durable target — the correction below names that, so the
# lead sees WHY the scratch write did not count (rendered surface).
# r2: an unresolvable Bash write target is a distinct reason from "scratch" --
# the guard could not tell, and the conservative answer is "not kept", not a
# silent fold into the scratch message. Check this FIRST: "write seen, not
# durable" is also true when unresolved, so SCRATCH_WRITE_ONLY must require
# the resolved state to actually be scratch, or it masks the unresolved case.
UNRESOLVED_WRITE="no"
[[ "${WRITE_TARGET_STATE}" == "unresolved" ]] && UNRESOLVED_WRITE="yes"
SCRATCH_WRITE_ONLY="no"
if [[ "${UNRESOLVED_WRITE}" == "no" \
      && ",${ACTION_KINDS_SEEN}," == *",write,"* \
      && ",${DURABLE_KINDS_SEEN}," != *",write,"* ]]; then
  SCRATCH_WRITE_ONLY="yes"
fi

[[ "$FINAL_FOUND" == "yes" ]] || exit 0

# commitments present? (python list -> count)
N_COMMIT="$(printf '%s' "$COMMITMENTS_JSON" | python3 -c '
import sys, json
try:
    print(len(json.loads(sys.stdin.read())))
except Exception:
    print(0)
' 2>/dev/null || true)"
[[ "${N_COMMIT:-0}" -gt 0 ]] || exit 0   # no commitment shape -> silent, no log row

# --- determine verdict ------------------------------------------------------
# PROMISE-GUARD-TURN-IT-ON-01: `verdict` keeps the pre-flip semantics (fired =
# promise unkept) so the journal's fired bucket stays comparable across the flip
# and keeps collecting UNCLASSIFIED shapes as taxonomy-widening evidence — 402 of
# 423 fired rows were unclassified at flip time. Whether a fired verdict actually
# BLOCKS is decided separately (BLOCK_DECISION below) and recorded in its own
# journal field, so "fired but log-only" stays visible as evidence, not lost.
BLOCK_DECISION="no"
if [[ -n "$PRIMARY_KIND" ]]; then
  # classified promise: kept only by an action of the same kind
  if [[ "$HAS_ACTION" == "yes" ]]; then
    VERDICT_KIND="suppressed_action"
  else
    VERDICT_KIND="fired"
    BLOCK_DECISION="yes"
  fi
else
  # unclassified promise: verdict follows the SAME binding the verdict JSON
  # already computed — PROMISE-GUARD-UNKNOWN-KIND-01: kept only by a
  # state-changing action, never by a read (the old HAS_ACTION_ANYWHERE_IN_TURN
  # here let a turn of pure reads suppress the verdict on the 2026-09-02
  # escape). Blocking still needs the explicit opt-in
  # LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1, so unclassified fired rows stay
  # evidence, not blocks.
  if [[ "$HAS_ACTION" == "yes" ]]; then
    VERDICT_KIND="suppressed_action"
  else
    VERDICT_KIND="fired"
    [[ "${LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED:-0}" == "1" ]] && BLOCK_DECISION="yes"
  fi
fi

# first commitment clause = the quote
QUOTE="$(printf '%s' "$COMMITMENTS_JSON" | python3 -c '
import sys, json
try:
    arr = json.loads(sys.stdin.read())
    print((arr[0] if arr else "")[:280])
except Exception:
    print("")
' 2>/dev/null || true)"

# detect which pattern family matched the quote (for telemetry)
PATTERN="$(printf '%s' "$QUOTE" | python3 -c '
import sys, re
q = sys.stdin.read()
if re.search(r"сейчас\s+(?:же\s+)?(?:приземляю|запускаю|поднимаю|диспатчу|начинаю|иду|сделаю|проверю|подниму|запущу|отправлю|дам|пойду|беру|поправлю|прогоню|закоммичу)", q, re.I):
    print("COMMIT_RU_NOW")
elif re.search(r"(приземляю|запускаю|поднимаю|диспатчу|начинаю|иду|сделаю|проверю|подниму|запущу|отправлю|дам|пойду|беру|поправлю|прогоню|закоммичу)", q, re.I):
    print("COMMIT_RU")
else:
    print("COMMIT_EN")
' 2>/dev/null || true)"

# --- durable log (one row per evaluated turn with a commitment shape) -------
LOG="$HOME/.claude/leadv2-promise-guard.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
TOOLS_LIST="$TOOLSJoined"
python3 -c '
import json, sys, os
row = {
    "ts": sys.argv[1],
    "session_id": sys.argv[2],
    "cwd": sys.argv[3],
    "verdict": sys.argv[4],
    "quote": sys.argv[5],
    "pattern": sys.argv[6],
    "tools": (sys.argv[7].split("|") if sys.argv[7] else []),
    "n_commitments": int(sys.argv[8] or 0),
    "primary_promise_kind": (sys.argv[9] or None),
    "action_kinds_seen": (sys.argv[10].split(",") if sys.argv[10] else []),
    # PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: trailing argv, appended —
    # makes the suppressed_action->fired flip for scratch-only turns
    # measurable, the way action_kinds_seen already is.
    "durable_kinds_seen": (sys.argv[13].split(",") if sys.argv[13] else []),
    "block_mode": sys.argv[11],
    "block_decision": sys.argv[12],
    # r2: trailing argv 14, appended — same discipline as argv 13 above.
    "write_target_state": (sys.argv[14] if len(sys.argv) > 14 else "none"),
}
path = os.path.expanduser("~/.claude/leadv2-promise-guard.jsonl")
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
' "$TS" "$SESSION_ID" "$CWD" "$VERDICT_KIND" "$QUOTE" "$PATTERN" "$TOOLS_LIST" "${N_COMMIT:-0}" \
  "$PRIMARY_KIND" "$ACTION_KINDS_SEEN" "${LEADV2_PROMISE_GUARD_BLOCK:-1}" "$BLOCK_DECISION" \
  "$DURABLE_KINDS_SEEN" "$WRITE_TARGET_STATE" 2>/dev/null || true

# suppressed by an action tool -> silent
[[ "$VERDICT_KIND" == "suppressed_action" ]] && exit 0

# --- blocking rollout (PROMISE-GUARD-TURN-IT-ON-01) -------------------------
# FLIPPED 2026-09-01: the default is now ON. A fired verdict blocks only when
# BLOCK_DECISION=yes (classified kind, or the BLOCK_UNCLASSIFIED opt-in); an
# unclassified fired row above is evidence, not a block. One-step rollback:
# LEADV2_PROMISE_GUARD_BLOCK=0 returns the hook to log-only immediately.
if [[ "${LEADV2_PROMISE_GUARD_BLOCK:-1}" != "1" ]]; then
  exit 0
fi
[[ "${BLOCK_DECISION:-no}" == "yes" ]] || exit 0

# --- block AT MOST ONCE per turn (sentinel, identical to prose-guard) -------
SENTINEL="$HOME/.claude/leadv2-promise-retry-${SESSION_ID}.txt"
if [[ -f "$SENTINEL" ]]; then
  # second Stop in the same turn -> pass through, no deadlock
  rm -f "$SENTINEL" 2>/dev/null || true
  exit 0
fi
printf '1\n' > "$SENTINEL" 2>/dev/null || true

# --- emit the correction (decision:block so the model gets one more turn) ---
python3 - "$QUOTE" "$TOOLS_LIST" "$SCRATCH_WRITE_ONLY" "$UNRESOLVED_WRITE" <<'PYEOF'
import sys, json
quote = sys.argv[1]
tools_raw = sys.argv[2]
scratch_only = (len(sys.argv) > 3 and sys.argv[3] == "yes")
unresolved_write = (len(sys.argv) > 4 and sys.argv[4] == "yes")
tools = ([t for t in tools_raw.split("|")] if tools_raw else [])
tools_str = ", ".join(tools) if tools else "(none)"
reason = (
    "PROMISE-GUARD: you ended the turn on a commitment with zero "
    "state-changing calls.\n"
    "Unkept: \"" + quote + "\"\n"
    "This turn's tools: " + tools_str + ".\n"
    "Either make the call now, or restate in past tense with the artifact "
    "(sha / path / probe output). A promise in chat is not work."
)
# PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01: name the scratch write — the
# acceptance surface of this fix is rendered, not a return value.
if scratch_only:
    reason += ("\nThis turn's only file write went to a scratch path (session "
               "scratchpad / tmp), which is not where the promised work lives.")
elif unresolved_write:
    reason += ("\nThis turn's only shell write has a target the guard could "
               "not resolve (variable, command substitution, or a relative "
               "path after cd); an unresolvable write does not count as "
               "starting the promised work.")
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
PYEOF
exit 0
