#!/usr/bin/env bash
# leadv2-task-judge.sh — L2 Task judge (smart-routing-v2 spec §3 L2, §8 task T5).
#
# WHAT THIS IS
#   Estimates how hard a TASK is — never which arm/model/provider should run
#   it, never what quota is left. One cheap `claude -p --model haiku` call per
#   dispatch, mission text in, schema-validated TaskEstimate JSON out.
#
# THE INVARIANT (do not weaken)
#   The prompt template (leadv2-task-judge-prompt.tmpl, next to this script)
#   contains ZERO arm/model/provider/quota vocabulary. The moment the judge's
#   prompt knows about arms or quota, its estimate stops being an independent
#   input and becomes a routing decision in disguise — see
#   tests/test-leadv2-task-judge.sh::test_lexicon_grep_on_prompt_template.
#
# RISK R2 (judge circularity, spec §5): the judge burns the same Anthropic
#   bucket it exists to help ration. If that bucket empties, the judge must
#   degrade, never block a dispatch. Three mitigations, all implemented here:
#     1. code-only fallback estimator — works with no model call at all;
#     2. cache by mission signature (sig8 of mission text) — a re-dispatch of
#        the same mission never re-pays the call;
#     3. --class Light skips the judge outright — cheap work doesn't deserve
#        a model call.
#   Fallback fires automatically on ANY failure — disable flag, timeout,
#   non-zero exit, empty output, malformed JSON, schema mismatch — never just
#   on the explicit disable flag.
#
# Usage:
#   leadv2-task-judge.sh --mission-file <path> [--task-id <id>] [--class Light|Standard|Heavy|Strategic]
#
# Always exits 0 (fallback covers every failure mode); stdout is exactly one
# line of TaskEstimate JSON. Usage errors (missing/unreadable --mission-file)
# exit 2 — those are caller bugs, not a runtime condition the fallback covers.
#
# JOURNAL (JUDGE-REVIVAL-01): every route_v2_estimate line carries judge_path=
# naming the exit path that produced it (disable | light_skip | cache_hit |
# judge | judge_fail); judge_fail lines also carry judge_fail_reason=
# (template_missing | prompt_build | timeout | nonzero_rc | empty_output |
# envelope_parse | schema_invalid). A fallback that cannot say why it fell
# back is indistinguishable from a skip — that silence is what kept the live
# Standard/Heavy judge failures invisible (Part 0, judge-revival-diagnosis.md).
#
# Env:
#   LEADV2_JUDGE_DISABLE       1 = never call the model; estimate_source=fallback always
#   LEADV2_JUDGE_MODEL         override model id (default: haiku)
#   LEADV2_JUDGE_TIMEOUT_SEC   override judge call timeout in seconds (default: 45)
#   LEADV2_JUDGE_CLAUDE_BIN    override the `claude` binary (tests)
#   LEADV2_JUDGE_CACHE_DIR     override cache directory (tests)
#   LEADV2_JUDGE_JOURNAL_BIN   override path to leadv2-journal.sh (tests)
#
# This script is inert until wired behind LEADV2_ROUTER_V2 (default off) by
# the T6 selector — building it does not change any live routing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}}"

JOURNAL_BIN="${LEADV2_JUDGE_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
CLAUDE_BIN="${LEADV2_JUDGE_CLAUDE_BIN:-claude}"
JUDGE_MODEL="${LEADV2_JUDGE_MODEL:-haiku}"
# SHARED-TREE-PERMISSION-09 (2026-09-07): 45 was set before any live-shaped
# measurement existed. 8 real invokes (5 at a 45s budget, 3 at 120s) measured
# 36.36-46.89s wall-clock -- the CALL ITSELF takes this long regardless of
# budget (the 120s runs finished in the same 36-45s range, not faster), so
# the tail (46.89s), not the median, is what a timeout must clear. 90 gives
# ~43s of margin over the worst observed call -- roughly 2x the max, chosen
# to absorb further gateway slowdowns (judge-revival-diagnosis.md's own E4
# finding) without being an arbitrary round number.
TIMEOUT_SEC="${LEADV2_JUDGE_TIMEOUT_SEC:-90}"
PROMPT_TMPL="${SCRIPT_DIR}/leadv2-task-judge-prompt.tmpl"

die() { printf -- '[leadv2-task-judge] %s\n' "$*" >&2; exit 2; }

# ── leadv2_dir resolution (mirrors leadv2-journal.sh) ───────────────────────
_sp_yaml="${PROJECT_ROOT}/.claude/leadv2-overrides/state-paths.yaml"
_leadv2_dir=$(grep -E "^[[:space:]]*leadv2_dir[[:space:]]*:" "${_sp_yaml}" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*leadv2_dir[[:space:]]*:[[:space:]]*//" | sed -E "s/^['\"]//; s/['\"][[:space:]]*\$//" | tr -d '\r' || true)
[[ -z "${_leadv2_dir}" || "${_leadv2_dir}" == "null" || "${_leadv2_dir}" == "~" ]] && _leadv2_dir="docs/leadv2"
CACHE_DIR="${LEADV2_JUDGE_CACHE_DIR:-${PROJECT_ROOT}/${_leadv2_dir}/judge-cache}"

# ── args ─────────────────────────────────────────────────────────────────────
MISSION_FILE=""
TASK_ID=""
CLASS_HINT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mission-file) MISSION_FILE="${2:-}"; shift 2 ;;
    --task-id)      TASK_ID="${2:-}"; shift 2 ;;
    --class)        CLASS_HINT="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done
[[ -n "${MISSION_FILE}" ]] || die "--mission-file is required"
[[ -r "${MISSION_FILE}" ]] || die "mission file not found or unreadable: ${MISSION_FILE}"

MISSION_TEXT="$(cat "${MISSION_FILE}")"
SIG8="$(python3 -c "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])" <<<"${MISSION_TEXT}")"
[[ -n "${SIG8}" ]] || die "failed to compute mission signature"

# ── safety risk-class matcher surface (CLASSIFIER-CALLS-SAFETY-DOCTRINE-
# SIMPLE-01, blueprint §3/§8) ────────────────────────────────────────────────
# protected_path_patterns (glm_policy.protected_path_patterns) are PATH GLOBS.
# Matching them -- or any safety keyword -- against the whole free-text
# mission body is the category error both directions of the bug trace to:
#   - HEAVY-TIER-VS-SAFETY-OPUS-01 (false negative): the task id carries the
#     bare token SAFETY, but no existing pattern ('safety gate'/'safety-gate')
#     requires it adjacent to 'gate', so the id never fires.
#   - CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 (false positive): the body
#     contains "...does not publish a reset..." -- 'publish' the English verb,
#     not the product-action path glob -- and the old whole-body scan fired.
# Fix (§3): restrict the scan to the mission's own id/title (its first '#'
# heading line -- in every real mission on disk the task id IS the title, see
# census 2b) with a token match, never the free-text body.
#
# Blueprint §3 also specs a third arm: match the dispatcher's *already-
# resolved* protected_path_patterns against actual paths. That arm is
# deliberately NOT implemented here. Verified before writing this: (a) the
# census (2b-a) found 0 of 324 real lane-mission.md files carry a Reads:/
# Writes:/Touches: line, so sourcing paths from the mission body would be
# decorative; (b) this script's only inputs are --mission-file/--task-id/
# --class (see arg parsing above) and the caller
# (leadv2-dispatch-code.sh:_dispatch_complexity_estimate) passes sig8 as
# --task-id, never a resolved path list -- so there is no channel through
# which _effective_protected's paths could reach this process today. Per
# §3's own instruction ("if no such list is reachable from the judge, ship
# the id+title arm alone and say so -- never ship an arm that cannot fire"),
# this ships id+title only. A prior uncommitted draft of this fix (rescued
# 2026-09-03 after a worker death, see `git log` on this branch) built the
# path-glob arm against Reads:/Writes:/Touches: anyway -- that was the exact
# decorative arm §3 forbids, and is removed here, not carried forward.
#
# No LEADV2_* bypass flag -- a kill-switch on a safety rule is the anti-
# pattern this fix deletes. Token set: see _fallback_estimate, SAFETY_TOKENS.

# ── code-only fallback estimator (R2 mitigation #1) ─────────────────────────
_fallback_estimate() {
  python3 -c "
import json, re, sys

mission_text = sys.argv[1]
sig8 = sys.argv[2]
class_hint = sys.argv[3] if len(sys.argv) > 3 else ''
text_lower = mission_text.lower()
lines = mission_text.count(chr(10)) + 1

if class_hint == 'Light':
    complexity, duration_class = 'simple', 'short'
    basis = 'class_hint'
elif class_hint == 'Standard':
    complexity, duration_class = 'standard', 'medium'
    basis = 'class_hint'
elif class_hint in ('Heavy', 'Strategic'):
    complexity, duration_class = 'complex', 'long'
    basis = 'class_hint'
elif lines <= 30:
    complexity, duration_class = 'trivial', 'short'
    basis = 'line_count'
elif lines <= 100:
    complexity, duration_class = 'simple', 'short'
    basis = 'line_count'
elif lines <= 300:
    complexity, duration_class = 'standard', 'medium'
    basis = 'line_count'
else:
    complexity, duration_class = 'complex', 'long'
    basis = 'line_count'

# ── structured-surface safety matcher (CLASSIFIER-CALLS-SAFETY-DOCTRINE-
# SIMPLE-01) -- protected_path_patterns are path globs; scanning them (or any
# safety keyword) against the free-text mission body is the category error
# HEAVY-TIER-VS-SAFETY-OPUS-01 (false negative, id-only) and CLASSIFIER-MUST-
# SEE-QUOTA-AND-RESET-DATE-01 (false positive, homograph 'publish') both trace
# to. Restricted to the mission's own id/title -- its first '#' heading line,
# token-matched (whole hyphen/underscore-delimited token, case insensitive)
# against safety/publish/payment/payments. The free-text body is never
# scanned for this risk class again (a path-glob arm against declared paths
# was considered and deliberately dropped -- see the comment above this
# function's caller for why). DATA_KEYWORDS below is unrelated prior art,
# deliberately left scanning the body as-is (out of scope for this fix).
SAFETY_TOKENS = ('safety', 'publish', 'payment', 'payments')

# flag_source priority (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 round 1) --
# the ONE place this order is declared; reorder here, nowhere else, when a
# source is added or promoted. Founder decision (docs/handoff/SMART-ARBITER-01/
# brief.md §10, D4): what makes a task "protected" is write paths, not prose --
# prose is demoted to advisory once the path arm ships, target field name
# 'flag_source=path' per that same decision row. 'path' is listed first (it is
# the target state) but is NOT YET AVAILABLE: LANE_WRITES is empty in 237/241
# dispatches (98.3%), filed as LANE-WRITES-IS-EMPTY-98-PERCENT-01 -- until that
# closes there is no reachable write-path signal for this resolver to key on
# (see the caller's comment above for why no decorative arm was built for it).
# So this resolver falls through to 'title' today. When LANE-WRITES-IS-EMPTY-
# 98-PERCENT-01 closes: add 'path' to FLAG_SOURCE_AVAILABLE (and implement the
# path arm) -- do not reorder FLAG_SOURCE_PRIORITY itself, its order already
# reflects the target state.
FLAG_SOURCE_PRIORITY = ('path', 'title')
FLAG_SOURCE_AVAILABLE = {'title'}  # add 'path' when LANE-WRITES-IS-EMPTY-98-PERCENT-01 closes
flag_source = next(s for s in FLAG_SOURCE_PRIORITY if s in FLAG_SOURCE_AVAILABLE)

title = ''
for ln in mission_text.splitlines():
    s = ln.strip()
    if s.startswith('#'):
        title = s.lstrip('#').strip()
        break
title_tokens = set(t for t in re.split(r'[^a-z0-9]+', title.lower()) if t)
title_hit = bool(title_tokens & set(SAFETY_TOKENS))

DATA_KEYWORDS = ('migration', 'schema', 'supabase', 'database', 'drop table', 'postgres')
if title_hit:
    risk_class = 'safety_publish_payments'
elif any(k in text_lower for k in DATA_KEYWORDS):
    risk_class = 'data'
else:
    risk_class = 'none'

REVIEW_KEYWORDS = ('code review', 'adversarial review', 'review the diff', 'critic pass')
DIAGNOSE_KEYWORDS = ('root cause', 'root-cause', 'diagnose', 'debug', 'bug report')
DOCS_KEYWORDS = ('documentation only', 'docs only', 'write docs', 'update the docs')
if any(k in text_lower for k in REVIEW_KEYWORDS):
    work_kind = 'review'
elif any(k in text_lower for k in DIAGNOSE_KEYWORDS):
    work_kind = 'diagnose'
elif any(k in text_lower for k in DOCS_KEYWORDS):
    work_kind = 'docs'
else:
    work_kind = 'build'

LIVE_KEYWORDS = ('vps', 'prod', 'live-verify', 'live verification', 'journalctl', 'live probe')
needs_live_verification = any(k in text_lower for k in LIVE_KEYWORDS)

SUBSYSTEM_KEYWORDS = ('agent/', 'platform/', 'web/', '.claude/scripts', 'supabase', 'qdrant',
                      'route-bandit', 'dispatch', 'journal', 'judge', 'router', 'bandit')
subsystems_touched = max(1, min(10, sum(1 for k in SUBSYSTEM_KEYWORDS if k in text_lower)))

estimate = {
    'estimate_v': 1,
    'complexity': complexity,
    'subsystems_touched': subsystems_touched,
    'needs_live_verification': needs_live_verification,
    'risk_class': risk_class,
    'duration_class': duration_class,
    'work_kind': work_kind,
    'estimate_id': sig8,
    'estimate_source': 'fallback',
    'complexity_basis': basis,
    'flag_source': flag_source,
}
print(json.dumps(estimate, sort_keys=True))
" "${MISSION_TEXT}" "${SIG8}" "${CLASS_HINT}"
}

# ── schema validation (shared: judge output, cache reads) ───────────────────
# Reads a candidate TaskEstimate JSON on stdin; prints it back unchanged and
# exits 0 if valid, exits 1 (prints nothing) otherwise.
_validate_estimate() {
  python3 -c "
import json, sys

ALLOWED = {
    'complexity': {'trivial', 'simple', 'standard', 'complex'},
    # complexity_basis (ARBITER-SCORING-DESIGN-01 §7.2) is OPTIONAL:
    # an estimate cached before the field existed must still validate.
    # It must never join REQUIRED -- every cached estimate on disk
    # would fail validation the moment this shipped.
    'complexity_basis': {'judge', 'class_hint', 'line_count'},
    'risk_class': {'none', 'data', 'safety_publish_payments'},
    'duration_class': {'short', 'medium', 'long'},
    'work_kind': {'build', 'review', 'diagnose', 'docs'},
    'estimate_source': {'judge', 'fallback'},
    'flag_source': {'path', 'title', 'judge'},
}
REQUIRED = ('estimate_v', 'complexity', 'subsystems_touched', 'needs_live_verification',
            'risk_class', 'duration_class', 'work_kind', 'estimate_id', 'estimate_source',
            'flag_source')

try:
    est = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(est, dict):
    sys.exit(1)
for k in REQUIRED:
    if k not in est:
        sys.exit(1)
for field, allowed in ALLOWED.items():
    # An absent ALLOWED key is skipped, not KeyError'd -- the old
    # est[field] read made every ALLOWED key de-facto REQUIRED,
    # which is exactly the cached-estimate break §7.2 forbids. Every
    # enum field that must be present is already in REQUIRED above.
    if field in est and est[field] not in allowed:
        sys.exit(1)
if not isinstance(est['subsystems_touched'], int) or isinstance(est['subsystems_touched'], bool):
    sys.exit(1)
if not (0 <= est['subsystems_touched'] <= 10):
    sys.exit(1)
if not isinstance(est['needs_live_verification'], bool):
    sys.exit(1)
if est['estimate_v'] != 1:
    sys.exit(1)
print(json.dumps(est, sort_keys=True))
" 2>/dev/null
}

# ── judge invocation (arm-blind LLM call) ───────────────────────────────────
# JUDGE-REVIVAL-01: every failure below records its reason via _fail() so the
# :500 fallback can journal it as judge_fail_reason= — a failed invoke stays
# forever distinguishable from disable/light_skip/cache_hit (Part 0 E4/E6:
# before this, all five exit paths journaled identically and the live
# 0-judge census could not say WHY). _fail writes to fd 3 because the caller
# captures this function in a $( ) command substitution — a subshell — so a
# plain JUDGE_FAIL_REASON= assignment would die with the subshell and the
# journal would read judge_fail_reason=unknown (caught by the first smoke run).
_fail() {  # <reason>
  JUDGE_FAIL_REASON="$1"
  { printf '%s' "$1" >&3; } 2>/dev/null || true
}

_invoke_judge() {
  [[ -f "${PROMPT_TMPL}" ]] || { _fail "template_missing"; printf -- '[leadv2-task-judge] prompt template missing: %s\n' "${PROMPT_TMPL}" >&2; return 1; }

  local prompt
  prompt="$(python3 -c "
import sys
tmpl = open(sys.argv[1], encoding='utf-8').read()
print(tmpl.replace('<<<MISSION_TEXT>>>', sys.argv[2]), end='')
" "${PROMPT_TMPL}" "${MISSION_TEXT}")" || { _fail "prompt_build"; return 1; }

  local timeout_cmd=""
  if command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout"
  elif command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout"
  fi

  local raw="" rc=0
  # BEAT-LOOP-ORPHANS-01 fix-round 2: every headless `claude -p` spawn site
  # pins LEADV2_SUBSESSION_ROLE so hooks/lib/leadv2-hook-session-kind.sh can
  # classify the child as a worker without reading its transcript (grep-gated
  # by tests/test-beat-loop-orphans.sh). Env prefix survives the timeout exec.
  # `< /dev/null` (JUDGE-REVIVAL-01, Part 0 E5): claude -p waits 3s for piped
  # stdin before proceeding — an unconditional 3s out of the 45s timeout
  # budget on every call, for stdin this script never sends.
  if [[ -n "${timeout_cmd}" ]]; then
    raw="$(LEADV2_SUBSESSION_ROLE="${LEADV2_SUBSESSION_ROLE:-judge}" "${timeout_cmd}" "${TIMEOUT_SEC}" "${CLAUDE_BIN}" -p "${prompt}" --model "${JUDGE_MODEL}" --max-turns 3 --permission-mode bypassPermissions --output-format json < /dev/null 2>/dev/null)" || rc=$?
  else
    raw="$(LEADV2_SUBSESSION_ROLE="${LEADV2_SUBSESSION_ROLE:-judge}" "${CLAUDE_BIN}" -p "${prompt}" --model "${JUDGE_MODEL}" --max-turns 3 --permission-mode bypassPermissions --output-format json < /dev/null 2>/dev/null)" || rc=$?
  fi
  # GNU timeout exits 124 on TERM-timeout, 137 after a -k KILL. Both used to
  # be an unconditional _fail "timeout" — SHARED-TREE-PERMISSION-09
  # (2026-09-07): a live measurement found the model had ALREADY produced a
  # complete answer in 2 of 3 "timeouts" (the process was killed after
  # writing its output, not before) — we were discarding finished work and
  # mislabelling it a failure. Only a genuinely EMPTY body on a timeout-kill
  # is a real failure now; a non-empty body falls through to the same
  # envelope/schema parsing every other path uses, so a truncated-mid-write
  # answer is still caught (and correctly labelled envelope_parse/
  # schema_invalid) rather than silently miscounted as "timeout".
  if [[ ${rc} -eq 124 || ${rc} -eq 137 ]]; then
    if [[ -z "${raw}" ]]; then
      _fail "timeout"
      return 1
    fi
  elif [[ ${rc} -ne 0 ]]; then
    _fail "nonzero_rc"
    return 1
  fi
  [[ -n "${raw}" ]] || { _fail "empty_output"; return 1; }

  # `claude -p --output-format json` wraps the assistant's answer in an
  # envelope under `.result`; the model may still fence it in ```json, or
  # precede/follow it with prose. Pull the envelope apart, then pull the
  # first COMPLETE, balanced {...} object out of the result.
  # Two-stage on purpose (JUDGE-REVIVAL-01): claude already succeeded above,
  # so a failure here is an envelope/parse problem, never an invoke problem —
  # the old single $(claude | python) pipeline folded both into one rc and
  # mislabelled parse failures as invoke failures.
  #
  # JUDGE-ENVELOPE-PARSE-FAILS-A-QUARTER-OF-THE-TIME-01: the prior extractor
  # was `re.search(r'\{.*\}', result_text, re.DOTALL)` -- greedy from the
  # FIRST '{' to the LAST '}' anywhere in the whole reply. Any brace character
  # in surrounding prose after a valid JSON object (a code-fence's own text
  # never contains one, but a sentence like "adjust the {} shape" does) makes
  # the match span past the real object and json.loads raises "Extra data" --
  # a correctly-formed answer misreported as envelope_parse. Live-captured
  # sample (redacted, this task's probe) reproduced it: a fenced JSON object
  # followed by one clause containing a bare '{}' broke the greedy match while
  # the object itself was perfectly valid. Fixed by scanning for the first
  # '{' whose braces balance (string-aware, so a brace inside a JSON string
  # value never miscounts depth) and only accepting it once it parses; on
  # failure the scan resumes from the NEXT '{' rather than giving up, so
  # leading prose before the real object is also tolerated. A reply with no
  # balanced, parseable object anywhere (truncated mid-write, pure prose, a
  # refusal) still finds nothing and still fails envelope_parse -- being
  # permissive about the WRAPPER must not become permissive about the
  # CONTENT.
  local parsed=""
  parsed="$(printf '%s' "${raw}" | python3 -c "
import json, sys

raw = sys.stdin.read()
try:
    env = json.loads(raw)
except Exception:
    sys.exit(1)
if env.get('is_error'):
    sys.exit(1)
result_text = env.get('result', '')
if not isinstance(result_text, str):
    sys.exit(1)

# EXTRACT-BEGIN (test-judge-parses-its-own-answer.sh mutates only between
# EXTRACT-BEGIN/EXTRACT-END; never at top level)
def first_balanced_object(text):
    n = len(text)
    search_from = 0
    while True:
        start = text.find('{', search_from)
        if start == -1:
            return None
        depth = 0
        in_str = False
        esc = False
        j = start
        while j < n:
            c = text[j]
            if in_str:
                if esc:
                    esc = False
                elif c == '\\\\':
                    esc = True
                elif c == '\"':
                    in_str = False
            else:
                if c == '\"':
                    in_str = True
                elif c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0:
                        candidate = text[start:j + 1]
                        try:
                            return json.loads(candidate)
                        except Exception:
                            break
            j += 1
        search_from = start + 1

est = first_balanced_object(result_text)
if est is None or not isinstance(est, dict):
    sys.exit(1)
# EXTRACT-END
est['estimate_v'] = 1
est['estimate_id'] = sys.argv[1]
est['estimate_source'] = 'judge'
# The judge path's risk_class comes from the LLM call itself, not the id/
# title resolver in _fallback_estimate -- flag_source='judge' says so
# honestly rather than borrowing a value from a resolver that never ran.
est['flag_source'] = 'judge'
# complexity_basis (ARBITER-SCORING-DESIGN-01 step 2, §7.2): 'judge' --
# the wrapper's knowledge, like estimate_source, never the model's.
est['complexity_basis'] = 'judge'
print(json.dumps(est))
" "${SIG8}")" || { _fail "envelope_parse"; return 1; }
  [[ -n "${parsed}" ]] || { _fail "envelope_parse"; return 1; }
  printf '%s\n' "${parsed}"
}

# ── journal helper (best-effort, never fatal) ───────────────────────────────
_journal() {
  local estimate_json="$1" cache_hit="$2" path="${3:-fallback}"
  local src complexity work_kind duration_class risk_class subsystems live
  src="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('estimate_source',''))" <<<"${estimate_json}" 2>/dev/null)"
  complexity="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('complexity',''))" <<<"${estimate_json}" 2>/dev/null)"
  work_kind="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('work_kind',''))" <<<"${estimate_json}" 2>/dev/null)"
  duration_class="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('duration_class',''))" <<<"${estimate_json}" 2>/dev/null)"
  risk_class="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('risk_class',''))" <<<"${estimate_json}" 2>/dev/null)"
  subsystems="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('subsystems_touched',''))" <<<"${estimate_json}" 2>/dev/null)"
  live="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('needs_live_verification',''))" <<<"${estimate_json}" 2>/dev/null)"
  # flag_source (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 round 1): what the
  # risk_class verdict was based on -- 'title' (interim) / 'path' (target
  # state, not yet reachable -- LANE-WRITES-IS-EMPTY-98-PERCENT-01) / 'judge'
  # (LLM decided directly). Priority order lives in one place: the
  # FLAG_SOURCE_PRIORITY list in _fallback_estimate above.
  local flag_source
  flag_source="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('flag_source',''))" <<<"${estimate_json}" 2>/dev/null)"
  # complexity_basis (ARBITER-SCORING-DESIGN-01 step 2, §7.2): what the
  # complexity verdict was based on -- judge / class_hint / line_count.
  # Empty on estimates cached before the field existed -> prints 'none'.
  local complexity_basis
  complexity_basis="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('complexity_basis',''))" <<<"${estimate_json}" 2>/dev/null)"
  # judge_path / judge_fail_reason (JUDGE-REVIVAL-01, Part 0 E4/E6): which of
  # the five exit paths produced this line — disable | light_skip | cache_hit |
  # judge | judge_fail — and, on judge_fail, why the invoke produced nothing:
  # template_missing | prompt_build | timeout | nonzero_rc | empty_output |
  # envelope_parse | schema_invalid. Before this token existed, a judge call
  # that timed out and a --class Light skip journaled identically, and the
  # live "0 judge decisions" census could not say which it was looking at.
  local path_suffix=" judge_path=${path}"
  if [[ "${path}" == "judge_fail" ]]; then
    path_suffix="${path_suffix} judge_fail_reason=${JUDGE_FAIL_REASON:-unknown}"
  fi
  if [[ -n "${TASK_ID}" && -f "${JOURNAL_BIN}" ]]; then
    # safety_floor (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01, blueprint §4):
    # "a rule with no reader is not a rule" -- SAFETY_FLOOR_STATUS is set by
    # _emit's call to _apply_safety_floor just before this call runs; the
    # default here only guards an unexpected empty value.
    bash "${JOURNAL_BIN}" append "${TASK_ID}" decision \
      "route_v2_estimate estimate_id=${SIG8} estimate_source=${src} complexity=${complexity} work_kind=${work_kind} duration_class=${duration_class} risk_class=${risk_class} flag_source=${flag_source:-none} subsystems_touched=${subsystems} needs_live_verification=${live} cache_hit=${cache_hit} safety_floor=${SAFETY_FLOOR_STATUS:-none} complexity_basis=${complexity_basis:-none}${path_suffix}" \
      >/dev/null 2>&1 || true
  fi
  # T13's audit joins durable estimate records against close outcomes.  The
  # append is v2-gated and locked, so flag-off judge behavior remains unchanged.
  if [[ "${LEADV2_ROUTER_V2:-0}" == "1" ]]; then
    local estimates_file="${PROJECT_ROOT}/${_leadv2_dir}/route-estimates.jsonl"
    mkdir -p "$(dirname "${estimates_file}")"
    (
      flock -x 200
      python3 -c 'import json,sys; row=json.loads(sys.argv[1]); row["task_id"]=sys.argv[2]; print(json.dumps(row, sort_keys=True))' \
        "${estimate_json}" "${TASK_ID:-unknown}" >> "${estimates_file}"
    ) 200>"${estimates_file}.lock" || true
  fi
}

# ── safety floor (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01, blueprint §4) ──
# Monotonic floor: an estimate whose risk_class is safety_publish_payments
# must never resolve to trivial/simple complexity. Applied inside _emit(),
# as its first statement -- before printf, before _journal -- because _emit
# is the single choke point all 5 exit paths (disable / --class Light /
# cache-hit / judge-validated / fallback) pass through. That includes the
# cache-hit path (§4): a stored pre-fix estimate self-heals on the next read
# with no migration, because the floor runs on the way OUT of the cache, not
# on the way in (the raw cache write at the judge-call site is untouched).
#
# Floors to 'standard', never 'complex' -- 'complex' would over-escalate
# duration/heavy-tier routing, which this fix is not chartered to touch.
# Touches ONLY complexity -- duration_class/work_kind/subsystems_touched
# pass through unchanged; a safety fix can honestly be short.
#
# This decides task SHAPE only. It never names, prefers, or excludes an arm
# -- the arbiter still chooses (leadv2-route-arbiter.sh, off-limits, read-
# only in this task); enforcement itself stays glm_policy.sonnet_exceptions
# [safety_gate_publish_payments], untouched by this fix.
#
# On any internal error the estimate passes through completely unchanged
# and SAFETY_FLOOR_STATUS is set to 'error' -- R2 (the judge must never
# block a dispatch) binds here exactly as it binds on judge-call failure.
_apply_safety_floor() {
  local estimate_json="$1"
  local out
  out="$(python3 -c "
import json, sys

raw = sys.argv[1]
try:
    est = json.loads(raw)
    if est.get('risk_class') == 'safety_publish_payments' and est.get('complexity') in ('trivial', 'simple'):
        est['complexity'] = 'standard'
        status = 'applied'
    else:
        status = 'none'
    out = json.dumps(est, sort_keys=True)
except Exception:
    out = raw
    status = 'error'
print(out)
print(status)
" "${estimate_json}" 2>/dev/null)"
  if [[ -z "${out}" ]]; then
    SAFETY_FLOOR_STATUS="error"
    printf '%s' "${estimate_json}"
    return 0
  fi
  SAFETY_FLOOR_STATUS="${out##*$'\n'}"
  printf '%s' "${out%$'\n'*}"
}

_emit() {
  local estimate_json="$1" cache_hit="${2:-false}" path="${3:-fallback}"
  estimate_json="$(_apply_safety_floor "${estimate_json}")"
  printf '%s\n' "${estimate_json}"
  _journal "${estimate_json}" "${cache_hit}" "${path}"
  exit 0
}

# ── 1. explicit disable — never touches the model, never touches cache ─────
if [[ "${LEADV2_JUDGE_DISABLE:-0}" == "1" ]]; then
  _emit "$(_fallback_estimate)" "false" "disable"
fi

# ── 2. classifier-Light skip (R2 mitigation #3) ─────────────────────────────
if [[ "${CLASS_HINT}" == "Light" ]]; then
  _emit "$(_fallback_estimate)" "false" "light_skip"
fi

# ── 3. cache hit (R2 mitigation #2) ─────────────────────────────────────────
CACHE_FILE="${CACHE_DIR}/${SIG8}.json"
if [[ -f "${CACHE_FILE}" ]]; then
  cached_valid="$(_validate_estimate < "${CACHE_FILE}")"
  if [[ -n "${cached_valid}" ]]; then
    _emit "${cached_valid}" "true" "cache_hit"
  fi
  # cache file present but corrupt/invalid — fall through and re-judge.
fi

# ── 4. judge call, validated; on ANY failure, fall back ─────────────────────
# fd 3 carries the fail reason out of the $( ) subshell (JUDGE-REVIVAL-01;
# see _fail above). On success the file stays empty -> reason empty.
_judge_reason_file="$(mktemp "${TMPDIR:-/tmp}/leadv2-judge-reason.XXXXXX")"
judge_raw="$(_invoke_judge 3>"${_judge_reason_file}")"
JUDGE_FAIL_REASON="$(cat "${_judge_reason_file}" 2>/dev/null)"
rm -f "${_judge_reason_file}"
if [[ -n "${judge_raw}" ]]; then
  judge_valid="$(_validate_estimate <<<"${judge_raw}")"
  if [[ -n "${judge_valid}" ]]; then
    mkdir -p "${CACHE_DIR}" 2>/dev/null || true
    if [[ -d "${CACHE_DIR}" ]]; then
      tmp_cache="${CACHE_DIR}/.tmp.$$.${SIG8}"
      if printf '%s' "${judge_valid}" > "${tmp_cache}" 2>/dev/null; then
        mv -f "${tmp_cache}" "${CACHE_FILE}" 2>/dev/null || rm -f "${tmp_cache}" 2>/dev/null || true
      fi
    fi
    _emit "${judge_valid}" "false" "judge"
  fi
  # judge answered but the answer failed schema validation — distinguish
  # this from the invoke-level failures below.
  JUDGE_FAIL_REASON="schema_invalid"
fi

# ── 5. fallback — reached ONLY past disable+Light+cache with a failed or
# unvalidated invoke (JUDGE-REVIVAL-01 Part 0: the silent-kill seam). The
# disable/Light/cache branches all _emit'd and exited above, so the path
# token here is judge_fail, never a bare "fallback" — a fallback journal
# line that cannot say which path produced it was exactly the defect.
_emit "$(_fallback_estimate)" "false" "judge_fail"
