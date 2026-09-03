# DISPATCH-PIN-CLUSTER-01 — round 10: two items, then the lane closes

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

HEAD is `5b17fe8`. Main is `6b5d651` — rebase onto it first.

**Round 9 is proven and stays.** I ran all four controls myself:

```
LEADV2_CONSUMER_FARM_MUTATE_LOADER=leadv2-dispatch-code.sh          rc=1
LEADV2_CONSUMER_FARM_MUTATE_LOADER=leadv2-dispatch-ledger.sh        rc=1
LEADV2_CONSUMER_FARM_MUTATE_LOADER=leadv2-dispatch-product-close.sh rc=1
LEADV2_CONSUMER_FARM_MUTATE_LOADER=lib/leadv2-admission-class.sh    rc=1
clean run                                                           rc=0
```

Each fails the run by exit code naming its own loader, and the standing
`RED control: lib/leadv2-admission-class.sh` line that round 8 printed on an unmutated tree is gone
— that loader now resolves in a no-lib consumer farm. `test-dirty-lane-never-lands.sh` passes and
`test-lane-placement-pin.sh` is 27/0.

Two items remain. Both are small.

## [High] demonstrate the fail-CLOSED close gate — it is claimed but never shown

Round 8 claimed a fail-closed close gate, and the suite that would have proved it was
non-diagnostic at the time, so the claim still has no evidence behind it. The original defect was:
with the lib absent, the guarded source printed **0 bytes** to stderr, left `lv2_lane_dirty`
undefined, `write_terminal:265-276` skipped both pins, and a **dirty lane recorded `landed`**.

Show it directly, both directions pasted:

- lib absent from BOTH the local path and the canonical root, dirty lane ⇒ the terminal is **not**
  `landed`, plus the named error it emits;
- lib present, clean lane ⇒ `landed` as normal.

Then hold it with an assertion in `test-consumer-symlink-farm.sh` (or a sibling suite) and
mutation-prove that assertion: restore the fail-open behaviour, show RED, revert, show GREEN.

## [Medium] `tests/run-all.sh`

Reconcile with main — keep the state-file bounding, the widened
`scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob and the `freepool-arm.yaml` stem case; re-apply this
lane's rows on top — and add an `EXTRA_SUITE_MAP` row for `test-consumer-symlink-farm.sh` so CI
selects it. Prove with `--scope changed`.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A suite that stays green with the fix removed is a failed control;
  a printed `RED control:` line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The close gate shown refusing `landed` with the lib absent and granting it with the lib present,
that behaviour held by a mutation-proven assertion, and CI selecting the farm suite. Then this lane
is merge-ready into main at `6b5d651`.
