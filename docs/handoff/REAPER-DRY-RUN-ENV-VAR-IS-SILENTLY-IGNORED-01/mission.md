# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01

Backlog row `0ef607442f84`. All writes in **`~/Projects/leadv2`**, file
`plugins/leadv2/scripts/leadv2-orphan-reaper.sh`.

## The defect
`DRY_RUN` is accepted from the environment and then **unconditionally overwritten** by the
script's own default. An operator who exports `DRY_RUN=1` — the universally understood way to ask
a reaper not to kill anything — gets a reaper that kills processes anyway, and is told nothing.

A safety switch that silently does the opposite of what it says is worse than no switch: it buys
confidence it does not earn. `--dry-run` as a flag is reported to work; the env var is the surface
that lies.

**Start by measuring it.** Run the reaper with `DRY_RUN=1` against a fixture that would be reaped
and record what actually happens. Do not fix anything you have not first reproduced — paste the
reproduction.

## Fix — pick one and say which
Either (a) honour `DRY_RUN` from the environment with the same semantics as `--dry-run`, or
(b) refuse at startup when `DRY_RUN` is set in the environment, naming the flag to use instead.
Silently ignoring it is the one option that is off the table. State your choice and the reason.

If the two surfaces can disagree (env says 1, flag absent; flag present, env says 0), state the
precedence you implemented and test that case too.

## Acceptance
- `DRY_RUN=1` against a fixture that would otherwise be reaped: **nothing is killed** (fix a), or
  the run refuses with a message naming `--dry-run` (fix b). Show the process still alive / the
  refusal text.
- `--dry-run` keeps working exactly as today — a regression test that would catch it breaking.
- The kill path still kills when neither switch is set. A dry-run fix that quietly disables the
  reaper is the same bug with the sign flipped; prove the live path survives.

## Negative control — one per independent check, RUN them
Restore the unconditional overwrite and show the `DRY_RUN=1` test go RED. If you also added a
precedence test, mutate the precedence and show that one go RED separately. One mutation is not a
control for two checks. Paste red-then-restored-green for each.

## Off limits
- Do not change WHICH processes the reaper selects — this row is about whether it acts, not about
  its target set.
- Do not touch the lane registry, the lane cap, or `leadv2-active-registry.sh`.

## Report
`docs/handoff/REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01/report.md`: the reproduction, the
choice and why, the tests, the controls. End with `DELIVERABLE_COMPLETE`.
