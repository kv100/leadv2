#!/usr/bin/env bash
# run-all-triggers: leadv2-task-judge
#
# tests/test-judge-parses-its-own-answer.sh —
# JUDGE-ENVELOPE-PARSE-FAILS-A-QUARTER-OF-THE-TIME-01
#
# Drives the REAL shipped leadv2-task-judge.sh (or, for negative controls, a
# scratch copy mutated only inside the EXTRACT-BEGIN/EXTRACT-END markers of
# _invoke_judge's envelope-parse block) against a stub `claude` binary, no
# real model call. Covers:
#   - the specific live failure mode this fix targets: a valid JSON object
#     followed by prose that itself contains a brace (the old greedy
#     `re.search(r'\{.*\}')` matched past the real object and json.loads
#     raised "Extra data" -> misreported envelope_parse on a correct answer)
#   - fenced JSON with leading prose still parses (already worked, must keep
#     working)
#   - a reply with literally no JSON anywhere still fails envelope_parse
#     (must stay a fallback, never manufactured)
#   - a truncated / unbalanced reply still fails envelope_parse
#   - two negative controls proving the suite actually exercises the fix,
#     not a log string: reverting to the old greedy regex must break the
#     brace-in-trailing-prose case; making the extractor manufacture a
#     default estimate when nothing is found must turn a should-fail case
#     into a false "judge" success.
#
# Run: bash plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUDGE_SH_REAL="${SCRIPT_DIR}/../leadv2-task-judge.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

_kv() { python3 -c "import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2],''))" "$1" "$2" 2>/dev/null; }

_fixture_root() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/judge-parse-test.XXXXXX")"
  mkdir -p "${root}/.claude/leadv2-overrides"
  printf 'leadv2_dir: docs/leadv2\n' > "${root}/.claude/leadv2-overrides/state-paths.yaml"
  printf '%s' "${root}"
}

_write_mission() {
  local root="$1" name="$2" content="$3"
  local f="${root}/${name}.md"
  printf '%s' "${content}" > "${f}"
  printf '%s' "${f}"
}

# Stub `claude -p --output-format json`: ignores its args, prints one fixed
# envelope built from the caller-supplied `result` string (already JSON-
# escaped by the caller via python -c so embedded quotes/newlines are safe).
_stub_claude_with_result() {
  local dir="$1" result_json_escaped="$2"
  local bin="${dir}/claude"
  cat > "${bin}" <<STUB
#!/usr/bin/env bash
cat <<'ENVELOPE'
{"is_error":false,"result":${result_json_escaped}}
ENVELOPE
STUB
  chmod +x "${bin}"
  printf '%s' "${bin}"
}

# Builds a JSON-escaped string literal (with surrounding quotes) from raw text
# via python, so the stub's heredoc embeds it safely regardless of quotes/
# backslashes/newlines in the fixture text.
_json_str() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }

_run_judge() {
  local judge_bin="$1" claude_bin="$2" cache_dir="$3" mission="$4"
  LEADV2_JUDGE_CLAUDE_BIN="${claude_bin}" LEADV2_JUDGE_CACHE_DIR="${cache_dir}" \
    bash "${judge_bin}" --mission-file "${mission}" 2>/dev/null
}

# ── fixture texts (as they would appear in claude -p's .result) ─────────────

# The exact shape that broke the old greedy regex: a fenced JSON object
# followed by a sentence that itself contains a brace pair. Live-reproduced
# during this task's investigation (redacted probe, see developer.full.md).
FENCED_TRAILING_BRACE='Sure thing! Here is the estimate:

```json
{"complexity":"simple","subsystems_touched":1,"needs_live_verification":false,"risk_class":"none","duration_class":"short","work_kind":"build"}
```

Let me know if you would like adjustments to the {} shape.'

# Leading prose before an inline (unfenced) object — already worked before
# this fix, must keep working.
LEADING_PROSE='Estimation complete: {"complexity":"standard","subsystems_touched":2,"needs_live_verification":true,"risk_class":"data","duration_class":"medium","work_kind":"build"}'

# No JSON anywhere at all — the live-captured contamination shape (a
# conversational reply with zero braces). Must stay envelope_parse -> fallback.
NO_JSON_AT_ALL='Estimation complete. Ready to dispatch.

status: active task in phase build'

# Truncated mid-object — unbalanced braces. Must stay envelope_parse -> fallback.
TRUNCATED='{"complexity":"standard","subsyst'

# ── T1: the regression case — brace-in-trailing-prose must now parse ───────
test_t1_fenced_trailing_brace_parses() {
  local root; root="$(_fixture_root)"
  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${FENCED_TRAILING_BRACE}")")"
  local m; m="$(_write_mission "${root}" "m" "Fix the retry loop.")"

  local out; out="$(_run_judge "${JUDGE_SH_REAL}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  local cx; cx="$(_kv "${out}" complexity)"
  if [[ "${src}" == "judge" && "${cx}" == "simple" ]]; then
    pass "T1: fenced JSON + brace-bearing trailing prose -> parsed as judge (regression case fixed)"
  else
    fail "T1: expected estimate_source=judge complexity=simple, got estimate_source=${src} complexity=${cx}"
  fi
  rm -rf "${root}"
}

# ── T2: leading prose + inline JSON still parses (no regression) ───────────
test_t2_leading_prose_still_parses() {
  local root; root="$(_fixture_root)"
  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${LEADING_PROSE}")")"
  local m; m="$(_write_mission "${root}" "m" "Add a migration.")"

  local out; out="$(_run_judge "${JUDGE_SH_REAL}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  [[ "${src}" == "judge" ]] && pass "T2: leading prose + inline JSON -> parsed as judge" \
    || fail "T2: expected estimate_source=judge, got ${src}"
  rm -rf "${root}"
}

# ── T3: no JSON anywhere -> envelope_parse -> fallback (never manufactured) ─
test_t3_no_json_stays_fallback() {
  local root; root="$(_fixture_root)"
  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${NO_JSON_AT_ALL}")")"
  local m; m="$(_write_mission "${root}" "m" "Any task.")"

  local out; out="$(_run_judge "${JUDGE_SH_REAL}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  [[ "${src}" == "fallback" ]] && pass "T3: reply with no JSON anywhere -> estimate_source=fallback" \
    || fail "T3: expected estimate_source=fallback, got ${src}"
  rm -rf "${root}"
}

# ── T4: truncated/unbalanced JSON -> envelope_parse -> fallback ────────────
test_t4_truncated_stays_fallback() {
  local root; root="$(_fixture_root)"
  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${TRUNCATED}")")"
  local m; m="$(_write_mission "${root}" "m" "Any task.")"

  local out; out="$(_run_judge "${JUDGE_SH_REAL}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  [[ "${src}" == "fallback" ]] && pass "T4: truncated mid-object reply -> estimate_source=fallback" \
    || fail "T4: expected estimate_source=fallback, got ${src}"
  rm -rf "${root}"
}

# ── mutation helper: copy the real script, replace ONLY the text strictly
# between the EXTRACT-BEGIN/EXTRACT-END markers inside _invoke_judge with the
# given replacement. Never touches anything outside the markers -- a
# top-level insert would make every case in this file (and the shipped
# suite) red for the wrong reason and read as a pass.
_mutate_extractor() {
  local out_path="$1" replacement_file="$2"
  python3 -c "
import sys
src = open(sys.argv[1], encoding='utf-8').read()
begin_marker = '# EXTRACT-BEGIN'
end_marker = '# EXTRACT-END'
b = src.index(begin_marker)
e = src.index(end_marker, b) + len(end_marker)
repl = open(sys.argv[3], encoding='utf-8').read()
out = src[:b] + repl + src[e:]
open(sys.argv[2], 'w', encoding='utf-8').write(out)
" "${JUDGE_SH_REAL}" "${out_path}" "${replacement_file}"
  chmod +x "${out_path}"
  # SCRIPT_DIR resolves PROMPT_TMPL next to the script's own path -- the
  # mutant must find the real prompt template beside it, or it fails at
  # template_missing before ever reaching the mutated extractor.
  cp "${SCRIPT_DIR}/../leadv2-task-judge-prompt.tmpl" "$(dirname "${out_path}")/leadv2-task-judge-prompt.tmpl"
}

# ── NC1: revert to the old greedy regex -> the T1 regression case must
# break (prove the suite actually exercises the fix, not a log string) ──────
test_nc1_old_greedy_regex_breaks_t1() {
  local root; root="$(_fixture_root)"
  local repl="${root}/nc1-replacement.py"
  cat > "${repl}" <<'PYEOF'
# EXTRACT-BEGIN
import re
m = re.search(r'\{.*\}', result_text, re.DOTALL)
if not m:
    sys.exit(1)
try:
    est = json.loads(m.group(0))
except Exception:
    sys.exit(1)
if est is None or not isinstance(est, dict):
    sys.exit(1)
# EXTRACT-END
PYEOF
  local mutant="${root}/judge-mutant-nc1.sh"
  _mutate_extractor "${mutant}" "${repl}"
  bash -n "${mutant}" >/dev/null 2>&1 || { fail "NC1: mutant script has a syntax error, cannot exercise the control"; rm -rf "${root}"; return; }

  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${FENCED_TRAILING_BRACE}")")"
  local m; m="$(_write_mission "${root}" "m" "Fix the retry loop.")"
  local out; out="$(_run_judge "${mutant}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  if [[ "${src}" == "fallback" ]]; then
    pass "NC1: reverting to the old greedy regex breaks T1 as expected (estimate_source=fallback) -- suite catches this regression"
  else
    fail "NC1: expected the greedy-regex mutant to regress T1 to fallback, but got estimate_source=${src} -- the suite would NOT catch a revert of this fix"
  fi
  rm -rf "${root}"
}

# ── NC2: manufacture a default estimate when nothing is found -> a reply
# with NO usable JSON must NOT become a false "judge" success ───────────────
test_nc2_manufactured_estimate_on_nothing_found() {
  local root; root="$(_fixture_root)"
  local repl="${root}/nc2-replacement.py"
  cat > "${repl}" <<'PYEOF'
# EXTRACT-BEGIN
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
    # DELIBERATE BUG (negative control NC2): manufacture a fully-fielded
    # estimate out of nothing instead of failing closed.
    est = {
        'complexity': 'standard',
        'subsystems_touched': 1,
        'needs_live_verification': False,
        'risk_class': 'none',
        'duration_class': 'medium',
        'work_kind': 'build',
    }
# EXTRACT-END
PYEOF
  local mutant="${root}/judge-mutant-nc2.sh"
  _mutate_extractor "${mutant}" "${repl}"
  bash -n "${mutant}" >/dev/null 2>&1 || { fail "NC2: mutant script has a syntax error, cannot exercise the control"; rm -rf "${root}"; return; }

  local claude_bin; claude_bin="$(_stub_claude_with_result "${root}" "$(_json_str "${NO_JSON_AT_ALL}")")"
  local m; m="$(_write_mission "${root}" "m" "Any task.")"
  local out; out="$(_run_judge "${mutant}" "${claude_bin}" "${root}/cache" "${m}")"
  local src; src="$(_kv "${out}" estimate_source)"
  if [[ "${src}" == "judge" ]]; then
    pass "NC2: manufacturing-on-nothing-found mutant turns a no-JSON reply into a false estimate_source=judge -- proves T3 would catch this exact defect"
  else
    fail "NC2: expected the manufacturing mutant to falsely report estimate_source=judge (that IS the bug this control demonstrates), got ${src} -- the mutation did not reach the code path this control targets"
  fi
  rm -rf "${root}"
}

# ── syntax guard on the real shipped script ────────────────────────────────
test_syntax_check() {
  if bash -n "${JUDGE_SH_REAL}" 2>/dev/null; then
    pass "bash -n syntax OK on leadv2-task-judge.sh"
  else
    fail "bash -n syntax check failed"
  fi
}

test_t1_fenced_trailing_brace_parses
test_t2_leading_prose_still_parses
test_t3_no_json_stays_fallback
test_t4_truncated_stays_fallback
test_nc1_old_greedy_regex_breaks_t1
test_nc2_manufactured_estimate_on_nothing_found
test_syntax_check

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${FAIL}" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
