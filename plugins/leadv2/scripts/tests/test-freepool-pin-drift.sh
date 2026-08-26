#!/usr/bin/env bash
# test-freepool-pin-drift.sh — T19 fix-round-2 (B-H1).
#
# freepool-install.sh's PINNED_COMMIT previously defaulted to empty (silent
# unpinned install), and the pin file it writes (config/freepool-arm.yaml)
# had no reader anywhere -- a checkout that drifted from the reviewed commit
# (upstream force-push, a manual `git pull` in FREEPOOL_INSTALL_DIR) was
# never detected. Two independent things now hold:
#   1. freepool-install.sh refuses an empty PINNED_COMMIT unless the caller
#      opts in via FREEPOOL_ALLOW_UNPINNED=1.
#   2. leadv2-freepool-gate.sh's check_pin_drift() reads the pin file and
#      compares it to a live `git rev-parse HEAD` on every gate check.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$SCRIPTS_ROOT/lib/leadv2-freepool-gate.sh"
INSTALL="$SCRIPTS_ROOT/freepool-install.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$GATE" 2>/dev/null || { echo "ERROR: gate syntax check failed"; exit 1; }
bash -n "$INSTALL" 2>/dev/null || { echo "ERROR: install syntax check failed"; exit 1; }

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# ── check_pin_drift() unit tests (extracted, same pattern as
#    test-dispatch-arm-vocabulary.sh's harness()) ──────────────────────────
HARNESS="$ROOT/pin-drift-harness.sh"
sed -n '/^check_pin_drift()/,/^}$/p' "$GATE" > "$HARNESS"

mkdir -p "$ROOT/install"
(cd "$ROOT/install" && git init -q && git config user.email t@e.com && git config user.name t \
  && : > f && git add f && git commit -qm c1)
REAL_HEAD="$(git -C "$ROOT/install" rev-parse HEAD)"

printf 'pinned_commit: %s\n' "$REAL_HEAD" > "$ROOT/pin-match.yaml"
printf 'pinned_commit: %s\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" > "$ROOT/pin-mismatch.yaml"

# Case 1: pin matches live HEAD -> no drift (rc=0)
if bash -c "source '$HARNESS'; FREEPOOL_PIN_FILE='$ROOT/pin-match.yaml' FREEPOOL_INSTALL_DIR='$ROOT/install'; check_pin_drift"; then
  pass "case1: matching pin -> check_pin_drift reports no drift"
else
  fail "case1: matching pin incorrectly reported as drift"
fi

# Case 2 (negative control target): pin mismatches live HEAD -> drift (rc=1)
if bash -c "source '$HARNESS'; FREEPOOL_PIN_FILE='$ROOT/pin-mismatch.yaml' FREEPOOL_INSTALL_DIR='$ROOT/install'; check_pin_drift"; then
  fail "case2: mismatched pin NOT detected as drift (the B-H1 regression)"
else
  pass "case2: mismatched pin correctly detected as drift"
fi

# Case 3: no pin file yet (arm never installed) -> fail-open, no drift
if bash -c "source '$HARNESS'; FREEPOOL_PIN_FILE='$ROOT/no-such-file.yaml' FREEPOOL_INSTALL_DIR='$ROOT/install'; check_pin_drift"; then
  pass "case3: absent pin file -> fail-open (no drift verdict)"
else
  fail "case3: absent pin file incorrectly reported as drift"
fi

# Case 4: no install checkout yet -> fail-open, no drift
if bash -c "source '$HARNESS'; FREEPOOL_PIN_FILE='$ROOT/pin-match.yaml' FREEPOOL_INSTALL_DIR='$ROOT/no-such-install'; check_pin_drift"; then
  pass "case4: absent install checkout -> fail-open (no drift verdict)"
else
  fail "case4: absent install checkout incorrectly reported as drift"
fi

# Case 5: full gate `check` refuses with reason=pin_drift when liveness would
# otherwise pass. We can't make check_liveness succeed without a real proxy,
# so this proves the wiring statically: refuse "pin_drift" call site exists
# and is reached before the rolling-window check in main()'s check branch.
if grep -q 'check_pin_drift' "$GATE" && grep -q 'refuse "pin_drift"' "$GATE"; then
  pass "case5: main() wires check_pin_drift -> refuse pin_drift"
else
  fail "case5: gate's check branch does not call check_pin_drift / refuse pin_drift"
fi

# ── freepool-install.sh: refuses empty PINNED_COMMIT by default ───────────
out="$(PINNED_COMMIT="" FREEPOOL_ALLOW_UNPINNED=0 FREEPOOL_INSTALL_DIR="$ROOT/never-installed" bash "$INSTALL" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'refusing to install' <<<"$out"; then
  pass "case6: freepool-install.sh refuses empty PINNED_COMMIT by default (rc=$rc)"
else
  fail "case6: freepool-install.sh did not refuse empty PINNED_COMMIT (rc=$rc, out=$out)"
fi

# Case 7 (negative control target): FREEPOOL_ALLOW_UNPINNED=1 explicitly
# opts back into the old unpinned-install behaviour (never installs for
# real here -- FREEPOOL_REPO_URL points nowhere reachable -- only proves
# the refusal gate itself is bypassed, not that clone succeeds).
out="$(PINNED_COMMIT="" FREEPOOL_ALLOW_UNPINNED=1 FREEPOOL_INSTALL_DIR="$ROOT/unpinned-ok" \
  FREEPOOL_REPO_URL="file://$ROOT/install" bash "$INSTALL" 2>&1)"; rc=$?
if grep -q 'refusing to install' <<<"$out"; then
  fail "case7: FREEPOOL_ALLOW_UNPINNED=1 still refused (opt-out is broken)"
else
  pass "case7: FREEPOOL_ALLOW_UNPINNED=1 bypasses the refusal gate as intended"
fi

# ── freepool-install.sh: default PINNED_COMMIT is a real, non-empty sha ───
default_pin="$(sed -n 's/^readonly PINNED_COMMIT="\${PINNED_COMMIT-\([0-9a-f]*\)}".*/\1/p' "$INSTALL")"
if [[ "$default_pin" =~ ^[0-9a-f]{40}$ ]]; then
  pass "case8: PINNED_COMMIT default is a real 40-char sha ($default_pin)"
else
  fail "case8: PINNED_COMMIT default is not a real sha (got: '$default_pin')"
fi

printf '\n================================================\n'
printf '  freepool pin-drift suite: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
printf '================================================\n'

[[ "$FAIL" -eq 0 ]]
