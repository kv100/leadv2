# Adversarial review — dispatcher fault round 2

Reviewed worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b4042501` (`worktree-b4042501`).

Scope included both `git diff 53d4465...HEAD` and the uncommitted working-tree diff. The committed diff adds the absolute subsession handoff paths, the original (then opt-in) foreign-root guard, `retry-dead`, and four focused tests. The working-tree round makes the guard default-on, fixes the no-env/subdirectory branch, adds pin preflight for `--resume-lane`/`--worktree`, repairs the retry test setup, and adjusts five test files.

## Findings

### 1. BLOCKER — foreign-root selection is not propagated to the task journal

The guard changes the dispatcher's shell-local `PROJECT_ROOT` at `leadv2-dispatch-code.sh:337`, then `cmd_resolve` emits the required `project_root_guard` decision. But `emit()` calls the journal as `bash "${JOURNAL_BIN}" append ...` without exporting the selected root or scrubbing the inherited `CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR`.

`leadv2-journal.sh:14` independently resolves its root as `CLAUDE_PROJECT_ROOT`, then `CLAUDE_PROJECT_DIR`, then cwd; it does not consume the dispatcher's non-exported `PROJECT_ROOT`. In the actual fault shape (cwd in leadv2, inherited `CLAUDE_PROJECT_DIR=persona-engine`), dispatch state and worker placement move to leadv2, while the guard decision—and the new `retry-dead` decision—are appended under persona-engine's task journal. The terminal warning is loud, but the required durable task-journal evidence is misplaced.

Fix `emit()` to invoke the journal with the selected root explicitly (for example, set both `CLAUDE_PROJECT_ROOT` and `CLAUDE_PROJECT_DIR` to `PROJECT_ROOT` for that child), and add a two-real-repo test that asserts the journal file is under the cwd-selected repository.

### 2. HIGH — `retry-dead` reports success even if it failed to remove the ledger row

`cmd_retry_dead` ignores every `_dispatch_abort_locked` result:

```bash
_dispatch_abort_locked "${f}" "${t}" || true
```

An `mktemp`/`mv` failure therefore still produces `dispatch_retry_over_dead_attempt` and exits 0. This is an operator-facing false success: the blocking row can remain present and a later dispatch can still be refused. Do not emit success until every selected token was removed (or has been re-read as absent) under the lock; return a nonzero error on a failed write.

The current positive test would not catch this. It does not inspect the ledger after `retry-dead`; its subsequent redispatch can independently reclaim a dead, evidence-free confirmed row through the existing outcome-reclaim path.

### 3. MEDIUM — the retry test is non-hermetic under the new default-on guard and does not prove journal delivery

`test-dispatch-retry-dead.sh` creates fixture repo `d` and sets `CLAUDE_PROJECT_ROOT=d`, but never runs dispatcher calls from `d` and does not set the guard escape hatch. From this lane worktree, the default guard correctly selects the lane worktree as `PROJECT_ROOT`. Consequently the test's control-plane handoff and task-journal effects occur in the review worktree, not its fixture; the observed untracked handoff/state debris is consistent with this path.

Run its dispatcher calls in `( cd "${d}" && ... )`. Stub the journal and assert that the successful `retry-dead` journal entry is written to `dispatch-<sig8>/journal.md`; also assert the matching ledger row is absent before attempting a redispatch.

### 4. MEDIUM — an env value that is inside, rather than equal to, its repository root still rejects a legitimate explicit pin

For a foreign cwd and `CLAUDE_PROJECT_ROOT=/repo/subdir`, preflight compares the pin's common-dir root (`/repo`) to `_LV2_ENV_GIT_ROOT` (`/repo`) and retains `PROJECT_ROOT=/repo/subdir`. Later `_resolve_pinned_placement` compares the same pin's `/repo` common-dir root to `project_root_phys=/repo/subdir` and refuses it as `foreign_repo`.

Normalize an accepted env root to its Git top-level before the resolver runs, or compare `cand_root` with the normalized env Git root. Add coverage for both `--resume-lane` and `--worktree` using an env path below the repository top-level.

## What is sound

- The working-tree guard is default-on and the no-env/subdirectory regression is fixed by computing `_LV2_CWD_GIT_ROOT` before the branch.
- Its pin preflight uses the candidate worktree's Git common-dir root, so normal repo-root `--resume-lane` and absolute `--worktree` pins correctly retain the explicitly pinned env repository. A genuinely foreign or missing pin falls through to cwd selection and the normal resolver refuses it loudly.
- The absolute `${HANDOFF_DIR}` boilerplate fixes the relative-cwd delivery mismatch. The working-tree follow-up also makes the question proxy absolute.
- Replacing the top-level SOFT_FINISH `return` with an `exit 0` is correct.
- `retry-dead` is conservative before its deletion step: it accepts only `dead` liveness and no attributable evidence; alive/unknown/evidence rows refuse.

## Test audit

Executed successfully:

- `test-subsession-absolute-handoff-path.sh`: 3/3 assertions passed.
- `test-subsession-soft-finish-dead-return.sh`: all three assertions passed.
- `test-foreign-project-root-guard.sh`: 4/4 assertions passed.
- `bash -n` passed for both changed scripts and the five working-tree test files.

The working-tree `test-lane-placement-pin.sh` is a good regression harness for normal root-valued `--resume-lane` and `--worktree` pins, but it is green against the committed pre-guard behavior; it specifically guards the discarded intermediate default-on implementation. The new cwd-else-branch test is likewise a regression test for the discarded intermediate and is green against `53d4465`. `test-dispatch-architect-prepass-late-artifact.sh` only changes its fixture cwd to accommodate the guard and does not exercise either new subsession hunk.

The retry test is red against a dispatcher without `retry-dead`, but its positive assertion is incomplete for the reasons in Findings 2–3. It must prove the ledger deletion and correct journal location.

## Diff hygiene

The worktree also contains unrelated tracked state mutations and extensive untracked dispatch artifacts (including `a.txt`, `b.txt`, `c.txt`, handoff directories, and `docs/leadv2` state files). They are not part of the implementation and must not be staged with it. The requested report is written only in the primary checkout handoff directory.

VERDICT: FAIL
