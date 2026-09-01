# PROMISE-GUARD-TURN-IT-ON-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01`
LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh,plugins/leadv2/scripts/tests/test-lib.sh,tests/run-all.sh,docs/leadv2/scheduled-decisions.md,docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 1
`status=fail reason=suite_not_falsifiable suite=plugins/leadv2/scripts/tests/test-lib.sh` — the
review gate probed `test-lib.sh` as a suite (it matches `tests/test-*.sh`) and it cannot go red.
No suite in the lane sources it: it is an orphan helper. Also
`test-promise-guard-classified-block.sh` is not registered in `tests/run-all.sh` (lines 136-138 map
`leadv2-promise-guard.sh` only to the two old suites + `plugins/leadv2/tests/test-promise-guard.sh`),
so CI would never select the suite that proves the flip.

## Do
1. Delete `plugins/leadv2/scripts/tests/test-lib.sh`. If any helper in it is needed, inline it into
   the suite that needs it. Nothing named `test-*.sh` may exist under `scripts/tests/` unless it is a
   suite that exits non-zero on failure.
2. Register `test-promise-guard-classified-block.sh` in `tests/run-all.sh` next to lines 136-138 so a
   change to `hooks/leadv2-promise-guard.sh` selects it. Prove it: `bash tests/run-all.sh --scope
   changed` (or the repo's equivalent) lists the suite in its selection output — paste that line.
3. Mutation negative control, RUN it and paste the red: in the hook body, force the classified-block
   branch to fall through (e.g. `verdict=suppressed_action` unconditionally) → the classified-block suite
   must exit non-zero. Revert the mutation.
4. Append the three outputs (suite green, selection line, mutation red) to `report.md` under
   "## Round 2 evidence". Commit.
