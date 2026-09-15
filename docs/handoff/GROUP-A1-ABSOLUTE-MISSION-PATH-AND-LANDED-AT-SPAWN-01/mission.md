# GROUP-A1-ABSOLUTE-MISSION-PATH-AND-LANDED-AT-SPAWN-01

Two red suites whose causes were **already located, with controls**, by the Wave-0 diagnosis lane.
This lane implements the two fixes. Subject: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**
**Read `docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` — Faces 1 and 3 — before
you touch anything.** That report is on main. It was produced by a lane that deliberately made no
production change, so nothing in it has been applied.

Its verdict matters for you: **four independent defects, not one.** Do not go looking for a shared
root-resolution fix. Two faces are yours; the other two belong to other lanes and you must not
touch `leadv2-journal.sh` or `leadv2-dispatch-product-close.sh`.

## Face 1 — `test-lane-placement-pin.sh`: an absolute `@mission` is refused
This one has cost us real time: today, twice, a `--resume-lane` dispatch with an absolute
`@mission` path was refused while the file existed on disk, in the lane branch and on main. Row
`RESUME-LANE-REJECTS-AN-ABSOLUTE-MISSION-PATH-01` is the owning backlog row and closes with this.

Observed refusal:
```
[leadv2-dispatch-code] REFUSE mission:
path=/tmp/root-path-f1.../repo/docs/handoff/X/mission.md
is absent from both lane worktree=/private/tmp/root-path-f1.../repo/.claude/worktrees/LANE and main
FACE-1-RC=5
```

Mechanism, already pinned: **`leadv2-dispatch-code.sh:1303`** sends the absolute filesystem path to
`git ls-tree`, which requires a **repository-relative tree path**. Lines **1313** and **1321**
repeat the same raw value in a candidate path join and a main-tree lookup, so all three need the
converted value, not just the first.

The diagnosis lane already proved the fix direction in a scratch copy: converting an absolute path
that lies beneath `PROJECT_ROOT` into `docs/handoff/X/mission.md` **before** the line-1303 lookup
turned `FACE-1-RC=5` into `FACE-1-CONTROL-RC=0`. That mutation moved Face 1 and nothing else.

Decide and state explicitly what happens to an absolute path that is **outside** `PROJECT_ROOT` —
it cannot become a tree path, and the refusal for it should say *that*, not "absent from both".
A refusal that names the wrong cause is the defect class we have been fighting all day.

Do not simply strip a prefix by string arithmetic: `/var` and `/private/var` are the same directory
on macOS and a naive prefix test will not match. The diagnosis's own control on that alias came
back `same_directory=1` but could not force a `/var` spelling from this host's `TMPDIR`, so treat
physical resolution as required, not proven unnecessary.

## Face 3 — `test-landed-at-spawn.sh`: the suite never reaches what it tests
Cause class `never_reaches_subject`. **The subject is correct** — the diagnosis verified target
keying is properly derived at `leadv2-dispatch-code.sh:481-495`:
```
target lane=/tmp/.../target-wt   PROJECT_ROOT=/tmp/.../decoy
WORK_ROOT=/tmp/.../target-wt     LEDGER_REPO_ROOT=/tmp/.../target
```

What actually happens is that the suite's ad-hoc mission has no backlog row, so the premise gate
invoked at **`:9098`** takes its no-row branch at **`:8410-8412`** and exits 8 before any ledger
assertion runs:
```
premise_probe task=ff7cfeec verdict=refused reason=backlog_row_not_found
FAIL: T-a: dispatch exited 8 (expected 0)
FAIL: T-b: dispatch exited 8 (expected 4)
[LANDED-AT-SPAWN-01] passed=4 failed=8
```

So the fix is in the **fixture**, not the subject: give the suite's dispatches either a real backlog
row or the audited `--no-probe-yet` route. `lane-rules.md` permits changing a test when the test is
the wrong party — here it plainly is, and the evidence above is your justification; quote it.

Related trap you will meet while doing this, already filed as
`NO-PROBE-YET-MEANS-TWO-DIFFERENT-THINGS-01`: dispatch-side `--no-probe-yet` is honoured **only**
when no backlog row was found at all (`:8366-8373`); a row that exists without a probe takes the
`no_premise_probe` branch instead. Pick whichever route actually works for the fixture and say which
and why. Do not fix that row's defect here — it is not in your write set.

## Boundaries
- Your write set is `leadv2-dispatch-code.sh` plus the two suites plus your report. Nothing else.
- Faces 2 and 4 are other lanes' work. If you find they share a line with yours, **say so in the
  report and do not act** — the diagnosis's double-ended control says no single line moves two
  faces, and if you have evidence against that, that evidence is the finding.
- `test-lane-placement-pin.sh` timed out at 240s in the diagnosis run. Give it room, report the wall
  time, and remember a timeout is a different verdict from a failure.

## Negative controls
Two independent claims, so **two** controls minimum: one mutation inside the line-1303 conversion
showing the placement suite go red and revert; one inside whatever the fixture fix touches showing
`landed-at-spawn` go red and revert. Paste both outputs.

## Deliverables
- Both fixes.
- `docs/handoff/GROUP-A1-ABSOLUTE-MISSION-PATH-AND-LANDED-AT-SPAWN-01/report.md` per
  `lane-rules.md`, naming explicitly what an out-of-root absolute mission path now does.

## Acceptance
```
cd ~/Projects/leadv2 \
  && bash plugins/leadv2/scripts/tests/test-lane-placement-pin.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-landed-at-spawn.sh >/dev/null 2>&1
```
Red today.
