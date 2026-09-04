#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code leadv2-state-path
# tests/test-fixture-state-leak-guard.sh -- SUITES-MUTATE-LIVE-CONTROL-PLANE-01.
#
# THE INCIDENT this guards: a fixture suite that `git init`s (or `git -C
# <tmp> init`s) a throwaway repo and then invokes leadv2-dispatch-code.sh
# with CLAUDE_PROJECT_ROOT/PROJECT_ROOT/LEADV2_PROJECT_ROOT pointed at that
# fixture, WITHOUT ever `cd`-ing the test process into it, hits
# FOREIGN-PROJECT-ROOT-GUARD-01 (leadv2-dispatch-code.sh:299-456): cwd's git
# toplevel (the real checkout the suite happens to be invoked from) and the
# env root (the fixture) disagree, no --resume-lane/--worktree pin proves
# the fixture legitimate, so the guard silently DISCARDS the fixture root
# and reroots the whole run at cwd -- printing only a stderr WARN nobody
# greps for. leadv2-state-path.sh then resolves the control-plane root via
# git-common-dir of that REAL cwd repo, landing every write
# (active.yaml/bus.jsonl/merge-queue.jsonl/journal) in the SAME shared
# ~/.claude/leadv2-state/<repo-slug>/ every live /leadv2 session uses.
# Confirmed source of one contaminated dimension already: 1773 of the
# arbiter's `all_arms_capped` journal rows were e2e-gate sandbox lines that
# leaked into the shared journal this exact way (see report.md).
#
# leadv2-state-path.sh's own B1 safety net (SUPERVISOR-AUDIT-01) only fires
# when LEADV2_STATE_ROOT is explicitly set but LINK_ROOT still resolves to a
# real checkout -- it has NO equivalent net for the more common shape (a
# suite sets only CLAUDE_PROJECT_ROOT/PROJECT_ROOT, no LEADV2_STATE_ROOT/
# LEADV2_STATE_BASE at all, and forgets the cd). Hardening that net at
# runtime would also have to fire for the LEGITIMATE leaked-env-var incident
# the guard exists for (a real, different repo in env with cwd elsewhere is
# indistinguishable at runtime from "a test fixture that forgot to cd") --
# so this suite is a STATIC gate instead: it audits every tests/test-*.sh
# for the exact hazardous shape and fails loudly, in CI, before any suite
# gets a chance to run against live state.
#
# Empirical baseline (2026-09-03, this task): auditing the full
# plugins/leadv2/scripts/tests/ fleet with this detector found ZERO
# suites currently exhibiting the unguarded shape -- every existing fixture
# that `git init`s a temp repo and calls dispatch-code.sh either wraps the
# call in `( cd "$fixture" && ... )`, threads LEADV2_STATE_ROOT/
# LEADV2_STATE_BASE inline, or exports one of those two earlier in the file.
# That is a snapshot, not a guarantee -- this suite is what keeps it true.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ── The detector (embedded so mutation testing targets THIS file, not a
#    separately-registered lib nobody re-runs) ───────────────────────────────
DETECTOR="${WORK}/detect.py"
cat > "${DETECTOR}" <<'PYEOF'
import re, sys

def find_hazards(text):
    """Return [(line_no, snippet), ...] for every dispatch-code.sh call that
    sets a project-root env var but has no cd, no inline LEADV2_STATE_ROOT/
    LEADV2_STATE_BASE, and no earlier `export LEADV2_STATE_(ROOT|BASE)=` in
    the file -- the FOREIGN-PROJECT-ROOT-GUARD-01 silent-reroot shape.

    The guard only fires when the env-provided root resolves as an actual,
    distinct git repo (`_LV2_ENV_GIT_ROOT` is non-empty) -- a fixture that
    is never `git init`'d has no git ancestry to compare, so the guard's
    foreign-mismatch branch never triggers regardless of cd/state-override.
    Require a preceding `git init` / `git -C <dir> init` somewhere earlier
    in the file before treating the call as hazardous."""
    hazards = []
    exported_state_pos = [
        m.start() for m in re.finditer(r'(^|\n)[ \t]*export\s+LEADV2_STATE_(ROOT|BASE)=', text)
    ]
    git_init_pos = [
        m.start() for m in re.finditer(r'git\s+(-C\s+\S+\s+)?init\b', text)
    ]
    # Scope the git-init search to the enclosing `name() {` function body --
    # a file with several `case_*` functions, only one of which git-inits
    # its own fixture, must not let that one taint an unrelated sibling
    # function's bare-tmpdir case (test-foreign-project-root-guard.sh's own
    # deliberate "no .git at all" case is exactly this shape).
    func_starts = [
        m.start() for m in re.finditer(r'(^|\n)[ \t]*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{', text)
    ]
    call_re = re.compile(r'\bbash\s+"\$\{?DC\}?"|\bbash\s+"\$\{?DISPATCH_CODE(_SH)?\}?"')
    for m in call_re.finditer(text):
        pos = m.start()
        line_start = text.rfind('\n', 0, pos) + 1
        line_end = text.find('\n', pos)
        if line_end == -1:
            line_end = len(text)
        full_line = text[line_start:line_end]
        if full_line.strip().startswith('#'):
            continue
        depth = 0
        i = pos - 1
        open_pos = None
        while i >= 0:
            c = text[i]
            if c == ')':
                depth += 1
            elif c == '(':
                if depth == 0:
                    open_pos = i
                    break
                depth -= 1
            i -= 1
        seg_start = open_pos + 1 if open_pos is not None else max(0, pos - 800)
        seg = text[seg_start:pos]
        sets_root = bool(re.search(r'\b(CLAUDE_PROJECT_ROOT|PROJECT_ROOT|LEADV2_PROJECT_ROOT)=', seg))
        if not sets_root:
            continue
        scope_start = max([s for s in func_starts if s < pos], default=0)
        has_git_init = any(scope_start <= g < pos for g in git_init_pos)
        if not has_git_init:
            continue
        has_cd = bool(re.search(r'(^|[\s;&|])cd\s+["\'$]', seg))
        has_state_override = bool(re.search(r'LEADV2_STATE_(ROOT|BASE)=', seg))
        has_earlier_export = any(e < pos for e in exported_state_pos)
        if not has_cd and not has_state_override and not has_earlier_export:
            line_no = text[:pos].count('\n') + 1
            hazards.append((line_no, full_line.strip()[:160]))
    return hazards

if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, errors="replace") as f:
        text = f.read()
    for line_no, snippet in find_hazards(text):
        print("%d\t%s" % (line_no, snippet))
PYEOF

run_detector() { # <fixture-file> -> hazard lines on stdout
  python3 "${DETECTOR}" "$1"
}

# ── Test 1: the hazardous shape IS flagged (git-inits a fixture, sets
#    CLAUDE_PROJECT_ROOT, calls dispatch-code.sh, never cd's, no state
#    override anywhere) ───────────────────────────────────────────────────
cat > "${WORK}/hazard.sh" <<'FIX'
d="$(mktemp -d)"
git -C "$d" init -q
CLAUDE_PROJECT_ROOT="$d" bash "${DC}" "mission" --kind code
FIX
HAZARD_OUT="$(run_detector "${WORK}/hazard.sh")"
if [[ -n "${HAZARD_OUT}" ]]; then
  ok "hazardous shape (no cd, no state override) IS flagged: ${HAZARD_OUT}"
else
  bad "hazardous shape was NOT flagged (detector blind to the live incident shape)"
fi

# ── Test 2: wrapping the call in ( cd "$d" && ... ) clears it ──────────────
cat > "${WORK}/safe-cd.sh" <<'FIX'
d="$(mktemp -d)"
git -C "$d" init -q
( cd "$d" && CLAUDE_PROJECT_ROOT="$d" bash "${DC}" "mission" --kind code )
FIX
SAFE_CD_OUT="$(run_detector "${WORK}/safe-cd.sh")"
if [[ -z "${SAFE_CD_OUT}" ]]; then
  ok "cd-wrapped call is NOT flagged (matches every already-fixed suite in this repo)"
else
  bad "cd-wrapped call was flagged as a false positive: ${SAFE_CD_OUT}"
fi

# ── Test 3: an inline LEADV2_STATE_ROOT override clears it, cd or not ──────
cat > "${WORK}/safe-stateroot.sh" <<'FIX'
d="$(mktemp -d)"
git -C "$d" init -q
CLAUDE_PROJECT_ROOT="$d" LEADV2_STATE_ROOT="$d/state" bash "${DC}" "mission" --kind code
FIX
SAFE_SR_OUT="$(run_detector "${WORK}/safe-stateroot.sh")"
if [[ -z "${SAFE_SR_OUT}" ]]; then
  ok "inline LEADV2_STATE_ROOT= is NOT flagged (fully sandboxed regardless of cwd)"
else
  bad "inline LEADV2_STATE_ROOT= was flagged as a false positive: ${SAFE_SR_OUT}"
fi

# ── Test 4: an earlier file-level `export LEADV2_STATE_BASE=` clears it ───
cat > "${WORK}/safe-export.sh" <<'FIX'
export LEADV2_STATE_BASE="/tmp/whatever/state"
d="$(mktemp -d)"
git -C "$d" init -q
CLAUDE_PROJECT_ROOT="$d" bash "${DC}" "mission" --kind code
FIX
SAFE_EXP_OUT="$(run_detector "${WORK}/safe-export.sh")"
if [[ -z "${SAFE_EXP_OUT}" ]]; then
  ok "earlier 'export LEADV2_STATE_BASE=' is NOT flagged (inherited by the call's env)"
else
  bad "earlier export was flagged as a false positive: ${SAFE_EXP_OUT}"
fi

# ── Test 5: a call with NO project-root override at all is not this hazard
#    (relies on cwd already being right, a different class of bug) ────────
cat > "${WORK}/no-root.sh" <<'FIX'
d="$(mktemp -d)"
git -C "$d" init -q
bash "${DC}" "mission" --kind code
FIX
NO_ROOT_OUT="$(run_detector "${WORK}/no-root.sh")"
if [[ -z "${NO_ROOT_OUT}" ]]; then
  ok "no project-root override at all is NOT flagged (out of this detector's scope)"
else
  bad "no-override call was flagged as a false positive: ${NO_ROOT_OUT}"
fi

# ── Test 6 (integration): the REAL fleet is clean today. This is the
#    regression net -- a future suite added with the hazardous shape turns
#    this red before it ever runs against live state. ─────────────────────
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"
FLEET_HAZARDS=""
FLEET_FILES=0
for f in "${SCRIPT_DIR}"/test-*.sh; do
  [[ -f "$f" ]] || continue
  # skip self: this file's own embedded example fixtures (heredocs used to
  # exercise the detector above) are literal hazard/safe-shape source text,
  # not real suite bodies -- scanning them here would be self-referential.
  [[ "$(basename "$f")" == "${SELF_NAME}" ]] && continue
  FLEET_FILES=$((FLEET_FILES + 1))
  out="$(run_detector "$f")"
  if [[ -n "${out}" ]]; then
    while IFS= read -r line; do
      FLEET_HAZARDS="${FLEET_HAZARDS}$(basename "$f"):${line}
"
    done <<<"${out}"
  fi
done
if [[ "${FLEET_FILES}" -lt 50 ]]; then
  bad "integration scan only saw ${FLEET_FILES} test files -- SCRIPT_DIR resolution looks wrong"
elif [[ -z "${FLEET_HAZARDS}" ]]; then
  ok "real fleet (${FLEET_FILES} suites) has zero unguarded fixture-state-leak shapes"
else
  bad "real fleet has unguarded fixture-state-leak shape(s):
${FLEET_HAZARDS}"
fi

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
