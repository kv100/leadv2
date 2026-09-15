# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01 — round 2

Backlog row `0ef607442f84`. Round 1 left an auto-checkpoint (`1fe356fe`) and was reviewed **FAIL:
2 High, 2 Low** — see `docs/handoff/dispatch-8a0d9618-review/critic.full.md`. All writes in
**`~/Projects/leadv2`**, in THIS worktree. Your round-1 work is still there; continue it, do not
restart.

## H1 — the switch still fails toward live
The fix honours only the literal string `1`:

```
102:_dry_run_env="${DRY_RUN:-}"
103:DRY_RUN=0
104:[[ "$_dry_run_env" == "1" ]] && DRY_RUN=1
```

Measured by the reviewer against your own lane copy:

```
env DRY_RUN=1    -> effective DRY_RUN=1
env DRY_RUN=true -> effective DRY_RUN=0
env DRY_RUN=yes  -> effective DRY_RUN=0
env DRY_RUN=on   -> effective DRY_RUN=0
```

`DRY_RUN=true` is not hypothetical: `leadv2-backfill-history.sh:38-40` uses `DRY_RUN=true` /
`DRY_RUN=false` as its own convention **in this repo**. An operator carrying that habit to the
reaper gets exactly what the row calls "worse than no switch" — the variable is set, the run says
nothing, processes die.

This is the same defect class the row exists to close, one spelling to the left.

**Fix — choose one and say which:**
- (a) accept the truthy spellings this repo already uses (`1`, `true`, `yes`, `on`, case-insensitive)
  and treat `0`/`false`/`no`/`off`/empty as off; or
- (b) accept only `1`/`0` and **refuse at startup** on any other non-empty value, naming the value
  and the accepted set.

What is not available is the current behaviour: silently discarding a value the operator set.
A safety switch fails toward safe.

**Test:** the full table above, each spelling asserted against the effective value — plus the
refusal case if you pick (b).

## H2 — no test and no report reached the diff
`review.diff` carried neither. Your regression suite
(`test-reaper-dry-run-env-precedence.sh`) is **uncommitted in the lane**, so from outside the lane
it does not exist. A suite that is not committed is not delivered.

**Fix:** commit the suite and the report on the lane branch. Re-diff the staged set in its own
call immediately before committing — a check chained onto the commit is a receipt, not a check.

## L2 — the controls bind to exact source bytes
`test-reaper-dry-run-env-precedence.sh:139,157` mutate by matching exact source text. That is a
control that rots into a permanent green the moment the line is reformatted: the mutation stops
matching, nothing is mutated, and the suite passes while proving nothing.

**Fix:** make each mutation fail loudly when its anchor does not match — an unmatched anchor is a
test failure, never a silent skip.

## L1 — trim the over-long inline rationale at `:59-69`
Keep the reason, lose the essay. One or two lines.

## Negative controls — one per independent property, all RUN
H1 and L2 are independent, and (b) adds a third (the refusal). For each: mutate, show the matching
test RED, restore, show green. Paste every pair. One mutation is not a control for three.

Also keep round 1's live-path control: with neither switch set, the reaper still kills. A dry-run
fix that quietly disables the reaper is the same bug with the sign flipped.

## Off limits — unchanged
- Do not change WHICH processes the reaper selects. This row is whether it acts, not its target set.
- Do not touch the lane registry, the lane cap, or `leadv2-active-registry.sh`.

## Report
`docs/handoff/REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01/report.md` — **committed**: the
spelling table measured after the fix, the choice and why, the tests, every control.
End with `DELIVERABLE_COMPLETE`.
