#!/usr/bin/env bash
# test-journal-honours-the-pinned-root.sh — TESTS-POLLUTE-REAL-JOURNAL-01
#
# Subject: the REAL leadv2-journal.sh, invoked as the product invokes it.
# Faked one level lower: throwaway git repos standing in for checkouts.
#
# The measured defect: docs/leadv2/tasks/dispatch-WSOTEST2/journal.md exists in
# the live leadv2 checkout, written by test-writeset-pending-overlap.sh -- a
# suite that pins LEADV2_PROJECT_ROOT on every one of its call sites. The pin
# was ignored: the resolution chain was CLAUDE_PROJECT_ROOT > CLAUDE_PROJECT_DIR
# > cwd, and LEADV2_PROJECT_ROOT was not in it at all, so the write fell through
# to the cwd repo -- the real one.
#
# DECLARED NEGATIVE CONTROLS (apply INSIDE leadv2-journal.sh; each must turn
# this suite RED):
#   N1  delete the LEADV2_PROJECT_ROOT rung from both sites => case (b) fails:
#       a pinned root falls through to cwd again.
#   N2  move the rung AHEAD of CLAUDE_PROJECT_ROOT => case (a) fails: an
#       ambient LEADV2_PROJECT_ROOT overrides an explicit CLAUDE_* pin, which is
#       the foreign-root regression this ordering exists to avoid.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL="${LEADV2_JOURNAL_SH:-${SCRIPT_DIR}/../leadv2-journal.sh}"
[[ -f "${JOURNAL}" ]] || { echo "FATAL: journal script not found: ${JOURNAL}" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journal-root.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT

mkrepo() { # <dir>
  mkdir -p "$1" && git init -q "$1" >/dev/null 2>&1 || return 1
  git -C "$1" config user.email t@t.local; git -C "$1" config user.name t
  printf 'x\n' > "$1/f.txt"; git -C "$1" add f.txt >/dev/null 2>&1
  git -C "$1" commit -qm base >/dev/null 2>&1
}
CWD_REPO="${WORK}/cwd-repo"; PINNED="${WORK}/pinned"; CLAUDE_ROOT="${WORK}/claude-root"
mkrepo "${CWD_REPO}" || { echo FATAL; exit 2; }
mkrepo "${PINNED}"   || { echo FATAL; exit 2; }
mkrepo "${CLAUDE_ROOT}" || { echo FATAL; exit 2; }

# Every case runs FROM the cwd repo -- that is the trap: the cwd repo stands in
# for the real checkout a suite must never write into.
jpath() { # <env assignments...> -> resolved journal path
  ( cd "${CWD_REPO}" && env "$@" bash "${JOURNAL}" path fixture-task 2>/dev/null )
}
# The journal does NOT live inside the repo: leadv2-state-path.sh maps a root to
# a central control-plane directory keyed by that root's basename
# (~/.claude/leadv2-state/<key>/tasks/...), identical from every worktree of the
# same repo. So "did the pin win" is answered by which KEY the path carries, not
# by filesystem containment. Measured while writing this suite -- the first
# version asserted containment and failed for its own reason, not the product's.
keyed() { case "$2" in */"$1"/tasks/*) return 0;; *) return 1;; esac; }

echo "== the journal writes where the caller pinned it"

# (b) the new property: a LEADV2_PROJECT_ROOT pin is honoured, not ignored.
P="$(jpath LEADV2_PROJECT_ROOT="${PINNED}")"
if keyed pinned "${P}"; then
  ok "(b) LEADV2_PROJECT_ROOT alone -> the pinned root, not cwd"
else
  bad "(b) pin ignored, resolved to '${P}'"
fi

# (a) NEG-CTL: an explicit CLAUDE_* pin still wins. Production sets it on
#     purpose so a foreign-root dispatch cannot land in the losing repo.
P="$(jpath CLAUDE_PROJECT_ROOT="${CLAUDE_ROOT}" LEADV2_PROJECT_ROOT="${PINNED}")"
if keyed claude-root "${P}"; then
  ok "(a) NEG-CTL: CLAUDE_PROJECT_ROOT still outranks LEADV2_PROJECT_ROOT"
else
  bad "(a) NEG-CTL: the new rung overrode an explicit CLAUDE_* pin -> '${P}'"
fi
P="$(jpath CLAUDE_PROJECT_DIR="${CLAUDE_ROOT}" LEADV2_PROJECT_ROOT="${PINNED}")"
if keyed claude-root "${P}"; then
  ok "(a2) NEG-CTL: CLAUDE_PROJECT_DIR too"
else
  bad "(a2) NEG-CTL: rung overrode CLAUDE_PROJECT_DIR -> '${P}'"
fi

# (c) with nothing pinned, the pre-existing resolution is untouched -- whatever
#     it resolves to, it must not be the pinned key.
P="$(jpath LEADV2_UNUSED=1)"
if keyed pinned "${P}"; then
  bad "(c) nothing pinned, yet it resolved to the pinned key: '${P}'"
else
  ok "(c) nothing pinned -> prior resolution unchanged"
fi

# (d) the whole point, end to end: a real append must not touch the cwd repo.
echo "== a real write, and the repo it must not touch"
( cd "${CWD_REPO}" && LEADV2_PROJECT_ROOT="${PINNED}" \
    bash "${JOURNAL}" append fixture-task note "pinned-root write" ) >/dev/null 2>&1
LEAK="$(find "${CWD_REPO}" -name 'journal.md' 2>/dev/null | wc -l | tr -d ' ')"
WROTE="$( cd "${CWD_REPO}" && LEADV2_PROJECT_ROOT="${PINNED}" bash "${JOURNAL}" path fixture-task 2>/dev/null )"
LANDED=0
[[ -n "${WROTE}" && -f "${WROTE}" ]] && LANDED=1
if [[ "${LEAK}" == "0" ]]; then
  ok "(d) nothing written into the cwd repo"
else
  bad "(d) ${LEAK} journal(s) leaked into the cwd repo — the live-tree pollution"
fi
if [[ "${LANDED}" != "0" ]] && grep -q 'pinned-root write' "${WROTE}" 2>/dev/null; then
  ok "(e) the line landed at the pinned root's own address"
else
  bad "(e) the append wrote nowhere readable ('${WROTE}') — a silent write is not a fix"
fi

echo
echo "passed=${PASS} failed=${FAIL}"
[[ ${FAIL} -eq 0 ]]
