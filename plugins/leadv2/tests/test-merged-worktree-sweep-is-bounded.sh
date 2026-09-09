#!/usr/bin/env bash
# run-all-triggers: leadv2-merged-worktree-sweep hooks.json
# SessionStart must not run orphan recovery: it can walk every lane and was the
# measured seven-minute startup cost.  The hook still sweeps merged lanes, but
# a registered lane is untouchable.
#
# Negative controls, run with leadv2-mutation-control.sh after this suite is
# committed:
#   session-start-orphan-mut-1: make the opt-in condition true -> the fake
#     two-second checkpointer exceeds the one-second SessionStart budget.
#   sweep-protection-mut-1: replace the shared protection check with true -> a
#     registered worktree is removed from the scratch fixture.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HOOK="${LEADV2_TEST_SWEEP_HOOK:-${ROOT}/plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh}"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/merged-sweep-bound.XXXXXX")" || exit 1
trap 'rm -rf "${TMP}"' EXIT

make_repo() { # <path>
  local repo="$1"
  mkdir -p "${repo}"
  git -C "${repo}" init -q -b main || return 1
  git -C "${repo}" config user.email test@local
  git -C "${repo}" config user.name test
  printf 'seed\n' > "${repo}/seed.txt"
  git -C "${repo}" add seed.txt && git -C "${repo}" commit -qm seed
  mkdir -p "${repo}/state"
  printf 'sessions: []\n' > "${repo}/state/active.yaml"
}

run_hook() { # <repo> <checkpoint-bin> -> elapsed seconds
  local repo="$1" checkpoint="$2" started ended
  started="$(python3 -c 'import time; print(time.time())')"
  LEADV2_STATE_ROOT="${repo}/state" \
  LEADV2_SWEEP_MIN_AGE_S=0 \
  LEADV2_ORPHAN_CHECKPOINT_BIN="${checkpoint}" \
  CLAUDE_PROJECT_DIR="${repo}" \
  bash "${HOOK}" >/dev/null 2>"${repo}/hook.err"
  ended="$(python3 -c 'import time; print(time.time())')"
  python3 - "${started}" "${ended}" <<'PY'
import sys
print(float(sys.argv[2]) - float(sys.argv[1]))
PY
}

checkpoint="${TMP}/slow-checkpoint.sh"
marker="${TMP}/checkpoint-ran"
printf '%s\n' '#!/usr/bin/env bash' "printf ran > '${marker}'" 'sleep 2' > "${checkpoint}"
chmod +x "${checkpoint}"

# Symptom: default SessionStart never calls the expensive recovery walker and
# returns within a one-second budget on an otherwise empty fixture repo.
budget_repo="${TMP}/budget"
make_repo "${budget_repo}" || { fail 'budget fixture setup'; exit 1; }
elapsed="$(run_hook "${budget_repo}" "${checkpoint}")"; run_rc=$?
if [[ "${run_rc}" == 0 ]]; then pass 'budget fixture hook exits 0'; else fail "budget fixture hook rc=${run_rc}"; fi
python3 - "${elapsed}" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) < 1.0 else 1)
PY
[[ $? == 0 ]] && pass "SessionStart budget <1s (${elapsed}s)" || fail "SessionStart exceeded 1s (${elapsed}s)"
[[ ! -e "${marker}" ]] && pass 'default path does not invoke orphan checkpoint' || fail 'orphan checkpoint ran on default SessionStart'

# Guard: a registered lane must survive the unchanged fast path.  The fixture
# starts old and clean so active.yaml is the only protection, not age or dirt.
guard_repo="${TMP}/guard"
make_repo "${guard_repo}" || { fail 'guard fixture setup'; exit 1; }
mkdir -p "${guard_repo}/.claude/worktrees"
lane="${guard_repo}/.claude/worktrees/registered"
git -C "${guard_repo}" worktree add -q -b registered "${lane}" main || fail 'guard worktree creation'
cat > "${guard_repo}/state/active.yaml" <<YAML
sessions:
  - task_id: registered
    worktree: ${lane}
YAML
touch -t 202001010000 "${lane}" "$(git -C "${lane}" rev-parse --git-dir)/gitdir" 2>/dev/null || true
run_hook "${guard_repo}" "${checkpoint}" >/dev/null; guard_rc=$?
[[ "${guard_rc}" == 0 ]] && pass 'registered-lane hook exits 0' || fail "registered-lane hook rc=${guard_rc}"
[[ -d "${lane}" ]] && pass 'registered lane survives sweep' || fail 'registered lane was removed'

if [[ "${FAIL}" != 0 ]]; then
  printf 'FAILURES=%s PASSES=%s\n' "${FAIL}" "${PASS}" >&2
  exit 1
fi
printf 'PASS: merged-worktree-sweep bounded (%s assertions)\n' "${PASS}"
