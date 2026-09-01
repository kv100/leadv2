# WORKERS-MUST-COMMIT-01 — report

## Root cause
Five lanes in one session (2026-09-01) reported `LEADV2_LANE_OUTCOME ... work=yes` while
leaving their diff uncommitted in the lane worktree — `glm-coder.sh`'s finalize path ran
`leadv2-lane-outcome.sh` (whose `work=` field IS already computed from `git`, never from
worker prose) but nothing *committed* a dirty exit first, so a worker that quit mid-edit
just left its diff sitting in the tree for the lead to `git add -A && git commit` by hand.

## What changed

1. **New:** `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` —
   `leadv2_worker_commit_epilogue(run_dir, cwd_dir, label)`. If `cwd_dir` is dirty at exit,
   it parses this run's own `LANE_WRITES:` line from `prompt.txt` (same parse convention as
   `mission_is_code_shaped()`), stages+commits only the files inside that scope as one
   commit (`"<label>: auto-commit (worker exited dirty)"`), and leaves anything outside
   scope untouched, recording it as `foreign_dirty=<paths>`. If no `LANE_WRITES:` line is
   present at all, it never guesses a scope — reports `foreign_dirty=undeclared_lane_writes`
   and commits nothing. Writes `worker_exit=clean|dirty`, `auto_committed=<n>`,
   `foreign_dirty=<n or list>` to both `progress.log` and `meta.yaml`.
2. **`plugins/leadv2/scripts/glm-coder.sh`** (`cmd_supervise`'s finalize path): sources the
   new lib and calls `leadv2_worker_commit_epilogue` right after `deadhand_check` (append-only
   window, meta.yaml no longer clobbered) and **before** the `work_delta_present()` call that
   feeds `leadv2-lane-outcome.sh` — so a HEAD-moving auto-commit is visible to the outcome
   classifier in the same run, not one run late.
3. **`tests/run-all.sh`**: three new `EXTRA_SUITE_MAP` rows so `--scope changed` selects
   `test-worker-commit-epilogue.sh` for either changed file, plus a `glm-coder.sh` row for
   the sibling `test-lane-outcome.sh` suite (same call site, was previously unmapped).
4. **New:** `plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh` — hermetic fixture
   repos, no network, no real `claude` invocation. Cases:
   - `case_a` — dirty, in-scope exit → commit exists, HEAD moves, tree clean after.
   - `case_b` — dirty, out-of-scope-only exit → no commit, `foreign_dirty=outside.txt`.
   - `case_c` — clean already-committed exit → untouched, `worker_exit=clean`.
   - `case_d` — dirty exit with **no** `LANE_WRITES:` declared → never guesses, reports
     `foreign_dirty=undeclared_lane_writes`, no commit.
   - `case_bash_n` — `bash -n` on the lib, `glm-coder.sh`, and this suite itself.

## Item 2 of the mission ("outcome computed, not quoted")
Already true in the code as found: `leadv2-lane-outcome.sh`'s `work=` field is derived
purely from `git` (HEAD/dirty-hash delta vs `.workbase`, or a `git rev-list --count
@{u}..HEAD` fallback) — never from the worker's own prose. The actual gap was that the
git state it reads could still be *dirty* at read time. Wiring the new epilogue in before
that read closes the gap: a worker that edited only in-scope files now always presents a
clean, committed tree (or an honestly-reported `foreign_dirty`) to the classifier.

Deviation from the mission's literal `"<task-id> round <n>" `wording: no `round` concept
exists anywhere in this codebase (verified: `grep -rn "round=" leadv2-dispatch-code.sh` /
`glm-coder.sh` — no hits). Used the run's own `run_id` as the commit label instead
(`"<run_id>: auto-commit (worker exited dirty)"`), which is unique per run and already
threaded through `meta_get run_id`.

## Falsification

### bash -n / py_compile
```
$ bash -n plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh && echo OK2
OK2
$ bash -n plugins/leadv2/scripts/glm-coder.sh && echo OK3
OK3
$ bash -n tests/run-all.sh && echo OK_SYNTAX
OK_SYNTAX
```
No Python files touched.

### New suite — green
```
PASS: case_bash_n
PASS: case_a_in_scope_auto_commit
PASS: case_b_out_of_scope_no_commit
PASS: case_c_clean_exit_untouched
PASS: case_d_undeclared_lane_writes_no_guess

test-worker-commit-epilogue: 5 passed, 0 failed
RC=0
```

### Mutation negative control — RED
Mutated the commit step to a no-op (`if true; then # MUTATION: skip commit` in place of the
real `git add && git commit` conditional) and reran the same suite:
```
PASS: case_bash_n
FAIL: case_a_in_scope_auto_commit -- HEAD did not move -- no commit happened
PASS: case_b_out_of_scope_no_commit
PASS: case_c_clean_exit_untouched
PASS: case_d_undeclared_lane_writes_no_guess

test-worker-commit-epilogue: 4 passed, 1 failed
RC=1
```
Reverted immediately after capturing this (`diff` against `/tmp/epilogue_backup.sh`
confirmed clean revert, `grep -n MUTATION` found nothing afterward).

### Full changed-scope run — `LEADV2_SUITE_LOCK_DISABLE=1 bash tests/run-all.sh --scope changed`
```
[TEST] test-worker-commit-epilogue: 5 passed, 0 failed  -> PASS
[TEST] test-lane-outcome: 8 passed, 0 failed            -> PASS
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 5 passed, 1 failed, scope=changed
RC=1
```
`run-core-offline.sh` (an aggregate of ~85 unrelated sub-suites, sharded) reported
`suites passed=67 failed=18`. Every failing line traced to one of two causes, both
pre-existing and outside this task's `LANE_WRITES`:
- The large majority: `[leadv2-dispatch-code] lane_plan_skipped task=... reason=shared_tree`
  — the dispatch-code exclusivity gate refusing because this is a live shared worktree host
  with a dozen+ other lanes/dispatch sessions concurrently active this session (see the
  `LEADV2_ACTIVE_OTHER_SESSIONS` list in this session's own system reminders) — an
  environment condition, not a regression from this diff.
- Two `FAIL: shellcheck: leadv2-review-run.sh` lines — a file this task never touched.

Neither of the two files this task's `LANE_WRITES` covers appears anywhere in the 18
failure lines. No file outside `LANE_WRITES` was edited to chase these down, per the
"never weaken a fixture to get green" rule — these are a finding for whoever owns
`run-core-offline.sh`'s shared-tree isolation, not a defect in this change.

## Left alone
- `kimi-coder.sh` and `freepool-coder.sh` have the identical `finalize`-style tail
  (`work_delta_present` + `leadv2-lane-outcome.sh` call) but were **not** wired to the new
  epilogue — out of `LANE_WRITES` for this task. Same gap likely exists there; flagging as
  a natural follow-up, not doing it here.
- No `round` tracking added (see deviation note above) — out of scope; would require a new
  concept invented across multiple files that this task's `LANE_WRITES` does not cover.
