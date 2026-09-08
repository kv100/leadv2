#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: run-core-offline known-red-suites known-red-suites.txt
# plugins/leadv2/scripts/tests/test-core-offline-known-red-skip.sh — B2-GATE-BUDGET-4 (seam M3)
#
# The budget-mode known-red skip seam in run-core-offline.sh. tests/run-all.sh
# forwards LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1 + the allow-list path ONLY in
# its budget scopes (--scope changed / changed-since = the close gate and PR
# CI); under that request this wrapper skips allow-listed labels with one
# [CORE-OFFLINE] KNOWN-RED-SKIP line each. Both halves of the contract:
#   * the skip DOES apply in --scope changed (that is the close-gate time it
#     buys back — measured 2026-09-09: lane-truth-batch-01 = 151s red);
#   * the skip NEVER applies to a bare invocation or --scope all, even when
#     the env is present (a leak). The nightly full sweep is the ONE place
#     allow-listed suites still execute, and run-all's
#     [KNOWN-RED-GONE-GREEN] depends on them running there.
#   * a skip that empties the whole selection is a NAMED verdict
#     (verdict=nothing_to_run reason=known_red_skip_emptied_selection), exit
#     0 — never a silent empty pass.
#
# Method (test-core-offline-scope-changed.sh's): a scratch git repo carries
# the REAL run-core-offline.sh; LEADV2_SUITE_DEFS_OVERRIDE injects fake defs
# (ALLOWED_ONE, FRESH_ONE) that share ONE command file so the scope selection
# keeps both; the scratch allow-list (OUTSIDE the repo, so it is not itself a
# changed file) holds core:ALLOWED_ONE. No real suite runs; every case is
# seconds-fast. Assertions are on VALUES (exit codes, machine-prefixed
# lines), never prose.
#
# DECLARED NEGATIVE CONTROL (E2E-KILLRATE-01, this lane's third), applied by
# leadv2-mutation-control.sh to the marker line INSIDE the function body
# (never top level — a top-level insert reddens every suite for the wrong
# reason):
#   M3 skip-mut-1 — drop the budget-scope gate, skip whenever the env is
#     present (even bare / --scope all):
#     leadv2-mutation-control.sh plugins/leadv2/scripts/tests/test-core-offline-known-red-skip.sh \
#       plugins/leadv2/scripts/tests/run-core-offline.sh \
#       's|return 1 # skip-mut-1 marker: budget scope gates the skip$|: # skip-mut-1 mutated: scope gate dropped|'
#     -> case 2 goes RED: a bare invocation handed the env starts skipping
#        allow-listed suites — the "dropped from everywhere" failure the
#        still-executed-somewhere contract forbids.
#
# Portable: bash 3.2, scratch fixtures only. Run from anywhere:
#   bash plugins/leadv2/scripts/tests/test-core-offline-known-red-skip.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
RUNNER_SRC="${LEADV2_TEST_CORE_OFFLINE:-$ROOT/plugins/leadv2/scripts/tests/run-core-offline.sh}"
[[ -f "$RUNNER_SRC" ]] || { echo "FAIL: runner not found at $RUNNER_SRC" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

if bash -n "$RUNNER_SRC"; then pass "bash -n clean (run-core-offline.sh)"; else fail "bash -n run-core-offline.sh"; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/b2-skip.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
SCRATCH="$TMP/repo"
mkdir -p "$SCRATCH/plugins/leadv2/scripts/tests" "$SCRATCH/tests"

cp "$RUNNER_SRC" "$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh"
cat > "$SCRATCH/tests/test-fake.sh" <<'FAKE'
#!/usr/bin/env bash
printf 'fake-suite-ran\n'
exit 0
FAKE
chmod +x "$SCRATCH/tests/test-fake.sh"

# The allow-list lives OUTSIDE the scratch repo: an untracked
# tests/known-red-suites.txt inside it would itself be a changed file, and an
# unmapped changed file forces full_set_fallback — masking the seam entirely.
ALLOW="$TMP/allowlist.txt"
printf 'core:ALLOWED_ONE\n' > "$ALLOW"

git init -q "$SCRATCH" 2>/dev/null
git -C "$SCRATCH" branch -m main 2>/dev/null
git -C "$SCRATCH" add plugins/leadv2/scripts/tests/run-core-offline.sh tests/test-fake.sh
git -C "$SCRATCH" -c user.email=t@t -c user.name=t commit -qm base

# Dirty the fake suite so --scope changed narrows to exactly it. Both OVERRIDE
# defs point at the same file: selection keeps an entry per def whose command
# basename matches a selected file, so ALLOWED_ONE and FRESH_ONE both survive.
printf '# dirty for scope\n' >> "$SCRATCH/tests/test-fake.sh"

RUNNER="$SCRATCH/plugins/leadv2/scripts/tests/run-core-offline.sh"
DEFS_BOTH="ALLOWED_ONE|||bash $SCRATCH/tests/test-fake.sh
FRESH_ONE|||bash $SCRATCH/tests/test-fake.sh"
DEFS_ONLY_ALLOWED="ALLOWED_ONE|||bash $SCRATCH/tests/test-fake.sh"

OUT=""; RC=0
run_wrap() { # <defs> <skip-env 0|1> <scope: changed|all|-> — sets OUT/RC
  local defs="$1" want_env="$2" scope="$3"
  local -a pre=(env -i "PATH=$PATH" "HOME=$HOME" "TMPDIR=${TMPDIR:-/tmp}"
    "LEADV2_SUITE_DEFS_OVERRIDE=$defs" "LEADV2_SUITE_SHARDS=1")
  if [[ "$want_env" == "1" ]]; then
    pre+=("LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1" "LEADV2_CORE_OFFLINE_KNOWN_RED_FILE=$ALLOW")
  fi
  local -a args=()
  if [[ "$scope" != "-" ]]; then args+=(--scope "$scope"); fi
  OUT="$(cd "$SCRATCH" && "${pre[@]}" bash "$RUNNER" ${args[@]+"${args[@]}"} 2>&1)"
  RC=$?
}

# ── case 1: the skip applies in --scope changed, loudly, one line per label ──
run_wrap "$DEFS_BOTH" 1 changed
if [[ $RC -eq 0 ]] \
   && grep -q 'scope=changed running 2 of 2 suites' <<<"$OUT" \
   && grep -q '^\[CORE-OFFLINE\] KNOWN-RED-SKIP: ALLOWED_ONE$' <<<"$OUT" \
   && ! grep -q 'KNOWN-RED-SKIP: FRESH_ONE' <<<"$OUT" \
   && grep -q '^\[CORE-OFFLINE\] FRESH_ONE$' <<<"$OUT" \
   && grep -q '^\[CORE-OFFLINE\] known-red skipped=1 ' <<<"$OUT" \
   && grep -q 'suites passed=1 failed=0 missing=0 known_red_skipped=1 repo=' <<<"$OUT"; then
  pass "(1) --scope changed + request: 2 selected, ALLOWED_ONE skipped with one line, FRESH_ONE executed, rc=0"
else
  fail "(1) budget skip failed; rc=$RC out=
$OUT"
fi

# ── case 2 (M3, E2E-KILLRATE-01 control 3): a bare invocation NEVER skips, ───
# even when the env leaks into it — that is the still-executed-somewhere half
run_wrap "$DEFS_BOTH" 1 -
if [[ $RC -eq 0 ]] \
   && grep -q '^\[CORE-OFFLINE\] ALLOWED_ONE$' <<<"$OUT" \
   && grep -q '^\[CORE-OFFLINE\] FRESH_ONE$' <<<"$OUT" \
   && ! grep -q 'KNOWN-RED-SKIP' <<<"$OUT" \
   && grep -q 'known_red_skipped=0 ' <<<"$OUT"; then
  pass "(2) bare invocation with the env present still executes ALLOWED_ONE (rc=$RC)"
else
  fail "(2) bare invocation skipped allow-listed suites; rc=$RC out=
$OUT"
fi

# ── case 3: --scope changed WITHOUT the request: nothing is skipped ─────────
run_wrap "$DEFS_BOTH" 0 changed
if [[ $RC -eq 0 ]] \
   && grep -q '^\[CORE-OFFLINE\] ALLOWED_ONE$' <<<"$OUT" \
   && grep -q '^\[CORE-OFFLINE\] FRESH_ONE$' <<<"$OUT" \
   && ! grep -q 'KNOWN-RED-SKIP' <<<"$OUT"; then
  pass "(3) --scope changed without the request: allow-listed suite still executes"
else
  fail "(3) skip applied without the request; rc=$RC out=
$OUT"
fi

# ── case 4: --scope all NEVER skips (the nightly full-sweep property) ───────
run_wrap "$DEFS_BOTH" 1 all
if [[ $RC -eq 0 ]] \
   && grep -q '^\[CORE-OFFLINE\] ALLOWED_ONE$' <<<"$OUT" \
   && ! grep -q 'KNOWN-RED-SKIP' <<<"$OUT"; then
  pass "(4) --scope all with the env present still executes ALLOWED_ONE (nightly full sweep)"
else
  fail "(4) --scope all wrongly skipped; rc=$RC out=
$OUT"
fi

# ── case 5: a skip that empties the selection is a NAMED verdict, not a ─────
# silent empty pass
run_wrap "$DEFS_ONLY_ALLOWED" 1 changed
if [[ $RC -eq 0 ]] \
   && grep -q 'verdict=nothing_to_run reason=known_red_skip_emptied_selection' <<<"$OUT" \
   && grep -q 'known_red_skipped=1 verdict=nothing_to_run' <<<"$OUT"; then
  pass "(5) emptied selection: named verdict nothing_to_run/known_red_skip_emptied_selection, rc=0"
else
  fail "(5) emptied-selection verdict missing; rc=$RC out=
$OUT"
fi

printf 'test-core-offline-known-red-skip: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
