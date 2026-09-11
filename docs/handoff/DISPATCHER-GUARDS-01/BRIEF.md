# DISPATCHER-GUARDS-01 — two refusals `leadv2-dispatch-code.sh` owes

Two backlog rows, one file, one lane so they cannot collide:

- `RESUME-LANE-ACCEPTS-A-MISSION-ITS-WORKTREE-CANNOT-SEE-01`
- `DUPLICATE-DISPATCHER-RECORDS-A-TERMINAL-FOR-A-LANE-IT-NEVER-PLACED-01`

Both were measured on 2026-09-11 and both cost real rounds the same day. Each is a case
where the dispatcher **continues past a condition it already detected** and the result
reads as a completed round.

## Defect 1 — a mission the lane worktree cannot see

`--resume-lane` accepts `@<path>` without checking the path resolves **inside the lane
worktree**. A mission committed to main *after* the lane branch was cut is invisible to
the worker, and nothing says so.

Measured, lane `0e3619bc27e0` / task `3b69d511`: `ROUND-2.md` was committed to main as
`51ce2ac5`; the lane sat on branch `worktree-0e3619bc27e0`, cut earlier; the worktree held
only `BRIEF.md` (round 1). The glm worker ran 30 minutes on round-1 instructions it had
already satisfied and auto-committed `33387ac9` containing nothing but `a.txt`/`b.txt`/
`c.txt` test junk. The reader was byte-unchanged at 266 lines. No journal line mentioned a
missing mission. The same trap then fired a second time the same evening on lane
`12cd3a2f6d16`, whose worktree held revision 1 of a brief whose revision 2 was on main.

There is a known rule "an untracked brief is absent from the worktree". **Tracked is not
sufficient** — the mission must be reachable from the LANE's branch, and `--resume-lane`
is precisely when that fails, because the branch is old by definition.

**Change:** on `--resume-lane`, resolve `@<path>` against the lane worktree
(`git -C <wt> ls-tree --name-only HEAD -- <path>`) and **refuse loudly** when it is not
there, printing the remedy:

    git -C <wt> checkout main -- <path> && git -C <wt> commit -- <path>

A missing mission must never read as a completed round.

## Defect 2 — a duplicate writes the terminal for a lane it never placed

A dispatcher that is refused placement continues into the gates of a lane it does not own,
and records that lane's terminal state.

Measured, same task `3b69d511`: two invocations ran 15:29–15:56Z. The first placed a live
glm worker (run `260911-182953-0e3619bc27e0-72e3`, alive at 27 min). The second logged
`lane_placement_refused reason=lane_is_live probe_id=0e3619bc27e0 verdict=starting:25` at
15:31:08 — and then ran the e2e gate anyway: 127 suites selected, rc=124 at
`timeout_s=3600` after 39 completed, then
`dispatch_terminal task=3b69d511 terminal=parked cause=e2e_timeout` at 15:56:15.
`dispatch_terminal_dedup` confirmed it won the race, so the live worker's own terminal
became unrecordable.

Two things are wrong and both must be fixed:

- **The continuation.** A dispatcher refused placement must exit at the refusal. It owns
  nothing in that lane; running its gates burns an hour and corrupts the lane's record.
- **The cause string.** `cause=e2e_timeout` names a downstream symptom. A reader sees a
  lane that built and stalled, not a duplicate that never built. Whatever terminal a
  non-owner could ever write must name the refusal, not what happened after it.

This is the WRITER side and is upstream of row `ff3b4cf52a02`
(`WATCHER-BLIND-TO-A-REDISPATCHED-LANE-01`), which is the reader side. That row says do not
watch terminal-line growth; this one says stop a non-owner from writing the line. Do not
close one by citing the other.

## Suites

`scripts/tests/test-resume-lane-refuses-invisible-mission.sh`

1. `--resume-lane` with a mission present in the worktree → proceeds.
2. Mission present on main but NOT in the worktree → refuses, non-zero, and the printed
   remedy contains both the worktree path and the mission path.
3. Mission absent from both → refuses, and says so distinctly from case 2 (a mission that
   exists nowhere is a different error from one the branch cannot see).
4. A non-resume dispatch is unaffected — same behaviour as today, byte-identical journal
   lines.

`scripts/tests/test-placement-refusal-exits-before-gates.sh`

5. Placement refused → the process exits at the refusal; assert NO `e2e_gate` line and NO
   `dispatch_terminal` line is written by that process.
6. Placement granted → the full chain runs as today.
7. The lane's real owner can still record its terminal after a refused duplicate has come
   and gone — i.e. the refusal left no `terminal_already_recorded` residue.

Fixtures in the suite's own temp dir. A suite whose result depends on live quota or a live
lane is a suite that reddens on a healthy system.

## Negative control

`scripts/tests/nc-dispatcher-guards.sh` — mutate the real script into a scratch copy, point
the suites at the mutant, assert RED **on the named case**:

- (a) accept `@<path>` without the worktree check → case 2 must go red.
- (b) let a refused dispatcher fall through into the gates → case 5 must go red.

If a mutation pattern is not found, **exit non-zero loudly**. A mutant suite that reddens
some other case is not a pass either. Both of those failure shapes have shipped here.

## Hard constraints

- Prove no regression for the ordinary path: one plain dispatch and one `--resume-lane`
  with a visible mission, before and after, emitting byte-identical journal decision lines
  apart from the new refusal lines.
- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file (`git ls-files --error-unmatch`).
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Do not touch `plugins/leadv2/scripts/leadv2-repo-install.sh` or the markdown-backlog
  tests — other lanes are editing both.
- Commit in `~/Projects/leadv2` with `git commit -- <your paths>`; do not push.

## Report back

Under 300 words: commit sha, suite counts for both suites, the NC output for both
mutations naming their case, and the before/after journal lines proving the ordinary path
is unchanged.
