verdict: APPROVE
next_action: deploy

# dispatch-a73c9b8f — TEST-FALSIFICATION-GATE-01 + stop-gate untracked-timeout leg

No context.yaml existed for this task; proceeded from the mission text directly (off_limits
respected: leadv2-dispatch-code.sh and leadv2-review-run.sh untouched; leadv2-dispatch-product-close.sh
was read/inspected but not modified — the untracked-timeout behaviour it already implements needed
only a test, not a code change).

Commit: `b1aba72` on branch `worktree-a73c9b8f`.

## 1. TEST-FALSIFICATION-GATE-01 (C4)

`plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh`: added a new independent check (C4,
marker-delimited `BEGIN-TEST-FALSIFICATION-GATE-01` / `END-TEST-FALSIFICATION-GATE-01`) that runs
after the existing C3 suite block. For every changed path matching `tests/test-*.sh` (either
`.../tests/test-*.sh` or bare `tests/test-*.sh`), it runs the file directly (same
`_lv2_selfcheck_timeout_run` + depth-guard idiom as C3) and inspects the raw output for a
`RED-then-GREEN:` line — the convention already used by `test-review-gate-scope-evidence.sh` and
`test-stop-gate.sh`'s own harnesses. Absence of that line -> `FAIL (falsification_missing)`, added to
`failed_names` as `falsification:<rel-path>`, raw output captured into selfcheck.md via
`_selfcheck_raw`. Independent of `tests_mode` (fires even under `never`), gated only by the
`depth >= 1` re-entry guard (shared with C3) and the new kill switch `LEADV2_TEST_FALSIFICATION_GATE`
(default 1; `=0` restores the pre-gate path byte-for-byte, zero bookkeeping, same idiom as
`LEADV2_SCOPE_DISCIPLINE`). Header env-var doc comment updated to document the new flag. The existing
SCOPE bounce (C0) and diff_hash stamp were read but not touched.

## 2. Stop-gate untracked-timeout leg

`pc_stop_gate_capture_diff` in `leadv2-dispatch-product-close.sh` (read only, not modified) already
handles an untracked declared path correctly: it stages the declared write-set with `git add -N`
into a throwaway index before diffing (same technique as `pc_scope_diff`'s `_pc_git_diff`), so an
untracked file's full content shows up in `review.diff`. `pc_stop_gate_autocommit` computes its own
view via `git status --porcelain` (also untracked-inclusive) and commits independently of
`capture_diff`. So this item needed a red-first *test*, not a code fix — the mission calls this out
("currently live-probe-proven only").

Added Case I to `tests/test-stop-gate.sh`: a worker timeout (`sleep 30` background PID,
`LEADV2_PC_WORKER_MAX_WAIT_S=1`) with a brand-new, never-`git add`-ed file declared in the write-set.
Asserts: exit rc==5 (timeout path), the file is fully committed (clean `git status`), the commit
message carries `STOP-GATE`, and `review.diff` contains the file's content.

No historic pre-fix SHA exists for this leg (the behaviour was already correct on HEAD), so the red
leg is a **synthetic mutant**: a full copy of `SCRIPT_DIR` with `pc_stop_gate_capture_diff` mechanically
replaced (via a `python3 -c` regex substitution matched on the function's exact signature/closing-brace
shape) with a version that does plain `git diff HEAD` — the mutant text explicitly named in the mission
("reverts pc_stop_gate_capture_diff to plain `git diff HEAD`"). Plain `git diff HEAD` never shows an
untracked path at all, so the `review.diff` assertion goes red against the mutant while the commit-side
assertion (computed independently by `pc_stop_gate_autocommit`) stays green on both trees — this is
exactly the falsifiability shape the case is meant to prove. Same red/green harness idiom as the
existing `run_case`/`run_c0_case` helpers (`run_case_i`), scored into the same PASS/FAIL/GREEN_PRE_FIX
counters.

## Falsification-gate self-tests (test-builder-selfcheck-gate.sh, new Part D)

Since C4 has no historic pre-fix ref either (it lands in this same commit), built `NO_C4_LIB_SH`: the
current `lib/leadv2-builder-selfcheck.sh` with the marker-delimited C4 block mechanically stripped by
the same `python3` regex idiom, used as the red-first mutant (`run_c4_case`, mirrors `run_c0_case`).
Three cases:
- `falsification-missing-blocks`: a changed `tests/test-lying.sh` that just `exit 0`s (no red-first
  evidence) must be blocked with `falsification:tests/test-lying.sh` in `failed_names`.
- `falsification-present-passes`: a changed test file that prints its own `RED-then-GREEN:` line must
  NOT be blocked (still gets a `falsification` row in selfcheck.md, rc 0).
- `falsification-kill-switch-byte-restore` (direct-only, not red/green-scored): `LEADV2_TEST_FALSIFICATION_GATE=0`
  against the fixed lib produces the same rc and no `falsification:` name as running the lying test
  directly against `NO_C4_LIB_SH`.

## Verification (raw output)

`bash -n` + `/bin/bash -n` (bash 3.2 syntax) on all three changed files: all PASS (shown inline in each
suite's own harness output below).

`shellcheck -S warning` on both changed test files and the lib: only pre-existing warnings survive
(SC2034 on `LV2_SELFCHECK_*`/`LV2_SELFCHECK_DEPTH_SKIP` globals in the lib, SC2206 on `local -a
dirs=(${PATH})` in test-builder-selfcheck-gate.sh line 625) — confirmed byte-identical in count/location
against `git show HEAD:<path>` before any of my edits; nothing new introduced.

### test-stop-gate.sh (13/0, was 12/0)

```
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] RED-then-GREEN: tracked-writeset-gets-committed (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: out-of-scope-junk-not-committed (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: staged-out-of-scope-not-laundered (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: missing-declared-path-still-commits (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: rename-stages-new-path (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: space-in-name-gets-committed (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: timeout-checkpoints-before-exit (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: foreign-repo-journaled (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: untracked-timeout-capture-and-commit (pre_rc=1 -> post_rc=0)
[TEST] PASS: kill-switch LEADV2_STOP_GATE=0 restores old path (file stays uncommitted)
Results: 13 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
```

### test-builder-selfcheck-gate.sh (34 passed, 1 failed — pre-existing)

```
[TEST] PASS: kill-switch LEADV2_BUILDER_SELFCHECK=0 restores old path (no selfcheck.md, no selfcheck_failed)
[TEST] FAIL: scope-kill-switch-byte-restore-and-bypasses
[TEST] RED-then-GREEN: scope-deletion-outside-write-set-blocks (SCOPE-DISCIPLINE-01) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: scope-rename-source-outside-write-set-blocks (SCOPE-DISCIPLINE-01) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: falsification-missing-blocks (TEST-FALSIFICATION-GATE-01) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: falsification-present-passes (TEST-FALSIFICATION-GATE-01) (pre_rc=1 -> post_rc=0)
[TEST] PASS: kill-switch LEADV2_TEST_FALSIFICATION_GATE=0 restores no-C4 behaviour
...
Results: 34 passed(red->green), 1 failed, 0 green-pre-fix, 0 could-not-run
FAIL: scope-kill-switch-byte-restore-and-bypasses
```

`scope-kill-switch-byte-restore-and-bypasses` reproduces identically against clean `git show
HEAD:plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh` run standalone (31 passed, 1 failed,
same case) — confirmed BEFORE touching this file. Environment-sensitive pre-existing finding, not a
regression from this change; left alone per "never weaken a fixture to get green."

### Full run-core-offline (FOREGROUND, `LEADV2_TEST_SOLO=1`, solo)

```
[CORE-OFFLINE] stop-gate autocommit on worker exit (V3-STOP-GATE-01)
... (13/0, all RED-then-GREEN, shown above)

[CORE-OFFLINE] builder selfcheck gate (recursion/depth guard, baseline attribution)
... (34/1, shown above)
[CORE-OFFLINE] FAILED: builder selfcheck gate (recursion/depth guard, baseline attribution)
...
[CORE-OFFLINE] suites passed=56 failed=1 missing=0 repo=.../worktrees/a73c9b8f
```

56/1/0 — the 1 failure is the same pre-existing `scope-kill-switch-byte-restore-and-bypasses` case,
unrelated to either of this task's two items.

## Cleanup note

Running `run-core-offline.sh` (and its constituent suites) writes real timestamped artifacts into
this worktree's `docs/handoff/dispatch-*` (test fixtures from `test-stop-gate.sh`,
`test-builder-selfcheck-gate.sh`, and others in the suite that don't fully sandbox `CLAUDE_PROJECT_ROOT`)
and touched two pre-existing tracked `phases.d/*.yaml` files' `started_at` timestamps. All of this was
reverted (`git checkout --`) / removed (`rm -rf` on newly-created untracked dirs) before committing —
the commit contains only the 3 intended source files. This test-isolation gap in some suites under
`run-core-offline.sh` is a pre-existing condition, out of scope for this task (off_limits: routing,
supervise*, leadv2-dispatch-code.sh, leadv2-review-run.sh), flagged here for visibility.

DELIVERABLE_COMPLETE
