# MAIN-RED-SUITES-BLOCK-EVERY-LANE-01

Founder-approved standing row `SD-MAIN-CORE-SUITE-RED-01` (2026-09-01), re-taken 2026-09-15 with
the founder's standing order to take anything measurably broken. All writes in
**`~/Projects/leadv2`**, under `plugins/leadv2/scripts/tests/`.

## Why this is being paid for now
The review gate runs a falsifiability check on the suites a lane's diff maps to. A suite that is
**already red on main** returns `could_not_determine`, and the gate answers
`blocked: suite_falsifiability_undetermined`. The lane's own work is never judged.

Measured in this session alone, on lanes that had already written `DELIVERABLE_COMPLETE`:

| suite | where it blocked | measured |
|---|---|---|
| `test-dispatch-architect-prepass-late-artifact.sh` | lane `891a4f9b` | red in main AND lane, identical `premise_probe backlog_row_not_found`; the fixture never reached its own assertions. Fixed in `62e7a253`. |
| `test-dispatch-architect-prepass-orphan-timeout.sh` | same family | same cause, same fix |
| `test-lane-writes-scoping.sh` | lane `891a4f9b`, next round | red on main: `H5/M7/L11: post-fix did not pass (rc=1)` |

Two of the three had never tested their subject at all — they refused at a premise gate added
after they were written, and reported that refusal as a test failure for months.

A false red costs exactly what a false green costs. It costs a wasted round, a manual triage, and
one more step toward the day a real red is waved off as "just the environment".

## Step 1 — a census, and nothing else until it exists
Run every suite under `plugins/leadv2/scripts/tests/` on **unmodified main**, one at a time, with
an explicit per-suite timeout. Produce a table: suite, rc, and the **cause class**:

- `never_reaches_subject` — refused at a gate before its own assertions (the two above)
- `real_regression` — the subject genuinely broke
- `environment_dependent` — passes alone, fails under the runner; name the specific difference
- `timeout` — its own verdict, neither pass nor fail; state the bound you used
- `rc_127` — three causes under one code (missing file, missing interpreter, cwd-relative path);
  say which one, never report it as a test failure

Rules the census must obey:
- **A loop over zero items prints success.** If the enumeration finds no suites, that is a named
  outcome, not a pass. State the count before you state any result.
- The count carries its boundary: say how many suites exist, how many ran, how many are red.
  "16 red" without "of how many, on which platform" is not a number.
- Several suites are known Linux-only (`TWELVE-LINUX-ONLY-SUITES-01`, `LAST-LINUX-RED-FAST-NAMES-01`).
  Those are `environment_dependent` with a *named* difference — not "flaky".

Paste the census table in the report before any fix appears in the diff.

## Step 2 — fix only what the census justifies
Priority order, and stop when the budget runs out rather than rushing the tail:
1. `never_reaches_subject` — these are the cheapest and the most dangerous, because they are
   suites that have been asserting nothing while reporting a verdict. Fix each so it reaches its
   assertions (the `62e7a253` pattern: the audited `--no-probe-yet` escape hatch that the sibling
   fixtures already pass), and show the assertions actually firing.
2. `real_regression` — report it, and fix it only if the fix is small and obviously correct.
   A regression that needs design is a **new row**, not this one. Name it in the report.
3. `environment_dependent` — declare it as such **in the suite itself**, with the difference
   named, so the falsifiability check can stop treating it as undetermined.

## Hard prohibition
**Do not weaken or delete a suite to make it green.** Deleting an assertion, loosening a grep, or
wrapping a check in `|| true` turns a false red into a false green, which is strictly worse. A
suite you cannot fix honestly stays red and is named in the report as still-red, with its cause.
Greenness is not the deliverable; a correct verdict per suite is.

Distrust `2>/dev/null` — a swallowed error reads exactly like success.

## Acceptance
- The census table: total suites, ran, red, and a cause class for every red one.
- For each suite you changed: the paired measurement (before rc and reason, after rc), and proof
  its assertions now fire — not merely that rc became 0.
- A negative control per *changed suite*, RUN: restore the broken condition, show that suite go
  RED again, restore. One mutation is not a control for N suites. If you fixed many suites by one
  shared cause, one control for that cause is honest — say so explicitly and name the group.
- The red count on main, before and after, with the same boundary stated both times.

## Off limits
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — lanes `891a4f9b` and the queued
  prepass/refusal rows own it. If a suite is red because of a real defect in that file, **report
  it, do not fix it**.
- `leadv2-review-run.sh` — lane `e6816fbf` owns it.
- `test-dispatch-architect-prepass-late-artifact.sh` and
  `test-dispatch-architect-prepass-orphan-timeout.sh` are already fixed in `62e7a253`; use them as
  the worked example, do not redo them.
- Do not change the falsifiability check itself. This row makes the suites honest; it does not
  relax the gate.

## Report
`docs/handoff/MAIN-RED-SUITES-BLOCK-EVERY-LANE-01/report.md`: census table first, then per-suite
fix + control, then the before/after red count. End with `DELIVERABLE_COMPLETE`.
