# PLUGIN-PAPERCUTS-01 round 2 — case P1 asserts a contract main deliberately retired

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-PAPERCUTS-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-plugin-papercuts.sh,plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh,docs/handoff/PLUGIN-PAPERCUTS-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## What happened

The lane was green in its own worktree (13/0) and is RED on main (12/1, exit 1 — the exit contract
is correct, that part is fine):

```
[TEST] FAIL: P1: beat loop outlived its run — still alive after UNKNOWN_MAX passes
```

This is not a merge accident. Both this lane and `WATCHER-LIFECYCLE-LEAK-01` (merged separately as
`d61b224`) rewrote `leadv2-single-lead-beat-loop.sh`, and the merge kept main's version because it
is strictly more capable: it kills the in-flight child on TERM and holds a race-safe singleton claim.

Main's version carries this, in its own words:

> `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` stop (fix-round H4) **is GONE**. Only a real zero stops
> the loop.

That removal was deliberate: a loop that dies on reader-error passes goes quiet, and the silence
this loop exists to prevent comes back. So `P1` asserts a contract that main removed on purpose.

## [Critical] 1 — decide which contract is right, do not tune the test until it passes

Two defensible answers, and the lane must pick one **and say why in `report.md`**:

- **Main is right**: an unknown-reader pass must never stop the loop. Then `P1` is testing a retired
  contract and must be replaced by one asserting main's actual rule — a loop stops on `ZERO_MAX`
  consecutive REAL zeros, and does NOT stop on reader errors. That new case must be shown to fail
  when the rule is mutated.
- **The lane is right**: an unbounded loop is the leak, and it needs some bound. Then argue it
  against the founder-blindness failure that motivated H4, and propose a bound that cannot go quiet
  — a bound that *reports* rather than exits, for instance.

The lead deliberately did NOT edit the assertion: changing a test so it stops catching something is
the exact failure this backlog exists to remove.

## [Critical] 2 — the owner tag is what this lane was for; keep it working

`leadv2-pulse-beat.sh` carries `LEADV2_BEAT_OWNER_TAG` and merged cleanly; cases P8/P8b are green on
main. Do not regress it while fixing P1. Its value is concrete: without an owner in the process, a
cross-repo sweep cannot tell whose watcher it is — the lead killed his own watchdog today for
exactly that reason.

## Acceptance

1. `test-plugin-papercuts.sh` is green on main, with the P1 replacement asserting whichever contract
   §1 chose;
2. the replacement case goes RED under a mutation of that contract inside the production body;
3. P8/P8b still green (owner tag regression guard);
4. `run-all.sh --scope changed` selects this suite on a `leadv2-single-lead-beat-loop.sh` change.

## Rules

- Never delete or weaken an assertion to reach green; if an assertion is wrong, replace it with one
  that is right and say so.
- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- Measure a suite's exit code WITHOUT a pipeline — `cmd > log 2>&1; echo $?`. Reading `$?` after
  `cmd | tail` measures `tail`, and the lead got a false "exit 0" that way today.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

Main's beat-loop suite is green because the contract it asserts is the contract main actually has,
and that assertion is proven able to fail.
