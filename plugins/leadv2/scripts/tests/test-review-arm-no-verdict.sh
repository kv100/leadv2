#!/usr/bin/env bash
# tests/test-review-arm-no-verdict.sh — ARM-NO-VERDICT-01 (dispatch-4fb7381a): a
# reviewer arm that runs to completion but produces nothing usable (no REVIEW_VERDICT:
# marker, truncated/empty output, or a provider error) must fall through to the NEXT
# arm in the resolved pool -- reusing the existing tried[]/next_ok_arm_after
# bookkeeping -- exactly like a refused_* arm already does. Only when the whole pool
# is exhausted does the lane die, with reason=no_verdict_marker and the FULL tried=
# list attached.
#
# Regression coverage for the 2026-08-07 incident: lane 4fb7381a resolved a 5-arm
# review pool (`review_pool_resolve rc=0 reviewer=kimi pool_n=5`), kimi's own transcript
# ended in "[Tool use interrupted]" with no verdict marker, and the lane was killed on
# THAT FIRST arm -- `review_gate status=blocked reason=no_verdict_marker` /
# `dispatch_terminal terminal=dead cause=no_verdict_marker` -- without ever trying the
# other 4 resolved arms.
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end, same harness pattern as
# test-review-silence-gate.sh (stub resolver + stub reviewer launchers, never a
# reimplementation of the gate's own logic).
#
# Run: bash scripts/tests/test-review-arm-no-verdict.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

SUITE_TMP="$(lv2_mktemp_dir "review-arm-no-verdict-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

make_fixture_root() {
  local name="$1" content="$2"
  local repo="${SUITE_TMP}/${name}/root"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "test"
  printf 'baseline\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m init
  lv2_assert_scratch_repo "$repo"
  printf '%s\n' "$content" >> "$repo/file.txt"
  printf '%s' "$repo"
}

make_resolver_stub() {
  local name="$1" reviewer="$2" pool="$3"
  local stub="${SUITE_TMP}/${name}/resolver.py"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<PY
print("reviewer=${reviewer}")
print("pool=${pool}")
print("refusal=")
PY
  printf '%s' "$stub"
}

# make_glm_stub <name> <mode> -> prints the stub path on stdout.
#   pass       - clean REVIEW_VERDICT: PASS
#   no_verdict - >200 bytes / >=3 lines of real prose, NO REVIEW_VERDICT: marker (rc 0)
#   empty      - writes nothing at all (rc 0)
make_glm_stub() {
  local name="$1" mode="$2"
  local stub="${SUITE_TMP}/${name}/glm-stub.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
outfile=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  if [[ "${args[$i]}" == "--out" ]]; then
    outfile="${args[$((i+1))]}"
  fi
  i=$((i+1))
done
SH
  case "$mode" in
    pass)
      cat >> "$stub" <<'SH'
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff, no issues found by the stub reviewer arm.\n' > "$outfile"
exit 0
SH
      ;;
    no_verdict)
      cat >> "$stub" <<'SH'
printf 'Reviewing the diff now, this looks like a reasonable change overall and the structure is sound.\nStill going through the files one by one to check for edge cases before writing up findings.\n[Tool use interrupted]\n' > "$outfile"
exit 0
SH
      ;;
    empty)
      cat >> "$stub" <<'SH'
: > "$outfile"
exit 0
SH
      ;;
  esac
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_arch_stub <name> <mode> -> prints the stub path on stdout (drives the sonnet/
# opus branch of run_reviewer_arm, whose launcher writes to stdout, redirected by the
# caller into review_out).
#   pass       - clean REVIEW_VERDICT: PASS
#   no_verdict - >200 bytes / >=3 lines of real prose, NO REVIEW_VERDICT: marker (rc 0)
#   empty      - writes nothing at all (rc 0)
make_arch_stub() {
  local name="$1" mode="$2"
  local stub="${SUITE_TMP}/${name}/arch-stub.sh"
  mkdir -p "$(dirname "$stub")"
  case "$mode" in
    pass)
      printf '#!/usr/bin/env bash\nprintf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\nAll good, reviewed thoroughly, nothing to flag in this diff.\\n"\nexit 0\n' > "$stub"
      ;;
    no_verdict)
      printf '#!/usr/bin/env bash\nprintf "Reviewing the diff now, this looks like a reasonable change overall and the structure is sound.\\nStill going through the files one by one to check for edge cases before writing up findings.\\n[Tool use interrupted]\\n"\nexit 0\n' > "$stub"
      ;;
    empty)
      printf '#!/usr/bin/env bash\nexit 0\n' > "$stub"
      ;;
  esac
  chmod +x "$stub"
  printf '%s' "$stub"
}

run_close() { # <root> <sig8> <author> <resolver>
  local root="$1" sig8="$2" author="$3" resolver="$4"
  local cache="${SUITE_TMP}/${sig8}/cache"
  mkdir -p "$cache"
  LEADV2_GLM_POLICY_RESOLVER="$resolver" \
  LEADV2_DISPATCH_CACHE_DIR="$cache" \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_E2E_OWNERSHIP=0 \
    bash "$PRODUCT_CLOSE_SH" "$root" "$sig8" "$author" "" 0 1 "" 2>&1
}

# ── Test 1 (RED against pre-fix code): first arm no-verdict -> second arm invoked and
#    ITS verdict is what gets recorded. reviewer=sonnet (arch stub, no_verdict) falls
#    through to glm (glm stub, pass).
root1="$(make_fixture_root t1 "t1-unique-diff-content")"
resolver1="$(make_resolver_stub t1 sonnet "sonnet:ok:,glm:ok:")"
arch1="$(make_arch_stub t1 no_verdict)"
glm1="$(make_glm_stub t1 pass)"
out1="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch1" LEADV2_DISPATCH_GLM_BIN="$glm1" run_close "$root1" t1sig001 codex "$resolver1")"; rc1=$?
gate1="${root1}/docs/handoff/dispatch-t1sig001/review-gate.md"
if [[ $rc1 -eq 0 ]]; then pass "Test 1 (fallthrough_to_second_arm): exit 0"; else fail "Test 1: expected exit 0, got ${rc1} -- ${out1}"; fi
if [[ -f "$gate1" ]] && grep -q '^status: pass$' "$gate1"; then
  pass "Test 1: review-gate.md status=pass -- second arm's PASS verdict was recorded"
else
  fail "Test 1: review-gate.md wrong -- $(cat "$gate1" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=arm_no_verdict arm=sonnet reason=no_verdict_marker tried=sonnet remaining=1' <<<"$out1"; then
  pass "Test 1: journal carries arm_no_verdict arm=sonnet reason=no_verdict_marker tried=sonnet remaining=1"
else
  fail "Test 1: no arm_no_verdict fallthrough line for sonnet -- ${out1}"
fi
if grep -q 'status=ran author=codex reviewer=glm verdict=PASS' <<<"$out1"; then
  pass "Test 1: journal confirms the RECORDED verdict came from glm (the second arm), not sonnet"
else
  fail "Test 1: no ran/verdict=PASS line attributing the verdict to glm -- ${out1}"
fi

# ── Test 2: truncated/empty reviewer output is treated the SAME as no-verdict (falls
#    through), not treated as a pass. reviewer=sonnet (arch stub, empty) falls through
#    to glm (glm stub, pass).
root2="$(make_fixture_root t2 "t2-unique-diff-content")"
resolver2="$(make_resolver_stub t2 sonnet "sonnet:ok:,glm:ok:")"
arch2="$(make_arch_stub t2 empty)"
glm2="$(make_glm_stub t2 pass)"
out2="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch2" LEADV2_DISPATCH_GLM_BIN="$glm2" run_close "$root2" t2sig002 codex "$resolver2")"; rc2=$?
gate2="${root2}/docs/handoff/dispatch-t2sig002/review-gate.md"
if [[ $rc2 -eq 0 ]]; then pass "Test 2 (empty_output_falls_through): exit 0"; else fail "Test 2: expected exit 0, got ${rc2} -- ${out2}"; fi
if [[ -f "$gate2" ]] && grep -q '^status: pass$' "$gate2"; then
  pass "Test 2: review-gate.md status=pass -- empty first arm was NOT mistaken for a pass, glm's PASS was recorded instead"
else
  fail "Test 2: review-gate.md wrong -- $(cat "$gate2" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=arm_no_verdict arm=sonnet reason=empty_response tried=sonnet remaining=1' <<<"$out2"; then
  pass "Test 2: journal carries arm_no_verdict arm=sonnet reason=empty_response tried=sonnet remaining=1"
else
  fail "Test 2: no arm_no_verdict fallthrough line for empty sonnet output -- ${out2}"
fi

# ── Test 3: every arm in the pool returns no verdict -> the lane still dies with
#    no_verdict_marker AND the journal carries the FULL tried= list (both arms).
root3="$(make_fixture_root t3 "t3-unique-diff-content")"
resolver3="$(make_resolver_stub t3 sonnet "sonnet:ok:,glm:ok:")"
arch3="$(make_arch_stub t3 no_verdict)"
glm3="$(make_glm_stub t3 no_verdict)"
out3="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch3" LEADV2_DISPATCH_GLM_BIN="$glm3" run_close "$root3" t3sig003 codex "$resolver3")"; rc3=$?
gate3="${root3}/docs/handoff/dispatch-t3sig003/review-gate.md"
if [[ $rc3 -eq 6 ]]; then pass "Test 3 (pool_exhausted_dies): exit 6"; else fail "Test 3: expected exit 6, got ${rc3} -- ${out3}"; fi
if [[ -f "$gate3" ]] && grep -q '^status: blocked$' "$gate3" && grep -q '^reason: no_verdict_marker$' "$gate3"; then
  pass "Test 3: review-gate.md status=blocked reason=no_verdict_marker after both arms exhausted"
else
  fail "Test 3: review-gate.md wrong -- $(cat "$gate3" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=blocked reason=no_verdict_marker tried=sonnet,glm' <<<"$out3"; then
  pass "Test 3: terminal journal line carries FULL tried=sonnet,glm list"
else
  fail "Test 3: terminal journal line missing full tried= list -- ${out3}"
fi
if grep -q 'status=arm_no_verdict arm=sonnet reason=no_verdict_marker tried=sonnet remaining=1' <<<"$out3" \
  && grep -q 'status=arm_no_verdict arm=glm reason=no_verdict_marker tried=sonnet,glm remaining=0' <<<"$out3"; then
  pass "Test 3: both per-arm arm_no_verdict lines present with correct tried=/remaining="
else
  fail "Test 3: missing one or both per-arm arm_no_verdict lines -- ${out3}"
fi

# ── Test 4: a normal PASS on the first arm still invokes exactly ONE arm (no wasted
#    spend / no regression). glm's stub is wired to a mode that would fail loudly (via
#    review-gate.md contents) if ever invoked -- but the real proof is the absence of
#    review-glm.md/review-glm.err, since sonnet passing must never call run_reviewer_arm
#    a second time.
root4="$(make_fixture_root t4 "t4-unique-diff-content")"
resolver4="$(make_resolver_stub t4 sonnet "sonnet:ok:,glm:ok:")"
arch4="$(make_arch_stub t4 pass)"
glm4="$(make_glm_stub t4 no_verdict)"
out4="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch4" LEADV2_DISPATCH_GLM_BIN="$glm4" run_close "$root4" t4sig004 codex "$resolver4")"; rc4=$?
gate4="${root4}/docs/handoff/dispatch-t4sig004/review-gate.md"
glm4_out="${root4}/docs/handoff/dispatch-t4sig004/review-glm.md"
if [[ $rc4 -eq 0 ]]; then pass "Test 4 (first_arm_pass_no_waste): exit 0"; else fail "Test 4: expected exit 0, got ${rc4} -- ${out4}"; fi
if [[ -f "$gate4" ]] && grep -q '^status: pass$' "$gate4"; then
  pass "Test 4: review-gate.md status=pass on the first arm"
else
  fail "Test 4: review-gate.md wrong -- $(cat "$gate4" 2>/dev/null || echo MISSING)"
fi
if [[ ! -f "$glm4_out" ]]; then
  pass "Test 4: glm (second arm) was never invoked -- review-glm.md does not exist"
else
  fail "Test 4: glm was invoked despite sonnet passing -- ${glm4_out} exists ($(cat "$glm4_out"))"
fi
if ! grep -q 'arm_no_verdict\|arm_refused' <<<"$out4"; then
  pass "Test 4: no arm_no_verdict/arm_refused journal lines -- exactly one arm ran"
else
  fail "Test 4: unexpected fallthrough journal line on a first-arm pass -- ${out4}"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
