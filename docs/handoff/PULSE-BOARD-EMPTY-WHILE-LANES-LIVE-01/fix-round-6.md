# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 6: two items, then the lane closes

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-active-registry.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

HEAD is `273a14a`. Main is `6b5d651` — rebase onto it first.

**Round 5's fix is proven and stays.** The registry suite is diagnostic now: 6/0 with the change,
4/2 with the production file replaced by main's copy. I ran both. The sibling suites are unmoved
(10/0, 4/0, 8/0), and the foreign-repo row genuinely renders.

**One item is now OFF your plate.** The `❓N` leak carried from round 4 item 5 is **not this lane's
bug and not a bug in `leadv2-broad-status.sh` at all** — I traced it: `❓N` is the pending-questions
counter `Q_N` (`leadv2-status-surface.5s.sh:454`), and `test-status-surface.sh` renders against the
real `docs/leadv2/questions/` directory, which currently holds 139 pending rows. It is a
non-hermetic suite in the ANTI-SILENCE-STATUSLINE-01 lane, assigned there. Do not spend a minute on
it.

Two items remain.

## [Critical] own-repo lanes are invisible behind ephemeral state roots

The board renders the foreign-repo row but not the leadv2-own lanes.
`~/Projects/leadv2/docs/leadv2/active.yaml` has **zero** `task_id` rows; lanes register under
isolated `.ephemeral/leadv2-lwt.*` state roots that are never consolidated into the root the board
reads.

Same disease as the founding defect, one layer down: the registry is written where the reader never
looks. Either consolidate the ephemeral roots into the project root, or make the board read every
root a lane can register under — say which you chose and why.

Then paste a board render listing **every** live lane, own-repo and foreign, and hold it with a
suite that fails when an ephemeral-root lane is dropped. Mutation-prove that suite: remove the
consolidation, show RED, restore, show GREEN, clean `git diff --stat`.

## [High] the liveness prober — fourth round, still nothing delivered

Rounds 3, 4 and 5 all allowed a fix or a writeup and got neither. Tonight it escalated
`SESSIONSTART-HOOKS-DISCARDED-01` as `corroborated dead` **five times** — `pid dead` twice,
`pid birth mismatch` twice — while that lane was actively writing files and, on the last two
occasions, had already committed its round. It compounds: a dispatch refused with `lane_is_live`
still registers an arm row, so the next retry is refused too.

Fix it, or write `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/liveness-prober-false-dead.md`
naming the file:line of the pid check and of the refusal-registration write, and say so in
`report.md`. A fourth silent drop is a FAIL on its own.

## [Medium] `tests/run-all.sh`

Reconcile with main (keep the state-file bounding, the widened glob and the `freepool-arm.yaml`
case; re-apply this lane's rows) and add an `EXTRA_SUITE_MAP` row for
`test-lane-registry-outlives-dispatcher.sh` so CI selects it. Prove with `--scope changed`.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A suite that stays green with the fix removed is a failed control;
  a printed `RED control:` line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial —
  four rounds were nearly lost on disk today.

## Done means

A board render listing every live lane including own-repo ones, held by a mutation-proven suite;
the liveness prober fixed or written up with file:line; and CI selecting the registry suite.
