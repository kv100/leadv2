# MERGE-QUEUE-DEAD-HEAD-01 — a dead ENQUEUED head blocks every land

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MERGE-QUEUE-DEAD-HEAD-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-merge-queue.sh,plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh,tests/run-all.sh,docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Evidence (2026-09-01)
`~/.claude/leadv2-state/leadv2/merge-queue.jsonl` held an `enqueued` event for `dispatch-42bad5a1`
whose pid had been dead since 2026-08-30. `try_acquire` (leadv2-merge-queue.sh:154-182) reclaims
only a dead+stale HOLDER (`reason: dead-holder-stale`); an entry that never got past `enqueued`
is never examined, so every later `leadv2-deploy-merge.sh` printed WAIT forever — two days of no
lands. The lead unblocked it by appending a `timeout` event by hand
(`.bak-20260901` is the pre-edit ledger).

## Do
1. In `try_acquire`: before computing the head, drop (emit `reclaimed` with
   `reason: dead-enqueued`) every `enqueued` entry whose pid is not alive AND whose enqueue ts is
   older than `LEADV2_MERGE_STALE_SEC` — same threshold as holders, same ledger shape.
2. `status` must show such entries as `DEAD-ENQUEUED` rather than plain queued, so the next lead
   sees the reason in one line.
3. New suite `test-merge-queue-dead-head.sh` (hermetic: `LEADV2_MERGE_QUEUE_FILE` pointed at a
   temp file, a fake dead pid, a fake live pid via `sleep`): (a) dead enqueued head → next
   `try_acquire` by another task returns ACQUIRED/RECLAIMED, ledger has `dead-enqueued`;
   (b) live enqueued head → WAIT (no reclaim); (c) fresh dead head under the threshold → WAIT.
   Suite under 20 s. Add the `EXTRA_SUITE_MAP` row in `tests/run-all.sh` so a change to
   `leadv2-merge-queue.sh` selects it; prove with `--scope changed`.
4. Mutation negative control, RUN and paste red: remove the dead-enqueued branch → case (a) red.
   Revert.
5. `report.md`: suite time, green run, control red, `--scope changed` selection line. Commit
   in the lane (the lead lands; an uncommitted exit is a failed round).
