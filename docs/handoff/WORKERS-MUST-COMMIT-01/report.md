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

## Round 2 evidence

### Fixes (review verdict: status=fail high=2)
1. **Porcelain collapse (High)** — `lib/leadv2-worker-epilogue.sh`: `git status --porcelain`
   → `git status --porcelain --untracked-files=all` so an untracked directory is expanded to
   one line per file before scope classification, instead of one collapsed `?? dir/` line.
2. **Epilogue wired on every arm (High)** — added the identical `leadv2_worker_commit_epilogue`
   call, at the same post-`deadhand_check`/pre-outcome-classifier window, to `kimi-coder.sh` and
   `freepool-coder.sh` (byte-identical pattern to the existing `glm-coder.sh` call site).
   `claude-subsession.sh` has a structurally different finalize shape (no `run_dir`/`prompt.txt`
   convention — it uses `MISSION_FILE` + `HANDOFF_DIR`/`RUN_DIR`), so:
   - `_lv2_epilogue_lane_writes()` now takes an optional `$2` mission-file override (defaults to
     `${run_dir}/prompt.txt`, unchanged for the three coder wrappers).
   - `leadv2_worker_commit_epilogue()` now takes an optional `$4` mission-file override, passed
     through to `_lv2_epilogue_lane_writes`.
   - Wired into both of `claude-subsession.sh`'s finalize points: the sync `WAIT=1` path (right
     after `run_subsession`/`parse_and_record_cost`, before the `DELIVERABLE_COMPLETE` checks),
     and the detached-background inline waiter (right after `wait "$PID"`, before the
     `.outcome`/`.finalized` write) — using `HANDOFF_DIR`/`RUN_DIR` respectively as the
     progress.log/meta.yaml sink and `PROJECT_ROOT` as `cwd_dir` (claude-subsession has no
     separate lane-worktree var; the caller sets `PROJECT_ROOT` to the lane worktree already).
   - `no_lane` case: `leadv2_worker_commit_epilogue()` now checks
     `git -C "${cwd_dir}" rev-parse --is-inside-work-tree` FIRST and, on failure, writes
     `worker_exit=no_lane auto_committed=0 foreign_dirty=0` and returns 0 instead of the prior
     silent `return 0` — covers the `--protected` (no lane worktree) case for any arm.

### New/updated test suite — `plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh`
- `case_e_new_dir_in_scope_committed` — new untracked directory inside LANE_WRITES: every file
  under it lands in the auto-commit.
- `case_f_new_dir_out_of_scope_listed` — new untracked directory outside LANE_WRITES: every file
  under it listed individually in `foreign_dirty`, nothing committed.
- `case_g_all_arms_wire_epilogue` — grep-gate: `glm-coder.sh`, `kimi-coder.sh`,
  `freepool-coder.sh`, `claude-subsession.sh` all reference `leadv2_worker_commit_epilogue`.
- `case_bash_n` extended to `bash -n` all four launcher files, not just `glm-coder.sh`.

Green run:
```
PASS: case_bash_n
PASS: case_a_in_scope_auto_commit
PASS: case_b_out_of_scope_no_commit
PASS: case_c_clean_exit_untouched
PASS: case_d_undeclared_lane_writes_no_guess
PASS: case_e_new_dir_in_scope_committed
PASS: case_f_new_dir_out_of_scope_listed
PASS: case_g_all_arms_wire_epilogue

test-worker-commit-epilogue: 8 passed, 0 failed
```

### Mutation negative controls (both reverted after)
(a) revert `--untracked-files=all` to plain `--porcelain`:
```
FAIL: case_f_new_dir_out_of_scope_listed -- progress.log missing other/lib/a.sh
test-worker-commit-epilogue: 7 passed, 1 failed
```
(b) remove the epilogue call from `kimi-coder.sh`:
```
FAIL: case_g_all_arms_wire_epilogue -- missing in: kimi-coder.sh
test-worker-commit-epilogue: 7 passed, 1 failed
```
Both mutations reverted; suite confirmed green again (`8 passed, 0 failed`) before proceeding.

### Falsifiability gate
```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
leadv2-suite-falsifiable: suite=.../test-worker-commit-epilogue.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=13
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

### Self-check: `bash -n` / `py_compile`
```
$ for f in lib/leadv2-worker-epilogue.sh glm-coder.sh kimi-coder.sh freepool-coder.sh claude-subsession.sh; do bash -n "plugins/leadv2/scripts/$f" && echo OK $f; done
OK plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh
OK plugins/leadv2/scripts/glm-coder.sh
OK plugins/leadv2/scripts/kimi-coder.sh
OK plugins/leadv2/scripts/freepool-coder.sh
OK plugins/leadv2/scripts/claude-subsession.sh
```
No `.py` files touched in this round.

### Changed-scope run-all
`tests/run-all.sh --scope changed` (`LEADV2_SUITE_LOCK_DISABLE=1`) is a known >10min run on
this repo (memory: `run-all-changed-scope-runtime`); a full foreground run timed out at 590s
inside `run-core-offline.sh` sharding without reaching a verdict for this task's files. Instead
ran every existing suite that directly exercises the four touched launchers/lib in the
foreground:

```
test-worker-commit-epilogue.sh              8 passed, 0 failed
test-claude-subsession-sentinel.sh           PASS=11 FAIL=5   (pre-existing, see below)
test-claude-subsession-turncap.sh            PASS=2  FAIL=0
test-freepool-capability-floor.sh            23 passed, 8 failed (pre-existing, see below)
test-freepool-install.sh                     PASS=8  FAIL=0
test-freepool-model-liveness.sh              6 passed, 1 failed (pre-existing, see below)
test-freepool-model-selector.sh              25 passed, 0 failed
test-freepool-pin-drift.sh                   PASS=10 FAIL=1   (pre-existing, see below)
test-glm-coder-529.sh                        8 passed, 1 failed (pre-existing, see below)
test-kimi-session-route.sh                   PASS=14 FAIL=0
test-subsession-absolute-handoff-path.sh     pass=3  fail=0
test-subsession-context-diet.sh              13 passed, 0 failed
test-subsession-soft-finish-dead-return.sh   pass=3  fail=0
```

Baseline check (never weaken a fixture to get green): temporarily restored the 5 pre-round-2
files to their pre-this-round content (`git checkout --`, edits saved to `/tmp/wmc01-mine/`
first) and re-ran the 5 failing suites — identical pass/fail counts and identical failing
sub-cases on baseline (`test-claude-subsession-sentinel.sh` PASS=11/FAIL=5,
`test-freepool-capability-floor.sh` a `rm: Directory not empty` fixture race,
`test-freepool-model-liveness.sh` 6/1, `test-freepool-pin-drift.sh` 10/1, `test-glm-coder-529.sh`
`case_revive_continuation` failing). Confirmed pre-existing and unrelated to this diff; edits
restored from `/tmp/wmc01-mine/` and the epilogue suite re-verified green (`8 passed, 0 failed`)
before committing.

## Left alone (round 2)
- The 5 pre-existing failing suites above — untouched, per "never weaken a fixture to get
  green"; they fail identically with or without this round's diff.
- No `round` tracking added — out of scope; would require a new concept invented across
  multiple files that this task's `LANE_WRITES` does not cover.
