#!/usr/bin/env bash
# tests/test-review-body-persist.sh — REVIEW-BODY-PERSIST-01: the opus/sonnet review
# arm's full body must land in review-<arm>.md, not just the label line. And when no
# body exists anywhere, the arm must surface as blocked/review_body_lost, not silence.
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end (never a reimplementation).
# Each scenario gets its own throwaway git repo. The resolver is stubbed via
# LEADV2_GLM_POLICY_RESOLVER (python3) and the architect arm via
# LEADV2_DISPATCH_ARCHITECT_BIN, reusing the test-review-silence-gate.sh patterns.
#
# Run: bash scripts/tests/test-review-body-persist.sh
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
if /bin/bash -n "$PRODUCT_CLOSE_SH" 2>/dev/null; then
  pass "/bin/bash 3.2 -n clean (leadv2-dispatch-product-close.sh)"
else
  fail "/bin/bash 3.2 -n failed on leadv2-dispatch-product-close.sh"
fi

SUITE_TMP="$(lv2_mktemp_dir "review-body-persist-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

# make_fixture_root <name> <unique-content> -> prints the repo path on stdout.
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

# make_arch_stub_deliverable <name> -> prints the stub path on stdout.
# Simulates claude-subsession: prints only LABEL=.../SESSION_ID=... on stdout while
# writing the full review body to docs/handoff/dispatch-<TASK>-review/critic.full.md
# and critic.summary.md.
make_arch_stub_deliverable() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/arch-stub.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
# Parse --task-id from args
tid=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--task-id" ]]; then
    j=$((i+1))
    tid="${!j}"
  fi
done
# PROJECT_ROOT is exported by the caller
adir="${PROJECT_ROOT}/docs/handoff/${tid}"
mkdir -p "$adir"
cat > "$adir/critic.full.md" <<'BODY'
REVIEW_VERDICT: PASS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=0

## Review

The diff is well-structured and the changes are minimal. I found one medium
issue with the naming convention but nothing blocking.

1. **Medium**: Variable name `_pc_body_min` could be more descriptive.
2. The rest of the changes look correct and follow existing patterns.
3. No security concerns identified in this diff.
4. Edge cases are handled properly with appropriate fallback logic.
5. The test coverage is adequate for the scope of changes made here.
BODY
cat > "$adir/critic.summary.md" <<'SUMM'
REVIEW_VERDICT: PASS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=0
One medium naming issue, otherwise clean.
SUMM
echo "LABEL=critic-${tid}-1234567890 SESSION_ID=sess-fake-001"
exit 0
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_arch_stub_stream_only <name> -> prints the stub path on stdout.
# Simulates claude-subsession: prints label on stdout, no deliverable files, but
# writes critic.stream.jsonl with the final assistant message.
make_arch_stub_stream_only() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/arch-stub.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
tid=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--task-id" ]]; then
    j=$((i+1))
    tid="${!j}"
  fi
done
adir="${PROJECT_ROOT}/docs/handoff/${tid}"
mkdir -p "$adir"
# Write a stream-json transcript with one assistant message
cat > "$adir/critic.stream.jsonl" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n\nThe diff is clean and well-written. No issues found by this reviewer.\nThe implementation follows existing patterns correctly.\nAll edge cases are handled and the test coverage is complete."}]}}
JSONL
echo "LABEL=critic-${tid}-1234567890 SESSION_ID=sess-fake-002"
exit 0
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_arch_stub_label_only <name> -> prints the stub path on stdout.
# Simulates the incident: label line on stdout, nothing written anywhere,
# but writes a cost line to stderr (evidence of real output).
make_arch_stub_label_only() {
  local name="$1"
  local stub="${SUITE_TMP}/${name}/arch-stub.sh"
  mkdir -p "$(dirname "$stub")"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
echo "cost recorded: critic/opus in=40 out=16109 usd=1.2" >&2
echo "LABEL=critic-dispatch-fake SESSION_ID=sess-fake-003"
exit 0
SH
  chmod +x "$stub"
  printf '%s' "$stub"
}

# make_glm_stub_pass <name> -> prints the stub path on stdout.
# Healthy glm arm: writes a full PASS body via --out, regression guard.
make_glm_stub_pass() {
  local name="$1"
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
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nClean diff, no issues found by the stub reviewer arm.\n' > "$outfile"
exit 0
SH
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
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
    bash "$PRODUCT_CLOSE_SH" "$root" "$sig8" "$author" "" 0 1 "" 2>&1
}

# ── Test (a): deliverable body materialised into review-opus.md ─────────────────────
root_a="$(make_fixture_root ta "ta-unique-diff-content-for-deliverable")"
resolver_a="$(make_resolver_stub ta sonnet "sonnet:ok:")"
arch_a="$(make_arch_stub_deliverable ta)"
out_a="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch_a" run_close "$root_a" tasig001 codex "$resolver_a")"; rc_a=$?
rev_a="${root_a}/docs/handoff/dispatch-tasig001/review-sonnet.md"
gate_a="${root_a}/docs/handoff/dispatch-tasig001/review-gate.md"
if [[ $rc_a -eq 0 ]]; then pass "Test (a) deliverable: exit 0"; else fail "Test (a): expected exit 0, got ${rc_a} -- ${out_a}"; fi
if [[ -f "$rev_a" ]]; then
  if grep -q 'REVIEW_VERDICT:' "$rev_a" && grep -q 'REVIEW_FINDINGS:' "$rev_a"; then
    pass "Test (a): review-sonnet.md has both contract lines"
  else
    fail "Test (a): review-sonnet.md missing contract lines -- $(head -5 "$rev_a")"
  fi
  rev_bytes="$(wc -c < "$rev_a" | tr -d '[:space:]')"
  if [[ "${rev_bytes}" -gt 300 ]]; then
    pass "Test (a): review-sonnet.md is ${rev_bytes} bytes (full body materialised, not 97)"
  else
    fail "Test (a): review-sonnet.md is only ${rev_bytes} bytes -- body not materialised"
  fi
  if grep -q 'Variable name' "$rev_a"; then
    pass "Test (a): review-sonnet.md contains the numbered findings prose"
  else
    fail "Test (a): review-sonnet.md missing findings prose"
  fi
else
  fail "Test (a): review-sonnet.md does not exist"
fi

# ── Test (a2): stream-only fallback (no deliverable files) ──────────────────────────
root_a2="$(make_fixture_root ta2 "ta2-unique-diff-content-for-stream")"
resolver_a2="$(make_resolver_stub ta2 sonnet "sonnet:ok:")"
arch_a2="$(make_arch_stub_stream_only ta2)"
out_a2="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch_a2" run_close "$root_a2" ta2sig002 codex "$resolver_a2")"; rc_a2=$?
rev_a2="${root_a2}/docs/handoff/dispatch-ta2sig002/review-sonnet.md"
gate_a2="${root_a2}/docs/handoff/dispatch-ta2sig002/review-gate.md"
if [[ $rc_a2 -eq 0 ]]; then pass "Test (a2) stream-fallback: exit 0"; else fail "Test (a2): expected exit 0, got ${rc_a2} -- ${out_a2}"; fi
if [[ -f "$rev_a2" ]]; then
  if grep -q 'REVIEW_VERDICT:' "$rev_a2"; then
    pass "Test (a2): review-sonnet.md has REVIEW_VERDICT from stream transcript"
  else
    fail "Test (a2): review-sonnet.md missing REVIEW_VERDICT -- $(head -5 "$rev_a2")"
  fi
  rev_a2_bytes="$(wc -c < "$rev_a2" | tr -d '[:space:]')"
  if [[ "${rev_a2_bytes}" -gt 300 ]]; then
    pass "Test (a2): review-sonnet.md is ${rev_a2_bytes} bytes (stream body recovered)"
  else
    fail "Test (a2): review-sonnet.md is only ${rev_a2_bytes} bytes"
  fi
else
  fail "Test (a2): review-sonnet.md does not exist"
fi

# ── Test (b): body genuinely absent -> review_body_lost ─────────────────────────────
root_b="$(make_fixture_root tb "tb-unique-diff-content-for-body-lost")"
resolver_b="$(make_resolver_stub tb sonnet "sonnet:ok:")"
arch_b="$(make_arch_stub_label_only tb)"
out_b="$(LEADV2_DISPATCH_ARCHITECT_BIN="$arch_b" run_close "$root_b" tbsig003 codex "$resolver_b")"; rc_b=$?
gate_b="${root_b}/docs/handoff/dispatch-tbsig003/review-gate.md"
if [[ $rc_b -eq 6 ]]; then pass "Test (b) body_lost: exit 6"; else fail "Test (b): expected exit 6, got ${rc_b} -- ${out_b}"; fi
if [[ -f "$gate_b" ]] && grep -q '^status: blocked$' "$gate_b" && grep -q '^reason: review_body_lost$' "$gate_b"; then
  pass "Test (b): review-gate.md status=blocked reason=review_body_lost"
else
  fail "Test (b): review-gate.md wrong -- $(cat "$gate_b" 2>/dev/null || echo MISSING)"
fi

# ── Test (c): glm-arm regression — healthy arm unaffected by guard ──────────────────
root_c="$(make_fixture_root tc "tc-unique-diff-content-for-glm-regression")"
resolver_c="$(make_resolver_stub tc glm "glm:ok:")"
glm_c="$(make_glm_stub_pass tc)"
out_c="$(LEADV2_DISPATCH_GLM_BIN="$glm_c" run_close "$root_c" tcsig004 codex "$resolver_c")"; rc_c=$?
gate_c="${root_c}/docs/handoff/dispatch-tcsig004/review-gate.md"
rev_c="${root_c}/docs/handoff/dispatch-tcsig004/review-glm.md"
if [[ $rc_c -eq 0 ]]; then pass "Test (c) glm-regression: exit 0"; else fail "Test (c): expected exit 0, got ${rc_c} -- ${out_c}"; fi
if [[ -f "$gate_c" ]] && grep -q '^status: pass$' "$gate_c"; then
  pass "Test (c): review-gate.md status=pass — guard did not trip on healthy glm arm"
else
  fail "Test (c): review-gate.md wrong -- $(cat "$gate_c" 2>/dev/null || echo MISSING)"
fi

# ── Test (d): bash -n already done above ────────────────────────────────────────────
# (Covered by the syntax checks at the top of this suite.)

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
