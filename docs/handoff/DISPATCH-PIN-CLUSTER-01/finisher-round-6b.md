# DISPATCH-PIN-CLUSTER-01 — round 6 second finisher (resume, do not restart)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

HEAD is `5ff8e54`. Resume from it. Context: `review-r5.md` and `finisher-round-6.md`.

## Done — verified, do not redo

C2 (`test-scope-gate-orchestration-dirt.sh` at `13 green-pre-fix, 0 could-not-run`), H8
(`test-close-chain.sh` 18/0), N1, N2, and now **N6** — `dead_with_unlanded_work` reaches the pulse
and the taxonomy, with `n6-pulse-dead-with-unlanded-work.log` in `round6-red/`.

Four findings remain. They are the last thing standing between this cluster and a merge.

## [High] N3 — the `pass_unlanded` exception is transitive, and its comment is false

`leadv2-dispatch-ledger.sh:325-329` allows the chain `pass_unlanded → refused → landed`. The
merge-base blocked both hops, so this lane currently leaves the ledger **weaker** than it found it.
The code comment states the opposite of what the code does.

Make the exception non-transitive, or justify the widening with evidence — either way the comment
must become true. Control: the three-step chain is rejected (or, if deliberately allowed, a test
documents the allowance and the comment says so).

## [High] N4 — `--scope changed` selection is one level short

A change to `lib/leadv2-lane-guard.sh` selects only 2 of the 6 suites that now grade it. This is
the same shape as H9, on the file the whole cluster depends on: a suite CI never selects is worth
nothing. Add the mappings and paste the `--scope changed` output showing all six.

## [Medium] N5 — the sweep ignores `LEADV2_DISPATCH_TERMINAL_LEDGER=0`

Proven by the reviewer. The kill switch does not switch anything off.

## [Medium] N7 — scope-gate's pre-image is HEAD, so its pre/post discrimination is vacuous

The suite compares against HEAD, which already contains the fix, so "green-pre-fix" cannot
distinguish anything. Give it a real pre-image.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round6-red/`.
- **An assertion that matches a function's own definition is not a control**, and a negated command
  is not an assertion (`set -e` ignores it). Grep your own write set for `grep -Fq` and `! grep`
  used as assertions before you finish.
- Re-run `test-scope-gate-orchestration-dirt.sh` and `test-close-chain.sh` before stopping and
  paste both counts — they are currently correct and must stay that way.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- **Commit before you stop.** If you cannot finish all four, commit what works and say plainly
  which remain — the last two workers on this lane each did one finding and stopped, which is fine,
  but only because they committed.

## Done means

N3 fixed with a control and a truthful comment; all six guard-grading suites selected by
`--scope changed` (output pasted); N5 and N7 fixed or disputed with evidence; C2 still 13/0 and
close-chain still 18/0.
