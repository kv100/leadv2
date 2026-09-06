# CLOSE-GATE-CALLS-A-FINISHED-LANE-no_work-01 — proofs run by the lead

The worker committed the fix and its suite, then died before producing any of the proofs below.
These were run by the lead against the branch; each is reproducible from the command shown.

## 1. The suite carries BOTH shapes, which was the whole point

    [TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
    [TEST] PASS: Case A: 3 commits ahead of origin/main are NOT stamped no_work/empty_diff
    [TEST] PASS: Case A: no empty_diff ledger row for the lane with real work ahead of main
    [TEST] PASS: Case B: a lane whose work genuinely landed in main is still stamped empty_diff
    [TEST] PASS: Case B: ledger row is no_work/empty_diff for the landed lane
    [TEST] 5 passed, 0 failed

Case A is the 2026-09-04 defect (lane `6436a2e2` stamped `no_work` while carrying 3 commits and 363
insertions). Case B is the legitimate verdict observed on the same lane on 2026-09-06 after its work
had landed. A fix that merely stopped emitting `no_work` would pass A and fail B, and would strand
re-dispatch forever.

## 2. Mutation control — inside the function body, both colours

Mutation: `return 0` inserted as the first statement of `_pc_diff_base_main()`, disabling the fix
(the origin/main diff-base candidate) while leaving the file syntactically valid.

    mutated    rc=1   3 passed, 2 failed
    restored   rc=0   5 passed, 0 failed      (byte-identical restore, `git status` clean)

The two failures under mutation are exactly the Case A assertions; Case B still passes. The control
kills the new behaviour specifically, not the suite as a whole.

## 3. Guarding suites — 21 of the 42 that guard leadv2-dispatch-product-close.sh

Four are red on the branch. **Every one of the four was baselined on clean main
(`559a91b6`) by running the same suite in a detached worktree**, and none is a regression:

    suite                                   branch      clean main
    test-no-work-terminal                   54 / 4      53 / 5      <- branch is BETTER by one case
    test-dispatch-product-close-exit-trap    6 / 2       6 / 2
    test-worker-outlives-terminal-state     10 / 1      10 / 1
    test-plugin-reliability-01              19 / 2      19 / 2

`test-no-work-terminal` is the suite that guards this exact behaviour, and the change fixes one of
its failing cases. `tests/known-red-suites.txt` was not touched and did not grow.

## 4. CI selects the new suite

    $ rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
    $ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
    [SELECT] .../plugins/leadv2/scripts/tests/test-close-gate-nowork-abandoned.sh

48 suites selected in total; the new one is among them.

## 5. Blast radius — measured, not repeated

The filed row estimated "72 branches of committed-but-abandoned work". The lead's independent census
of `~/Projects/leadv2` on 2026-09-06:

    lane branches                                          405
    carrying a non-anchor commit not in main                62
    of those, carrying two or more                           5

So the real population is **62**, not 72 — and of the five substantial ones, all five turned out to
be landed-under-a-reworded-subject or superseded by a sibling, not abandoned. See
`docs/handoff/WAVES-TASKS-RECONCILIATION-01/nothing-lost-20260906.md` in persona-engine. The
mechanism this fix addresses is real and worth fixing, but it has not, on this evidence, stranded
delivered work.

Method note: count with `git for-each-ref 'refs/heads/worktree-*'` **quoted** — unquoted, zsh expands
it as a filesystem glob and the census silently reports zero branches.
