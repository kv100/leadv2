#!/usr/bin/env bash
# tests/test-review-silence-gate.sh — N-5: the review channel must fail loudly, never
# silently. Regression coverage for the four defects fixed in
# leadv2-dispatch-product-close.sh (D1 refusal-exits-0, D3 no-artifact-guarantee, D4
# one-reason-for-four-causes, D5 kimi-only refusal fallback).
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end (never a reimplementation
# of its logic). Each scenario gets its own throwaway git repo (fixture root) so diffs,
# review-ledger dedup, and close-owner pidfiles never collide across scenarios. The
# resolver is stubbed via LEADV2_GLM_POLICY_RESOLVER (a tiny python3 script -- the real
# resolver is invoked with `python3 "$resolver" ...`, so the stub must be valid python,
# not bash) and reviewer arms are stubbed via the existing injection points
# (LEADV2_DISPATCH_GLM_BIN, LEADV2_DISPATCH_ARCHITECT_BIN).
#
# Run directly, assert $? inline -- no wrapper that swallows the exit code.
# Run: bash scripts/tests/test-review-silence-gate.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$PRODUCT_CLOSE_SH"; then
  pass "bash -n clean (leadv2-dispatch-product-close.sh)"
else
  fail "bash -n failed on leadv2-dispatch-product-close.sh"
fi
if bash -n "${SCRIPTS_ROOT}/lib/leadv2-refusal-classify.sh"; then
  pass "bash -n clean (lib/leadv2-refusal-classify.sh)"
else
  fail "bash -n failed on lib/leadv2-refusal-classify.sh"
fi

SUITE_TMP="$(lv2_mktemp_dir "review-silence-gate-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

# make_fixture_root <name> <unique-content> -> prints the repo path on stdout.
# A fresh scratch git repo with one committed file, then one uncommitted edit --
# gives the close gate a real, non-empty `git diff HEAD` to scope and hash, and the
# unique content keeps every scenario's diff_hash (and therefore its review-ledger
# dedup key) distinct.
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

# make_resolver_stub <name> <reviewer> <pool> -> prints the stub path on stdout.
# Must be valid python3 (invoked as `python3 "$resolver" ...`), never bash.
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

# make_glm_stub <name> <mode> -> prints the stub path on stdout. mode=refuse_peak
# writes the peak_hours refusal marker to stderr and exits 1 (the real glm-coder.sh
# admission-refusal contract); mode=pass writes a clean PASS verdict to --out.
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
  if [[ "$mode" == refuse_peak ]]; then
    cat >> "$stub" <<'SH'
echo "LEADV2_DISPATCH_REFUSED: peak_hours" >&2
exit 1
SH
  elif [[ "$mode" == refuse_quota ]]; then
    cat >> "$stub" <<'SH'
echo "LEADV2_DISPATCH_REFUSED: quota" >&2
exit 1
SH
  else
    cat >> "$stub" <<'SH'
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff, no issues found by the stub reviewer arm.\n' > "$outfile"
exit 0
SH
  fi
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_arch_stub <name> <mode> -> prints the stub path on stdout (drives the sonnet/
# opus branch of run_reviewer_arm, whose launcher writes to stdout, redirected by the
# caller into review_out).
make_arch_stub() {
  local name="$1" mode="$2"
  local stub="${SUITE_TMP}/${name}/arch-stub.sh"
  mkdir -p "$(dirname "$stub")"
  case "$mode" in
    empty)
      printf '#!/usr/bin/env bash\nexit 0\n' > "$stub"
      ;;
    thin)
      printf '#!/usr/bin/env bash\nprintf "connectors: unrelated warning line\\n"\nexit 0\n' > "$stub"
      ;;
    pass)
      printf '#!/usr/bin/env bash\nprintf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\nAll good, reviewed thoroughly, nothing to flag in this diff.\\n"\nexit 0\n' > "$stub"
      ;;
    refuse_peak)
      printf '#!/usr/bin/env bash\necho "LEADV2_DISPATCH_REFUSED: peak_hours" >&2\nexit 1\n' > "$stub"
      ;;
    hang)
      printf '#!/usr/bin/env bash\nsleep 30\nexit 0\n' > "$stub"
      ;;
  esac
  chmod +x "$stub"
  printf '%s' "$stub"
}

run_close() { # <root> <sig8> <author> <resolver> [extra env assignments already exported by caller]
  local root="$1" sig8="$2" author="$3" resolver="$4"
  local cache="${SUITE_TMP}/${sig8}/cache"
  mkdir -p "$cache"
  LEADV2_GLM_POLICY_RESOLVER="$resolver" \
  LEADV2_DISPATCH_CACHE_DIR="$cache" \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_E2E_OWNERSHIP=0 \
    bash "$PRODUCT_CLOSE_SH" "$root" "$sig8" "$author" "" 0 1 "" 2>&1
}

# ── Test 1: empty_output ────────────────────────────────────────────────────────────
root1="$(make_fixture_root t1 "t1-unique-diff-content")"
resolver1="$(make_resolver_stub t1 sonnet "sonnet:ok:")"
arch1="$(make_arch_stub t1 empty)"
out1="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch1" run_close "$root1" t1sig001 codex "$resolver1")"; rc1=$?
gate1="${root1}/docs/handoff/dispatch-t1sig001/review-gate.md"
if [[ $rc1 -eq 6 ]]; then pass "Test 1 (empty_output): exit 6"; else fail "Test 1: expected exit 6, got ${rc1} -- ${out1}"; fi
# ARM-NO-VERDICT-01: a single-arm pool that produces empty output now dies via the
# SAME collapsed exhaustion reason (no_verdict_marker) every "arm ran but produced
# nothing usable" outcome shares once the pool is exhausted -- see the arm_no_verdict
# fallthrough tests in test-review-arm-no-verdict.sh for the per-arm reason
# (empty_response) still being visible on the journal line BEFORE exhaustion.
if [[ -f "$gate1" ]] && grep -q '^status: blocked$' "$gate1" && grep -q '^reason: no_verdict_marker$' "$gate1"; then
  pass "Test 1 (empty_output): review-gate.md status=blocked reason=no_verdict_marker (pool exhausted)"
else
  fail "Test 1: review-gate.md wrong -- $(cat "$gate1" 2>/dev/null || echo MISSING)"
fi

# ── Test 2: thin_output ─────────────────────────────────────────────────────────────
root2="$(make_fixture_root t2 "t2-unique-diff-content")"
resolver2="$(make_resolver_stub t2 sonnet "sonnet:ok:")"
arch2="$(make_arch_stub t2 thin)"
out2="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch2" run_close "$root2" t2sig002 codex "$resolver2")"; rc2=$?
gate2="${root2}/docs/handoff/dispatch-t2sig002/review-gate.md"
if [[ $rc2 -eq 6 ]]; then pass "Test 2 (thin_output): exit 6"; else fail "Test 2: expected exit 6, got ${rc2} -- ${out2}"; fi
# ARM-NO-VERDICT-01: same collapse as Test 1 -- floor-reject is one of the
# "produced nothing usable" reasons folded into no_verdict_marker at exhaustion.
if [[ -f "$gate2" ]] && grep -q '^status: blocked$' "$gate2" && grep -q '^reason: no_verdict_marker$' "$gate2"; then
  pass "Test 2 (thin_output): review-gate.md status=blocked reason=no_verdict_marker (floor rejects a 1-line unrelated file, pool exhausted)"
else
  fail "Test 2: review-gate.md wrong -- $(cat "$gate2" 2>/dev/null || echo MISSING)"
fi

# ── Test 3: peak_hours_refusal_with_fallback ────────────────────────────────────────
root3="$(make_fixture_root t3 "t3-unique-diff-content")"
resolver3="$(make_resolver_stub t3 glm "glm:ok:,sonnet:ok:")"
glm3="$(make_glm_stub t3 refuse_peak)"
arch3="$(make_arch_stub t3 pass)"
out3="$(LEADV2_DISPATCH_GLM_BIN="$glm3" LEADV2_DISPATCH_ARCHITECT_BIN="$arch3" run_close "$root3" t3sig003 codex "$resolver3")"; rc3=$?
gate3="${root3}/docs/handoff/dispatch-t3sig003/review-gate.md"
if [[ $rc3 -eq 0 ]]; then pass "Test 3 (peak_hours_refusal_with_fallback): exit 0"; else fail "Test 3: expected exit 0, got ${rc3} -- ${out3}"; fi
if [[ -f "$gate3" ]] && grep -q '^status: pass$' "$gate3"; then
  pass "Test 3: review-gate.md status=pass after glm refused and sonnet fell back"
else
  fail "Test 3: review-gate.md wrong -- $(cat "$gate3" 2>/dev/null || echo MISSING)"
fi
if grep -q 'status=arm_refused arm=glm reason=refused_peak_hours' <<<"$out3"; then
  pass "Test 3: journal/decision line carries arm_refused arm=glm reason=refused_peak_hours"
else
  fail "Test 3: no arm_refused decision line for glm -- ${out3}"
fi

# ── Test 4: peak_hours_refusal_no_fallback ──────────────────────────────────────────
root4="$(make_fixture_root t4 "t4-unique-diff-content")"
resolver4="$(make_resolver_stub t4 glm "glm:ok:,sonnet:ok:")"
glm4="$(make_glm_stub t4 refuse_peak)"
arch4="$(make_arch_stub t4 refuse_peak)"
out4="$(LEADV2_DISPATCH_GLM_BIN="$glm4" LEADV2_DISPATCH_ARCHITECT_BIN="$arch4" run_close "$root4" t4sig004 codex "$resolver4")"; rc4=$?
gate4="${root4}/docs/handoff/dispatch-t4sig004/review-gate.md"
if [[ $rc4 -eq 9 ]]; then pass "Test 4 (peak_hours_refusal_no_fallback): exit 9"; else fail "Test 4: expected exit 9, got ${rc4} -- ${out4}"; fi
if [[ -f "$gate4" ]] && grep -q '^status: unreviewed$' "$gate4" && grep -q '^reason: all_arms_unavailable$' "$gate4" && grep -q '^tried: glm,sonnet$' "$gate4"; then
  pass "Test 4: review-gate.md status=unreviewed reason=all_arms_unavailable tried=glm,sonnet"
else
  fail "Test 4: review-gate.md wrong -- $(cat "$gate4" 2>/dev/null || echo MISSING)"
fi

# ── Test 5: normal_review_still_passes ──────────────────────────────────────────────
root5="$(make_fixture_root t5 "t5-unique-diff-content")"
resolver5="$(make_resolver_stub t5 sonnet "sonnet:ok:")"
arch5="$(make_arch_stub t5 pass)"
out5="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch5" run_close "$root5" t5sig005 codex "$resolver5")"; rc5=$?
gate5="${root5}/docs/handoff/dispatch-t5sig005/review-gate.md"
if [[ $rc5 -eq 0 ]]; then pass "Test 5 (normal_review_still_passes): exit 0"; else fail "Test 5: expected exit 0, got ${rc5} -- ${out5}"; fi
if [[ -f "$gate5" ]] && grep -q '^status: pass$' "$gate5"; then
  pass "Test 5: review-gate.md status=pass -- silence-loudness fix does not trade for a false red"
else
  fail "Test 5: review-gate.md wrong -- $(cat "$gate5" 2>/dev/null || echo MISSING)"
fi

# ── Test 6: crash_backstop ──────────────────────────────────────────────────────────
# The reviewer arm hangs (sleep 30) instead of returning; SIGTERM is delivered to the
# close-gate process itself while it is blocked waiting on that foreground child --
# same technique as test-dispatch-product-close-exit-trap.sh's Test (b), but this time
# positioned AFTER the review phase (and its kill-switch check) has been entered, so
# it proves the NEW D3 backstop (review-gate.md must exist once the phase starts),
# not the pre-existing ledger-only backstop that test already covers.
root6="$(make_fixture_root t6 "t6-unique-diff-content")"
resolver6="$(make_resolver_stub t6 sonnet "sonnet:ok:")"
arch6="$(make_arch_stub t6 hang)"
gate6="${root6}/docs/handoff/dispatch-t6sig006/review-gate.md"
out6_file="${SUITE_TMP}/t6/out.log"
LEADV2_DISPATCH_ARCHITECT_BIN="$arch6" LEADV2_GLM_POLICY_RESOLVER="$resolver6" \
LEADV2_DISPATCH_CACHE_DIR="${SUITE_TMP}/t6/cache" LEADV2_JOURNAL_BIN=/bin/true LEADV2_E2E_OWNERSHIP=0 \
  bash "$PRODUCT_CLOSE_SH" "$root6" t6sig006 codex "" 0 1 "" > "$out6_file" 2>&1 &
pc6_pid=$!
# INVESTIGATE-30e50f97: a fixed `sleep 0.7` here raced the close-gate's own startup
# cost (fixture git init/commit already paid before this point, then the resolver
# python3 fork, review-signals/pool-resolve, THEN the arm launch) against a load-
# dependent wall clock -- on a busy box 0.7s can elapse before the hung arch stub
# (the thing SIGTERM is meant to interrupt) ever starts, so the signal lands before
# _PC_REVIEW_ENTERED is even set and the backstop legitimately has nothing to write.
# Confirmed by interleaved A/B runs of this exact scenario against main and this
# worktree's script: both showed the SAME flake rate (main also drops the gate write
# under load) -- this was a test synchronisation bug, not a fall-through regression.
# Poll for a plain file marker instead of `pgrep -f` (a per-iteration fork+exec that
# on a loaded box costs more than the 0.05s sleep beside it, defeating the point of
# polling): run_reviewer_arm's sonnet/opus branch writes "${HANDOFF}/review-mission.md"
# BEFORE invoking the launcher (the arch6 stub, which then hangs in `sleep 30`) -- its
# existence is cheap-to-check, load-independent evidence that the review arm has
# actually started, i.e. that _PC_REVIEW_ENTERED (set well before this, at kill-switch
# check time) is already true. Fast machines proceed almost immediately; slow/loaded
# machines wait as long as they actually need, bounded so a genuine setup failure
# still surfaces instead of hanging forever.
mission6="${root6}/docs/handoff/dispatch-t6sig006/review-mission.md"
_t6_waited=0
while (( _t6_waited < 100 )); do
  [[ -f "$mission6" ]] && break
  kill -0 "$pc6_pid" 2>/dev/null || break
  sleep 0.05
  _t6_waited=$((_t6_waited + 1))
done
if kill -0 "$pc6_pid" 2>/dev/null; then
  kill -TERM "$pc6_pid" 2>/dev/null
else
  fail "Test 6 setup: close-gate process exited before SIGTERM could be sent -- out=$(cat "$out6_file" 2>/dev/null)"
fi
wait "$pc6_pid" 2>/dev/null
rc6=$?
if [[ "$rc6" != "0" ]]; then
  pass "Test 6 (crash_backstop): non-zero exit (rc=${rc6}) on SIGTERM mid-review"
else
  fail "Test 6: expected non-zero exit, got 0 -- $(cat "$out6_file" 2>/dev/null)"
fi
if [[ -f "$gate6" ]] && grep -q '^status: unreviewed$' "$gate6" && grep -q '^reason: review_crashed$' "$gate6"; then
  pass "Test 6: review-gate.md exists with reason=review_crashed -- the EXIT-trap backstop fired (D3)"
else
  fail "Test 6: review-gate.md wrong or missing -- $(cat "$gate6" 2>/dev/null || echo MISSING)"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
