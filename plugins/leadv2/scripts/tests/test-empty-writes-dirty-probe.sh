#!/usr/bin/env bash
# tests/test-empty-writes-dirty-probe.sh — LANE-WRITES-IS-EMPTY-98-PERCENT-01 item 4
#
# _dl_derive_lane_state's dirty-tree probe (leadv2-dispatch-ledger.sh) built its
# pathspec from lane_writes and only ran the probe when that pathspec was
# non-empty. An empty lane_writes -- ~70% of real dispatches per this row's own
# premise recheck -- meant `dirty` stayed 0 UNCONDITIONALLY: a worker that died
# holding real uncommitted bytes in a lane with no declared writes was stamped
# plain `dead` (bytes silently discarded) instead of `dead_with_unlanded_work`
# (the shape the reap funnel exists to rescue). Fixed by falling back to an
# UNSCOPED status probe on the lane's OWN worktree when the pathspec is empty
# -- safe because `repo` here is never the shared main checkout, only this
# lane's isolated worktree -- filtered through the same
# _PC_PORCELAIN_EXCLUDE_RE every other containment check in this codebase uses
# to exclude dispatcher bookkeeping paths.
# run-all-triggers: leadv2-dispatch-ledger

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="${SCRIPT_DIR}/../leadv2-dispatch-ledger.sh"
LANE_GUARD="${SCRIPT_DIR}/../lib/leadv2-lane-guard.sh"
FAIL=0

bash -n "${LEDGER}" || { echo "ERROR: bash -n failed for ${LEDGER}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

REPO="${TMP_ROOT}/lane-repo"
git init -q "${REPO}"
git -C "${REPO}" config user.email t@t
git -C "${REPO}" config user.name t
echo x > "${REPO}/f.txt"
git -C "${REPO}" add .
git -C "${REPO}" commit -qm init

run_derive() { # <writes_csv> <verdict>
  ( source "${LEDGER}" >/dev/null 2>&1
    source "${LANE_GUARD}"
    LEADV2_RECONCILE_VERDICT="$2" _dl_derive_lane_state "${REPO}" "" "$1" "" "test-lane-01" ""
  )
}

# --- test 1: empty writes_csv, worker died (dead:*), tree IS dirty ---
# -> must rescue as dead_with_unlanded_work, never plain dead.
echo dirty > "${REPO}/untracked.txt"
out1="$(run_derive "" "dead:wedged")"
if [[ "${out1}" == dead_with_unlanded_work* ]]; then
  pass "empty writes_csv + dirty tree + dead worker -> rescued as dead_with_unlanded_work (bytes not discarded)"
else
  fail "dirty rescue with empty writes_csv" "got '${out1}' want dead_with_unlanded_work*"
fi

# --- test 2: empty writes_csv, worker died, tree is genuinely clean ---
# -> plain dead is correct (nothing to rescue).
rm -f "${REPO}/untracked.txt"
out2="$(run_derive "" "dead:wedged")"
if [[ "${out2}" == "dead"$'\x1f'* ]]; then
  pass "empty writes_csv + clean tree + dead worker -> plain dead (nothing to falsely rescue)"
else
  fail "clean-tree negative" "got '${out2}' want plain dead (not dead_with_unlanded_work)"
fi

# --- test 3: dispatcher bookkeeping alone (docs/handoff/, docs/leadv2/) must
# NOT count as dirty -- the exclusion this fix reuses must still apply on the
# unscoped fallback path, same as it does on the pathspec'd path.
mkdir -p "${REPO}/docs/handoff/dispatch-xyz" "${REPO}/docs/leadv2"
echo bookkeeping > "${REPO}/docs/handoff/dispatch-xyz/note.md"
echo bookkeeping > "${REPO}/docs/leadv2/scratch.md"
out3="$(run_derive "" "dead:wedged")"
if [[ "${out3}" == "dead"$'\x1f'* ]]; then
  pass "dispatcher bookkeeping alone (docs/handoff, docs/leadv2) is never mistaken for real dirt"
else
  fail "bookkeeping-exclusion negative" "got '${out3}' want plain dead"
fi
rm -rf "${REPO}/docs"

# --- test 4: MUTATION CONTROL -- neuter the fallback INSIDE the function
# body (never a top-level/line-number insert): force the new elif branch's
# condition to never fire, restoring the original bug. Confirms this suite
# actually exercises the fallback, not just "function runs".
MUT_SH="${TMP_ROOT}/mutated-ledger.sh"
sed -E 's/elif \[\[ -z "\$\{writes_csv\}" \]\]; then/elif false; then/' "${LEDGER}" > "${MUT_SH}"
if diff -q "${LEDGER}" "${MUT_SH}" >/dev/null 2>&1; then
  fail "mutation control" "sed produced a byte-identical file -- the mutation never applied, this control proves nothing"
else
  echo dirty > "${REPO}/untracked.txt"
  mut_out="$( ( source "${MUT_SH}" >/dev/null 2>&1
    source "${LANE_GUARD}"
    LEADV2_RECONCILE_VERDICT="dead:wedged" _dl_derive_lane_state "${REPO}" "" "" "" "test-lane-01" "" ) )"
  rm -f "${REPO}/untracked.txt"
  if [[ "${mut_out}" == "dead"$'\x1f'* ]]; then
    pass "MUTATION CONTROL: neutering the empty-writes fallback inside the function body reintroduces the discard-real-bytes bug (suite would go red)"
  else
    fail "mutation control" "mutated function still returned '${mut_out}' -- mutation did not neutralize the fix as intended"
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-empty-writes-dirty-probe.sh"
  exit 0
else
  echo "SOME FAILED: test-empty-writes-dirty-probe.sh"
  exit 1
fi
