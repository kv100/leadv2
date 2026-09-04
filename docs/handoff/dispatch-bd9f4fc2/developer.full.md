verdict: APPROVE
next_action: review_round_2

# WORKERS-MUST-COMMIT-01 round 2 — developer full report

Both High findings from the round-1 review are fixed, committed on the lane branch
(commit `48a5140`), and self-verified. Full evidence, mutation controls, and the
baseline-comparison for pre-existing suite failures are written to
`docs/handoff/WORKERS-MUST-COMMIT-01/report.md` (§ "Round 2 evidence" / "Left alone
(round 2)") — pasting the same content here per the task's own instruction to put
"## Round 2 evidence" in report.md.

## What changed
1. `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` — `git status --porcelain`
   → `--porcelain --untracked-files=all` so a new untracked directory is classified
   file-by-file, not collapsed to one `?? dir/` line (was misfiling in-scope work as
   foreign, the BEAT-LOOP-ORPHANS-01 defect this task exists to remove).
2. `_lv2_epilogue_lane_writes()` and `leadv2_worker_commit_epilogue()` now accept an
   optional mission-file-path override (still defaults to `${run_dir}/prompt.txt`,
   unchanged for the three coder wrappers).
3. Wired the epilogue call into `kimi-coder.sh` and `freepool-coder.sh` at the exact
   same post-`deadhand_check`/pre-`leadv2-lane-outcome.sh` window `glm-coder.sh`
   already used.
4. Wired the epilogue into `claude-subsession.sh` at both of its finalize points (sync
   `WAIT=1` path and the detached-background inline waiter), passing `MISSION_FILE` as
   the mission-file override and `PROJECT_ROOT` as `cwd_dir`.
5. Added a `no_lane` outcome: `leadv2_worker_commit_epilogue()` now checks
   `git -C "${cwd_dir}" rev-parse --is-inside-work-tree` first and reports
   `worker_exit=no_lane` (instead of silently no-op'ing) when the cwd is not a lane
   worktree — covers `--protected` mode on any arm.
6. `test-worker-commit-epilogue.sh`: added `case_e` (new dir in-scope → committed
   file-by-file), `case_f` (new dir out-of-scope → foreign_dirty per file),
   `case_g` (grep-gate: all four launchers wire the epilogue). `case_bash_n` now
   syntax-checks all four launcher files.

## Verification (raw output in docs/handoff/WORKERS-MUST-COMMIT-01/report.md)
- Suite green: 8 passed, 0 failed.
- Mutation (a) revert to plain `--porcelain` → `case_f` red (7 passed, 1 failed); reverted.
- Mutation (b) remove epilogue call from kimi-coder.sh → `case_g` red (7 passed, 1
  failed); reverted.
- `leadv2-suite-falsifiable.sh` → verdict: falsifiable.
- `bash -n` clean on all 5 touched shell files. No `.py` files touched.
- `tests/run-all.sh --scope changed` times out >10min on this shared worktree host
  (known, memory: run-all-changed-scope-runtime) without reaching a verdict for this
  task's files; ran the 13 suites that directly exercise the touched launchers/lib
  instead. 5 of them fail — confirmed identical failures (same pass/fail counts, same
  failing sub-cases) when the round-2 diff is temporarily reverted, i.e. pre-existing
  and unrelated to this change. Diff restored and re-verified green before committing.

## Left alone
- The 5 pre-existing failing suites (test-claude-subsession-sentinel.sh,
  test-freepool-capability-floor.sh, test-freepool-model-liveness.sh,
  test-freepool-pin-drift.sh, test-glm-coder-529.sh) — untouched.
- No "round" tracking concept added — out of `LANE_WRITES` scope for this task.

Commit: `48a5140` on branch `worktree-WORKERS-MUST-COMMIT-01`, tree clean after commit.

DELIVERABLE_COMPLETE
