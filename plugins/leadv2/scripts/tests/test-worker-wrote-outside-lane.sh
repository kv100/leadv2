#!/usr/bin/env bash
# tests/test-worker-wrote-outside-lane.sh — NESTED-AGENTS-AND-FORKS-01 (item 4)
#
# The epilogue guard: a lane whose own worktree carries NO new work while a
# DIFFERENT worktree holds a commit naming this task's sig8 means the worker
# wrote its actual output into the wrong lane. lv2_lane_wrote_outside_lane()
# (lib/leadv2-lane-guard.sh) detects it; leadv2-dispatch-ledger.sh's
# dispatch_ledger_write_terminal() journals `worker_wrote_outside_lane
# task=<sig8> path=<other>` on every successful terminal write. Both are
# purely additive/observational: the guard function never mutates state, and
# the ledger wiring never touches terminal/cause/rc -- only emits one extra
# journal line when the guard fires. Fixtures use real git worktrees; no
# canonical script beyond leadv2-lane-guard.sh is exercised, so a plain
# mktemp git repo is the fixture, not a full canonical-tree copy.
# run-all-triggers: leadv2-lane-guard leadv2-dispatch-ledger

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SH="${SCRIPT_DIR}/../lib/leadv2-lane-guard.sh"
FAIL=0

bash -n "${GUARD_SH}" || { echo "ERROR: bash -n failed for ${GUARD_SH}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

git -C "${TMP_ROOT}" init -q main-repo
MAIN="${TMP_ROOT}/main-repo"
git -C "${MAIN}" config user.email t@t
git -C "${MAIN}" config user.name t
echo x > "${MAIN}/f.txt"
git -C "${MAIN}" add .
git -C "${MAIN}" commit -qm init

OWN="${TMP_ROOT}/wt-own"
OTHER="${TMP_ROOT}/wt-other"
git -C "${MAIN}" worktree add -q "${OWN}" -b own-branch
git -C "${MAIN}" worktree add -q "${OTHER}" -b other-branch

run_check() { ( source "${GUARD_SH}"; lv2_lane_wrote_outside_lane "$1" "$2" ) ; }

# --- test 1: positive -- own worktree clean, sibling names the sig ---
# Commit is verified read-back before the check runs: this host runs under
# heavy concurrent load (control-plane watchers from other live sessions),
# and a git subprocess occasionally needs a retry before its own commit is
# visible to a fresh `git log` in the same second -- without this, the test
# flaked (rc=1) on a load spike unrelated to the function under test.
_commit_ok=0
for _try in 1 2 3; do
  ( cd "${OTHER}" && echo y > g.txt && git add . && git commit -qm "SIG1234 landed something here" >/dev/null 2>&1 )
  git -C "${OTHER}" log --oneline -n1 2>/dev/null | grep -qF "SIG1234" && { _commit_ok=1; break; }
  sleep 0.3
done
[[ ${_commit_ok} -eq 1 ]] || fail "fixture setup" "commit to wt-other never became visible after 3 tries -- unrelated to the function under test"
# Same load-noise hardening applied to the check call itself: `git status`
# on a sibling worktree of a repo mid-commit-elsewhere can transiently see
# stale/locked state under heavy host load. Retrying the CHECK, not loosening
# what it must return, keeps the assertion exact.
out="" rc=1
for _try in 1 2 3; do
  out="$(run_check SIG1234 "${OWN}")"; rc=$?
  [[ ${rc} -eq 0 && -n "${out}" ]] && break
  sleep 0.3
done
OTHER_PHYS="$(cd -P "${OTHER}" && pwd -P)"
if [[ ${rc} -eq 0 && "${out}" == "${OTHER_PHYS}" ]]; then
  pass "detects the sibling worktree that actually carries the work"
else
  fail "positive case" "rc=${rc} out='${out}' want rc=0 out='${OTHER}'"
fi

# --- test 2: negative control A -- own worktree is dirty (not this failure) ---
echo dirty > "${OWN}/dirty.txt"
out="$(run_check SIG1234 "${OWN}")"; rc=$?
if [[ ${rc} -ne 0 && -z "${out}" ]]; then
  pass "own worktree with new work is never flagged, even with a matching sibling commit"
else
  fail "dirty-own negative" "rc=${rc} out='${out}' want rc!=0 empty"
fi
rm -f "${OWN}/dirty.txt"

# --- test 3: negative control B -- no sibling names this sig ---
out="$(run_check NOMATCH999 "${OWN}")"; rc=$?
if [[ ${rc} -ne 0 && -z "${out}" ]]; then
  pass "no false positive when no sibling worktree names the sig"
else
  fail "no-match negative" "rc=${rc} out='${out}' want rc!=0 empty"
fi

# --- test 4: MUTATION CONTROL -- neutralize the check INSIDE the function
# body (never a top-level/line-number insert) and confirm the suite goes RED.
# The mutation flips the git-log grep to always match (a tautology), so the
# function reports every sibling worktree as the culprit, including one with
# no commit naming the sig at all -- proving this suite actually exercises
# the discriminating line, not just "function runs without crashing".
MUT_SH="${TMP_ROOT}/mutated-lane-guard.sh"
sed -E 's/git -C "\$\{wt\}" log --oneline -n 20 2>\/dev\/null \| grep -qF -- "\$\{sig8\}" \|\| continue/git -C "\${wt}" log --oneline -n 20 2>\/dev\/null | grep -qF -- "" || continue/' \
  "${GUARD_SH}" > "${MUT_SH}"
if diff -q "${GUARD_SH}" "${MUT_SH}" >/dev/null 2>&1; then
  fail "mutation control" "sed produced a byte-identical file -- the mutation never applied, this control proves nothing"
else
  mut_out="$(cd "${TMP_ROOT}" && source "${MUT_SH}"; lv2_lane_wrote_outside_lane NOMATCH999 "${OWN}")"; mut_rc=$?
  if [[ ${mut_rc} -eq 0 && -n "${mut_out}" ]]; then
    pass "MUTATION CONTROL: neutering the sig-match check inside the function body flips the no-match case to a false positive (suite would go red)"
  else
    fail "mutation control" "mutated function still returned rc=${mut_rc} out='${mut_out}' -- mutation did not neutralize the check as intended"
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-worker-wrote-outside-lane.sh"
  exit 0
else
  echo "SOME FAILED: test-worker-wrote-outside-lane.sh"
  exit 1
fi
