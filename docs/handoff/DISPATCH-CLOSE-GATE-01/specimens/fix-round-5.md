# DISPATCH-PIN-CLUSTER-01 — round 5 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,.gitignore

Eight commits, HEAD `2f6649d`. Full report:
`docs/handoff/DISPATCH-PIN-CLUSTER-01/review-r4.md`. Read it.

**Won, and mutation-proven by the reviewer — do not redo:**
- **Defect C (plan-not-in-lane) is FIXED.** The glob is anchored, both silent arms journal.
- **Defect D (class-from-mission-length) is FIXED.** The floor applies across the digest-match
  early return and the suite drives the real `_admission_classify`.
- H1, H2, H4, H5 verified fixed by **production probes**, not reading. H4 confirmed on
  `/bin/bash` 3.2.57 under `set -u`.
- H3's code fix is real: the reviewer's standalone CLOSE-gate probe flips
  `reason: no_work` → `reason: unscoped_lane_work` when the shadow is reinserted.

Two of four original defects are genuinely closed. That is the first real ground taken on this
cluster. What is left is worse than it looks, because it is invisible to CI.

## [Critical] C3 — the dirty-lane control is inert: `! grep -Fq` under `set -e`

`test-dirty-lane-never-lands.sh:89` asserts with `! grep -Fq …`, and `set -e` does not trip on a
negated command. So MUT-1 **survives green while the artifact literally contains the defect** —
proven with an instrumented run. That is the load-bearing control for defect A, and it cannot
fail. Rewrite it to capture the grep result and assert on it explicitly, then prove the rewrite by
reinserting the defect and showing RED.

## [Critical] C2 — this lane broke four other suites and CI is blind to it

Deleting `_PC_PORCELAIN_EXCLUDE_RE` / `_pc_phys` / `_pc_drop_bootstrap_dirt` from
`leadv2-dispatch-product-close.sh` (the H3 de-shadowing) broke four suites, bisected against
`e9e22d3`:

```
t13-slice1            19/0  → 16/3
scope-gate            9 passed → 2 FAIL + 11 could-not-run
merged-sweep          8/0   → 1 FAIL
worktree-lane-safety  24/0  → 1 FAIL
```

They were not shadowing duplicates after all — other call sites depend on them. Restore what is
still needed as a single definition (sourced, not re-defined) so both the CLOSE gate and these
four suites get the fixed behaviour.

## [High] H8 — `test-close-chain.sh` 18/0 → 17/1 is a proven regression

The `pass_unlanded` write-once removal from round 3 (M7). Bisected against the merge-base ledger.
Restore the write-once semantics or justify the change with evidence and fix the suite
deliberately — but it may not simply stay red.

## [High] H9 — the reason all five regressions shipped green

`run-all.sh --scope changed` selects **zero** suites for `leadv2-dispatch-product-close.sh` and
`leadv2-dispatch-ledger.sh`. Two of the most load-bearing files in the dispatcher have no CI
mapping at all. Add the rows and prove selection with `--scope changed`, pasting the output. This
is the same shape as `tests/contract/` having no mapping — the failure mode this repo has been
burned by repeatedly.

## [Critical] Defect B is NOT FIXED — and this round it went backwards

Graded down from PARTIAL. The mechanism, named by the reviewer:

- `dispatch_ledger_sweep_write_dead` **takes no lane root** and deliberately bypasses the
  dirty-lane funnel, so it cannot see that a dead lane has uncommitted work.
- `cmd_sweep` has **no automatic invoker at all** — the only entry point is the CLI verb at
  `leadv2-dispatch-code.sh:7698`, which nothing calls.

That is precisely why **six worker deaths today** each needed a human to notice uncommitted work
in a lane and commit it by hand. Today's toll, all in this session: 150 lines, 263 lines, 0 lines,
43 lines, 111 lines, and one worker that wrote 62 insertions into the MAIN checkout instead of its
lane.

Build the missing half:
1. `dispatch_ledger_sweep_write_dead` must take the lane root and run the dirty-lane funnel before
   recording a terminal state. A lane with uncommitted work under its write set is not `dead`, it
   is `dead_with_unlanded_work` — a distinct terminal the ledger records and the pulse can show.
2. Give `cmd_sweep` an automatic invoker: every dispatch should sweep dead lanes before it
   registers a new one. A verb nothing calls is not a mechanism.
3. Control: a fixture lane whose worker process is gone while its write set is dirty must produce
   the new terminal, and must NOT produce plain `dead`. Mutate the funnel out and show RED.

Do not report B fixed on the strength of a suite. Report it fixed when a killed worker leaves a
lane and the dispatcher itself names the uncommitted work.

## [Medium] C1 recurrence is one command away

HEAD is clean — 0 tracked residue, no absolute symlinks — but `ef90ce2` still carries 16 in
history, and **neither residue prefix is gitignored**. Add `plugins/leadv2/scripts/docs/` and
`plugins/leadv2/scripts/.claude/` to `.gitignore` so `git add plugins/` cannot do it again.

**Write set note (corrected):** round 5's first dispatch omitted `lib/leadv2-lane-guard.sh` and the
four C2 harnesses from LANE_WRITES, and the worker correctly stopped to ask rather than write
outside its scope. That was the lead's error. All ten files above are now in scope — edit them
freely; nothing else.

## Rules

- Every fix keeps a control you RUN: mutation inside the function body, RED, revert, GREEN. Leave
  the RED logs in `docs/handoff/DISPATCH-PIN-CLUSTER-01/round5-red/`.
- **An assertion that cannot fail is not a control.** C3 is one; check every negated-command
  assertion in your write set for the same `set -e` hole.
- Run the four suites C2 names before you finish. A round that fixes six things and breaks four is
  not progress.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

The four suites in C2 back to their pre-lane counts, `test-close-chain.sh` 18/0,
`test-dirty-lane-never-lands.sh` with a control that actually fails, `--scope changed` selecting
suites for both dispatcher files (output pasted), the sweep mechanism built with its control, and
one line per finding saying fixed or disputed-with-evidence.
