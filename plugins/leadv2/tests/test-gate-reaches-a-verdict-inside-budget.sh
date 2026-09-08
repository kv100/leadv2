#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: run-all run-all.sh known-red-suites known-red-suites.txt
# plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh — B2-GATE-BUDGET-4
#
# The close gate (leadv2-phase8-e2e-gate.sh, 900s) could reach only ONE
# terminal on this machine: rc=124 / verdict=timeout — because a selection
# holding the heavy leaf suites (measured 2026-09-08/09: ~355s lane-truth-
# batch-01, red+allow-listed; ~321s test-status-surface-bash32.sh, green)
# cannot fit the budget. tests/run-all.sh now (a) ceilings every suite so an
# overrun becomes a NAMED blocking failure — a verdict — and (b) asks
# run-core-offline.sh to skip allow-listed labels in the budget scopes, while
# --scope all still executes them and a pass there is surfaced as
# [KNOWN-RED-GONE-GREEN].
#
# Method (test-known-red-allowlist-nested-match.sh's): a scratch git repo
# carries the REAL tests/run-all.sh plus a FAKE, env-controlled
# run-core-offline.sh; no real suite runs, every case is seconds-fast.
# Assertions are on VALUES (exit codes, machine-prefixed lines), never prose.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to marker lines INSIDE function bodies of
# tests/run-all.sh (never top level). Both must turn THIS suite red:
#   M1 ceiling-mut-1 — disable the ceiling:
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh \
#       tests/run-all.sh \
#       's|^  printf '\''%s'\'' "${v}" # ceiling-mut-1 marker.*$|  printf '\''0'\''|'
#     -> case 1 goes RED: the hanging stub suite is never killed, no
#        [SUITE-TIMEOUT], run-all exits 0 instead of 1 (the gate would pay
#        the full hang out of its own 900s and still end rc=124).
#   M2 known-red-mut-1 — is_known_red accepts everything ("exclude
#     everything red", the always-green-gate shape):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh \
#       tests/run-all.sh \
#       's|# known-red-mut-1 marker: the allow-list decision every classification consumes|return 0 # known-red-mut-1: everything is known-red|'
#     -> case 2 goes RED: a NOT-allow-listed failing nested suite no longer
#        blocks the run (rc=0 where non-zero is asserted).
#
# Portable: bash 3.2, scratch fixtures only. Run from anywhere:
#   bash plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUN_ALL="${LEADV2_TEST_RUN_ALL:-$ROOT/tests/run-all.sh}"
[[ -f "$RUN_ALL" ]] || { echo "FAIL: run-all not found at $RUN_ALL" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

if bash -n "$RUN_ALL"; then pass "bash -n clean (tests/run-all.sh)"; else fail "bash -n tests/run-all.sh"; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/b2-budget.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
SCRATCH="$TMP/repo"
mkdir -p "$SCRATCH"
git init -q "$SCRATCH" 2>/dev/null
# B6-SCOPE-CHANGED: --scope changed refuses when no base ref resolves — pin
# the fixture's init branch to main.
git -C "$SCRATCH" branch -m main 2>/dev/null
mkdir -p "$SCRATCH/tests" "$SCRATCH/plugins/leadv2/scripts/tests"

cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"

# FAKE wrapper — the observable contract of run-core-offline.sh, env-steered:
#   FAKE_CORE_OFFLINE_FAIL    labels to fail with ([CORE-OFFLINE] FAILED:)
#   FAKE_CORE_OFFLINE_SKIPS   labels to report skipped when the skip env is on
#   FAKE_CORE_OFFLINE_MODE    full (no SCOPE_RESULT line) | narrow (verdict=selected)
#   FAKE_CORE_OFFLINE_HANG=1  sleep past the ceiling AFTER printing failures
#   FAKE_ENV_OUT              file receiving the LEADV2_CORE_OFFLINE_* env it saw
cat > "$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
{ env | grep -E '^LEADV2_CORE_OFFLINE_(SKIP_KNOWN_RED|KNOWN_RED_FILE)=' || true; } > "${FAKE_ENV_OUT:-/dev/null}" 2>/dev/null || true
printf 'args:%s\n' "$*" >> "${FAKE_ENV_OUT:-/dev/null}" 2>/dev/null || true
n=0
if [[ -n "${FAKE_CORE_OFFLINE_FAIL:-}" ]]; then
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    printf -- '[CORE-OFFLINE] FAILED: %s\n' "$label"
    n=$((n + 1))
  done <<< "${FAKE_CORE_OFFLINE_FAIL}"
fi
if [[ "${LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED:-}" == "1" && -n "${FAKE_CORE_OFFLINE_SKIPS:-}" ]]; then
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    printf -- '[CORE-OFFLINE] KNOWN-RED-SKIP: %s\n' "$label"
  done <<< "${FAKE_CORE_OFFLINE_SKIPS}"
fi
if [[ "${FAKE_CORE_OFFLINE_MODE:-}" == "narrow" ]]; then
  printf -- '[CORE-OFFLINE] SCOPE_RESULT selected=1 total=9 base=main@deadbeef changed=1 unmapped=0 verdict=selected reason=-\n'
fi
if [[ "${FAKE_CORE_OFFLINE_MODE:-}" == "fallback" ]]; then
  printf -- '[CORE-OFFLINE] SCOPE_RESULT selected=9 total=9 base=main@deadbeef changed=1 unmapped=1 verdict=full_set_fallback reason=unmapped_files (cannot prove the diff is covered)\n'
fi
if [[ "${FAKE_CORE_OFFLINE_NESTED_FALLBACK:-0}" == "1" ]]; then
  # A nested suite inside this run simulated a wrapper invocation that fell
  # open to the full set — printed AFTER the wrapper's own SCOPE_RESULT and
  # BEFORE the wrapper's own summary, exactly as in the real gate transcript
  # that minted 14 false gone-greens from a 13-of-95 narrowed run
  # (B2-GATE-BUDGET-4 gate run 2026-09-09).
  printf -- '[CORE-OFFLINE] SCOPE_RESULT selected=95 total=95 base=main@feedface changed=1 unmapped=1 verdict=full_set_fallback reason=unmapped_files (nested test transcript)\n'
  printf -- '[CORE-OFFLINE] suites passed=3 failed=0 missing=0 repo=nested-fixture\n'
fi
printf -- '[CORE-OFFLINE] suites passed=%d failed=%d missing=0 repo=fake\n' "$((1-n))" "$n"
[[ "${FAKE_CORE_OFFLINE_HANG:-0}" == "1" ]] && sleep "${FAKE_CORE_OFFLINE_HANG_S:-30}"
(( n == 0 ))
FAKE
chmod +x "$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh"

# Ceiling victim: env-gated sleep so --scope all runs of this fixture (which
# select every tests/test-*.sh) stay instant unless the case wants the hang.
cat > "$SCRATCH/tests/test-hang.sh" <<'HANGEOF'
#!/usr/bin/env bash
[[ "${HANG_SLEEP:-0}" == "1" ]] && sleep 30
exit 0
HANGEOF
chmod +x "$SCRATCH/tests/test-hang.sh"

write_allowlist() { printf '%s\n' "$1" > "$SCRATCH/tests/known-red-suites.txt"; }
write_allowlist "# scratch allow-list — empty baseline"

git -C "$SCRATCH" add -A
git -C "$SCRATCH" -c user.email=t@t -c user.name=t commit -qm base

# Always run --scope changed against a dirty tree (tests/test-hang.sh edited
# => the changed-suite rule selects it).
printf 'x\n' >> "$SCRATCH/tests/test-hang.sh"
# Case env goes in as VAR=VAL positional words: prefix assignments on a
# FUNCTION call never reach "$@" (measured: every FAKE_* was silently lost
# that way — the fixture "passed" by running nothing it was asked to run).
run_it() {
  OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    "$@" bash tests/run-all.sh --scope changed 2>&1)"
  RC=$?
}

# ── case 1 (THE SYMPTOM, E2E-KILLRATE-01 control 1): a selection that
# exceeds the budget produces a NAMED verdict, not a hang/124 ───────────────
FAKE_ENV_OUT="$TMP/env1"; rm -f "$TMP/env1"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=3 HANG_SLEEP=1 FAKE_ENV_OUT="$TMP/env1"
if [[ $RC -eq 1 ]] \
   && grep -q '^\[SUITE-TIMEOUT\] tests/test-hang.sh exceeded 3s ceiling' <<<"$OUT" \
   && grep -q '^  Failures (blocking):' <<<"$OUT" \
   && grep -q '^    - tests/test-hang.sh$' <<<"$OUT"; then
  pass "(1) ceiling: over-budget suite killed+named, rc=1 with blocking entry (a verdict, not rc=124)"
else
  fail "(1) ceiling verdict failed; rc=$RC out=
$OUT"
fi

# ── case 2 (THE GUARD, E2E-KILLRATE-01 control 2): a failing nested suite
# NOT on the allow-list still blocks ───────────────────────────────────────
write_allowlist "core:KNOWN_ONE"
FAKE_ENV_OUT="$TMP/env2"; rm -f "$TMP/env2"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_FAIL="SUDDEN_RED" FAKE_ENV_OUT="$TMP/env2"
if [[ $RC -ne 0 ]] && grep -q '^\[NOT-KNOWN-RED\] core:SUDDEN_RED' <<<"$OUT" \
   && grep -q '^  Failures (blocking):' <<<"$OUT"; then
  pass "(2) guard: not-allow-listed nested failure still blocks (rc=$RC)"
else
  fail "(2) guard failed; rc=$RC out=
$OUT"
fi

# ── case 3: allow-listed nested failure stays non-blocking (round-3 pin) ───
FAKE_ENV_OUT="$TMP/env3"; rm -f "$TMP/env3"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_FAIL="KNOWN_ONE" FAKE_ENV_OUT="$TMP/env3"
if [[ $RC -eq 0 ]] && grep -q '^\[KNOWN-RED\] ' <<<"$OUT" \
   && ! grep -q '^  Failures (blocking):' <<<"$OUT"; then
  pass "(3) known-red nested failure classified non-blocking, rc=0"
else
  fail "(3) known-red classification regressed; rc=$RC out=
$OUT"
fi

# ── case 4: budget scope forwards the skip env; --scope all does NOT ──────
FAKE_ENV_OUT="$TMP/env4a"; rm -f "$TMP/env4a"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_ENV_OUT="$TMP/env4a"
if grep -q '^LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1$' "$TMP/env4a" 2>/dev/null \
   && grep -q '^LEADV2_CORE_OFFLINE_KNOWN_RED_FILE=.*known-red-suites.txt$' "$TMP/env4a" 2>/dev/null \
   && grep -q '^args:--scope changed$' "$TMP/env4a" 2>/dev/null; then
  pass "(4a) --scope changed forwards skip env + allow-list path to the wrapper"
else
  fail "(4a) skip env not forwarded; env=$(cat "$TMP/env4a" 2>/dev/null)"
fi
FAKE_ENV_OUT="$TMP/env4b"; rm -f "$TMP/env4b"
OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_ENV_OUT="$TMP/env4b" \
  bash tests/run-all.sh --scope all 2>&1)"
RC=$?
if ! grep -q '^LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=' "$TMP/env4b" 2>/dev/null \
   && grep -q '^args:--scope all$' "$TMP/env4b" 2>/dev/null; then
  pass "(4b) --scope all does NOT skip: allow-listed suites still execute there (rc=$RC)"
else
  fail "(4b) scope=all wrongly skipped; env=$(cat "$TMP/env4b" 2>/dev/null)"
fi

# ── case 5: wrapper skips are relayed loudly, not silently dropped ─────────
FAKE_ENV_OUT="$TMP/env5"; rm -f "$TMP/env5"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_SKIPS="KNOWN_ONE" FAKE_ENV_OUT="$TMP/env5"
if [[ $RC -eq 0 ]] && grep -q '^\[KNOWN-RED-SKIP\] core:KNOWN_ONE — skipped in budget mode' <<<"$OUT" \
   && grep -q 'known-red-skipped (budget mode' <<<"$OUT"; then
  pass "(5) [KNOWN-RED-SKIP] relayed + counted in summary, rc=0"
else
  fail "(5) skip relay failed; rc=$RC out=
$OUT"
fi

# ── case 6: red->green surfaced in a FULL-set run ──────────────────────────
# (allow-list has KNOWN_ONE; the fake wrapper fails NOTHING => KNOWN_ONE
# passed a full-set run => [KNOWN-RED-GONE-GREEN], or the allow-list would
# become permanent.)
FAKE_ENV_OUT="$TMP/env6"; rm -f "$TMP/env6"
OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_MODE=full FAKE_ENV_OUT="$TMP/env6" \
  bash tests/run-all.sh --scope all 2>&1)"
RC=$?
if [[ $RC -eq 0 ]] && grep -q '^\[KNOWN-RED-GONE-GREEN\] core:KNOWN_ONE — passed a full-set run' <<<"$OUT"; then
  pass "(6) gone-green surfaced in full-set run (rc=$RC)"
else
  fail "(6) gone-green not surfaced; rc=$RC out=
$OUT"
fi

# ── case 7: gone-green NOT claimed from a narrowed run (it never ran there) ─
FAKE_ENV_OUT="$TMP/env7"; rm -f "$TMP/env7"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_MODE=narrow FAKE_ENV_OUT="$TMP/env7"
if [[ $RC -eq 0 ]] && ! grep -q 'KNOWN-RED-GONE-GREEN' <<<"$OUT"; then
  pass "(7) narrowed run claims no gone-green (allow-listed suite did not run)"
else
  fail "(7) false gone-green from narrowed run; rc=$RC out=
$OUT"
fi

# ── case 8: a ceiling-killed WRAPPER is blocking even when its partial
# transcript shows only allow-listed failures (no laundering a kill) ───────
FAKE_ENV_OUT="$TMP/env8"; rm -f "$TMP/env8"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=3 FAKE_CORE_OFFLINE_FAIL="KNOWN_ONE" FAKE_CORE_OFFLINE_HANG=1 FAKE_ENV_OUT="$TMP/env8"
if [[ $RC -ne 0 ]] && grep -q '^\[SUITE-TIMEOUT\] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 3s' <<<"$OUT" \
   && grep -q '^  Failures (blocking):' <<<"$OUT"; then
  pass "(8) ceiling-killed wrapper stays blocking despite allow-listed partial transcript (rc=$RC)"
else
  fail "(8) killed wrapper laundered; rc=$RC out=
$OUT"
fi

# ── case 9: --scope all does NOT ceiling the wrapper — the nightly full
# sweep is DESIGNED to run long (CI budget: 120 min), and it is the one
# place allow-listed suites still execute; ceilinging it there would kill
# the gone-green surface. The fake sleeps 8s with the ceiling set to 3: a
# wrongly-applied ceiling kills it at 3s and prints [SUITE-TIMEOUT].
FAKE_ENV_OUT="$TMP/env9"; rm -f "$TMP/env9"
OUT="$(cd "$SCRATCH" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  LEADV2_RUN_ALL_SUITE_TIMEOUT_S=3 FAKE_CORE_OFFLINE_HANG=1 FAKE_CORE_OFFLINE_HANG_S=8 \
  FAKE_ENV_OUT="$TMP/env9" bash tests/run-all.sh --scope all 2>&1)"
RC=$?
if [[ $RC -eq 0 ]] && ! grep -q '^\[SUITE-TIMEOUT\] plugins/leadv2/scripts/tests/run-core-offline.sh' <<<"$OUT"; then
  pass "(9) --scope all wrapper NOT ceiling-killed despite ceiling=3s (nightly long-run property kept; rc=$RC)"
else
  fail "(9) scope=all wrapper wrongly ceilinged; rc=$RC out=
$OUT"
fi

# ── case 10: a NESTED transcript line claiming full_set_fallback must NOT
# mint gone-green in a narrowed run. Reproduces the real gate transcript
# (2026-09-09): the wrapper ran 13 of 95 (verdict=selected), a nested test
# suite inside it printed its own SCOPE_RESULT verdict=full_set_fallback +
# its own suites-passed line, and 14 allow-listed labels were falsely
# declared gone-green ("remove from tests/known-red-suites.txt") from a run
# that never executed them. Allow-list still holds KNOWN_ONE from case 3/5.
FAKE_ENV_OUT="$TMP/env10"; rm -f "$TMP/env10"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_MODE=narrow FAKE_CORE_OFFLINE_NESTED_FALLBACK=1 FAKE_ENV_OUT="$TMP/env10"
if [[ $RC -eq 0 ]] && ! grep -q 'KNOWN-RED-GONE-GREEN' <<<"$OUT"; then
  pass "(10) nested full_set_fallback transcript line mints NO gone-green from a narrowed run (rc=$RC)"
else
  fail "(10) false gone-green from nested transcript; rc=$RC out=
$OUT"
fi

# ── case 11: the wrapper's OWN failed-open fallback still mints gone-green
# (the fix must not over-tighten: a genuine full-set run — asked or fell
# open — remains the allow-list's only shrink path).
FAKE_ENV_OUT="$TMP/env11"; rm -f "$TMP/env11"
run_it LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 FAKE_CORE_OFFLINE_MODE=fallback FAKE_ENV_OUT="$TMP/env11"
if [[ $RC -eq 0 ]] && grep -q '^\[KNOWN-RED-GONE-GREEN\] core:KNOWN_ONE — passed a full-set run' <<<"$OUT"; then
  pass "(11) wrapper's OWN full_set_fallback still surfaces gone-green (rc=$RC)"
else
  fail "(11) own-fallback gone-green lost; rc=$RC out=
$OUT"
fi

printf 'test-gate-reaches-a-verdict-inside-budget: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
