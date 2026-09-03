# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-pulse-empty-board.sh,plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

Round 1 is committed as `b63662a`. Read the original brief at
`docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/lane-mission.md`.

## What round 1 found, and it looks right

One line in `leadv2-status-collector.sh`: `LEADV2_LANES_ALL_REPOS=1`. If that is the root cause,
the collector was only ever scanning one repo, so a lane living in another repo was invisible and
the board rendered `ДОСКА ПУСТА` while that lane wrote thousands of files. That is a plausible and
economical explanation of the incident. It is also entirely unproven.

## What round 1 did that must not happen again

The worker cut `plugins/leadv2/scripts/tests/test-pulse-empty-board.sh` from **553 lines to 75** —
536 lines of existing coverage deleted. That deletion was **not** committed; the suite is restored
intact at `b63662a`, and you are resuming from the restored state.

Deleting a test suite is never part of a fix. If a case in it is genuinely wrong, change that case
and say why in the commit message; if it is inconvenient, it stays. This repo has lost weeks to
suites that were trimmed until they were green.

## The work

1. **Prove the diagnosis.** Show, by running the collector, that without `LEADV2_LANES_ALL_REPOS=1`
   a lane registered in another repo is dropped, and with it the lane survives into a row. If that
   is *not* the actual mechanism, say so and find the real one — do not keep a one-line change
   whose justification you cannot demonstrate.
2. **Keep `test-pulse-empty-board.sh` whole** and add to it, or put new cases in
   `test-collector-sees-registered-lane.sh`. Both suites must be green.
3. **The control**: a fixture with one registered live lane in `active.yaml` renders that lane as a
   row and does **not** render `ДОСКА ПУСТА`. Mutate the fix out — inside the function body, on the
   production file — and show the suite RED, then restore and show GREEN. A zero-match `sed` is a
   hard failure, not a skip.
4. **Live proof.** This is the requirement that matters most and the one the incident was reported
   from. Lanes are live on disk right now in both `~/Projects/leadv2/.claude/worktrees/` and
   `~/Projects/persona-engine/.claude/worktrees/`. Run the collector and the board against the real
   registry and paste the output showing a real lane as a real row.
5. `--scope changed` must select both suites from a dirty tree — a lane's control plane is always
   ~20 files dirty, so a fallback that needs a clean tree silently selects nothing.

## Out of scope

The `TypeError: 'NoneType' object is not iterable` that makes `lane_state_register` fail in the
`leadv2` repo is a **different** defect (`DISPATCH-LANE-INFRA-3PACK-01`) and lives in
`leadv2-dispatch-code.sh`, which is not in your write set. Two lanes editing that file will
collide. Leave it.

## Rules

- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  ignores it); no mutation applied to a scratch copy instead of production.
- Bash 3.2.57 only: no `read -N`, no bash-4 array idioms, no unbound array under `set -u`.
- `git add <file> <file>`, never `git add <dir>`.
- **Commit before you stop.** Round 1 did not, and the lead committed for you.

## Done means

The diagnosis demonstrated rather than asserted; `test-pulse-empty-board.sh` still 553 lines or
larger and green; the fixture control mutation-proven RED against production; a pasted live board
showing a real lane as a row; `--scope changed` selecting both suites; and one paragraph in
`report.md` naming what the collector read and why the row was lost.
