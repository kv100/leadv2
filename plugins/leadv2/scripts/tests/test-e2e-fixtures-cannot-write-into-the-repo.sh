#!/usr/bin/env bash
# run-all-triggers: leadv2-state-path test-plugin-papercuts
# tests/test-e2e-fixtures-cannot-write-into-the-repo.sh --
# E2E-FIXTURES-CANNOT-WRITE-INTO-THE-REPO-01 (row e9aca6a4c15a, 2026-09-12).
#
# THE INCIDENT this guards: the tracked file docs/leadv2/open-threads.md was
# found at merge time replaced by a symlink into
# /tmp/leadv2-plugin-papercuts-W1ZI8Z/e2e/state/leadv2/open-threads.md — a
# plugin-papercuts e2e sandbox. The ledger is since deleted, so asserting on
# that one filename would pin nothing (the file is gone). What this suite
# pins is the WRITER, name-agnostically:
#
#   leadv2-state-path.sh's migration block (relink_if_needed + the
#   move-then-symlink legs) re-points any docs/leadv2/<name> that is already
#   a symlink — or moves an untracked regular file out and links it — at THIS
#   call's own state_root. The plugin-papercuts e2e arms that env suite-wide
#   (test-plugin-papercuts.sh e2e_setup: `export LEADV2_STATE_BASE="$E2E_STATE"`)
#   and its P8 phase drives the production resolvers (leadv2-pulse-beat.sh,
#   leadv2-lane-heartbeat.sh) with cwd = the launch checkout — a REAL repo
#   whenever the suite runs from one. Any invocation in that tree that misses
#   PROJECT_ROOT threading resolves LINK_ROOT=<real checkout> +
#   STATE_ROOT=<sandbox>/state/<slug> and relinks repo paths into the tmp
#   tree; git then reports a typechange at the next merge. Live-fired on main
#   2026-09-12 (see the B1-net comment in leadv2-state-path.sh): one unpinned
#   call with LEADV2_STATE_BASE=<tmp> + cwd inside a leadv2 checkout
#   retargeted docs/leadv2/glm-deferred.jsonl into the tmp root.
#
# THE FIX under test: the B1 safety net in leadv2-state-path.sh now treats
# LEADV2_STATE_BASE exactly like LEADV2_STATE_ROOT (production never sets
# either): sandbox state signal + LINK_ROOT resolving to a REAL repo checkout
# => hard abort, never a re-pointed root. Structural by construction — the
# refusal keys on the contradiction itself at the one chokepoint every
# resolver call passes through, so there is no "corrected variable" left that
# could drift back.
#
# Fixtures here RECREATE the incident shape rather than grep for its corpse:
# a git repo that carries a remote (the B1 "real checkout" predicate), a
# REGULAR TRACKED file at docs/leadv2/open-threads.md (the pre-incident
# shape), and an untracked leftover symlink at docs/leadv2/glm-deferred.jsonl
# (a MERGE_FILE set member — the name proven live-fireable). The two names
# are illustrative; every assertion is on the mechanism.
#
# Negative control (declared, run via plugins/leadv2/scripts/
# leadv2-mutation-control.sh): revert the net's condition to
# LEADV2_STATE_ROOT-only — T1/T5 must go RED (the writer relinks again).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SP="${SCRIPT_DIR}/leadv2-state-path.sh"          # the writer under constraint
HB="${SCRIPT_DIR}/leadv2-lane-heartbeat.sh"      # production caller (audit-proven)

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/home"                          # hermetic ${HOME} control plane

# ── fixture builders ─────────────────────────────────────────────────────────
# real_repo <dir>  — git repo WITH a remote: the B1 net's "real checkout"
#                    predicate (git remote non-empty). This is the tree the
#                    writer must be structurally unable to touch.
# bare_repo <dir>  — git repo WITHOUT a remote: the plugin-papercuts fixture
#                    shape; the resolver must keep working normally in it.
seed_incident_shape() {  # <repo>
  local r="$1"
  mkdir -p "${r}/docs/leadv2"
  # pre-incident shape: a REGULAR TRACKED file at the ledger path
  printf 'authored ledger content — the repo owns this\n' > "${r}/docs/leadv2/open-threads.md"
  # live leftover: an untracked control-plane symlink at a MERGE_FILE set
  # member's path (the exact live-fire shape from 2026-09-12)
  ln -sfn "${WORK}/fake-control-plane/glm-deferred.jsonl" "${r}/docs/leadv2/glm-deferred.jsonl"
  ( cd "$r" && git add docs/leadv2/open-threads.md \
    && git -c user.email=t@e.com -c user.name=t commit -qm seed ) 2>/dev/null || true
  # only the ledger path is committed; the leftover symlink stays UNtracked,
  # exactly as it was in the incident (a tracked name is skipped by the
  # migration's is_git_tracked belt and would not exercise the writer)
}
real_repo() {  # <dir>
  git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" checkout -q -b main; }
  git -C "$1" remote add origin https://example.invalid/repo.git
  seed_incident_shape "$1"
}
bare_repo() {  # <dir>
  git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" checkout -q -b main; }
  seed_incident_shape "$1"
}

snap_repo() {  # <repo> <outfile> — deterministic signature: index modes,
               # porcelain status, and every symlink target under docs/
  local r="$1" out="$2" l
  {
    git -C "$r" ls-files -s
    git -C "$r" status --porcelain
    find "${r}/docs" -type l 2>/dev/null | sort | while IFS= read -r l; do
      printf 'SYMLINK %s -> %s\n' "${l#${r}/}" "$(readlink "$l")"
    done
  } > "$out"
}

# hostile() — the incident env: state sandboxed under WORK, cwd inside the
# given repo, every PROJECT_ROOT threading deliberately MISSING (the B1
# comment's own failure class: "forgot to ALSO thread PROJECT_ROOT for one
# specific call"). <state-var-name> selects LEADV2_STATE_BASE (the papercuts
# export) or LEADV2_STATE_ROOT (the original B1 shape).
hostile() {  # <repo> <state-var> <state-val> <resolver-args...>
  local r="$1" svar="$2" sval="$3"; shift 3
  ( cd "$r" && HOME="${WORK}/home" \
      env -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
      -u LEADV2_STATE_ROOT -u LEADV2_STATE_BASE \
      "${svar}=${sval}" bash "$SP" "$@" )
}

SB="${WORK}/sandbox/state"   # the suite-style throwaway state tree

# ═══ T1: THE WRITER REFUSES — LEADV2_STATE_BASE + real checkout ══════════════
printf '\ntest: T1 writer aborts loudly on LEADV2_STATE_BASE + real repo, repo byte-identical\n'
T1="${WORK}/real1"; real_repo "$T1"
snap_repo "$T1" "${WORK}/t1.before"
T1_OUT="$(hostile "$T1" LEADV2_STATE_BASE "$SB" glm-deferred.jsonl 2>"${WORK}/t1.err")"; T1_RC=$?
snap_repo "$T1" "${WORK}/t1.after"
if [[ "$T1_RC" -ne 0 ]] && grep -q "ABORT: LEADV2_STATE_BASE" "${WORK}/t1.err" \
   && diff -q "${WORK}/t1.before" "${WORK}/t1.after" >/dev/null; then
  ok "T1: sandbox state signal + real checkout => loud abort, repo tree byte-identical"
else
  bad "T1: expected loud abort with an unchanged repo; rc=${T1_RC} err=$(head -1 "${WORK}/t1.err" 2>/dev/null) changed=$(diff -q "${WORK}/t1.before" "${WORK}/t1.after" >/dev/null && printf no || printf YES)"
fi
# The incident's exact observable, asserted explicitly (not just via diff):
# the leftover symlink must still point at the ORIGINAL target, not the sandbox.
T1_LINK="$(readlink "${T1}/docs/leadv2/glm-deferred.jsonl" 2>/dev/null || printf GONE)"
case "$T1_LINK" in
  "${WORK}/sandbox"*|"${SB}"*) bad "T1b: leftover symlink retargeted into the sandbox (${T1_LINK}) — the incident, live" ;;
  GONE) bad "T1b: leftover symlink deleted from the repo tree" ;;
  *) ok "T1b: leftover symlink not retargeted (${T1_LINK#"${WORK}/"})" ;;
esac
if [[ -f "${T1}/docs/leadv2/open-threads.md" && ! -L "${T1}/docs/leadv2/open-threads.md" ]]; then
  ok "T1c: the tracked regular file is still a regular file (no typechange to report at merge time)"
else
  bad "T1c: tracked docs/leadv2/open-threads.md is no longer a regular file — the merge-blocking typechange"
fi

# ═══ T2: B1 regression net — LEADV2_STATE_ROOT + real checkout still aborts ══
printf '\ntest: T2 B1 net unchanged for LEADV2_STATE_ROOT\n'
T2="${WORK}/real2"; real_repo "$T2"
snap_repo "$T2" "${WORK}/t2.before"
hostile "$T2" LEADV2_STATE_ROOT "${WORK}/sandbox/root2" glm-deferred.jsonl >/dev/null 2>"${WORK}/t2.err"; T2_RC=$?
snap_repo "$T2" "${WORK}/t2.after"
if [[ "$T2_RC" -ne 0 ]] && grep -q "ABORT: LEADV2_STATE_ROOT" "${WORK}/t2.err" \
   && diff -q "${WORK}/t2.before" "${WORK}/t2.after" >/dev/null; then
  ok "T2: LEADV2_STATE_ROOT shape still aborts loudly with an untouched repo (B1 preserved)"
else
  bad "T2: B1 net regressed; rc=${T2_RC} err=$(head -1 "${WORK}/t2.err" 2>/dev/null)"
fi

# ═══ T3: benign fixture (no remote — the papercuts shape) keeps working ══════
printf '\ntest: T3 remote-less fixture: resolver still functions, writes stay in the sandbox\n'
T3="${WORK}/bare1"; bare_repo "$T3"
T3_OUT="$(hostile "$T3" LEADV2_STATE_BASE "$SB" glm-deferred.jsonl 2>"${WORK}/t3.err")"; T3_RC=$?
T3_LINK="$(readlink "${T3}/docs/leadv2/glm-deferred.jsonl" 2>/dev/null || printf GONE)"
if [[ "$T3_RC" -eq 0 ]] && [[ "$T3_LINK" == "${SB}"* ]]; then
  ok "T3: no remote => no abort (rc=0); link maintenance relocated the fixture symlink INTO the sandbox (${T3_LINK#"${SB}"/})"
else
  bad "T3: fixture repos must keep working; rc=${T3_RC} link=${T3_LINK} err=$(head -1 "${WORK}/t3.err" 2>/dev/null)"
fi
if [[ -f "${T3}/docs/leadv2/open-threads.md" && ! -L "${T3}/docs/leadv2/open-threads.md" ]]; then
  ok "T3b: fixture's tracked regular file untouched (tracked paths are never migration input)"
else
  bad "T3b: fixture tracked file mutated"
fi

# ═══ T4: production shape (no sandbox vars at all) resolves normally ═════════
printf '\ntest: T4 no sandbox signals => normal resolution (hermetic HOME)\n'
T4="${WORK}/bare2"; bare_repo "$T4"
T4_OUT="$( ( cd "$T4" && HOME="${WORK}/home" \
      env -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
      -u LEADV2_STATE_ROOT -u LEADV2_STATE_BASE bash "$SP" root) 2>"${WORK}/t4.err" )"; T4_RC=$?
if [[ "$T4_RC" -eq 0 && -n "$T4_OUT" ]]; then
  ok "T4: no state vars => rc=0, root resolved (${T4_OUT#"${WORK}"/})"
else
  bad "T4: production shape broke; rc=${T4_RC} out=${T4_OUT} err=$(head -1 "${WORK}/t4.err" 2>/dev/null)"
fi

# ═══ T5: the PRODUCTION caller path (audit-proven: lane-heartbeat resolves
#        state via leadv2-state-path.sh) driven from a real checkout's cwd
#        with the papercuts env — repo must come back byte-identical ═════════
printf '\ntest: T5 production resolver caller leaves a real repo untouched\n'
T5="${WORK}/real3"; real_repo "$T5"
snap_repo "$T5" "${WORK}/t5.before"
if [[ -x "$HB" ]]; then
  ( cd "$T5" && HOME="${WORK}/home" \
      env -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
      -u LEADV2_STATE_ROOT LEADV2_STATE_BASE="$SB" \
      bash "$HB" status --all --json ) >"${WORK}/t5.out" 2>"${WORK}/t5.err"; T5_RC=$?
  snap_repo "$T5" "${WORK}/t5.after"
  if diff -q "${WORK}/t5.before" "${WORK}/t5.after" >/dev/null; then
    ok "T5: leadv2-lane-heartbeat from a real checkout with LEADV2_STATE_BASE set: repo byte-identical (rc=${T5_RC})"
  else
    bad "T5: production caller mutated a real repo under a sandbox state signal; diff:"
    diff "${WORK}/t5.before" "${WORK}/t5.after" | head -5 >&2
  fi
else
  bad "T5 setup: leadv2-lane-heartbeat.sh not found at ${HB}"
fi

# ═══ T6: tracked-path sweep — after everything above ran against real-repo
#        fixtures, no tracked path in ANY of them became a symlink ═══════════
printf '\ntest: T6 tracked-path symlink sweep over every real-repo fixture\n'
T6_BAD=0
for r in "${WORK}"/real1 "${WORK}"/real2 "${WORK}"/real3; do
  [[ -d "$r" ]] || continue
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ -L "$r/$p" ]]; then
      bad "T6: tracked path ${p} in $(basename "$r") is a symlink — a typechange git will report at merge time"
      T6_BAD=$((T6_BAD+1))
    fi
  done < <(git -C "$r" ls-files)
done
[[ "$T6_BAD" -eq 0 ]] && ok "T6: zero tracked paths are symlinks across all real-repo fixtures after the writer ran"

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
