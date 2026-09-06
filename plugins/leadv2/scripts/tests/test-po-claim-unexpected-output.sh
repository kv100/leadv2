#!/usr/bin/env bash
# tests/test-po-claim-unexpected-output.sh — SET-U-ABORTS-THE-FAILURE-PATH-01
# run-all-triggers: leadv2-helpers
#
# leadv2_po_claim()'s "unexpected output from claim script" branch (the
# multi-lane parse producing an empty lane or item_id -- a real shape: a
# claim script printing "onlylane:" with nothing after the colon) used to
# reference $_env_file, a variable the function never declares. Under this
# file's own `set -euo pipefail`, that aborted the whole calling process
# with "unbound variable" before ever reaching `return 1`. Reproduced live
# 2026-09-06.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS="${SCRIPT_DIR}/../leadv2-helpers.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '[TEST] FAIL: %s -- %s\n' "$1" "${2:-}"; }

run_claim() { # <helpers_path> <fake_claim_output>
  local helpers="$1" claim_out="$2"
  local fake_root; fake_root="$(mktemp -d)"
  mkdir -p "$fake_root/scripts"
  printf '#!/usr/bin/env bash\nprintf %s\n' "'${claim_out}\n'" > "$fake_root/scripts/leadv2-queue-claim.sh"
  chmod +x "$fake_root/scripts/leadv2-queue-claim.sh"
  ( set -u
    CLAUDE_PLUGIN_ROOT="$fake_root"
    unset LEADV2_PROJECT_ROOT
    export CLAUDE_PLUGIN_ROOT
    export LEADV2_TASK_ID="repro-task"
    source "$helpers"
    leadv2_po_claim "test-claimer"
  ) >/tmp/.po-claim-stdout.$$ 2>/tmp/.po-claim-stderr.$$
  echo $?
  rm -rf "$fake_root"
}

echo "=== T1: current code (fixed) -- unparsable output returns 1 cleanly, no crash ==="
rc="$(run_claim "$HELPERS" "onlylane:")"
if [[ "$rc" == "1" ]]; then
  pass "T1a: leadv2_po_claim returns 1 (not an unbound-variable abort, rc!=1 and !=0)"
else
  fail "T1a: leadv2_po_claim returns 1" "got rc=$rc"
fi
if grep -q "unbound variable" /tmp/.po-claim-stderr.$$; then
  fail "T1b: no 'unbound variable' in stderr" "found it: $(cat /tmp/.po-claim-stderr.$$)"
else
  pass "T1b: no 'unbound variable' in stderr"
fi
if grep -q "unexpected output from claim script" /tmp/.po-claim-stderr.$$; then
  pass "T1c: the intended diagnostic still fires"
else
  fail "T1c: the intended diagnostic still fires" "stderr: $(cat /tmp/.po-claim-stderr.$$)"
fi
rm -f /tmp/.po-claim-stdout.$$ /tmp/.po-claim-stderr.$$

echo "=== T2 (negative control): pre-fix HEAD copy of leadv2-helpers.sh crashes on the same input ==="
PREFIX_COPY="$(mktemp)"
# NOTE: a `set -u` abort inside the `()` subshell and a clean `return 1`
# both surface as rc=1 to the caller (bash exits status 1 on an unbound
# reference too) -- rc alone cannot discriminate crash from clean failure.
# The stderr text is the only reliable signal, so this checks for "unbound
# variable" rather than comparing exit codes.
if git -C "$SCRIPT_DIR/../.." show "HEAD:plugins/leadv2/scripts/leadv2-helpers.sh" > "$PREFIX_COPY" 2>/dev/null \
   && grep -q '_env_file' "$PREFIX_COPY"; then
  run_claim "$PREFIX_COPY" "onlylane:" >/dev/null
  if grep -q "unbound variable" /tmp/.po-claim-stderr.$$; then
    pass "T2: pre-fix HEAD copy crashes with 'unbound variable' -- suite discriminates"
  else
    fail "T2: pre-fix HEAD copy crashes" "no 'unbound variable' in stderr: $(cat /tmp/.po-claim-stderr.$$)"
  fi
else
  # HEAD already carries the fix (this suite is being run post-commit) --
  # reconstruct the exact pre-fix line inline so the negative control still
  # runs rather than silently skipping.
  MUT="$(mktemp)"
  sed -E 's/^(    return 1)$/    rm -f "\$_env_file" || true\n\1/' "$HELPERS" > "$MUT"
  if diff -q "$HELPERS" "$MUT" >/dev/null 2>&1; then
    fail "T2: mutation applied" "sed did not change the file -- pattern did not match, mutation is a no-op"
  else
    run_claim "$MUT" "onlylane:" >/dev/null
    if grep -q "unbound variable" /tmp/.po-claim-stderr.$$; then
      pass "T2: reintroducing the \$_env_file reference crashes with 'unbound variable' -- suite discriminates"
    else
      fail "T2: reintroducing the \$_env_file reference crashes" "no 'unbound variable' in stderr: $(cat /tmp/.po-claim-stderr.$$)"
    fi
  fi
  rm -f "$MUT"
fi
rm -f "$PREFIX_COPY"

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
