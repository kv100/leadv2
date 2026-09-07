#!/usr/bin/env bash
# JUDGE-REVIVAL-01 (docs/handoff/F1-ARBITER-SCORING-20260907/
# judge-revival-diagnosis.md): the five exit paths of leadv2-task-judge.sh
# must be distinguishable ON THE JOURNAL LINE. Part 0 proved the live defect
# was mechanism 2 — Standard/Heavy invokes run, fail (timeout under gateway
# load), and fall back SILENTLY, journaling a line indistinguishable from a
# --class Light skip or a disable. This suite pins the fix:
#   judge_path=      disable | light_skip | cache_hit | judge | judge_fail
#   judge_fail_reason=  timeout | nonzero_rc | empty_output | envelope_parse
#                      | schema_invalid | template_missing | prompt_build
# plus the fd-3 plumbing that carries the reason out of the $( ) subshell
# (a plain global set inside _invoke_judge dies with the subshell — the first
# smoke run of the fix read judge_fail_reason=unknown for exactly that
# reason; case 4 would have caught it).
# Also pinned: stdin </dev/null on the invoke (Part 0 E5 — claude -p waits 3s
# for stdin it never gets) is asserted structurally by the sentinel stubs
# never blocking, and the Light-skip (R2 mitigation #3) is asserted NOT to
# call the model at all — this suite must stay green if and only if the skip
# stays a skip; loosening it is a founder decision, not a test fixture.
#
# run-all-triggers: leadv2-task-judge
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/../scripts" && pwd)"
JUDGE_BIN="${SCRIPTS_ROOT}/leadv2-task-judge.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/judge-path.XXXXXX")"
trap '[[ "${JUDGEPATH_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"; rm -f "${SCRIPTS_ROOT}/.judge-mutant-timeout-old.sh"' EXIT

bash -n "$JUDGE_BIN" || { fail "bash syntax: judge"; exit 1; }
pass "bash syntax: judge"

MISSION="$TMP/mission.md"
printf '# Test mission header\nRefactor the frobnicator module and its tests.\n' > "$MISSION"

# journal stub: leadv2-journal.sh append <task> decision <line> — keep the
# line. The log path is BAKED IN at stub-creation time (a stub reading
# $JOURNAL_LOG from its own env gets nothing — the first suite run logged
# zero lines and every path assertion red-failed on that artifact alone).
JOURNAL_LOG="$TMP/journal.log"; : > "$JOURNAL_LOG"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$4" >> "%s"\n' "$JOURNAL_LOG" > "$TMP/journal-stub.sh"
chmod +x "$TMP/journal-stub.sh"

# claude stubs. Every stub touches a sentinel so "was the model called" is a
# file-existence check, not an inference. Envelope payloads are pre-rendered
# by python3 into .payload files (embedding json.dumps output raw inside a
# bash double-quoted printf breaks quoting — second artifact of the first run:
# the "healthy" stub was a syntax error and case 1 fell back envelope_parse).
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
VALID_EST='{"complexity":"standard","subsystems_touched":3,"needs_live_verification":false,"risk_class":"none","duration_class":"medium","work_kind":"build"}'
python3 -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"is_error":False,"result":sys.argv[2]}))' "$STUBS/ok.payload" "$VALID_EST"
python3 -c 'import json,sys; d=json.loads(sys.argv[2]); d["complexity"]="gigantic"; open(sys.argv[1],"w").write(json.dumps({"is_error":False,"result":json.dumps(d)}))' "$STUBS/offschem.payload" "$VALID_EST"

mkstub() { # <name>  body lines on stdin — sentinel + body -> executable stub
  local name="$1"
  { printf '#!/usr/bin/env bash\ntouch "%s"\n' "$STUBS/$name.called"; cat; } > "$STUBS/$name"
  chmod +x "$STUBS/$name"
}
mkstub ok       < <(printf 'cat "%s"\n' "$STUBS/ok.payload")
mkstub rc1      <<< 'exit 1'
mkstub empty    <<< 'exit 0'
mkstub badenv   <<< 'printf "not json at all"'
mkstub timeout  <<< 'sleep 30'
mkstub timeout_with_answer < <(printf 'cat "%s"\nsleep 30\n' "$STUBS/ok.payload")
mkstub offschem < <(printf 'cat "%s"\n' "$STUBS/offschem.payload")

run_judge() { # <case-name> <stub-path|-> [extra env KEY=VAL ...] [--class <c>]
  local case_name="$1" stub="$2"; shift 2
  local class="Heavy" kv
  local -a envs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      KEY=*) envs+=("${1#KEY=}"); shift ;;
      --class) class="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local cache="$TMP/cache-$case_name"
  rm -rf "$cache"; mkdir -p "$cache"
  if [[ "$stub" == "-" ]]; then
    env "${envs[@]+"${envs[@]}"}" LEADV2_JUDGE_JOURNAL_BIN="$TMP/journal-stub.sh" \
      LEADV2_JUDGE_CACHE_DIR="$cache" PROJECT_ROOT="$TMP" \
      bash "$JUDGE_BIN" --mission-file "$MISSION" --task-id "t-$case_name" --class "$class" \
      > "$TMP/out-$case_name.json" 2>"$TMP/err-$case_name"
  else
    env "${envs[@]+"${envs[@]}"}" LEADV2_JUDGE_CLAUDE_BIN="$stub" \
      LEADV2_JUDGE_JOURNAL_BIN="$TMP/journal-stub.sh" \
      LEADV2_JUDGE_CACHE_DIR="$cache" PROJECT_ROOT="$TMP" \
      bash "$JUDGE_BIN" --mission-file "$MISSION" --task-id "t-$case_name" --class "$class" \
      > "$TMP/out-$case_name.json" 2>"$TMP/err-$case_name"
  fi
  tail -1 "$TMP/journal.log"
}

last_line_has() { grep -q -- "$1" <<<"$(tail -1 "$JOURNAL_LOG")"; }

# ── 1. healthy invoke: judge_path=judge, basis=judge, stub called once ──────
: > "$JOURNAL_LOG"
line="$(run_judge ok "$STUBS/ok")"
last_line_has 'judge_path=judge$' && ! last_line_has 'judge_fail_reason=' \
  && pass "judge success -> judge_path=judge (no fail reason)" \
  || fail "judge success path token" "$line"
grep -q '"estimate_source": "judge"' "$TMP/out-ok.json" && grep -q '"complexity_basis": "judge"' "$TMP/out-ok.json" \
  && pass "judge success -> estimate_source/complexity_basis=judge on stdout" \
  || fail "judge success stdout" "$(cat "$TMP/out-ok.json")"
[[ -f "$STUBS/ok.called" ]] && pass "stub claude invoked" || fail "stub claude NOT invoked"

# ── 2. cache hit: judge_path=cache_hit, model NOT re-called ─────────────────
# (deliberately NOT via run_judge: that helper makes a fresh cache dir; the
# whole point here is case 1's cache entry, same mission, same cache-ok dir)
: > "$JOURNAL_LOG"; rm -f "$STUBS/rc1.called"
env LEADV2_JUDGE_CLAUDE_BIN="$STUBS/rc1" LEADV2_JUDGE_JOURNAL_BIN="$TMP/journal-stub.sh" \
  LEADV2_JUDGE_CACHE_DIR="$TMP/cache-ok" PROJECT_ROOT="$TMP" \
  bash "$JUDGE_BIN" --mission-file "$MISSION" --task-id t-okcached --class Heavy \
  > "$TMP/out-okcached.json" 2>/dev/null
last_line_has 'judge_path=cache_hit$' && last_line_has 'estimate_source=judge' \
  && pass "cache hit -> judge_path=cache_hit with judge estimate" \
  || fail "cache hit path token" "$(tail -1 "$JOURNAL_LOG")"
[[ ! -f "$STUBS/rc1.called" ]] && pass "cache hit never calls the model" \
  || fail "cache hit called the model"

# ── 3. the four invoke-failure reasons (Part 0 E4 is `timeout`) ─────────────
line="$(run_judge timeout "$STUBS/timeout" KEY=LEADV2_JUDGE_TIMEOUT_SEC=1)"
last_line_has 'judge_path=judge_fail ' && last_line_has 'judge_fail_reason=timeout' \
  && pass "timeout -> judge_fail_reason=timeout" || fail "timeout reason" "$line"

# ── 3b. SHARED-TREE-PERMISSION-09: a non-empty answer must survive a ────────
# timeout-kill (real bug found 2026-09-07: median 46.31s against a 45s
# budget, 2 of 3 "timeouts" had already produced a complete answer that got
# discarded). timeout_with_answer prints the full envelope THEN sleeps 30s,
# reproducing the exact production race -- the process is killed only after
# its answer is already flushed to the pipe.
line="$(run_judge timeout_with_answer "$STUBS/timeout_with_answer" KEY=LEADV2_JUDGE_TIMEOUT_SEC=1)"
last_line_has 'judge_path=judge$' && ! last_line_has 'judge_fail_reason=' \
  && pass "timeout-with-answer: non-empty body survives the kill -> judge_path=judge (fix)" \
  || fail "timeout-with-answer fix" "$line"
grep -q '"estimate_source": "judge"' "$TMP/out-timeout_with_answer.json" \
  && pass "timeout-with-answer: harvested answer still parses to estimate_source=judge" \
  || fail "timeout-with-answer parse" "$(cat "$TMP/out-timeout_with_answer.json" 2>/dev/null)"

# negative control (execution-proven, real behavior delta): a mutant that
# restores the OLD unconditional discard-on-timeout must lose the exact same
# answer this base binary just kept -- proving the fix, not the stub, is what
# changed the outcome. Mutation inside the function body (F1-HARD-WORK
# discipline): a top-level line-number insert would paint the suite red for
# an unrelated reason and read as a false pass (2026-08-25 incident).
# Must live NEXT TO the real script, not in $TMP: PROMPT_TMPL is resolved
# from the running script's own SCRIPT_DIR, so a copy anywhere else fails
# with template_missing before it ever reaches the mutated branch (caught by
# this suite's own first run).
MUTANT_TO="${SCRIPTS_ROOT}/.judge-mutant-timeout-old.sh"
python3 - "$JUDGE_BIN" "$MUTANT_TO" <<'PY'
import sys
p, dst = sys.argv[1], sys.argv[2]
s = open(p).read()
anchor = '''  if [[ ${rc} -eq 124 || ${rc} -eq 137 ]]; then
    if [[ -z "${raw}" ]]; then
      _fail "timeout"
      return 1
    fi
  elif [[ ${rc} -ne 0 ]]; then
    _fail "nonzero_rc"
    return 1
  fi'''
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- timeout/rc branch moved or was reworded; re-anchor this control, do not silence it' % n)
old_behavior = '''  if [[ ${rc} -eq 124 || ${rc} -eq 137 ]]; then
    _fail "MUTANT_DISCARD_ON_TIMEOUT"
    return 1
  fi
  [[ ${rc} -eq 0 ]] || { _fail "nonzero_rc"; return 1; }'''
open(dst, 'w').write(s.replace(anchor, old_behavior))
PY
chmod +x "$MUTANT_TO"
if grep -q 'MUTANT_DISCARD_ON_TIMEOUT' "$MUTANT_TO"; then
  : > "$JOURNAL_LOG"
  rm -f "$STUBS/timeout_with_answer.called"
  env LEADV2_JUDGE_TIMEOUT_SEC=1 LEADV2_JUDGE_CLAUDE_BIN="$STUBS/timeout_with_answer" \
    LEADV2_JUDGE_JOURNAL_BIN="$TMP/journal-stub.sh" LEADV2_JUDGE_CACHE_DIR="$TMP/cache-mutant-to" \
    PROJECT_ROOT="$TMP" \
    bash "$MUTANT_TO" --mission-file "$MISSION" --task-id t-mutant-to --class Heavy \
    > "$TMP/out-mutant-to.json" 2>/dev/null
  if last_line_has 'judge_fail_reason=MUTANT_DISCARD_ON_TIMEOUT'; then
    pass "NC: pre-fix behavior (restored in a mutant) discards the SAME non-empty answer the base binary just kept"
  else
    fail "NC pre-fix discard" "mutant token absent: $(tail -1 "$JOURNAL_LOG")"
  fi
else
  fail "NC pre-fix discard setup" "mutation anchor not found in ${JUDGE_BIN}"
fi
rm -f "$MUTANT_TO"
line="$(run_judge rc1 "$STUBS/rc1")"
last_line_has 'judge_fail_reason=nonzero_rc' && pass "rc!=0 -> nonzero_rc" \
  || fail "nonzero_rc reason" "$line"
line="$(run_judge empty "$STUBS/empty")"
last_line_has 'judge_fail_reason=empty_output' && pass "empty -> empty_output" \
  || fail "empty_output reason" "$line"
line="$(run_judge badenv "$STUBS/badenv")"
last_line_has 'judge_fail_reason=envelope_parse' && pass "bad envelope -> envelope_parse" \
  || fail "envelope_parse reason" "$line"
line="$(run_judge offschem "$STUBS/offschem")"
last_line_has 'judge_path=judge_fail ' && last_line_has 'judge_fail_reason=schema_invalid' \
  && pass "off-schema answer -> schema_invalid (distinguish from envelope_parse)" \
  || fail "schema_invalid reason" "$line"
# the model ANSWERED (stub ran) but the answer was rejected — fallback out.
grep -q '"estimate_source": "fallback"' "$TMP/out-offschem.json" \
  && pass "schema-invalid still falls back (R2: never block)" \
  || fail "schema_invalid did not fall back" "$(cat "$TMP/out-offschem.json")"

# ── 4. the skip paths never touch the model, and say so ─────────────────────
# (reset the sentinel: case 3's rc1 run created it — "was the model called"
# must mean "called BY THIS case", not "called at least once ever")
rm -f "$STUBS/rc1.called"
line="$(run_judge disable "$STUBS/rc1" KEY=LEADV2_JUDGE_DISABLE=1)"
last_line_has 'judge_path=disable$' && pass "disable -> judge_path=disable" \
  || fail "disable path token" "$line"
[[ ! -f "$STUBS/rc1.called" ]] && pass "disable never calls the model" \
  || fail "disable called the model"
rm -f "$STUBS/rc1.called"
line="$(run_judge light "$STUBS/rc1" --class Light)"
last_line_has 'judge_path=light_skip$' && pass "Light -> judge_path=light_skip (R2 #3 intact)" \
  || fail "light_skip path token" "$line"
[[ ! -f "$STUBS/rc1.called" ]] && pass "Light skip never calls the model" \
  || fail "Light skip called the model"

# ── 5. fd-3 plumbing: a reason lost to the $( ) subshell reads unknown ──────
# A judge binary whose _fail writes only the in-subshell global (the bug the
# first smoke run caught) must fail here: reason would be empty -> unknown.
if grep -q 'printf .%s. "\$1" >&3' "$JUDGE_BIN"; then
  pass "fd-3 reason plumbing present in binary"
else
  fail "fd-3 reason plumbing missing" "grep >&3 in $JUDGE_BIN"
fi

# ── 6. negative control (execution-proven): mutate the judge_fail branch in ──
# a throwaway copy; the mutant's own token must appear in its journal line,
# proving the branch under test is the one that executed (F1-HARD-WORK
# discipline: token from the mutation itself, not a red suite).
MUTANT="$TMP/judge-mutant.sh"
sed 's/judge_fail_reason=\${JUDGE_FAIL_REASON:-unknown}/judge_fail_reason=MUTANT_TOKEN_X7F/' \
  "${JUDGE_BIN}" > "${MUTANT}"
chmod +x "$MUTANT"
if grep -q 'MUTANT_TOKEN_X7F' "$MUTANT"; then
  : > "$JOURNAL_LOG"
  env LEADV2_JUDGE_CLAUDE_BIN="$STUBS/rc1" LEADV2_JUDGE_JOURNAL_BIN="$TMP/journal-stub.sh" \
    LEADV2_JUDGE_CACHE_DIR="$TMP/cache-mutant" PROJECT_ROOT="$TMP" \
    bash "$MUTANT" --mission-file "$MISSION" --task-id t-mutant --class Heavy >/dev/null 2>&1
  if last_line_has 'judge_fail_reason=MUTANT_TOKEN_X7F'; then
    pass "negative control: mutated judge_fail branch executed (its own token printed)"
  else
    fail "negative control" "mutant token absent: $(tail -1 "$JOURNAL_LOG")"
  fi
else
  fail "negative control setup" "mutation anchor not found in ${JUDGE_BIN}"
fi

printf 'judge-complexity-path: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
