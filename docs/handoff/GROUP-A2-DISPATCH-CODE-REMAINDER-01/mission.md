# GROUP-A2-DISPATCH-CODE-REMAINDER-01

The remainder of the census-red suites that live around `leadv2-dispatch-code.sh`. **Five suites, not
seven** — two of the seven the plan originally listed are already green from main (see below).

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**
Also read `docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` — Face 3 is the same
cause as two of your suites, and Group A1 is fixing it for a third.

## Measured by the lead from main, 2026-09-16, macOS Darwin 25.6.0, 600s ceiling

```
test-t13-slice2.sh                    rc=1  wall=38s
test-claim-evidence-gate.sh           rc=1  wall=37s
test-phase-precondition-bootstrap.sh  rc=1  wall=30s
test-glm-deferred-ladder.sh           rc=1  wall=212s
test-dispatch-arm-vocabulary.sh       rc=1  wall=8s
test-dispatch-refusal-truth.sh        rc=0  wall=55s   <- ALREADY GREEN
test-writeset-admission-block.sh      rc=0  wall=17s   <- ALREADY GREEN
```

Do not touch the two green ones. `test-dispatch-refusal-truth.sh` is green because the row
`DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01` was fixed and merged after the census was taken;
`test-writeset-admission-block.sh` is green alone and may have been a sharding-only red — say which,
in one line, if you learn it cheaply, but do not spend the lane on it.

## Cluster 1 — the premise gate refuses the suites' own fixtures (2 of your 5)

Both of these fail for **one shared reason**, and it is not their subject:

`test-phase-precondition-bootstrap.sh` — every failure carries the same refusal:
```
FAIL: fresh Standard dispatch should exit 0 (rc=8, out=... premise_probe task=36c9123f
      verdict=refused reason=backlog_row_not_found ...)
FAIL: admitted dispatch spawned no worker
FAIL: dispatch after remedies should exit 0 (rc=8, same refusal)
FAIL: false verified-plan claim should exit 3 (rc=8, same refusal)
FAIL: false claim refusal should name plan and gate1 ()
FAIL: fresh Heavy dispatch should exit 0 (rc=8, same refusal)
```

`test-glm-deferred-ladder.sh` — the park rows are missing because the dispatch never happened:
```
FAIL: (a) park row missing for sig8=38131d44 -- deferred_file=<missing>
FAIL: (b) glm-deferred --list missing sig8=38131d44
FAIL: (c) expected exactly 1 codex_credits_empty line after 2 runs, got 0
       -- journal=... premise_probe task=6870a0d0 verdict=refused reason=backlog_row_not_found
FAIL: (e) expected count=2 after two distinct-sig8 refusals -- content=<missing>
```

Cause class for both: **`never_reaches_subject`**. The suites dispatch an ad-hoc mission that has no
row in `docs/tasks.yaml`, and `PREMISE-PROBE-BEFORE-A-LANE-IS-DISPATCHED-01` refuses with exit 8
before the code under test runs. Counting Face 3's `test-landed-at-spawn.sh`, that is **three
measured suites** killed by the same gate — a gate added for lane discipline that nobody taught the
test fixtures about.

The gate documents its own sanctioned way out: `--no-probe-yet` is "the explicit, audited escape
hatch for an intentionally ad-hoc dispatch with no backlog row". A test fixture is exactly that.

**Two cautions before you reach for it.**
1. It is honoured **only** when no backlog row is found at all (`leadv2-dispatch-code.sh:8366-8373`).
   A row that exists without a probe takes the `no_premise_probe` branch at `:8438` instead. That
   collision is filed as `NO-PROBE-YET-MEANS-TWO-DIFFERENT-THINGS-01`; do not fix it here, it is not
   in your write set.
2. `test-phase-precondition-bootstrap.sh` asserts on **dispatch exit codes**. Changing the
   invocation changes the thing under test. Make sure each case still tests what its name claims —
   if adding a flag makes a case vacuous, say so and restructure the case rather than let it pass
   for the wrong reason.

Group A1 is solving the same problem for `test-landed-at-spawn.sh` right now. **Read what A1 landed
before you invent your own technique**, and use the same one unless you can say why it does not fit.
Two different fixtures for one gate is how this rots again.

## Cluster 2 — a rotten negative control (1 suite)

`test-t13-slice2.sh` has exactly one failure:
```
FAIL: NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) unexpectedly still passed
```
Everything else passes, including three other negative controls (`NEGATIVE CONTROL 3b`,
`NEGATIVE CONTROL 4a`) and the structural scans. The suite also prints `UNGATED_SPAWN line=10961`.

So: the control's mutation **no longer bites**. Either the code it mutates moved and the mutation
now lands somewhere inert, or the assertion it was protecting is genuinely reachable without the
`allowed_arms` filter. Those are very different findings and you must distinguish them:
- If the mutation is inert, fix the mutation so it bites again and show it going red then green.
- If the filter really is bypassable, that is a **live routing hole**, not a test bug. Report it as
  such, loudly, with the path that reaches a spawn without the filter.

A negative control that has rotted into a permanent green is the failure mode this whole plan exists
to prevent. Do not "fix" it by deleting or weakening it.

## Cluster 3 — one localised case (1 suite)

`test-claim-evidence-gate.sh`:
```
FAIL: dispatch-mission-glm-h2 -- post-fix rc=1, expected 0
```
Everything else is green, including `C9 canonical marker sentence identical (count=1) in all three
sites`, `C9 marker absent from baseline (red-first confirmed)`, and a recorded
`RED-then-GREEN: rendered-prefix-h1 (pre_rc=1 -> post_rc=0)`. The harness works; one case does not.

## Cluster 4 — task-class does not surface in the dispatch trace (1 suite)

`test-dispatch-arm-vocabulary.sh`:
```
FAIL: case1: no journal and no stdout mismatch line found
FAIL: case9: --task-class Heavy did not surface in DC_TASK_CLASS / arm_excluded (dispatch trace had no match)
```
Note `case10` **passes**: "both fanout call sites forward `--task-class` to dispatch-code.sh". So the
forwarding is fine and the surfacing inside the dispatcher is not. This one does write
`leadv2-dispatch-code.sh`.

## Negative controls
Four independent clusters, so **at least four** controls, each run, each with both outputs pasted.
Cluster 2's control is special: you must show the repaired mutation actually biting.

## Boundaries
- Write set: `leadv2-dispatch-code.sh` and the five suites plus your report. Nothing else.
- Do not touch `leadv2-journal.sh` (Group C) or `leadv2-dispatch-product-close.sh` (Group B).
- Do not touch the two already-green suites.

## Deliverable
`docs/handoff/GROUP-A2-DISPATCH-CODE-REMAINDER-01/report.md` per `lane-rules.md`, with a cause class
per suite and an explicit statement of anything left red.

## Acceptance
```
cd ~/Projects/leadv2 \
  && bash plugins/leadv2/scripts/tests/test-t13-slice2.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh >/dev/null 2>&1
```
Red today. Budget it above 350s — `test-glm-deferred-ladder.sh` alone takes 212s.
