#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# HANDOFF-DOCS-INVISIBLE-IN-LANES-01 (second cause): pick_base() base-ref
# selection lives in leadv2-lane-worktree.sh but the suite proving it is
# named for the behaviour (base-pick), not the carrier — self-select by
# convention (test-leadv2-lane-worktree.sh) would never match it.
# run-all-triggers: leadv2-lane-worktree
# test-lane-worktree-base-pick.sh — HANDOFF-DOCS-INVISIBLE-IN-LANES-01 (second cause)
#
# pick_base() in leadv2-lane-worktree.sh used to unconditionally prefer
# origin/main over local main whenever origin/main existed at all — even when
# origin/main was BEHIND local main. The lead commits a brief and deliberately
# withholds the push (a push cancels an in-flight CI run through the
# workflow's concurrency group); the next lane worktree then forks from a
# stale origin/main that has no docs/handoff/<id>/ at all. The worker finds
# nothing to read and returns an empty diff — see
# docs/handoff/HANDOFF-DOCS-INVISIBLE-IN-LANES-01/brief-addendum-second-cause.md
# for the measured proof (two lanes, two arms, zero output).
#
# origin/main was preferred in the first place to pick up sibling landings —
# another push having landed ahead of a stale local main. This suite proves
# the fixed pick_base() handles BOTH directions (whichever ref is NOT behind
# the other wins) plus the diverged case, entirely inside fixture repos —
# never against this repo's own refs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_SH="${SCRIPT_DIR}/../leadv2-lane-worktree.sh"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

if ! bash -n "${LANE_SH}"; then
  fail "0: bash -n ${LANE_SH}"
  printf 'test-lane-worktree-base-pick: %d passed, %d failed\n' "${PASS}" "$((FAIL+1))"
  exit 1
fi
pass "0: bash -n ${LANE_SH}"

FIXTURES=()
cleanup() { local d; for d in "${FIXTURES[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

new_repo() { # -> prints repo dir, on branch main with one commit
  local d
  d="$(mktemp -d)"
  FIXTURES+=("${d}")
  ( cd "${d}" && git init -q -b main \
      && git config user.email t@example.com && git config user.name t \
      && git commit -q --allow-empty -m base )
  printf '%s\n' "${d}"
}

# run_pick_base <repo-dir> <out-file> <err-file> — stdout/stderr go to files,
# not a captured global, since `choice="$(run_pick_base ...)"` would run the
# whole function in a subshell and silently drop any variable it sets.
run_pick_base() {
  local d="$1" outf="$2" errf="$3"
  ( cd "${d}" && LEADV2_PROJECT_ROOT="${d}" bash -c "source '${LANE_SH}'; resolve_root; pick_base" ) >"${outf}" 2>"${errf}"
}

run_ensure() {
  local d="$1" outf="$2" errf="$3"
  ( cd "${d}" && LEADV2_PROJECT_ROOT="${d}" LEADV2_WORKTREE_DIR="${d}/lane-worktrees" \
      LEADV2_CODEX_WORKTREE_TRUST=off LEADV2_LANE_WORKTREE_ERRF="${errf}" \
      bash -c "source '${LANE_SH}'; cmd_ensure FIXTURE-ID" ) >"${outf}" 2>"${errf}"
}

outf="$(mktemp)"; errf="$(mktemp)"

# ── 1: no origin/main -> main ───────────────────────────────────────────────
d="$(new_repo)"
run_pick_base "${d}" "${outf}" "${errf}"; choice="$(cat "${outf}")"
[[ "${choice}" == "main" ]] && pass "1: no origin/main ref -> main" || fail "1: got '${choice}', want main"

# ── 2: origin/main ahead of main (sibling landings) -> origin/main ─────────
d="$(new_repo)"
base_sha="$(cd "${d}" && git rev-parse HEAD)"
( cd "${d}" && git commit -q --allow-empty -m sibling )
sibling_sha="$(cd "${d}" && git rev-parse HEAD)"
( cd "${d}" && git update-ref refs/heads/main "${base_sha}" \
    && git update-ref refs/remotes/origin/main "${sibling_sha}" )
run_pick_base "${d}" "${outf}" "${errf}"; choice="$(cat "${outf}")"
[[ "${choice}" == "origin/main" ]] \
  && pass "2: origin/main ahead (sibling landing) -> origin/main preserved" \
  || fail "2: got '${choice}', want origin/main"

# ── 3: main ahead of origin/main (unpushed brief) -> main (THE FIX) ────────
d="$(new_repo)"
base_sha="$(cd "${d}" && git rev-parse HEAD)"
( cd "${d}" && git commit -q --allow-empty -m "unpushed brief" )
( cd "${d}" && git update-ref refs/remotes/origin/main "${base_sha}" )
run_pick_base "${d}" "${outf}" "${errf}"; choice="$(cat "${outf}")"
[[ "${choice}" == "main" ]] \
  && pass "3: main ahead of origin/main (unpushed brief) -> main (regression fixed)" \
  || fail "3: got '${choice}', want main — this is the addendum's second cause"

# ── 4: diverged -> main, logged loudly (never silently guesses wrong) ──────
d="$(new_repo)"
base_sha="$(cd "${d}" && git rev-parse HEAD)"
( cd "${d}" && git commit -q --allow-empty -m "local-only" )
# origin/main gets a SIBLING commit off the same base — not a descendant of
# local main's tip, and local main is not a descendant of it either.
origin_sha="$(cd "${d}" && git commit-tree -p "${base_sha}" -m "origin-only" "${base_sha}^{tree}")"
( cd "${d}" && git update-ref refs/remotes/origin/main "${origin_sha}" )
run_pick_base "${d}" "${outf}" "${errf}"; choice="$(cat "${outf}")"; stderr_out="$(cat "${errf}")"
if [[ "${choice}" == "main" && "${stderr_out}" == *diverged* ]]; then
  pass "4: diverged refs -> main, with a loud diverged warning (never silent)"
else
  fail "4: got choice='${choice}' stderr='${stderr_out}'"
fi

# ── 5: end-to-end visibility — ensure must fork from local main ────────────
d="$(new_repo)"
base_sha="$(cd "${d}" && git rev-parse HEAD)"
mkdir -p "${d}/docs/handoff/FIXTURE-ID"
printf '# fixture brief\n' > "${d}/docs/handoff/FIXTURE-ID/brief.md"
( cd "${d}" && git add docs/handoff/FIXTURE-ID/brief.md && git commit -q -m "brief committed locally" \
    && git update-ref refs/remotes/origin/main "${base_sha}" )
run_ensure "${d}" "${outf}" "${errf}"
lane_path="$(cat "${outf}")"
if [[ -f "${lane_path}/docs/handoff/FIXTURE-ID/brief.md" ]]; then
  pass "5: ensure forks from local main and the committed brief reaches the lane"
else
  fail "5: ensure output='${lane_path}' did not contain the local brief (stderr: $(cat "${errf}"))"
fi
rm -f "${outf}" "${errf}"

printf 'test-lane-worktree-base-pick: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
