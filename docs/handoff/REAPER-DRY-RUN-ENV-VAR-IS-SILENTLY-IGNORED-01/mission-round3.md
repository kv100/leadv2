# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01 — round 3

Row `0ef607442f84`. Round 2 **landed on `main` (merge `dca2eeb1`) with its High unfixed**, and
shipped a suite that is green while the defect survives. All writes in **`~/Projects/leadv2`**.

## What is on `main` right now — measured by the lead, 2026-09-15

`plugins/leadv2/scripts/leadv2-orphan-reaper.sh` still carries the round-1 form:

```
_dry_run_env="${DRY_RUN:-}"
DRY_RUN=0
[[ "$_dry_run_env" == "1" ]] && DRY_RUN=1
```

Probed against that exact code on `main`:

```
DRY_RUN=1       -> effective=1
DRY_RUN=true    -> effective=0      <-- kills
DRY_RUN=yes     -> effective=0      <-- kills
DRY_RUN=on      -> effective=0      <-- kills
DRY_RUN=0       -> effective=0
DRY_RUN=<empty> -> effective=0
```

`DRY_RUN=true` is this repo's own convention: `leadv2-backfill-history.sh:38-40` uses
`DRY_RUN=true` / `DRY_RUN=false`. An operator carrying that habit gets a reaper that kills while
saying nothing — the state the row calls "worse than no switch".

## The second, worse problem: the suite is green anyway

`plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh` passes (`ALL PASS`) on `main`
today. A grep of that suite for `DRY_RUN=true`, `DRY_RUN=yes`, `DRY_RUN=on`, `truthy` or a refusal
assertion returns **nothing**. It tests only the literal `1`.

So the repo has moved from "known gap" to "false green": a suite now asserts this switch is
covered while the defect lives one spelling away. That is strictly worse than before the row was
opened, and fixing it is the more important half of this round.

## Fix — two parts, both required

**Part 1 — the switch.** Choose and state which:
- (a) accept the truthy spellings this repo already uses (`1`, `true`, `yes`, `on`,
  case-insensitive), treat `0`/`false`/`no`/`off`/empty as off; or
- (b) accept `1`/`0` only and **refuse at startup** on any other non-empty value, naming the value
  received and the accepted set.

Silently discarding a value the operator set is not an option. A safety switch fails toward safe.

**Part 2 — the suite.** Extend it to assert the **whole table above**, one case per spelling, plus
the refusal case if you pick (b). The suite must fail today, before your fix — run it against
unmodified `main` first and paste that red output. A suite that was already green cannot be the
evidence that this round fixed anything.

## Negative controls — one per property, all RUN
1. Restore the `== "1"` comparison → the truthy-spelling cases go RED.
2. If you pick (b): remove the refusal → the refusal case goes RED.
3. Keep the live-path control: with neither switch set, the reaper still kills. A dry-run fix that
   quietly disables the reaper is the same bug with the sign flipped.

Every mutation anchor must fail loudly when it does not match — an unmatched anchor is a test
failure, never a silent skip. Paste every red/green pair.

## Off limits
- Do not change WHICH processes the reaper selects. This row is whether it acts, not its targets.
- Do not touch the lane registry, the lane cap, or `leadv2-active-registry.sh`.
- Do not delete or weaken any existing assertion in the suite to make it pass.

## Report
`docs/handoff/REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01/report.md`, appended as `## Round 3`:
the pre-fix RED of the extended suite, the choice and why, the post-fix table, every control.
End with `DELIVERABLE_COMPLETE`.
