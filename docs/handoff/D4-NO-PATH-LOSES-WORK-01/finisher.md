# D4 FINISHER — the code is written and its suite is green; only the evidence is missing

Do NOT redesign anything. Do NOT rewrite the three files. They are committed on this branch
(`348ba016`, `18e4636c`) and the suite passes 13/13 as of 2026-09-03T22:28Z:

```
PASS: several-handles-one-alive: ALL dead -> DEAD
PASS: bash/zsh agree: alive case (rc=0)
PASS: bash/zsh agree: several-handles-one-alive (rc=0)
PASS: A1 SIGKILL -> checkpoint commits tracked+untracked, tree clean after
PASS: A2 process-group-kill, 14 dirty files -> exactly ONE commit
PASS: A3 idempotent -- ONE (ORPHAN) commit across 2 runs, 2nd skipped_clean
PASS: A4 clean lane -> HEAD unchanged, no empty commit
PASS: A5 live worker -> skipped_alive, nothing committed
PASS: A6 out-of-scope dirty file -> orphan-quarantine/<lane>, not the lane branch
PASS: D12 --dry-run makes no commits
PASS: D12 LEADV2_ORPHAN_CHECKPOINT=0 makes no commits
SUITE_RC=0
```

Your job is the four things that stand between this and a merge. Nothing else.

## 1. A negative control for EVERY function you changed — not one for the lane

This rule superseded "one NC per row" today, and it was born from a measurement: lane D3 changed
two functions, ran one control, and the second function reached main with no assertion behind it.

- List every function in `leadv2-orphan-checkpoint.sh` and `lib/leadv2-lane-worker-alive.sh` that
  this branch added or modified (`git diff main...HEAD` — THREE dots).
- For EACH one: apply a mutation **inside that function's body** (never a top-level insert — a
  line-number insert that lands at top level makes every suite red for the wrong reason and reads
  as a pass), run the suite, record `baseline_rc` and `mutated_rc`, revert, re-run, confirm green.
- Report the pairs in a table: function → mutation → baseline_rc → mutated_rc.
- If a changed function has no mutation that turns the suite red, say so plainly. That is a
  coverage hole and it is a finding, not a failure to hide.

## 2. The liveness review criterion — check it yourself before claiming done

The defect this lane exists to kill is: **"I cannot ask" rendered as "it is not there."**
Liveness is a three-valued type — `alive` / `dead` / `unknown` — and `unknown` must be
unrepresentable as either of the others anywhere.

Read your own diff and answer in the report: is there ONE line where an unanswerable case becomes
`dead`? If yes, the row is not done, however many fixtures are green. Specifically confirm:
- `kill -0` failure is classified by **stderr**, not by exit code (rc=1 covers both
  *no such process* and *operation not permitted*).
- Liveness compares the pair **(PID, process start time)**, never the PID alone — PIDs are reused
  and a recycled PID gives false LIFE. `leadv2-lane-state.sh` already compares `pid_start_time`;
  match that discipline.
- A timeout is `unknown`, and `unknown` is never replaced by the last known value.
- No recorded handle at all → `unknown`, never `dead`.

## 3. CI must SELECT the suite

A green suite that CI never runs is worth nothing. Add the `EXTRA_SUITE_MAP` row in
`tests/run-all.sh` (~line 134+) mapping the changed scripts to
`plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh`, then PROVE it: run the runner
with `--scope changed` against a tree where one of those scripts is modified, and paste the output
line showing the suite was selected.

## 4. Say plainly what the green suite does and does not prove

The plugin **cache** is a separate real file. Editing `plugins/leadv2/scripts/…` in this worktree
does not change the dispatcher that is running right now. The report must contain, in words:
"verified by the suite against this lane's own copy; the live dispatcher loads the plugin cache and
is unaffected until that cache is updated and the session restarts." Do not present the green suite
as proof that the running system behaves differently.

## Bounds

- Both shells: the suite must pass under bash AND zsh and fail on disagreement. Unquoted `$var`
  does not word-split in zsh — a `for p in $pids` loop iterates ONCE over a glued blob and reports
  every lane dead. This trap was hit by the person who had documented it one screen earlier.
- Green on macOS and in a linux container; put both exit codes in the report.
- NEVER touch `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh` — all three are held by other sessions.
- Do not commit to `main`. Do not add to `tests/known-red-suites.txt`. Do not weaken an assertion
  to make something pass.
- Before you claim a file is saved, confirm it appears in `git ls-files` — `.gitignore:49`
  (`docs/handoff/*/*`) swallows handoff files silently and `git add` exits 0 while doing nothing.
- Deletion check before merge: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
  Two dots compare against main's current tip and report every file main gained since you branched
  as if you had deleted it.

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
