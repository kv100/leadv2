# RESUME-LANE-ACCEPTS-PATH-01 — `--resume-lane` must accept an absolute path, or refuse it clearly

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RESUME-LANE-ACCEPTS-PATH-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh,tests/run-all.sh,docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

This is one small, self-contained defect. Do exactly this and nothing else.

## The defect (measured 2026-08-31)

`--resume-lane` accepts only a bare lane name. Given an absolute path to the lane's own worktree it
concatenates the two and refuses with a mangled path:

```
lane_placement_refused reason=no_lane_worktree_for_ref
  looked_for=.../.claude/worktrees//Users/.../.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01
```

The refusal shows a path nobody asked for and gives no hint about the accepted shape, so the caller
retries the same wrong thing.

## What to do

In `leadv2-dispatch-code.sh`, where `--resume-lane`'s value is turned into a worktree path:

- a **bare name** keeps working exactly as today (this is the common path — do not regress it);
- an **absolute path** that is the lane's worktree resolves to that lane;
- anything else refuses with a message that states the accepted shapes and echoes what was given —
  never a concatenated path.

Do not change any other behaviour, do not touch other flags, and do not refactor surrounding code.

## Acceptance

Create `plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh` with fixture worktrees — never
a real lane, never a real dispatch:

1. bare name of an existing lane ⇒ resolves to that lane (regression guard);
2. absolute path to that same lane's worktree ⇒ resolves to the same lane;
3. absolute path that is not a lane worktree ⇒ refuses, and the message names the accepted shapes;
4. the refusal message never contains a doubled `.claude/worktrees/` segment.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path: undo the path handling ⇒ suite red;
  revert ⇒ green; `git diff --stat` clean. A kill counts only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Both argument shapes work, a bad path is refused with a message that shows the accepted shapes, and
removing the handling turns the suite red with the exit code following.
