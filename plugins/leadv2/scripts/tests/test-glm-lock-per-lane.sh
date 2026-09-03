#!/usr/bin/env bash
# tests/test-glm-lock-per-lane.sh — GLM-ARM-THROUGHPUT-01.
#
# glm-coder.sh's GLM arm lock guards a WORKING TREE, not a repository:
#   (a)  two `bg` calls in two worktrees of ONE repo must BOTH acquire
#        (the 2026-09-01 incident: four lanes in ~/Projects/leadv2, 3 of 4
#        dispatches refused glm_refused_lock_busy and burned Claude quota);
#   (b)  two `bg` calls in the SAME worktree must NOT — second is rc 75 with
#        the LEADV2_DISPATCH_REFUSED: lock_busy admission marker (the
#        dispatcher's refusal_reason() contract), including from a SUBDIR of
#        the occupied worktree (the key resolves the git worktree root, not
#        the raw cwd string);
#   (c)  the MAIN checkout keeps its repo-wide lock: a second run there —
#        from the root or any subdir — is still refused.
#
# Hermetic: GLM_RUNS_DIR + LEADV2_GLM_LOCK_ROOT at temp dirs, a stub `claude`
# that sleeps (keeps the lock held), GLM_SKIP_QUOTA_GATE=1, no network.
#
# Negative-control seam: GLM_LOCK_SUITE_SCRIPT overrides the launcher under
# test (default: the real glm-coder.sh) so the repo-only-key mutation can be
# proven RED against a scratch copy without touching the working tree.
#
# Run: bash plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${GLM_LOCK_SUITE_SCRIPT:-${PLUGIN_SCRIPTS}/glm-coder.sh}"

export LEADV2_BURN_GOVERNOR=0 LEADV2_ALLOW_FG_DISPATCH=1

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-lock-lane.XXXXXX")"
cleanup() {
  # Kill whatever the fixture launchers left behind (children run as session
  # leaders; their pids are in each run dir / lock dir), then remove the tree.
  local f pid
  for f in "${FIXTURE}"/runs/pgid "${FIXTURE}"/locks/.lock-*/pgid "${FIXTURE}"/locks/.lock-*/pid; do
    [[ -f "${f}" ]] || continue
    pid="$(cat "${f}" 2>/dev/null || true)"
    [[ -n "${pid}" ]] && kill -TERM -"${pid}" 2>/dev/null || true
    [[ -n "${pid}" ]] && kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  rm -rf "${FIXTURE}"
}
trap cleanup EXIT INT TERM

# ── syntax floor (bash + the macOS 3.2 binary the lanes actually run) ───────
if bash -n "${GLM_SCRIPT}" 2>/dev/null && /bin/bash -n "${GLM_SCRIPT}" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: bash -n glm-coder.sh (incl. 3.2)"
else
  FAIL=$((FAIL + 1)); log "FAIL: bash -n glm-coder.sh"
fi

# ── dependency floor (round 2): an assertion that cannot run is FAIL, never a
# skip. Every tool the assertions read state through must be present AND
# functional; a missing or sabotaged tool means the suite exits red — a green
# run must certify that the assertion tools could actually assert.
if command -v grep >/dev/null 2>&1 \
   && printf 'leadv2-dep-floor-probe\n' | grep -q 'leadv2-dep-floor-probe' 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: dep floor: grep present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: grep missing or non-functional (cannot match a literal)"
fi
if git --version >/dev/null 2>&1; then
  PASS=$((PASS + 1)); log "PASS: dep floor: git present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: git missing or non-functional"
fi
if python3 -c 'pass' >/dev/null 2>&1; then
  PASS=$((PASS + 1)); log "PASS: dep floor: python3 present and functional"
else
  FAIL=$((FAIL + 1)); log "FAIL: dep floor: python3 missing or non-functional (mutation control needs it)"
fi
if [[ "${FAIL}" -ne 0 ]]; then
  printf -- '[TEST] %s: %d passed, %d failed\n' "test-glm-lock-per-lane" "${PASS}" "${FAIL}"
  exit 1
fi

# ── fixture: repo with two linked worktrees, stub claude, hermetic env ──────
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=lock@test -c user.name=lock commit -q --allow-empty -m init 2>/dev/null || true
git -C "${REPO}" worktree add -q "${FIXTURE}/wt-a" -b wt-a 2>/dev/null || true
git -C "${REPO}" worktree add -q "${FIXTURE}/wt-b" -b wt-b 2>/dev/null || true
mkdir -p "${FIXTURE}/wt-a/sub"
# Fixture floor: if git could not build the repo/worktrees, every later case
# would fail for a fixture reason — name it now instead of letting it pass as
# "both acquire" on absent directories.
for d in "${REPO}/.git" "${FIXTURE}/wt-a" "${FIXTURE}/wt-b"; do
  if [[ -e "${d}" ]]; then
    PASS=$((PASS + 1)); log "PASS: fixture floor: ${d} exists"
  else
    FAIL=$((FAIL + 1)); log "FAIL: fixture floor: ${d} missing (git fixture setup failed)"
  fi
done

STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/claude" <<'STUBEOF'
#!/usr/bin/env bash
# Sleep: the run stays "active" so the lock is held for the whole suite.
sleep 120
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
export GLM_SECRETS_FILE="${SECRETS}"
export GLM_RUNS_DIR="${FIXTURE}/runs"
export LEADV2_GLM_LOCK_ROOT="${FIXTURE}/locks"
export GLM_SKIP_QUOTA_GATE=1
export TMPDIR="${FIXTURE}"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"

# bg_rc <cwd> — launches bg, echoes "rc<TAB>handle" (handle empty on refusal).
bg_rc() {
  local out rc=0
  out="$(bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "$1" --timeout 60 2>/dev/null)" || rc=$?
  printf 'rc%s\t%s\n' "${rc}" "${out}"
}

# ── Case (a): two worktrees of one repo BOTH acquire ────────────────────────
a1="$(bg_rc "${FIXTURE}/wt-a")"; a2="$(bg_rc "${FIXTURE}/wt-b")"
if [[ "${a1}" == rc0* && -n "${a1#rc0	}" && "${a2}" == rc0* && -n "${a2#rc0	}" ]]; then
  pass "(a) two worktrees of one repo both acquire (${a1#rc0	}, ${a2#rc0	})"
else
  fail "(a) worktree serialization survived: a1=[${a1}] a2=[${a2}]"
fi

# ── Case (a2): the acquisitions above are REAL on disk — the lock dirs under
# the hermetic lock root must exist and each name a LIVE holder pid. This is
# the on-disk state the refusals below are adjudicated on; unreadable or dead
# holder state is a FAIL, not a skip.
holder_live=0; holder_total=0
for pf in "${FIXTURE}"/locks/.lock-*/pid; do
  [[ -f "${pf}" ]] || continue
  holder_total=$((holder_total + 1))
  hpid="$(cat "${pf}" 2>/dev/null || true)"
  if [[ -n "${hpid}" ]] && kill -0 "${hpid}" 2>/dev/null; then
    holder_live=$((holder_live + 1))
  fi
done
if [[ "${holder_total}" -ge 2 && "${holder_live}" -eq "${holder_total}" ]]; then
  pass "(a2) lock dirs on disk name live holder pids (${holder_live}/${holder_total})"
else
  fail "(a2) lock-dir pid files unreadable or dead: live=${holder_live} total=${holder_total}"
fi

# ── Case (b): same worktree second run refused, rc 75 + admission marker ────
# The marker is asserted with grep on the captured stderr FILE, so the check
# is load-bearing through the tool it names: a grep that cannot read the file
# fails this case (never resolves as pass).
b_err_file="${FIXTURE}/b.err"
bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "${FIXTURE}/wt-a" --timeout 60 > /dev/null 2> "${b_err_file}"; b_rc=$?
if [[ "${b_rc}" == "75" ]] && grep -q 'LEADV2_DISPATCH_REFUSED: lock_busy' "${b_err_file}" 2>/dev/null; then
  pass "(b) same-worktree second bg: rc 75 + lock_busy marker"
else
  fail "(b) same-worktree second bg: rc=${b_rc} err=$(tail -2 "${b_err_file}" 2>/dev/null | tr '\n' ' ')"
fi

# ── Case (b2): a SUBDIR of the occupied worktree shares its lock key ────────
b2_err_file="${FIXTURE}/b2.err"
bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "${FIXTURE}/wt-a/sub" --timeout 60 > /dev/null 2> "${b2_err_file}"; b2_rc=$?
if [[ "${b2_rc}" == "75" ]] && grep -q 'LEADV2_DISPATCH_REFUSED: lock_busy' "${b2_err_file}" 2>/dev/null; then
  pass "(b2) subdir of occupied worktree refused (key resolves the worktree root, not the cwd string)"
else
  fail "(b2) subdir escaped the worktree lock: rc=${b2_rc}"
fi

# ── Case (c): main checkout keeps its repo-wide lock ────────────────────────
c1="$(bg_rc "${REPO}")"
if [[ "${c1}" == rc0* && -n "${c1#rc0	}" ]]; then
  pass "(c) main checkout acquires when a worktree run is live (${c1#rc0	})"
else
  fail "(c) main checkout wrongly blocked by a worktree run: [${c1}]"
fi
c2_err_file="${FIXTURE}/c2.err"
bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "${REPO}" --timeout 60 > /dev/null 2> "${c2_err_file}"; c2_rc=$?
c3_rc=0
bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "${REPO}/nonexistent-sub" --timeout 60 >/dev/null 2>&1 || c3_rc=$?
# nonexistent-sub can't launch (cwd check), so prove the subdir rule from a
# real subdir of the main checkout instead:
mkdir -p "${REPO}/sub"
bash "${GLM_SCRIPT}" bg "lock probe mission" --cwd "${REPO}/sub" --timeout 60 >/dev/null 2>&1 || c3_rc=$?
if [[ "${c2_rc}" == "75" && "${c3_rc}" == "75" ]] && grep -q 'LEADV2_DISPATCH_REFUSED: lock_busy' "${c2_err_file}" 2>/dev/null; then
  pass "(c) main checkout stays repo-wide: second run at root AND at a subdir refused"
else
  fail "(c) main-checkout repo lock lost: root rc=${c2_rc} subdir rc=${c3_rc}"
fi

# ── Mutation negative control: revert the lock key to repo-only (drop the
# main-vs-worktree toplevel branch, collapsing every worktree of a repo onto
# ONE key -- the exact pre-fix bug: "ONE per-repo GLM lock serialises every
# lane") and prove case (a) goes RED against a scratch copy -- never against
# the working tree, never via git stash/reset. A SEPARATE fixture repo (not
# REPO) with its own two worktrees, so the long-sleeping locks cases (a)/(b)/
# (c) above are still holding on REPO's key cannot confound it.
REPO2="${FIXTURE}/repo2"
mkdir -p "${REPO2}"
git -C "${REPO2}" init -q
git -C "${REPO2}" -c user.email=lock2@test -c user.name=lock2 commit -q --allow-empty -m init
git -C "${REPO2}" worktree add -q "${FIXTURE}/wt-c" -b wt-c 2>/dev/null || true
git -C "${REPO2}" worktree add -q "${FIXTURE}/wt-d" -b wt-d 2>/dev/null || true
MUT_SCRIPT="${FIXTURE}/glm-coder.mutated.sh"
cp "${GLM_SCRIPT}" "${MUT_SCRIPT}"
python3 - "${MUT_SCRIPT}" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
needle = '''  if [[ "$(dirname "${common_abs}")" == "${toplevel}" ]]; then
    key="${common_abs}"
  else
    key="${common_abs}|${toplevel}"
  fi
'''
replacement = '  key="${common_abs}"\n'
assert needle in src, "glm_lock_key_for branch not found -- fixture drifted from source"
src = src.replace(needle, replacement, 1)
open(path, 'w').write(src)
PYEOF
chmod +x "${MUT_SCRIPT}"
# The mutation MUST be verified applied before the control asserts anything:
# if python3 was missing/broken the heredoc above silently no-ops and the
# "control" would judge an UNMUTATED copy — fail that loudly instead.
if grep -Fq 'key="${common_abs}|${toplevel}"' "${MUT_SCRIPT}" 2>/dev/null; then
  fail "mutation_control: mutation NOT applied (python3 broken or needle drifted from source) — control invalid"
elif ! grep -Fq 'key="${common_abs}"' "${MUT_SCRIPT}" 2>/dev/null; then
  fail "mutation_control: mutated key line not found in scratch copy — control invalid"
else
mut1="$(GLM_LOCK_SUITE_SCRIPT="${MUT_SCRIPT}" bash -c 'out="$(bash "$1" bg "lock probe mission" --cwd "$2" --timeout 60 2>/dev/null)"; rc=$?; printf "rc%s\t%s\n" "$rc" "$out"' _ "${MUT_SCRIPT}" "${FIXTURE}/wt-c")"
mut2_rc=0
bash "${MUT_SCRIPT}" bg "lock probe mission" --cwd "${FIXTURE}/wt-d" --timeout 60 >/dev/null 2>&1 || mut2_rc=$?
if [[ "${mut1}" == rc0* && "${mut2_rc}" == "75" ]]; then
  pass "mutation_control_repo_only_key_collides_across_worktrees (RED reproduced — confirms case (a) actually exercises the fix)"
else
  fail "mutation_control_repo_only_key_collides_across_worktrees: expected mut1 rc0 + mut2_rc 75 (collision), got mut1=[${mut1}] mut2_rc=${mut2_rc}"
fi
fi

printf -- '[TEST] %s: %d passed, %d failed\n' "test-glm-lock-per-lane" "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
