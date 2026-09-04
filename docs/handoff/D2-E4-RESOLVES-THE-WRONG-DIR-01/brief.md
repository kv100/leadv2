# D2-E4-RESOLVES-THE-WRONG-DIR-01 — FINISHER. The fix is written; the evidence is not.

Do NOT redesign and do NOT rewrite. Two real commits are already on this branch:

- `7de54f50` — E4 resolves the lane's REAL handoff dir, not `docs/handoff/<tid>`.
- `d072d785` — founder-shaped fixtures: dispatch-dir deliverable, no-deliverable dead,
  unreadable-dir unknown.

Changed files: `plugins/leadv2/scripts/leadv2-lane-liveness.sh`,
`plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`.

Your job is only what stands between this and a merge.

## Why this row matters — read it before you touch anything

E4 is the rung that decides whether a lane produced a deliverable. When it resolved the WRONG
directory, it found nothing and the lane read as "produced nothing". That misreading is what cost
this fleet twelve lanes in one night: a worker finished, its report sat in a directory E4 never
looked at, a lead saw no commits, declared death, and re-dispatched — and the re-dispatch
overwrote the previous attempt's stream, destroying the evidence. **The bug you are finishing is
the one that made completed work look like death.**

So the third state is not decoration. `unreadable-dir → unknown` is the whole point: a directory
that cannot be read is not a directory that is empty.

## 1. A negative control for EVERY changed function — not one for the lane

This superseded "one control per row" after lane D3 changed two functions, ran one control, and
shipped the second with nothing behind it.

- Enumerate every function this branch added or changed: `git diff main...HEAD` — **THREE dots**.
  Two dots compare against main's current tip and misreport files main gained since you branched.
- For EACH: apply a mutation **inside that function's body** — never a top-level line insert, which
  makes every suite red for the wrong reason and reads as a pass.
- Record `baseline_rc` and `mutated_rc`, revert, re-run, confirm green.
- Report a table: function → mutation → baseline_rc → mutated_rc.
- A changed function with no mutation that turns the suite red is a **coverage hole**. Say so.
  It is a finding, not something to hide behind a green line.

## 2. Ten consecutive runs, not one

A suite that passes once is not green — flakiness is exactly how a red main hides. Report the exit
codes of ten consecutive runs. If any run disagrees with the others, that disagreement IS the
finding and it outranks the rest of the report.

## 3. The three-state criterion — audit your own diff

`alive` / `dead` / `unknown`, and `unknown` must be unrepresentable as either of the others.
Answer explicitly in the report: is there ONE line where an unanswerable case becomes `dead`?
If yes, this row is not done, however many fixtures are green. Confirm specifically:

- `kill -0` failure classified by **stderr**, not exit code — rc=1 covers both *no such process*
  and *operation not permitted*.
- Liveness compares the pair **(pid, process start time)**, never the pid alone; PIDs are reused.
  And `pid: 1` is `launchd` — alive forever, so a row carrying it can never be reaped. Treat `1`
  and empty as NOT alive.
- A timeout is `unknown`; `leadv2-lane-liveness.sh` has been measured taking 20s+ under lock
  contention. `unknown` may never be replaced by the last known value.
- No handle on record → `unknown`, never `dead`.

## 4. CI must SELECT the suite

Add the `EXTRA_SUITE_MAP` row in `tests/run-all.sh` (~line 134+) mapping the changed script to
`plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`, then prove it: run with
`--scope changed` against a tree where that script is modified and paste the line showing the
suite was selected. A green suite CI never runs is worth nothing.

## 5. Say what the green suite does NOT prove

The plugin **cache** is a separate real file. Editing `plugins/leadv2/scripts/…` in this worktree
does not change the dispatcher running right now. The report must say, in words: "verified by the
suite against this lane's own copy; the live dispatcher loads the plugin cache and is unaffected
until that cache is updated and the session restarts."

## Bounds

- Both shells: pass under bash AND zsh, fail on disagreement. Unquoted `$var` does not word-split
  in zsh — `for p in $pids` iterates ONCE over a glued blob and reports every lane dead.
- Green on macOS and in a linux container; both exit codes in the report.
- NEVER touch `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh` — held by other sessions.
- Do not commit to `main`; do not add to `tests/known-red-suites.txt`; do not weaken an assertion.
- A file counts as saved when it appears in `git ls-files`, verified by eye — `.gitignore`
  swallows handoff paths silently and `git add` exits 0 while doing nothing.
- Deletion check before merge: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.

---

## LEAD NOTE — do NOT edit `tests/run-all.sh` in this lane

This lane was refused once with `writeset_conflict`: lane `D4-NO-PATH-LOSES-WORK-01` holds
`tests/run-all.sh`, because every lane that adds a suite needs a row in the same
`EXTRA_SUITE_MAP` table. The refusal is CORRECT — two lanes editing one table produce a merge
conflict at best and a silently dropped row at worst.

So, for this lane only:

- **Do not touch `tests/run-all.sh`.** It is outside your declared write set and the dispatcher
  will refuse you again if you add it.
- Instead, put the exact row you need in your report, verbatim and ready to paste — the pattern it
  must match, the suite path it maps to, and the line it belongs after. The lead lands it once the
  file is free.
- Your CI-selection claim then reads honestly: *"the suite exists and is green; its
  `EXTRA_SUITE_MAP` row is specified in this report and is NOT yet landed, so CI does not select it
  yet."* Do not write that CI selects it. A row that is not in the file does not select anything,
  and claiming otherwise is the exact lying-green shape this wave exists to remove.

Everything else in this brief stands unchanged.
