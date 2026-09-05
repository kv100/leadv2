# Mission — the scope gate attributes ANOTHER tree's dirt to the lane

Repo: ~/Projects/leadv2. File: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`,
the scope-gate block at L1860-1900.

## Root cause, measured 2026-08-23 (not a hypothesis)

Lane `f72c8c9c` was refused with `status: blocked, reason: unscoped_lane_work`,
offending = `leadv2-broad-status.sh`, `ZZ-pre-review-run.sh`,
`tests/test-broad-status-lanes-blind.sh`, `tests/test-review-fanout-visibility.sh`.
**The lane never touched any of those four.** They are another session's uncommitted
work sitting in the MAIN tree — `git status --porcelain` in
`/Users/kostiantyn.vlasenko/Projects/leadv2` lists exactly them.

Why the gate saw them: `.claude/worktrees/f72c8c9c` was **not a registered git
worktree**. It has no `.git` entry and does not appear in `git worktree list` (contrast
`6f1dded5` -> b32d740 and `67198a6e` -> aed1f2b, which are registered). So
`git -C "${_lane_root}" status --porcelain` at L1872 walked UP out of the directory and
returned the MAIN repository's status. Every one of main's dirty paths is undeclared
relative to the lane's write-set, so `_pc_undeclared_n > 0` and `unscoped_lane_work`
fired at L1898.

The partition logic at L1877-1894 is correct. The defect is that `_lane_root` is trusted
to be a git worktree without ever being checked, so the gate silently grades the wrong
tree. The lane's real work (`plugins/leadv2/scripts/lib/leadv2-trace.sh`, 161 lines)
sits in that unregistered directory to this day — preserved at
`docs/handoff/SCRIPT-SIZE-AUDIT-20260821/partial-lane-f72c8c9c/`.

## Required fix

1. **Validate `_lane_root` before grading it.** Before the `git status` at L1872,
   assert that `git -C "${_lane_root}" rev-parse --show-toplevel` resolves to
   `_lane_root` itself. If it resolves elsewhere (or fails), the gate is looking at a
   different repository and MUST NOT grade the lane on it.
2. **Distinct terminal reason.** In that case emit a NEW reason —
   `lane_root_not_a_worktree` — never `unscoped_lane_work`. Record the resolved
   toplevel vs the expected `_lane_root` in the evidence line so the next reader sees
   the mismatch immediately. Keep it retryable (same `refused` terminal word), and make
   sure the lane's produced files are named in the gate output so nobody assumes the
   lane did nothing.
3. **Never let another tree's dirt reach `_pc_offending`.** Even under any future
   fallback, offending paths must come only from a tree whose toplevel == `_lane_root`.
4. Add the new reason to whatever vocabulary/verdict lists already enumerate
   `unscoped_lane_work` (grep for it — `leadv2-backlog-pump.sh` also references it) so
   it is not an unknown word downstream.

## Do NOT

- Do not weaken the real scope check. An undeclared path the worker genuinely wrote in a
  correctly-registered lane worktree must still refuse with `unscoped_lane_work`.
- Do not touch the main tree's 5 dirty files. They belong to another session:
  no `git stash`, no `reset`, no `clean`, no commit of them. Hard rule.
- Do not attempt to fix the dispatch-side worktree-registration bug in this mission —
  record what you observed about it in the report and stop there.

## Verify (real output in the report, not claims)

1. A regression test reproducing the exact failure: an unregistered lane dir inside a
   dirty parent repo must now yield `lane_root_not_a_worktree`, NOT `unscoped_lane_work`,
   and must list zero offending paths from the parent.
2. The existing scope tests still pass — run `tests/test-scope-gate-orchestration-dirt.sh`
   and `tests/test-review-gate-scope-evidence.sh` and paste both results verbatim.
3. A positive control: a genuinely-registered lane worktree with an undeclared written
   file still refuses with `unscoped_lane_work`. Paste it.
4. Full offline core suite pass/fail counts verbatim; name any pre-existing failure you
   did not cause.

## Deliverable

`docs/handoff/REVIEW-GATE-LANEROOT-01/report.md` — the changed lines with file:line, the
four verifications with pasted output, what you observed about why the worktree was never
registered, and `git diff --stat`. End with DELIVERABLE_COMPLETE.
