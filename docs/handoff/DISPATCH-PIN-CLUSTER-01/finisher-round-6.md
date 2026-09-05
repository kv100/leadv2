# DISPATCH-PIN-CLUSTER-01 — round 6 finisher (resume, do not restart)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

The previous worker committed `d45d792` ("fix(dispatch): preserve dirty lane death terminals") and
stopped partway. **Resume from it — do not restart.** Full brief: `fix-round-6.md`; the review it
answers: `review-r5.md`.

## Verified done by the lead just now — do not redo

- **C2 restored.** `test-scope-gate-orchestration-dirt.sh` →
  `0 passed(red->green), 0 failed, 13 green-pre-fix, 0 could-not-run`, matching the merge-base
  baseline exactly. The four `COULD-NOT-RUN` cases are gone.
- **H8 confirmed.** `test-close-chain.sh` → `18 passed, 0 failed`.
- `round6-red/` holds `n1-delete-bootstrap-call.log` and `n2-remove-dirty-death-pin.log`, so N1 and
  N2 have their RED artifacts.

## What is left

**N3 [High] — the `pass_unlanded` exception is transitive, and its comment is false.**
`leadv2-dispatch-ledger.sh:325-329` allows `pass_unlanded → refused → landed`; the merge-base
blocked both hops, so this lane made the ledger weaker than it was. Worse, the code comment asserts
the opposite of what the code does. Either make the exception non-transitive, or justify the
widening with evidence — but the comment must stop lying. Control: the chain
`pass_unlanded → refused → landed` must be rejected (or, if deliberately allowed, a test must
document the allowance and the comment must say so).

**N4 [High] — `--scope changed` selection is one level short.** A change to
`lib/leadv2-lane-guard.sh` selects only 2 of the 6 suites that now grade it. Same shape as H9, on
the file this whole cluster now depends on. Add the mappings and paste the `--scope changed` output
proving all six are selected.

**N6 [Medium] — `dead_with_unlanded_work` has zero readers.** The terminal is emitted and proven by
fixture, but it is absent from the allowlist at `leadv2-dispatch-ledger.sh:278` and the taxonomy at
`:19`, so nothing can act on it. Wire it in, including the founder pulse — a terminal nobody reads
is the same "verb nothing calls" failure that graded defect B unfixed for two rounds.

**N5 [Medium]** — the sweep ignores `LEADV2_DISPATCH_TERMINAL_LEDGER=0` (proven by the reviewer).
**N7 [Medium]** — scope-gate's pre-image is HEAD, so its pre/post discrimination is vacuous.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round6-red/`.
- **An assertion that matches a function's own definition is not a control**, and neither is a
  negated command (`set -e` ignores it). Before finishing, grep your own write set for `grep -Fq`
  and `! grep` used as assertions and check every one — that exact defect is why round 6 exists.
- Do not regress C2 or H8; re-run both before you stop and paste the counts.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- **Commit before you stop.** If you run out of room, commit what works and list plainly which
  findings remain — an honest partial beats work stranded in the lane.

## Done means

N3 resolved with a control and a comment that matches the code; all six guard-grading suites
selected by `--scope changed` (output pasted); `dead_with_unlanded_work` present in the allowlist,
the taxonomy and the pulse; N5 and N7 fixed or disputed with evidence; C2 still 13/0 and
close-chain still 18/0.
