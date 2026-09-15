# REDSUITE-D-BURN-GOVERNOR-SUITE-ENCODES-A-SUPERSEDED-REQUIREMENT-01

Row `4ab82abf8512`. One red suite, ten failing cases, one cause — and **the subject is not broken.**

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.** This lane is
the one legitimate instance of its "changing the test instead of the subject" clause. Read that
clause before you write anything.

## What was measured, by the lead, on main, before this lane existed
macOS Darwin 25.6.0, run alone at a 400s ceiling, 2026-09-15: `test-burn-governor.sh rc=1
wall=195s`. That is **above the census's 120s ceiling**, so in the census this suite was also being
cut short — but it fails on merit at a budget it fits in, which is what the number above shows.

Ten cases fail and every one fails the same way — the governor answers `reason=disabled` whatever
the case configures:

```
3: burn==soft            verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
4: burn==hard            verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
5: burn>hard             verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
6: 24h window boundary   verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
8: missing db            verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled
9: hourly missing        verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled
10: sqlite3 absent       verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled rc=0
11: hard<=soft misconfig verdict=ok burn24h=0 soft=100 hard=1 reason=disabled
12: non-numeric threshold verdict=ok burn24h=0 soft=abc hard=1300000000 reason=disabled
13: NULL column          verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
```

## Why the subject is not broken — read this before touching the governor
`plugins/leadv2/scripts/leadv2-burn-governor.sh:112-118`, in `cmd_verdict`:

```
# BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01 (2026-09-07): default flipped 1 -> 0 on the
# founder's explicit order ("убери везде burn лимит"). It was refusing real work:
# dispatch task=12f54b7c died rc=6 with burn24h=2579779075 over hard=1300000000 and
# parked the lane that was proving the codex arm fixed. The gate is not deleted, so
# the rollback stays one flag: LEADV2_BURN_GOVERNOR=1 restores the old behaviour.
local governor_on="${LEADV2_BURN_GOVERNOR:-0}"
```

The default is off **by a recorded founder decision**. The suite was never updated and now asserts
the pre-order default. Note also that the file's own header at line 17 still documents
`LEADV2_BURN_GOVERNOR default 1 (0 disables …)` — the code and its own documentation disagree, and
the documentation is the stale party.

**Do not flip the default back to 1.** That reverses a founder decision, and it would re-introduce
the exact failure the comment records.

## What to do instead
1. Every case that exercises gate **behaviour** sets `LEADV2_BURN_GOVERNOR=1` explicitly. Those
   cases are about what the gate does when it runs, and they should keep asserting exactly that.
2. Add **one new case** asserting that with the variable unset the verdict is `reason=disabled`,
   and name `BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01` in its label. Without this the founder decision
   is guarded by nothing and the next person will "fix" the default back.
3. Correct the line-17 header so it documents the real default.
4. Check whether cases 11 and 12 still pass with the governor on: they exist to prove `hard<=soft`
   and a non-numeric threshold are **refused**, and `reason=disabled` was making both look
   accepted. If either genuinely fails once the gate runs, that IS a real subject bug — report it
   separately with its own control, and fix it if your write set covers it.

## Negative controls
At minimum two independent claims, so at least two controls:
- the behaviour cases: mutate inside `cmd_verdict`'s live path, show the suite go red, revert;
- the new default-off case: set `LEADV2_BURN_GOVERNOR=1` in the environment it runs under, show
  that case go red, revert.

## Deliverables
- The suite fix and the header correction.
- `docs/handoff/REDSUITE-D-BURN-GOVERNOR-SUITE-ENCODES-A-SUPERSEDED-REQUIREMENT-01/report.md` per
  `lane-rules.md`, quoting the decision id, date and `file:line` that licensed changing the test.

## Acceptance
```
cd ~/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-burn-governor.sh >/dev/null 2>&1
```
Red today (rc=1), ~195s. Give it room; report the wall time with the result.
