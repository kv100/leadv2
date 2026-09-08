#!/usr/bin/env bash
# tests/test-known-red-allowlist-nested-match.sh
# E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01
#
# CI-RUNS-THE-SUITES-01 round 2 measured (2026-09-02) that the e2e gate's
# blocking decision only ever saw the WRAPPER name
# (plugins/leadv2/scripts/tests/run-core-offline.sh) — a name that is
# deliberately never on tests/known-red-suites.txt (putting it there would
# allow-list all 83 nested suites at once). Consequence: no `core:<label>`
# entry could ever unblock a lane; PULSE-HOOK-IS-A-FORKED-COPY-01 and
# CI-RUNS-THE-SUITES-01 both died at that wall with correct work committed.
#
# Round 3 fixed this inside tests/run-all.sh (and tests/ci-gate.sh
# independently re-parses the same `[CORE-OFFLINE] FAILED: <label>` lines for
# the GitHub Actions job) by classifying failures against `core:<label>`
# allow-list entries keyed by the NESTED suite's label, never by the
# wrapper's path. No suite existed to prove this or to catch a regression
# back to wrapper-level matching — this is that suite.
#
# Method: a scratch git repo carries the REAL tests/run-all.sh and
# tests/ci-gate.sh, plus a FAKE, controllable
# plugins/leadv2/scripts/tests/run-core-offline.sh that emits
# `[CORE-OFFLINE] FAILED: <label>` for whichever labels
# FAKE_CORE_OFFLINE_FAIL names (newline-separated) and exits non-zero iff
# that list is non-empty — the exact observable contract of the real
# wrapper, without running the real 83-suite set.
#
# Cases (each is a mutation gate — revert round 3's classification and every
# "unblocked" case below must go red again):
#   1. baseline: one nested failure, allow-list empty            -> BLOCKED
#   2. positive control: allow-list the failing nested label     -> UNBLOCKED
#   3. negative control: remove that entry again                 -> BLOCKED
#   4. allow-list the WRAPPER's own name instead of the nested
#      label (naive attempt to "fix" it by widening the entry)   -> STILL BLOCKED
#   5. two nested failures, only ONE allow-listed                -> STILL BLOCKED
#      (pointwise: unblocking is per-nested-name, not per-wrapper-run)
#   6. both nested failures allow-listed                          -> UNBLOCKED
#
# Run: bash tests/test-known-red-allowlist-nested-match.sh
set -uo pipefail

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ALL="${LEADV2_TEST_RUN_ALL:-$ROOT/tests/run-all.sh}"
CI_GATE="${LEADV2_TEST_CI_GATE:-$ROOT/tests/ci-gate.sh}"
[[ -f "$RUN_ALL" ]] || { echo "FAIL: run-all not found at $RUN_ALL"; exit 1; }
[[ -f "$CI_GATE" ]] || { echo "FAIL: ci-gate not found at $CI_GATE"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

SCRATCH="$TMP/repo"
git init -q "$SCRATCH" 2>/dev/null
# B6-SCOPE-CHANGED: run-all now REFUSES --scope changed when no base ref
# resolves (scope_changed_anchor) — pin the init branch to main so the
# fixture has one regardless of the machine's init.defaultBranch.
git -C "$SCRATCH" branch -m main 2>/dev/null
mkdir -p "$SCRATCH/tests" "$SCRATCH/plugins/leadv2/scripts/tests"

cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"
cp "$CI_GATE" "$SCRATCH/tests/ci-gate.sh"
chmod +x "$SCRATCH/tests/run-all.sh" "$SCRATCH/tests/ci-gate.sh"

# FAKE wrapper — controllable stand-in for run-core-offline.sh. Reads
# FAKE_CORE_OFFLINE_FAIL (newline-separated labels), emits the real wrapper's
# exact `[CORE-OFFLINE] FAILED: <label>` line per failing label, exits
# non-zero iff at least one label was given.
cat > "$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
n=0
if [[ -n "${FAKE_CORE_OFFLINE_FAIL:-}" ]]; then
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    printf -- '[CORE-OFFLINE] FAILED: %s\n' "$label"
    n=$((n + 1))
  done <<< "${FAKE_CORE_OFFLINE_FAIL}"
fi
(( n == 0 ))
FAKE
chmod +x "$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh"

WRAPPER_REL="plugins/leadv2/scripts/tests/run-core-offline.sh"

write_allowlist() { # <content>
  printf '%s\n' "$1" > "$SCRATCH/tests/known-red-suites.txt"
}
write_allowlist "# scratch allow-list — empty baseline"

git -C "$SCRATCH" add -A
git -C "$SCRATCH" -c user.email=t@t -c user.name=t commit -qm base

run_run_all() { # <fail_labels_newline_separated> -> sets OUT, RC
  OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    FAKE_CORE_OFFLINE_FAIL="$1" bash tests/run-all.sh --scope changed 2>&1)"
  RC=$?
}

run_ci_gate() { # <fail_labels_newline_separated> -> sets OUT, RC
  OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    FAKE_CORE_OFFLINE_FAIL="$1" bash tests/ci-gate.sh changed 2>&1)"
  RC=$?
}

# ── case 1: baseline — one nested failure, empty allow-list -> BLOCKED ──────
run_run_all "LABEL_A"
if [[ $RC -ne 0 ]] && grep -q '\[NOT-KNOWN-RED\] core:LABEL_A' <<<"$OUT" \
  && grep -q "Failures (blocking):" <<<"$OUT" && grep -q -- "- ${WRAPPER_REL}" <<<"$OUT"; then
  pass "(1) run-all: baseline nested failure blocks, named NOT-KNOWN-RED, wrapper listed as the blocking path"
else
  fail "(1) run-all: baseline blocking failed; rc=$RC out=
$OUT"
fi

run_ci_gate "LABEL_A"
if [[ $RC -ne 0 ]] && grep -qE '^\s*-\s*core:LABEL_A\s*$' <<<"$OUT" && grep -q "ci-gate: FAIL" <<<"$OUT"; then
  pass "(1) ci-gate: baseline nested failure blocks, named core:LABEL_A, unexpected"
else
  fail "(1) ci-gate: baseline blocking failed; rc=$RC out=
$OUT"
fi

# ── case 2: positive control — allow-list the failing label -> UNBLOCKED ───
write_allowlist "core:LABEL_A"

run_run_all "LABEL_A"
if [[ $RC -eq 0 ]] && grep -q "\[KNOWN-RED\] ${WRAPPER_REL}" <<<"$OUT" \
  && grep -q "core:LABEL_A" <<<"$OUT" && ! grep -q "Failures (blocking):" <<<"$OUT"; then
  pass "(2) run-all: allow-listing the nested label unblocks the wrapper (rc=0, KNOWN-RED, no blocking block)"
else
  fail "(2) run-all: allow-listed nested label did NOT unblock; rc=$RC out=
$OUT"
fi

run_ci_gate "LABEL_A"
if [[ $RC -eq 0 ]] && grep -q "ci-gate: PASS" <<<"$OUT" && grep -q "core:LABEL_A" <<<"$OUT"; then
  pass "(2) ci-gate: allow-listing the nested label unblocks the job (rc=0, PASS, known-red core:LABEL_A)"
else
  fail "(2) ci-gate: allow-listed nested label did NOT unblock; rc=$RC out=
$OUT"
fi

# ── case 3: negative control — remove the entry again -> BLOCKED again ─────
write_allowlist "# scratch allow-list — empty baseline"

run_run_all "LABEL_A"
if [[ $RC -ne 0 ]] && grep -q '\[NOT-KNOWN-RED\] core:LABEL_A' <<<"$OUT" && grep -q "Failures (blocking):" <<<"$OUT"; then
  pass "(3) run-all: removing the allow-list entry re-blocks the same failure (reversibility proven)"
else
  fail "(3) run-all: removing the entry did not re-block; rc=$RC out=
$OUT"
fi

run_ci_gate "LABEL_A"
if [[ $RC -ne 0 ]] && grep -q "ci-gate: FAIL" <<<"$OUT"; then
  pass "(3) ci-gate: removing the allow-list entry re-blocks the same failure (reversibility proven)"
else
  fail "(3) ci-gate: removing the entry did not re-block; rc=$RC out=
$OUT"
fi

# ── case 4: allow-list the WRAPPER's name instead of the nested label ──────
# This is the exact defect this suite guards against: a list that can only
# ever name the wrapper is a list that can never unblock anything. Prove the
# converse holds too — naming the wrapper (by path, the only form ci-gate.sh
# even parses for a non-core-offline suite) must NOT unblock a nested failure.
write_allowlist "path:${WRAPPER_REL}"

run_run_all "LABEL_A"
if [[ $RC -ne 0 ]] && grep -q '\[NOT-KNOWN-RED\] core:LABEL_A' <<<"$OUT" && grep -q "Failures (blocking):" <<<"$OUT"; then
  pass "(4) run-all: allow-listing the WRAPPER's own path does NOT unblock the nested failure"
else
  fail "(4) run-all: wrapper-path entry unexpectedly unblocked (or blocking machinery broke); rc=$RC out=
$OUT"
fi

run_ci_gate "LABEL_A"
if [[ $RC -ne 0 ]] && grep -qE '^\s*-\s*core:LABEL_A\s*$' <<<"$OUT" && grep -q "ci-gate: FAIL" <<<"$OUT"; then
  pass "(4) ci-gate: allow-listing the WRAPPER's own path does NOT unblock the nested failure"
else
  fail "(4) ci-gate: wrapper-path entry unexpectedly unblocked (or blocking machinery broke); rc=$RC out=
$OUT"
fi

# ── case 5: two nested failures, only ONE allow-listed -> STILL BLOCKED ────
# Proves unblocking is pointwise per nested name, not "any allow-listed
# failure inside the wrapper turns the whole wrapper green".
write_allowlist "core:LABEL_A"

run_run_all "$(printf 'LABEL_A\nLABEL_B')"
if [[ $RC -ne 0 ]] \
  && grep -q '\[NOT-KNOWN-RED\] core:LABEL_B' <<<"$OUT" \
  && ! grep -q '\[NOT-KNOWN-RED\] core:LABEL_A' <<<"$OUT" \
  && grep -q "Failures (blocking):" <<<"$OUT"; then
  pass "(5) run-all: partial allow-listing (LABEL_A only) still blocks on the unlisted LABEL_B"
else
  fail "(5) run-all: partial allow-listing did not block correctly; rc=$RC out=
$OUT"
fi

run_ci_gate "$(printf 'LABEL_A\nLABEL_B')"
if [[ $RC -ne 0 ]] \
  && grep -qE '^\s*-\s*core:LABEL_B\s*$' <<<"$OUT" \
  && ! grep -qE '^\s*-\s*core:LABEL_A\s*$' <<<"$OUT" \
  && grep -q "ci-gate: FAIL" <<<"$OUT"; then
  pass "(5) ci-gate: partial allow-listing (LABEL_A only) still blocks on the unlisted LABEL_B"
else
  fail "(5) ci-gate: partial allow-listing did not block correctly; rc=$RC out=
$OUT"
fi

# ── case 6: both nested failures allow-listed -> fully UNBLOCKED ───────────
write_allowlist "core:LABEL_A
core:LABEL_B"

run_run_all "$(printf 'LABEL_A\nLABEL_B')"
if [[ $RC -eq 0 ]] && ! grep -q "Failures (blocking):" <<<"$OUT" \
  && grep -q "\[KNOWN-RED\] ${WRAPPER_REL}" <<<"$OUT"; then
  pass "(6) run-all: allow-listing both nested failures fully unblocks the wrapper"
else
  fail "(6) run-all: allow-listing both did not fully unblock; rc=$RC out=
$OUT"
fi

run_ci_gate "$(printf 'LABEL_A\nLABEL_B')"
if [[ $RC -eq 0 ]] && grep -q "ci-gate: PASS" <<<"$OUT"; then
  pass "(6) ci-gate: allow-listing both nested failures fully unblocks the job"
else
  fail "(6) ci-gate: allow-listing both did not fully unblock; rc=$RC out=
$OUT"
fi

printf 'test-known-red-allowlist-nested-match: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
