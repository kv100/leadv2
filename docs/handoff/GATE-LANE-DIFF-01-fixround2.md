# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — fix round 2 (target hit, three suites regressed)

Your diff is committed on this lane's branch as `a8abb02`. Continue from it; do not restart.

## What you got right — keep it

The target defect is FIXED. `review body persist` now passes (`Test (a) deliverable: exit 0`)
where it previously failed four fixtures with `review_diff repo=<sig8> bytes=0 base=HEAD`. That
was the whole point of the mission, and the new `test-lane-diff-single-repo.sh` plus its
registration line in `run-core-offline.sh` are correct and stay.

## What you broke — three suites, measured against a real baseline

I ran `run-core-offline.sh` three ways before concluding anything:

| Where | Result |
|---|---|
| clean `main` | 34 passed, 0 failed |
| clean worktree of `main` (`.claude/worktrees/baseline-check`) | 33 passed, **1** failed |
| your diff, in lane `6bbcca99` | 30 passed, **4** failed |

The ONE baseline failure is `product-close waits for worker exit`, whose assertion is
`codex liveness probe called only 2 times`. That is environmental — codex is under a quota
lockout until 2026-08-08 (`~/.claude/cache/codex-lockout.state`). **Do not try to fix it** and do
not count it against yourself.

The other three are yours:

- `dispatch refusal fallback chain`
- `landed-at-spawn (no terminal=landed at spawn; target repo keying)`
- `lane placement pin (--resume-lane/--worktree)` — 13 passed / 11 failed inside it

Their assertions, verbatim:

```
T-a: dispatch exited 4 (expected 0)
T-a: TARGET terminal ledger has 0
T-a: reservation row is NOT confirmed (or missing)
P-a: dispatch exited 4 (expected 0)
P-a: worker cwd='' != RESUME='/private/tmp/leadv2-lpp-.../target/.claude/worktrees/RESUME-ME-01'
P-h(a): prompt pin line MISSING with --resume-lane
P-b: worker cwd='' != RESUME=...   /  P-h(b): prompt pin line MISSING with --worktree
P-g: worker cwd='' == RESUME or empty (regression)
P-h(g): prompt pin line MISSING on default ensure-created path
P-h(g2): pin line does NOT name the worktree (expected '')
```

The shape is consistent: the worker's cwd comes out EMPTY and the pin line disappears, on all
three placement paths (`--resume-lane`, `--worktree`, and the default ensure-created path), and
dispatch then exits 4 instead of 0. Something in your lane-root resolution now returns an empty
string where the placement code previously got a path — most likely a resolution that succeeds
only under the conditions your new test exercises and yields empty otherwise. Find the branch
that returns empty and make it fall back to the previous behaviour rather than propagating "".

## Rules

- Fix forward on `a8abb02`. Do not revert the working part to make the suite green.
- **Do not weaken or edit any of the three failing suites' assertions.** They are describing a
  real regression. If you believe an assertion is genuinely wrong, say so in the deliverable with
  the reasoning and leave it failing — I will judge it.
- Same shared-tree rules: branch only, no commit to main, no push, no merge.
- `bash` 3.2 compatibility still applies.

## Done means

`run-core-offline.sh` from inside this lane shows **33 passed / 1 failed**, where the single
failure is the environmental `product-close waits for worker exit`. Paste the full tail. Also
paste the `review body persist` and `test-lane-diff-single-repo` sections proving the target fix
still holds.

<!-- attempt: post-reboot re-dispatch, lead 2026-08-04 -->
