# Mission — the close gate calls a committed lane "produced nothing", and it races the worker

Repo: ~/Projects/leadv2.
File: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`.

## Measured 2026-08-23 on lane `4d5aabd0` — timestamps, not theory

That lane delivered a complete, correct change: commit `4d340e2`
"fix: detect workers parked on background jobs", 231 insertions across 10 files,
including a new suite `tests/test-parked-worker-resume.sh` wired into
`run-core-offline.sh`. The lead ran that suite by hand: **9 passed, 0 failed.**
`docs/handoff/dispatch-4d5aabd0/review.diff` is 20,320 bytes.

The gate nevertheless wrote:
```
status: blocked
reason: arm_produced_nothing
arm: codex
```

Observed file/commit times in that lane:
```
08:48:09  worker's commit 4d340e2
08:48:22  gate writes review-gate.md  (arm_produced_nothing)
08:48:24  arm-registered written
08:51:13  developer.stream.jsonl still growing — ~3 min AFTER the verdict
```

Two independent defects produce that verdict.

### Defect 1 — "clean worktree" is read as "produced nothing"

`pc_silent_arm_probe` (L1243-1276) ends with:
```
[[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] || return 1
_pc_lane_dirty "${_lane_root}" && return 1     # dirty  => NOT silent
return 0                                        # clean  => SILENT
```
A worker that **commits its work** leaves the worktree clean. The probe never looks at
commits, so committing properly is indistinguishable from doing nothing — and the
better-behaved the worker, the more likely it is judged silent. The commit existed 13
seconds before the verdict.

### Defect 2 — the probe runs while the worker is still alive

The stream kept growing for ~3 minutes after the verdict was written, so the worker had
not exited. Step 1 counts `"type":"assistant"` events; that stream now holds **16** of
them, which would have returned NOT-silent had the probe looked later. The 60 s growth
guard (`LEADV2_PC_SILENT_GROWTH_S`, L1259-1270) did not save it — determine why (the
stream file may not have existed yet at probe time, in which case `_PC_SILENT_STREAM_STATE`
is `absent` and the guard is skipped entirely) and close that hole.

## Required fix

1. **Commits count as production.** Before concluding silence, compare the lane branch
   against the base the gate itself uses: any commit ahead of base means NOT silent,
   whatever the dirty state. Take the base from the same source `pc_scope_diff` uses so
   the two cannot disagree.
2. **Never judge a live worker.** If the stream is `absent` OR was modified within the
   growth window, the probe must return NOT-silent — an absent stream must be treated as
   "too early to tell", never as evidence of silence. Where a worker pid/handle is
   available, a live process is also NOT-silent.
3. Keep the genuinely-silent path intact: a registered arm, worker exited, no commits
   ahead of base, clean worktree, no assistant events → still `arm_produced_nothing`
   with the existing `_pc_arm_advance` behaviour. Do not widen or narrow anything else,
   and do not touch the `empty_diff` / `unscoped_lane_work` verdict paths.

## Off-limits
- Do not touch `pc_scope_diff`'s verdict logic, the e2e gate, or any test assertion.
- Do not touch main's unrelated uncommitted files (another session owns them):
  no stash/reset/clean.
- Do not merge or alter anything in `.claude/worktrees/4d5aabd0` — that lane's commit is
  a separate deliverable awaiting its own re-gate.

## Verify (real pasted output)
1. Regression test reproducing the exact failure: a lane whose worktree is CLEAN but
   carries a commit ahead of base must NOT yield `arm_produced_nothing`.
2. Regression test: a probe run while the stream is absent, and again while it was
   touched < growth-window ago, must both return NOT-silent.
3. Positive control: a truly silent arm (registered, exited, no commits, clean, no
   assistant events) still yields `arm_produced_nothing` and still advances the arm
   exactly once.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Known
   pre-existing failures, NOT yours: `deferred-GLM ladder (V3-GLM-LADDER-01)` and
   `fanout classifier/runner guard`. Name them and move on.

## Deliverable
`docs/handoff/GATE-FALSE-SILENT-01/report.md` — changed lines with file:line, why the
growth guard did not fire, the four verifications with pasted output, `git diff --stat`.
**Run every verification in the FOREGROUND with a timeout; do not end your turn waiting
on a background job.** End with DELIVERABLE_COMPLETE.
