# REDSUITE-D-TERMINAL-STATE-PARTIAL-DIFF-AND-PARKED-CONTRACT-01

Row `088197b5e53d`. Two red suites on the terminal-state path.
Subjects: `leadv2-status-surface.sh` and `leadv2-helpers.sh`.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**

## What was measured, by the lead, on main, before this lane existed
macOS Darwin 25.6.0, each run alone at a 400s ceiling, 2026-09-15:

```
test-no-work-terminal.sh        rc=1  wall=116s
test-parked-worker-resume.sh    rc=1  wall=21s
```

### Suite 1 — `test-no-work-terminal.sh`, three failing cases
```
FAIL: partial_diff should stay refused (got: status: blocked ...)
FAIL: revived waited to timeout instead of finalizing original handle
FAIL: revive_blocked_by_gate waited to timeout instead of finalizing original handle
```
The entire freepool half of the suite is green (`freepool worker is never no_work`,
`freepool terminal reflects the real diff`, `freepool rides the shared waiting_worker beat`, and
three more). So the author path works and the defect is on the **revive** path.

Why this one matters beyond its suite: "waited to timeout instead of finalizing the original
handle" is the exact shape that makes **real work read as no work**. We watched the sibling of this
failure live today — a resumed lane journaling
`stop_gate_autocommit_skipped reason=empty_scope_writes_csv` left a worker's commits unmade. Treat
the two revive cases as the priority; `partial_diff` is the cheaper one.

Note the two revive cases fail identically. Test whether one mutation moves both before claiming
one cause.

### Suite 2 — `test-parked-worker-resume.sh`, exactly one case
```
FAIL: contract red-first (post=1)
```
All seven behavioural cases pass — `parked outcome carries continue next`, `parked lane launches
exactly one resume`, `second parked exit does not loop`, `second parked exit journals
already_attempted`, and three more. So the **behaviour is right and the contract assertion is the
thing that does not hold.** Read the contract before you touch any behaviour. If the contract
encodes something the behaviour deliberately stopped doing, `lane-rules.md` tells you exactly what
you must prove before changing a test instead of a subject.

## Deliverables
- Fixes with one negative control per independent claim (at minimum: one for `partial_diff`, one
  for the revive path, one for the parked contract — more if the revive cases turn out to be two
  causes).
- `docs/handoff/REDSUITE-D-TERMINAL-STATE-PARTIAL-DIFF-AND-PARKED-CONTRACT-01/report.md` per
  `lane-rules.md`.

## Acceptance
```
cd ~/Projects/leadv2 \
  && bash plugins/leadv2/scripts/tests/test-no-work-terminal.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh >/dev/null 2>&1
```
Red today (rc=1). `test-no-work-terminal.sh` needs ~116s — give it room and report the wall time.
