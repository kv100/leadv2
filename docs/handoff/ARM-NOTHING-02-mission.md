# ARM-PRODUCES-NOTHING-02 — the fix is correct and it regresses the guard. Resolve who owns a clean lane.

**Repo for this work: `~/Projects/leadv2` (the plugin source), not persona-engine.**

## State on disk right now

The silent-arm fix EXISTS and is CORRECT in isolation: branch `worktree-621328a0`, commit
`3bffb24` — a silent-arm probe plus `_pc_arm_advance` in
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` and
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, with a new suite
`tests/test-dispatch-silent-arm.sh`.

It was merged and then **reverted** from main (`9fe0ee1` reverts `3d3108c`) because it regresses a
guard. Measured three ways, not inferred:

- In the lane worktree: `test-dispatch-silent-arm.sh` 10/0 AND `test-lane-diff-single-repo.sh` 4/4.
- On main pre-merge (`c1e8cbf`): `test-lane-diff-single-repo.sh` **4/0, C3-clean-anti-rescue GREEN**.
- On main post-merge (`3d3108c`): **3/1, C3-clean-anti-rescue RED**.
- After the revert: 4/0 green again.

So the merge, not the environment, is the cause. Do not re-merge without fixing this.

## Why it matters more than a red test

C3 is the guard that a lane which genuinely produced NOTHING still terminates as `no_work` and is
not "rescued" into looking like a pass. The silent-arm probe claims that same clean-lane case as
`arm_produced_nothing` and short-circuits BEFORE the diff classification. Two fixes from the same
day disagree about who owns the empty lane. That is a semantic collision, not flakiness.

This plugin tree dispatches for persona-engine, m3-market and respiro-ios, so shipping a red
anti-rescue guard puts "a lane that did nothing gets rescued into a pass" into all three.

## The decision — made by the lead, encode it, do not relitigate it

Both states look identical in the worktree: clean tree, no stream. So **the worktree cannot be the
discriminator, and neither can the diff.** The discriminator is whether an arm was ever dispatched:

- **An arm WAS registered for this lane** (dispatch receipt / arm registration / recorded pid
  exists) **and the lane is clean with no stream** -> `arm_produced_nothing`. This is the real defect
  the probe exists to catch: glm has now been spawned and written zero bytes on multiple plugin
  lanes in one day (`b0370efc`, `b12e69cc`).
- **No arm was ever registered** -> the existing empty-diff path owns it and it terminates
  `no_work`. C3 keeps its current expectation, untouched.

Find where dispatch records the arm/pid and use THAT as the gate on the silent-arm probe. If no such
record survives to close time, making one is part of this task — a boolean written at spawn is
enough, and it is the honest fix. Do NOT relax C3 to make the merge green: C3 is the guard, and
weakening it re-opens the exact failure it exists to catch.

## Done means

- `worktree-621328a0`'s behaviour is preserved: a lane whose arm was spawned and wrote nothing
  terminates `arm_produced_nothing` and the chain advances to the next arm.
- On main, after merge: `test-lane-diff-single-repo.sh` **4/0 with C3-clean-anti-rescue GREEN**, and
  `test-dispatch-silent-arm.sh` 10/0 or better.
- A NEW test case in one of the two suites that asserts the discriminator directly: same clean
  worktree, same absent stream, arm-registered vs not-arm-registered, two different terminals. Both
  suites must encode it so they can never disagree again.
- Run the dispatch/lane suites only. Do NOT run `run-core-offline.sh`.

## Constraints

- No commit, no push. The lead merges.
- You may rebase or rebuild on top of `3bffb24` — do not throw that work away and start over.
