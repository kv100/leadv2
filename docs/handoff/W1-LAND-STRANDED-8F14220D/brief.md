Repository: ~/Projects/leadv2 (the leadv2 plugin's canonical source). SHARED TREE — never a bulk
`git add -A`, never a hard reset, never `git clean`, never `git stash`, never push to origin.

## The job

Three lanes finished real work, died, and their commits are stranded in worktrees under
`.claude/worktrees/`. Wave В1 of `docs/WAVES.md` is exactly this: get finished branches into main.
Two of the three are already landed (see below). **Land the third, and prove it.**

### Already done by the lead — do NOT redo

- `SELFCHECK-FORGED-MARKER-REGRESSION-01B` -> landed as `d539d364` (suite went 37/1 -> 38/0).
- `STALE-ROW-STARTING-GRACE-01` -> landed as `4aa51b34` (13/13, mutation control declared).
- `RECOVER-WAVE1-TEN-01` -> landed as `50148393` (report-only lane, single file).

### Your target

Branch in `.claude/worktrees/8f14220d1e93`, commit `d2971b7e`, "wip: suite fixes from prior run".
Five files, all test suites:

    plugins/leadv2/scripts/tests/test-idle-lead-guard.sh        (+27/-…)  <- CONFLICTS
    plugins/leadv2/scripts/tests/test-injector-dedup.sh
    plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
    plugins/leadv2/scripts/tests/test-phase-precondition.sh
    plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh

Measured by the lead at 2026-09-06T02:5xZ: a plain `git cherry-pick -n d2971b7e` onto main applies
four of the five and **conflicts on `test-idle-lead-guard.sh`**. The lead reverted that attempt;
main is byte-identical to `50148393` and has no conflict markers. Do not assume the conflict is
gone — reproduce it yourself first.

## How to land it — rebase, not cherry-pick

The lane's anchor is stale: main has moved on the same files while the lane ran. A cherry-pick
resolves the conflict line-by-line with no understanding of what main changed. **Rebase the branch
onto current main and resolve each conflict by reading BOTH sides** — then decide, per hunk, whether
main's version already covers the lane's intent. This exact failure has now cost us the same fix
written three times in three trees (`6abbc44f` in main is itself a union-merge of a parallel
evolution of another lane's fix), so understanding the conflict IS the task, not an obstacle to it.

## Proof required — do not skip any of it

1. **Per-suite before/after on main.** For each of the five suites, run it on main BEFORE your change
   and AFTER, and report both numbers. A suite that was green must not become red.
2. **If any suite ends red**, name the failing cases individually and say for each whether it fails on
   main WITHOUT your change. Do not call a failure "pre-existing" unless you measured it on main —
   measuring against the lane's own stale anchor is what produced a wrong verdict earlier tonight.
3. **State explicitly, for `test-idle-lead-guard.sh`, what the conflict was about** and which side you
   kept and why. One short paragraph.
4. `tests/known-red-suites.txt` and `tests/known-failures.txt` may only SHRINK. If your change would
   require adding a line to either, stop and report instead of adding it.

## Commit

Name every path explicitly in `git add`. Run `git diff --cached --name-only` and confirm nothing else
rode along — in particular NEVER commit `docs/leadv2/active.yaml`, `bus.jsonl`, `merge-queue.jsonl`,
`open-threads.md`, `.bus-offsets`, any `.lock`, `docs/LEAD_V2_STATE.md`, or another lane's
`docs/handoff/*/phases.d/`. The tree is shared and those files change under you.

Commit message: `test: land stranded suite fixes from lane 8f14220d1e93 (rebased onto main)`, with the
before/after numbers in the body.

## Discipline

- **`rc=0` means nothing in this repository.** Dispatch refusals, 17 failures and 5 failures all
  exited 0 tonight. Read the summary line, never the exit code.
- **Derive every zero a second way.** A grep returning nothing is more often a wrong grep than an
  absent implementation.
- If you cannot land a file honestly, land the ones you can, and report the rest as UNCERTAIN with
  the one command that would settle it. A partial landing with honest numbers is a good result; a
  full landing with a suite quietly turned red is not.

## Report

Write `docs/handoff/W1-LAND-STRANDED-8F14220D/report.md` in THIS repository (a path in any other
repository is outside your writable roots and the delivery will fail). Under 120 lines: the
before/after table, the conflict explanation, what landed, what did not and why.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.
