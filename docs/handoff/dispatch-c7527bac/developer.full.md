verdict: APPROVE
next_action: review_round_2

# FLEET-RUNTIME round 4 — developer deliverable

Mission: fix exactly the four defects rounds 1-3 all reported as still present, nothing else,
inside the declared write set. Full detail (including the "Done means" greps, both mission-required
controls, and the extra control for edit 4) is in
`docs/handoff/FLEET-RUNTIME-UNATTENDED-01/report.md`'s new "Round 4" section — this file summarizes
the same work for the /leadv2 subagent protocol.

## What changed, per edit

**Edit 1 (controlled stop must not be restarted).** `leadv2-fleet-lib.sh` gained
`FLEET_STOP_EXIT_CODE=42`. `leadv2-fleet-unit.sh`'s default `--restart` changed from `always` to
`on-failure`, and `_render_service` now emits `SuccessExitStatus=${FLEET_STOP_EXIT_CODE}` alongside
`Restart=${4}`. `leadv2-fleet-runner.sh`'s four self-stop exit sites (`stop_flag`, `disk_floor`,
`no_landing_streak`, `no_arm`/`quota_window`) changed from `exit 0` to
`exit "${FLEET_STOP_EXIT_CODE}"`. The `unwired` wiring-gap path is untouched (`exit 2`, meant to be
retried).

**Edit 2 (unit file loads).** `WorkingDirectory=${2}` — quotes removed (systemd takes the rest of
the line literally there; quotes become part of the path). `Environment="LEADV2_FLEET_LANE_CMD=${5}"`
— whole assignment now quoted (systemd's documented syntax for a value containing spaces).

**Edit 3 (no control mutation ships inside the product).** Removed the `# c1-mut`, `# c2-mut`,
`# c3-mut` trailing comments from `leadv2-fleet-unit.sh`, `leadv2-fleet-runner.sh`,
`leadv2-fleet-lib.sh`. Updated `test-fleet-runtime-guards.sh`'s Group 0 assertions and Group H
mutation sed patterns to target the bare code lines (no marker dependency), and added a Group 0 case
asserting `grep -rn 'c[0-9]-mut' plugins/leadv2/scripts/fleet/` is empty.

**Edit 4 (reaper no longer forces) + a regression it exposed.** Removed both `--force` occurrences
(command + comment) from `leadv2-fleet-guard.sh`.

While verifying edit 4 I found that a non-forcing `git worktree remove` refuses on **any** untracked
file in the worktree — including `leadv2-fleet-runner.sh`'s own `.fleet-terminal` completion marker,
which round 2 wrote *inside* the worktree. Reproduced before touching anything:
```
$ git worktree add -q wt2 -b wt2-branch && : > wt2/.fleet-terminal
$ git worktree remove wt2
fatal: 'wt2' contains modified or untracked files, use --force to delete it
```
Without a fix, removing `--force` would have made every cleanly-landed lane permanently
unreapable — not a hypothetical, it reproduced on the very first "positive reap" case in the
existing suite once `--force` was removed. Fix (both files already in the declared write set):
the marker is now written as a SIBLING of the worktree directory
(`<worktree-dir>.fleet-terminal`, not `<worktree-dir>/.fleet-terminal`) by the runner, and read +
removed (on successful reap) by the guard. Git's dirty-check never sees a path outside the
worktree's own tree, so the marker no longer blocks its own reap.

## Controls run (both mission-required, plus one more for edit 4)

1. **Restart/SuccessExitStatus (Group I, new).** Runs the REAL runner with the stop flag pre-set
   (self-stops before any lane starts), captures its real exit code (42), and evaluates a
   mini-systemd decision function against the REAL generated unit's `Restart=`/`SuccessExitStatus=`
   (extracted from `print-unit`, not hardcoded). on-failure+SuccessExitStatus=42 → NO respawn.
   Negative control (same script, `--restart always`) → YES respawn, reproducing the round-2/3
   defect.
2. **Unit verification (Group J, new).** `systemd-analyze verify` when on PATH, else a structural
   parser stub (checks WorkingDirectory unquoted, Environment= fully quoted if present) — real
   generated unit → VALID; scratch copy with the pre-round-4 quoted WorkingDirectory reinstated →
   INVALID.
3. **Reaper never forces, extra (Group K, new, not mission-required but the direct proof of edit
   4's claim).** A worktree with a genuinely uncommitted tracked-file change, marked terminal. Fixed
   guard: refuses, leaves it in place, file intact. Negative control: scratch copy of guard.sh with
   `--force` reinstated → deletes the dirty worktree, reproducing the pre-fix data-loss defect.

Existing Group 0/H mutation controls (c1/c2/c3-mut, now markerless) re-verified RED as before.

## Self-check

```
$ bash -n plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh \
    plugins/leadv2/scripts/fleet/leadv2-fleet-state.sh plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh \
    plugins/leadv2/scripts/fleet/leadv2-fleet-lib.sh plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
(all OK — no output, no failures)
```
No Python files changed this round.

```
$ bash plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
... (12 groups, see report.md for full per-group breakdown) ...
42 of 42 passed (fleet guard suite, macOS Darwin, no systemd — unit layer stubbed per mission)
```
rc=0.

## Done-means greps (all four, clean)

```
$ grep -n 'Restart='                 plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
104:Restart=${4}
$ grep -rn 'c[0-9]-mut'              plugins/leadv2/scripts/fleet/
(no output)
$ grep -n 'WorkingDirectory'         plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
101:WorkingDirectory=${2}
$ grep -n 'worktree remove --force'  plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh
(no output)
```

## Write set discipline

Touched only: `leadv2-fleet-unit.sh`, `leadv2-fleet-guard.sh`, `leadv2-fleet-runner.sh`,
`leadv2-fleet-lib.sh`, `test-fleet-runtime-guards.sh`, `docs/handoff/FLEET-RUNTIME-UNATTENDED-01/report.md`,
and this task's own `docs/handoff/dispatch-c7527bac/developer.{summary,full}.md`.
`leadv2-fleet-state.sh` needed no change. `docs/leadv2/.compact-freeze.md` was already modified in
the worktree before this round started (pre-existing, unrelated, a runtime-state path) — left
untouched and excluded from this round's commit by pathspec.

## Left alone

`tests/mutations/catalog.yaml` (touched by round 3, outside the declared set) — not needed by any
of the four edits, not touched.

DELIVERABLE_COMPLETE
