#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: known-red-suites.txt known-red-guard.sh known-red-suites known-red-guard
# tests/test-known-red-guard.sh — THE-KNOWN-RED-REGISTRY-ROTTED-AND-EVERY-LANE-PAYS-01
#
# Proves tests/known-red-guard.sh actually refuses the three ways the
# allow-list (tests/known-red-suites.txt) can drift from fact, instead of
# just being coded to:
#   1. undated growth  — a new entry with no YYYY-MM-DD reason token
#   2. stale core:     — a label that matches nothing in the live SUITE_DEFS
#      (this doubles as the NEGATIVE CONTROL: registering a suite name that
#      is not a real, currently-red suite must be refused, not silently
#      tolerated — the guard cannot tell "never existed" from "went green
#      under a stale label", and correctly refuses both the same way)
#   3. stale path:      — a path: entry pointing at a file that does not exist
#   4. gone-green transcript — a [KNOWN-RED-GONE-GREEN] line for a
#      currently-registered core: label, fed in via the optional second arg
#      (this is the actually-green-suite negative control in its strict
#      form: even a label that DOES match a live SUITE_DEFS entry must be
#      refused once a transcript proves that suite now passes)
# ...and that a clean, honestly-dated, live-matching list still passes.
#
# Method: no scratch git repo needed — known-red-guard.sh only reads the
# working tree (via base-ref git show) and an optional transcript file, so
# fixtures are a scratch known-red-suites.txt + a scratch run-core-offline.sh
# stand-in (LEADV2_TEST_CORE_OFFLINE-less; the guard hardcodes the real
# path) — instead each case runs the REAL guard script against a scratch
# ROOT laid out to mimic the repo shape, keeping the real repo's
# known-red-suites.txt and run-core-offline.sh untouched.
#
# Portable: bash 3.2, scratch fixtures only, hermetic (no shared state).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD_SRC="${ROOT}/tests/known-red-guard.sh"
[[ -f "${GUARD_SRC}" ]] || { echo "FAIL: guard not found at ${GUARD_SRC}" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

if bash -n "${GUARD_SRC}"; then pass "bash -n clean (known-red-guard.sh)"; else fail "bash -n known-red-guard.sh"; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/known-red-guard-test.XXXXXX")" || exit 1
trap 'rm -rf "${TMP}"' EXIT
SCRATCH="${TMP}/repo"
mkdir -p "${SCRATCH}/tests" "${SCRATCH}/plugins/leadv2/scripts/tests"

cat > "${SCRATCH}/plugins/leadv2/scripts/tests/run-core-offline.sh" <<'DEFS'
SUITE_DEFS=(
  "Fixture suite A|||true|||"
  "Fixture suite B|||true|||"
)
DEFS

git -C "${SCRATCH}" init -q
git -C "${SCRATCH}" config user.email "test@example.com"
git -C "${SCRATCH}" config user.name "test"

# base-ref state: one legitimately dated entry (fixture-suite A), matching a
# live SUITE_DEFS label.
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'BASE'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
BASE
git -C "${SCRATCH}" add -A
git -C "${SCRATCH}" commit -q -m "baseline"

# known-red-guard.sh hardcodes its own paths relative to itself
# (HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="${HERE}/.."), so
# to point it at the scratch tree we must run a scratch COPY of the guard
# script, not the real one against a foreign ROOT.
cp "${GUARD_SRC}" "${SCRATCH}/tests/known-red-guard.sh"
run_guard() { # <transcript-file-or-empty>
  ( cd "${SCRATCH}/tests" && bash ./known-red-guard.sh main "$@" )
}

# ── case 1: unchanged list still passes ─────────────────────────────────────
if run_guard >/tmp/.krg-out.$$ 2>&1; then
  pass "case 1: clean baseline (unchanged) -> exit 0"
else
  fail "case 1: clean baseline should pass, got: $(cat /tmp/.krg-out.$$)"
fi
rm -f /tmp/.krg-out.$$

# ── case 2: dated growth against a real label -> still passes ──────────────
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'GROW'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
core:Fixture suite B  # fixture — red 2026-09-14, new and real
GROW
if run_guard >/tmp/.krg-out.$$ 2>&1; then
  pass "case 2: dated growth against a real live label -> exit 0"
else
  fail "case 2: dated growth against a real label should pass, got: $(cat /tmp/.krg-out.$$)"
fi
rm -f /tmp/.krg-out.$$

# ── case 3: undated growth is refused ───────────────────────────────────────
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'UNDATED'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
core:Fixture suite B  # fixture — no date in this reason at all
UNDATED
if run_guard >/tmp/.krg-out.$$ 2>&1; then
  fail "case 3: undated growth should be refused, but guard exited 0"
else
  if grep -q 'FAIL undated-growth' /tmp/.krg-out.$$; then
    pass "case 3: undated growth -> refused with undated-growth"
  else
    fail "case 3: refused for the wrong reason: $(cat /tmp/.krg-out.$$)"
  fi
fi
rm -f /tmp/.krg-out.$$

# ── case 4: negative control — a NON-EXISTENT/never-red suite is refused,
# never silently tolerated (a label with no matching live SUITE_DEFS entry
# is indistinguishable from "actually green" to a static check, and the
# guard must refuse both the same way rather than let either through) ──────
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'STALECORE'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
core:Fixture suite that was never real  # fixture — red 2026-09-14, fabricated
STALECORE
if run_guard >/tmp/.krg-out.$$ 2>&1; then
  fail "case 4: a never-existed core: label should be refused, but guard exited 0"
else
  if grep -q 'FAIL stale-core' /tmp/.krg-out.$$; then
    pass "case 4 (negative control): unmatched core: label -> refused with stale-core, not silently tolerated"
  else
    fail "case 4: refused for the wrong reason: $(cat /tmp/.krg-out.$$)"
  fi
fi
rm -f /tmp/.krg-out.$$

# ── case 5: stale path: entry is refused ────────────────────────────────────
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'STALEPATH'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
path:tests/does-not-exist-anywhere.sh  # fixture — red 2026-09-14, fabricated
STALEPATH
if run_guard >/tmp/.krg-out.$$ 2>&1; then
  fail "case 5: a nonexistent path: entry should be refused, but guard exited 0"
else
  if grep -q 'FAIL stale-path' /tmp/.krg-out.$$; then
    pass "case 5: nonexistent path: entry -> refused with stale-path"
  else
    fail "case 5: refused for the wrong reason: $(cat /tmp/.krg-out.$$)"
  fi
fi
rm -f /tmp/.krg-out.$$

# ── case 6: negative control, strict form — a label that DOES match a live
# SUITE_DEFS entry is still refused once a transcript proves it now passes
# (GONE-GREEN). Registering an actually-green suite must never be silently
# suppressed just because its label happens to be real. ────────────────────
cat > "${SCRATCH}/tests/known-red-suites.txt" <<'BASE'
core:Fixture suite A  # fixture — red 2026-09-01, baseline
BASE
cat > "${TMP}/gone-green.log" <<'GG'
[KNOWN-RED-GONE-GREEN] core:Fixture suite A — passed a full-set run; remove the entry from tests/known-red-suites.txt (the list may only shrink)
GG
if run_guard "${TMP}/gone-green.log" >/tmp/.krg-out.$$ 2>&1; then
  fail "case 6 (negative control): a gone-green label should be refused, but guard exited 0"
else
  if grep -q 'FAIL gone-green' /tmp/.krg-out.$$; then
    pass "case 6 (negative control): live-matching label proven green by transcript -> refused with gone-green, not silently suppressed"
  else
    fail "case 6: refused for the wrong reason: $(cat /tmp/.krg-out.$$)"
  fi
fi
rm -f /tmp/.krg-out.$$

# ── case 7: same list, clean transcript (no gone-green line) -> passes ─────
cat > "${TMP}/clean.log" <<'CLEAN'
[CORE-OFFLINE] suites passed=2 failed=0 missing=0 known_red_skipped=0 repo=fixture
CLEAN
if run_guard "${TMP}/clean.log" >/tmp/.krg-out.$$ 2>&1; then
  pass "case 7: clean transcript (no gone-green lines) -> exit 0"
else
  fail "case 7: clean transcript should pass, got: $(cat /tmp/.krg-out.$$)"
fi
rm -f /tmp/.krg-out.$$

echo
echo "test-known-red-guard.sh: pass=${PASS} fail=${FAIL}"
[[ "${FAIL}" -eq 0 ]]
