verdict: APPROVE
next_action: review_round_2

# dispatch-beee6495 — SUITES-MUTATE-LIVE-CONTROL-PLANE-01 — full report

See `docs/handoff/SUITES-MUTATE-LIVE-CONTROL-PLANE-01/report.md` for the
full write-up (mechanism, audit findings, mutation-control evidence,
registration proof, dual-OS proof). Summary of that content:

## What I found

`FOREIGN-PROJECT-ROOT-GUARD-01` (`leadv2-dispatch-code.sh:299-456`) silently
discards an env-only `PROJECT_ROOT`/`CLAUDE_PROJECT_ROOT` override that
disagrees with cwd's git toplevel, rerouting the run onto cwd's own repo.
`leadv2-state-path.sh` then resolves the control-plane root from that real
repo via `git-common-dir`, landing writes in the shared
`~/.claude/leadv2-state/<repo-slug>/` used by every live `/leadv2` session.
A fixture suite that `git init`s a temp repo, sets the project-root env var,
and never `cd`s into the fixture hits exactly this path — green suite,
silently corrupted shared state.

## What I did NOT find

I audited ~14 named candidate suites plus a full static sweep across all
332 `plugins/leadv2/scripts/tests/test-*.sh` files for this exact shape
(git-init'd fixture + env-only root override + no cd + no state-root
override anywhere in scope). Every suite checked out safe. I could not
substantiate the brief's "at least four currently-broken suites" within
this session — either they were already fixed by other concurrent lanes, or
the cited 1773-row `all_arms_capped` contamination traces to the e2e-gate's
own sandbox mechanism rather than a `tests/` fixture (a thread I started —
`leadv2-phase8-e2e-gate.sh` resolves `PROJECT_ROOT` then `cd`s into it,
which looked safe on inspection, but I did not finish tracing
`leadv2-route-arbiter.sh`'s state-file resolution to rule it out
completely). This is reported as an open gap, not papered over.

## What I built instead

`plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh` — a
self-contained static detector + regression suite:
- unit tests (5 cases) proving the detector correctly flags the hazardous
  shape and correctly clears all four safe shapes (cd-wrapped, inline
  `LEADV2_STATE_ROOT=`, earlier file-level `export LEADV2_STATE_BASE=`, and
  no-root-override-at-all);
- an integration case scanning the real fleet (332 files, self excluded)
  asserting zero hazards today — this is the actual regression net: any
  future suite added with the hazardous shape turns this suite red before
  it ever runs against live state.

Detector logic requires (a) a `bash "${DC}"`/`bash "${DISPATCH_CODE}"` call
whose enclosing command-substitution/subshell segment sets
`CLAUDE_PROJECT_ROOT`/`PROJECT_ROOT`/`LEADV2_PROJECT_ROOT`, (b) a preceding
`git init`/`git -C <dir> init` within the same enclosing function (not
whole-file, to avoid a sibling function's git-init tainting an unrelated
bare-tmpdir case — this was an actual false positive I hit and fixed against
`test-foreign-project-root-guard.sh`'s own deliberate no-`.git` test case),
and (c) no `cd`, no inline state-root override, and no earlier file-level
`export LEADV2_STATE_(ROOT|BASE)=` covering the call.

## Evidence

- Mutation negative control (in-function, not top-level): flipped
  `if not has_cd and not has_state_override and not has_earlier_export:` to
  `if False and ...` inside `find_hazards`. `baseline_rc=0` →
  `mutated_rc=1`, red line `[TEST] FAIL: hazardous shape was NOT flagged
  (detector blind to the live incident shape)`. Reverted, `bash -n` clean,
  `reverted_rc=0`.
- Registration: `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope
  changed` selects the new suite via self-select convention (new
  `test-*.sh` under `plugins/leadv2/scripts/tests/` self-selects even
  without a matching production-file stem change). Also added two
  `EXTRA_SUITE_MAP` rows (`leadv2-dispatch-code.sh` and
  `leadv2-state-path.sh` → this suite) so future carrier changes re-trigger
  it. `test-run-all-carrier-map.sh` (the map-format suite, auto-selected by
  editing `run-all.sh`) still passes 5/5 after the addition.
- Dual-OS: macOS local `rc=0` (6 passed, 0 failed); Linux container
  (`docker run --rm -v $(pwd):/repo -w /repo python:3-slim bash
  plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`) `rc=0` (6
  passed, 0 failed).
- `bash -n` clean on both changed `.sh` files. No `.py` files changed.
- `git diff --diff-filter=D --name-only main...HEAD` → empty, nothing
  wrongly deleted.
- Diff scope: only `plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`
  (new) and `tests/run-all.sh` (+2 `EXTRA_SUITE_MAP` rows). No runtime-state
  paths touched; `leadv2-dispatch-code.sh` read-only throughout.

## Honest caveat for the reviewer

This deliverable is a prevention/detection net, not a set of "N suites
found and patched." If the brief's "at least four broken suites" claim is
still live, the most likely remaining place to look is
`leadv2-phase8-e2e-gate.sh` / `leadv2-route-arbiter.sh`'s own sandbox
dry-run path rather than `tests/` fixtures — I ran out of budget before
fully tracing that thread.

DELIVERABLE_COMPLETE
