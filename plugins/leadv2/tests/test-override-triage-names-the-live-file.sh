#!/usr/bin/env bash
# test-override-triage-names-the-live-file.sh — negative controls for leadv2-override-triage.sh.
#
# E2E-KILLRATE-01 controls, both directions:
#   1. SYMPTOM — a RETIRE file that gains a real reader must be reported BY NAME with a
#      non-zero exit; disabling the verdict comparison inside compare_entry()'s body must
#      make that detection disappear (mutation must be killed, i.e. the real assertion
#      genuinely depends on the comparison).
#   2. GUARD — a tree whose readers match the yaml must pass with checked=N asserted > 0;
#      mutating the entry scan so it examines nothing must exit non-zero on checked=0
#      (a green "I looked at nothing" is the failure mode being prevented).
#
# Hermetic: everything runs against a scratch tree via LEADV2_OVERRIDE_TRIAGE_ROOTS; no
# live repo is touched.
# run-all-triggers: leadv2-override-triage override-triage
set -uo pipefail

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
CHECKER="$TEST_DIR/../scripts/leadv2-override-triage.sh"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/ovr-triage-test.XXXXXX")
FAILS=0
trap 'rm -rf "$SCRATCH"' EXIT

fail() { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
pass() { printf '  ok   %s\n' "$1"; }

build_tree() {
  rm -rf "$SCRATCH"
  mkdir -p "$SCRATCH/.claude/leadv2-overrides" "$SCRATCH/.claude/scripts" \
           "$SCRATCH/.claude/scripts-vendor-backup-20260101"
  printf 'retire-me: true\n' > "$SCRATCH/.claude/leadv2-overrides/alpha.yaml"
  printf 'live: true\n'          > "$SCRATCH/.claude/leadv2-overrides/beta.yaml"
  printf 'backup-only: true\n'   > "$SCRATCH/.claude/leadv2-overrides/gamma.yaml"
  # a real consumer for beta:
  printf '# policy loader reads .claude/leadv2-overrides/beta.yaml here\n' \
    > "$SCRATCH/.claude/scripts/run.sh"
  # an inert vendored copy referencing gamma (backup-class reader):
  printf '# legacy copy of .claude/leadv2-overrides/gamma.yaml wiring\n' \
    > "$SCRATCH/.claude/scripts-vendor-backup-20260101/b.sh"
  cat > "$SCRATCH/triage.yaml" <<YAML
schema: 1
entries:
  - repo: leadv2
    path: alpha.yaml
    verdict: retire
    retire_candidate: true
    consumer: none
    absent_default: "no consumer exists - absence unobservable"
    evidence: "four proofs recorded in lane C4"
  - repo: leadv2
    path: beta.yaml
    verdict: keep
    consumer: "leadv2:.claude/scripts/run.sh:1"
    absent_default: "not triaged - live consumers"
    evidence: "live reader in run.sh"
  - repo: leadv2
    path: gamma.yaml
    verdict: unproven
    consumer: none
    absent_default: "no live consumer"
    evidence: "backup-only readers are not liveness"
YAML
}

run_checker() { # $1 = checker path
  LEADV2_OVERRIDE_TRIAGE_ROOTS="leadv2=$SCRATCH" bash "$1" --yaml "$SCRATCH/triage.yaml" 2>&1
}

mutate() { # $1 = sed expr, $2 = output path
  sed -e "$1" "$CHECKER" > "$2" || { fail "sed mutation failed: $1"; return 1; }
}

echo "case 1 GUARD: matching tree passes with checked>0"
build_tree
OUT=$(run_checker "$CHECKER"); RC=$?
N=$(printf '%s\n' "$OUT" | sed -n 's/.*checked=\([0-9]*\).*/\1/p' | tail -1)
[[ $RC -eq 0 ]]            || fail "guard rc=$RC (want 0); out: $OUT"
printf '%s\n' "$OUT" | grep -q "checked=3" || fail "guard must print checked=3, got: $OUT"
[[ "${N:-0}" -gt 0 ]]      || fail "checked must be > 0, got '${N:-unset}'"
pass "guard green, checked=$N"

echo "case 2 SYMPTOM: retire file gains a reader -> named + non-zero"
build_tree
printf 'source "$ROOT/.claude/leadv2-overrides/alpha.yaml"\n' >> "$SCRATCH/.claude/scripts/run.sh"
OUT=$(run_checker "$CHECKER"); RC=$?
[[ $RC -ne 0 ]] || fail "symptom must exit non-zero, got 0; out: $OUT"
printf '%s\n' "$OUT" | grep -q "alpha.yaml" || fail "must name alpha.yaml by name; out: $OUT"
printf '%s\n' "$OUT" | grep -q "yaml=retire derived=keep" || fail "must show retire->keep drift; out: $OUT"
pass "symptom named, rc=$RC"

echo "case 3 KEEP-BROKEN: consumer vanishes -> named + non-zero"
build_tree
rm "$SCRATCH/.claude/scripts/run.sh"
OUT=$(run_checker "$CHECKER"); RC=$?
[[ $RC -ne 0 ]] || fail "keep-broken must exit non-zero, got 0"
printf '%s\n' "$OUT" | grep -q "beta.yaml" || fail "must name beta.yaml; out: $OUT"
pass "keep-broken named, rc=$RC"

echo "case 4 MUTATION m1: comparison disabled in function body -> symptom detection lost"
build_tree
printf 'source "$ROOT/.claude/leadv2-overrides/alpha.yaml"\n' >> "$SCRATCH/.claude/scripts/run.sh"
MUT="$SCRATCH/mut-compare.sh"
mutate 's/if entry_verdict != derived:/if False:/' "$MUT" || exit 1
grep -q "if False:" "$MUT" || fail "m1 sed did not apply (marker missing)"
grep -q "if entry_verdict != derived:" "$MUT" && fail "m1 left original comparison in place"
OUT=$(run_checker "$MUT"); RC=$?
[[ $RC -eq 0 ]] || fail "m1: with comparison disabled the checker must go green on the symptom (rc=$RC); if it still fails, the case-2 assertion does not depend on the comparison; out: $OUT"
grep -q "disagree=0" <<<"$OUT" || fail "m1: expected disagree=0, got: $OUT"
pass "m1 killed: detection genuinely depends on compare_entry()"

echo "case 5 MUTATION m2: scan examines nothing -> checked=0 refuses to pass"
build_tree
MUT="$SCRATCH/mut-empty.sh"
mutate 's/for entry in entries:/for entry in []:/' "$MUT" || exit 1
grep -q "for entry in \[\]:" "$MUT" || fail "m2 sed did not apply (marker missing)"
OUT=$(run_checker "$MUT"); RC=$?
[[ $RC -ne 0 ]] || fail "m2: checker examining nothing must exit non-zero (green-on-nothing); out: $OUT"
printf '%s\n' "$OUT" | grep -q "checked=0" || fail "m2: must print checked=0; out: $OUT"
pass "m2 killed: empty scan exits rc=$RC"

if [[ $FAILS -gt 0 ]]; then
  printf 'PASS-FALSE test-override-triage-names-the-live-file: %d failure(s)\n' "$FAILS"
  exit 1
fi
printf 'PASS test-override-triage-names-the-live-file\n'
