# LANE-LIVENESS-THREE-STATES-02 (dispatch-83645a5a) — three lane states, not two

## Defect

A lane is `running`, `dead`, or `finished`. Only `alive`/`dead` existed. Result, observed live on
V5-M0-SKELETON-01:

- **Direction 1**: a finished lane (worker exited normally, already committed) got read as dead —
  three founder escalations for successful rounds (`corroborated dead: pid dead`).
- **Direction 2**: a finished lane blocked its own re-dispatch — `lane_placement_refused
  reason=lane_is_live ... verdict=alive age=443`, because liveness was judged by stream freshness
  alone, forcing an ~11-minute wait.

## Fix

Introduced `finished` derived from two externally-checkable facts only: no live pid AND a commit
in the lane's own worktree within `LEADV2_LANE_FINISHED_WINDOW_S` (default 1800s — between
`SILENT_MAX` 900s and `ABANDON_MAX` 3600s, and comfortably covers the observed ~11–40 min
incident window). Never derived from a worker's self-reported success.

Both touched files read the identical env var name/default so the two probes (placement,
escalation) can't structurally disagree about the same lane.

### `plugins/leadv2/scripts/leadv2-lane-liveness.sh` (authoritative liveness reader, used by both
supervisor and dispatch placement)

- New argv-threaded tunable `LEADV2_LANE_FINISHED_WINDOW_S` (positional, matching this file's
  existing convention — never `os.environ` here).
- New `commit_age_s(worktree)`: `git -C worktree log -1 --format=%ct`; returns `None` on any
  failure (unborn HEAD, not a git repo) — never fabricates an age.
- In `resolve()`, immediately after the session/pid/attempt fields are populated and **before**
  the log/stream-freshness logic that would otherwise fall through to `alive`/`silent:*`: if pid
  is gone and `commit_age_s(worktree) <= finished_window`, set
  `verdict=f"finished:{age}s", source="git_commit", reason="no_pid_recent_commit"` and return.
  This ordering is what stops stream mtime from ever masking the finished evidence (acceptance
  item 4).

### `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh` (escalation path — corroborated-dead
detection + prune)

- Same tunable, read via `os.environ.get(...)` (this file's existing convention, different from
  `leadv2-lane-liveness.sh` — honored per-file, not unified).
- New `_commit_age_s(worktree)` — same logic as above.
- In the dead-candidate reasons loop: right after `reasons` is populated from pid/tmux evidence
  and **before** the pre-existing LANE-LIVENESS-LIES-01 freshness veto, if `reasons` is truthy and
  `_commit_age_s(worktree) <= _LANE_FINISHED_WINDOW_S`, clear `reasons = []`. The subsequent `if
  not reasons: continue` means the lane is never added to `dead_candidates_next`, never
  corroborated, never escalated, never pruned.
- Bug fix incidental to this work: the heredoc's import line was missing `time` (`import sys, os,
  json, glob, datetime, subprocess` → `..., subprocess, time`); the new helper calls `time.time()`
  and would `NameError` at runtime without it. Not caught by `bash -n`/`py_compile` since it's a
  runtime name error, not a syntax error — caught by actually running the script against a
  fixture.

## Tests — `plugins/leadv2/scripts/tests/test-lane-finished-state.sh` (new, 6/6 pass)

Fixtures only (`_new_fixture`: scratch git repo + scratch state root under `$TMPDIR`, guarded by
`lv2_assert_scratch_repo`) — never real state.

1. live pid → `alive`; placement would refuse, escalation path agrees (not dead).
2. no pid + commit inside window → `finished:Ns`; no escalation; row kept (re-dispatch admitted).
3. no pid + no commit + no deliverable → `dead:no_handoff_dir`; corroborated across 2 polls,
   pruned/escalated exactly as before.
4. no pid + commit + fresh stream mtime → still `finished:0s` — stream freshness does not override
   the pid+commit evidence (this is the literal Direction-2 defect).
5a. **Mutation gate, `leadv2-lane-liveness.sh`**: real production file mutated in place (`sed`
   collapses the finished-check condition to `False`) → verdict regresses to
   `dead:no_handoff_dir` (RED) → `cp` restore from a `.finstate-orig` backup → `finished:Ns` again
   (GREEN). Backup/restore, not a scratch copy of the function, per the mission's explicit ban on
   scratch-copy mutation.
5b. **Mutation gate, `leadv2-lanes-snapshot.sh`**: same backup/mutate/restore pattern on the
   `reasons = []` veto line. Non-obvious fixture detail: the commit is backdated to **600s** old
   (`_commit_aged`, using `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), not `age=0`. A fresh (age≈0)
   commit satisfies BOTH the new finished-veto and the pre-existing LANE-LIVENESS-LIES-01
   freshness veto (`age_s <= LEADV2_LANE_FRESH_S=120`, since a `finished` verdict's `age_s` *is*
   the commit age) — mutating only the new veto would then still pass control, because the old
   veto silently covers for it, hiding the real code path being tested. Backdating to 600s (>120s,
   ≤1800s) makes the old veto not fire, so the mutation gate genuinely isolates the new code:
   baseline row kept (GREEN) → mutated row pruned/escalated (RED, `_row_present=False`) → reverted
   row kept again (GREEN).

Both mutation gates use `cp file file.finstate-orig` / `sed -i.bak` + `rm -f *.bak` / `cp
file.finstate-orig file` + `rm -f file.finstate-orig`, with an unconditional `cleanup()` EXIT trap
restoring both production files from backup as a safety net. No `grep`-as-assertion, no negated
command as assertion, no `git show HEAD:` pre-image (would falsely pass with the fix uncommitted).

## `EXTRA_SUITE_MAP` (`tests/run-all.sh`)

Added two rows (neither script has a naturally-matching `test-<stem>.sh`):

```
leadv2-lane-liveness.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-lane-finished-state.sh
```

Selection proof (`tests/run-all.sh --scope changed`, traced with `bash -x`, first 8s before the
shared `run-core-offline.sh` lock wait — see below): both changed stems independently resolve to
`.../test-lane-finished-state.sh` (lines 325 and 529 of the trace), added to `SUITES` exactly once
(deduped by `add_suite`, confirmed by only one `SUITES+=` for that path).

**Environment note**: the full `tests/run-all.sh --scope changed` run itself timed out (600s) —
blocked on `/tmp/leadv2-core-offline.lock`, held by a concurrent sibling lane's run of the
always-on `run-core-offline.sh` suite. This is shared-lock contention across lanes, not a
regression from this change; the selection-logic trace above proves the mapping independent of
that suite actually executing.

## Regression checks

- `bash -n` on all 4 changed files: OK.
- `python3 -m py_compile`-equivalent (exact-delimiter heredoc extraction + `compile()`) on both
  embedded Python heredocs: OK.
- `test-lane-liveness-lies.sh`: 4/4 pass (unaffected; the new finished-check runs and returns
  before this suite's freshness-veto code path is reached in its fixtures).
- `test-lane-liveness-authoritative.sh`: 41/41 assertions pass, including its own tripwire that
  `leadv2-lane-liveness.sh`'s md5 is unchanged across its own run (self-mutation guard, not a
  claim about my diff).
- `test-lane-liveness-sentinel.sh`: 13/13 pass.
- **`test-lane-registry-outlives-dispatcher.sh` (the mission's named worker_pid regression
  guard) does not exist in this lane's branch.** `git merge-base --is-ancestor 7f22d3d HEAD` is
  false — this lane's HEAD (merge-base with `main` = `5d1a5d7`) branched before `7f22d3d` (the
  worker_pid fix, plus its test file) was merged into `main`; `main`'s current tip is `de44cc7`,
  far ahead. This is a pre-existing lane/branch-lineage state, not something introduced by this
  change. What I can and did verify: `git diff --stat plugins/leadv2/scripts/leadv2-active-registry.sh`
  is empty — this lane never touches that file, so the worker_pid fix (wherever it lives in this
  branch's history) cannot be weakened by this diff regardless.

## `git diff --stat` (mutation-gate byte-identity + final diff)

Post-test-run, pre-commit, all four intended files and nothing else:

```
 plugins/leadv2/scripts/leadv2-lane-liveness.sh     |  52 ++-
 plugins/leadv2/scripts/leadv2-lanes-snapshot.sh    |  44 +-
 .../scripts/tests/test-lane-finished-state.sh      | 499 +++++++++++++++++++++
 tests/run-all.sh                                   |   4 +-
 4 files changed, 595 insertions(+), 4 deletions(-)
```

No leftover `.finstate-orig`/`.bak` files; no drift in any other repo path or real state root
(the one untracked leak found — `plugins/leadv2/scripts/docs/leadv2/*`, a wrong-cwd artifact from
earlier manual reproduction of the `time`-import bug, predating this test file's current form —
was deleted and confirmed not to reappear on a clean rerun of the suite from the repo root).

## Files changed

- `plugins/leadv2/scripts/leadv2-lane-liveness.sh`
- `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh`
- `plugins/leadv2/scripts/tests/test-lane-finished-state.sh` (new)
- `tests/run-all.sh`

DELIVERABLE_COMPLETE
