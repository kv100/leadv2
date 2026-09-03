# DISPATCH-PIN-CLUSTER-01 — round 6 (review said fail / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

Full report: `docs/handoff/DISPATCH-PIN-CLUSTER-01/review-r5.md`. Read it.

**Round 5 took the ground that mattered. Do not redo any of it:**
- **Defect B is FIXED** — the big one. The reviewer built the fixture the brief demanded: real
  `cmd_sweep` → real `path-of` → real `lv2_lane_dirty` emits `dead_with_unlanded_work` for a dirty
  dead lane and plain `dead` for a clean one, and the automatic invoker at
  `leadv2-dispatch-code.sh:5950` fires. That is the defect behind nine hand-committed worker deaths
  in a single day.
- **C3 FIXED** — the dirty-lane control now goes RED under two independent mutations.
- **H8 FIXED** (18/0, controlled), **H9 FIXED** (selection pasted), **C1 FIXED**.

What is left is one more relapse of the disease this cluster keeps returning to.

## [Critical] N1 — the C2 counts came back, the controls did not

`test-scope-gate-orchestration-dirt.sh:91-96` asserts with `grep -Fq '_pc_drop_bootstrap_dirt'`,
which matches the function's **own definition** at `lib/leadv2-lane-guard.sh:29`. Delete the call
site from the body of `lv2_lane_dirty` and **all four** "restored" C2 suites stay fully green.

Fourth round running where the load-bearing assertion is a grep against source text while the
runtime result is discarded. Rewrite it behaviourally: call the function, capture what it returns,
assert on that. Then delete the call site and show RED.

## [Critical] C2 — the restoration is not complete

Merge-base baseline for `test-scope-gate-orchestration-dirt.sh` is `13 green-pre-fix, 0
could-not-run`; the lane gives `9, 4 COULD-NOT-RUN`. Line `:113` still probes `_pc_lane_dirty`,
which the guard renamed to `lv2_lane_dirty`, so the four lane-dirtiness cases never execute — and
`COULD-NOT-RUN` is **not counted as a failure**, which is exactly why this read as restored.

Fix the probe to the current name, get back to 13/0, and make `COULD-NOT-RUN` count as a failure so
a silently-skipped case can never look like a pass again.

## [High] N2 — the new terminal is erased by a later write

`dead_with_unlanded_work` is missing from the write-once arms at
`leadv2-dispatch-ledger.sh:320,324,364`, so a later `write-terminal … landed` flips the state and
the pin is lost. The point of the terminal is that it survives until a human deals with the
unlanded work.

## [High] N3 — the `pass_unlanded` exception is transitive, and its comment is false

The exception at `:325-329` allows `pass_unlanded → refused → landed`; merge-base blocked both
hops. The code comment asserts the opposite of what the code does. Make the exception
non-transitive or justify the widening with evidence — but the comment must stop lying.

## [High] N4 — H9 has recreated itself one level down

A change to `lib/leadv2-lane-guard.sh` selects only 2 of the 6 suites that now grade it — the same
failure shape as H9, on the file the whole cluster now depends on. Add the mappings, paste
`--scope changed`.

## [Medium] N5-N7

N5: the sweep ignores `LEADV2_DISPATCH_TERMINAL_LEDGER=0` (proven). N6: `dead_with_unlanded_work`
has **zero readers** — absent from the allowlist at `:278` and the taxonomy at `:19`, so nothing
can act on the terminal the fixture proves is emitted; wire it in, including the pulse. N7:
scope-gate's pre-image is HEAD, so its pre/post discrimination is vacuous.

## Rules

- **An assertion that matches a function's own definition is not a control.** Neither is a negated
  command (`set -e` ignores it). Before finishing, grep your own write set for `grep -Fq` and
  `! grep` used as assertions and check every one.
- Every fix keeps a control you RUN: mutation INSIDE the function body, RED, revert, GREEN. Logs in
  `docs/handoff/DISPATCH-PIN-CLUSTER-01/round6-red/`.
- Bash 3.2.57 only. The r5 scan was clean — keep it that way.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

`test-scope-gate-orchestration-dirt.sh` back to 13/0 with `COULD-NOT-RUN` counted as failure; N1's
assertion behavioural and proven RED by deleting the call site; `dead_with_unlanded_work`
write-once and readable by the ledger, the taxonomy and the pulse; N3 resolved with the comment
made true; `--scope changed` selecting all six guard-grading suites (output pasted); and one line
per finding saying fixed or disputed-with-evidence.
