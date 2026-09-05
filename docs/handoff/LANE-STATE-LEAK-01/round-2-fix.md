# LANE-STATE-LEAK-01, fix round — one red test, and it is a real regression

The selfcheck caught it before review: 13 checks, 1 failed. Everything else is green, including
`bash -n` on all nine touched files and the three new suites. Keep the work.

## The failure

`plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh`, case **(d)**:

```
FAIL: (d) expected sonnet-fallback line missing from rendered artifact
  content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1
```

Every other case in that suite passes — (a) ordering, (b) list rendering, (c) the 24h journal
stamp, (e) shared-cache double refusal, (e2), (f) real retry-all, (g) reaping, (h), (i). Only (d)
broke, and (d) is the one asserting the rendered status artifact contains the sonnet-fallback line.

That is the expected blast radius of this change: the deferral ladder writes a fallback record, the
status renderer reads it, and you moved where both of those live. The two halves are now resolving
to different places, or the renderer reads before the migration has moved the content. The
neighbouring PASS at `(d) a day with no fallback renders no sonnet-fallback line` tells you the
renderer itself still works — it is the read/write pairing that is off.

**Fix the pairing, not the test.** If the assertion is genuinely wrong, say precisely why in the
report; do not weaken it to green. This suite is one of the four that exist to protect exactly this
file set.

## Also close before review

Three of the four falsification checks came back `ADVISORY (no_falsification_marker)`:

- `tests/test-state-path-migration.sh`
- `tests/test-state-path-no-raw-paths.sh`
- `tests/test-state-path-worktree-identity.sh`

These are your three new suites, and they are the ones proving the whole invariant. A suite with no
falsification marker has not been shown capable of failing. Add the marker and demonstrate each one
red against the regression it names — worktree-identity against a raw `$PROJECT_ROOT/docs/leadv2/…`
path, migration against a migration that clobbers instead of merging, no-raw-paths against a
reintroduced hardcoded path. Then green.

This repo has hit blindfolded tests on six separate lanes in the last week. Do not add a seventh.

## Done means

1. `test-glm-deferred-ladder.sh` green, with the cause stated in one sentence.
2. The three new suites carry falsification markers and were each verified red-then-green by
   deliberately breaking the thing they guard. Say that you did it.
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` green, plus
   `test-broad-status-lanes-blind.sh`, `test-broad-status-renderer-truth.sh`,
   `test-pulse-empty-board.sh`.
4. `git diff --stat`.

## Scope

Unchanged from round 1. Do not widen it — the durable half (writing state outside the repo
entirely, plus a guard and a migration command) is already written up at
`docs/handoff/LANE-STATE-LEAK-01/round-2-durable.md` and runs only after this lands.
