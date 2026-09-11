# STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01

## Outcome

The resolver refuses before path derivation when `BASH_SOURCE[0]` is unavailable. The refusal is non-zero, emits no stdout, and names `not_file_backed_bash` plus `BASH_SOURCE[0]`. Executed bash and sourced-from-file bash probes retain the explicit state-root result. No registry caller was changed; `leadv2-active-registry.sh` remained off limits.

The obsolete zsh-dependent suite was replaced with `test-state-path-fails-closed.sh` plus `test-state-path-zsh-source.sh`. The first suite's unset-context probe uses `bash -c` plus `eval`; the second exercises the reported zsh-source shape. Both suites' mutation controls restore the cwd/repo-relative fallback in scratch copies, and both now fail closed if their assertion tool is unavailable.

## Green suite output

Raw artifact: `round1-green.txt`.

```text
[TEST] PASS: bash -c eval with BASH_SOURCE unset refuses closed (rc=4, stdout empty)
[TEST] PASS: diagnostic names the unavailable location mechanism, not a sibling lookup
[TEST] PASS: executed bash still resolves the explicit state root
[TEST] PASS: sourced from a real bash file context still resolves normally
[TEST] PASS: declared silent-fallback mutation fails open (negative control flips)
[TEST] PASS: bash -n clean
[TEST] ----------------------------------------
[TEST] RESULTS: 6 passed, 0 failed
```

The companion zsh-source suite also ran green:

```text
[TEST] PASS: zsh source from the scripts dir refuses closed (rc=4, stdout empty)
[TEST] PASS: zsh source from a neutral cwd refuses closed (rc=4, stdout empty)
[TEST] PASS: guard removal restores the silent repo-relative fallback (negative control flips)
[TEST] PASS: bash -n clean
[TEST] ----------------------------------------
[TEST] RESULTS: 4 passed, 0 failed
```

## Round 1 red mutation artifact

Raw artifact: `round1-red.txt`. The resolver copy had the refusal guard removed, `set -u` deferred, and `SCRIPT_DIR` restored to `$PWD`; the final suite returned `rc=1` because the unset-BASH_SOURCE assertion observed the old successful repo-relative path and the guard-presence assertion rejected the mutated resolver.

```text
[TEST] FAIL: unset BASH_SOURCE did not refuse closed: rc=0 out='/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/state-path-fails-closed.4qHAz0/eval-refusal/project/docs/leadv2/active.yaml' err=''
[TEST] PASS: diagnostic names the unavailable location mechanism, not a sibling lookup
[TEST] PASS: executed bash still resolves the explicit state root
[TEST] PASS: sourced from a real bash file context still resolves normally
[TEST] FAIL: resolver refusal guard is absent or its assertion tool failed (grep rc=1)
[TEST] PASS: bash -n clean
[TEST] ----------------------------------------
[TEST] RESULTS: 4 passed, 2 failed
[TEST] FAIL: unset BASH_SOURCE did not refuse closed: rc=0 out='/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/state-path-fails-closed.4qHAz0/eval-refusal/project/docs/leadv2/active.yaml' err=''
[TEST] FAIL: resolver refusal guard is absent or its assertion tool failed (grep rc=1)
```

The external mutation command asserted `negative_control_rc=1`.

## Falsification commands

### Changed-scope runner

Post-commit command: `timeout 120 bash tests/run-all.sh --scope changed`.
The runner admitted the committed suite and delegated to the repository core
runner; the explicit 30-second bound then terminated it with rc=124 before
the core runner could emit a verdict. Raw artifact: `changed-scope.txt`.

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
post_commit_changed_scope_rc=124
```

The timeout is an ambient changed-scope gate blocker: the deleted legacy
`test-state-path-zsh-refusal.sh` is treated as an unmapped changed test by the
core selector, so it falls back to the full suite set. The targeted resolver
suites are independently green above.

Final self-check raw output:

```text
--- BASH -N CHANGED EXISTING SHELLS ---
PASS bash -n plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
PASS bash -n plugins/leadv2/scripts/tests/test-state-path-zsh-source.sh
--- PYTHON COMPILE CHANGED EXISTING PYTHON ---
PASS no changed Python files
--- DIFF CHECK / DOD MECHANICS ---
PASS git diff --check
PASS runtime-state path policy
--- CHANGED-SCOPE RUNNER (120s FOREGROUND BOUND) ---
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
changed_scope_rc=124
```

### Falsifiability

Both committed suites turned red under the generic assertion-tool failure
injection:

```text
leadv2-suite-falsifiable: suite=plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=1
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
leadv2-suite-falsifiable: suite=plugins/leadv2/scripts/tests/test-state-path-zsh-source.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=1
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

### Shell syntax

`bash -n` passed for the changed suite and the resolver; no Python file was
changed, so `python3 -m py_compile` had no applicable target.

## Lifecycle gates

The lane was merged with `main` at `8cffa53d` before the final review. The
final review used that frozen merged parent because the local `main` ref moved
again during the review. The gate returned `rc=0`, `status: pass`, and
`PASS_WITH_NITS` with no Critical, High, or Medium findings.

The code task's deploy verification is N/A:

```text
deploy-verify: N/A (task_class=code)
deploy_verify_rc=3
```

The plugin-cache deploy hook was attempted with `--write` and failed closed
when rsync hit sandbox permission errors updating the active cache. No deploy
success is claimed:

```text
[2026-09-11 05:16:07] Mode: WRITE (--write)
rsync(11593): error: tests/quality-engine/fixtures/__pycache__/test_parallel_dispatch.cpython-314-pytest-9.0.3.pyc: unlinkat: Operation not permitted
rsync(11593): error: docs/leadv2/active.yaml: unlinkat: Operation not permitted
BLOCK: rsync failed syncing /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2 -> /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7
```

Phase-8 E2E verification was run in the foreground with a 120-second bound:

```text
[leadv2-phase8-e2e-gate] e2e_gate task=518b42814626 status=ran verdict=timeout rc=124 timeout_s=120 elapsed_s=120 budget_s=120
leadv2-phase8-e2e-gate: TIMEOUT (tests/run-all.sh --scope changed exceeded 120s; elapsed_s=120 budget_s=120)
e2e_rc=5
```

The machine-readable result is `e2e-gate.md` with `status: unknown` and
`reason: e2e_timeout`; therefore no E2E pass sentinel or close record was
created, and this lane remains blocked from close pending a green E2E gate.

The close assertion was intentionally not forced without that evidence:

```text
[2026-09-11 05:19:40] FAIL: A7 E2E gate sentinel missing: docs/handoff/518b42814626/e2e-gate-passed.flag
[2026-09-11 05:19:41] INFO: A8 N/A (non-deploy): deploy-verify: N/A (task_class=code)
[2026-09-11 05:19:41] PASS: A6 merge-blocker: absent (Phase 6 clean)
[2026-09-11 05:19:41] INFO: === Phase 8 assertions for 518b42814626: 4 / 9 HARD checks PASS ===
GATE FAILED: 5 assertion(s) not satisfied for 518b42814626
phase8_assert_rc=1
```

## Phase 6-8 continuation (2026-09-11)

`main` was merged into this lane before deployment:

```text
a4bc9e8f Merge branch 'main' into worktree-518b42814626
```

The official plugin-cache deployment was retried in explicit write mode. It
failed closed because the sandbox denied rsync mutations to the active cache;
the raw artifact is `/private/tmp/518b42814626-deploy-write-wrapper.log`.

```text
[2026-09-11 05:52:15] Mode: WRITE (--write)
rsync(56369): error: docs/leadv2/active.yaml: unlinkat: Operation not permitted
BLOCK: rsync failed syncing /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2 -> /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7
deploy_write_wrapper_rc=1
```

### Continuation self-check: red then green

The first syntax census was deliberately kept as red evidence: it tried to
parse a deleted shell test named by the merge-base diff.

```text
--- BASH -N CHANGED SHELL FILES ---
PASS bash -n plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
bash: plugins/leadv2/scripts/tests/test-state-path-zsh-refusal.sh: No such file or directory
selfcheck_syntax_rc=1
```

The corrected census excludes deletions and preserves paths as lines. Its raw
green output is:

```text
--- BASH -N CHANGED EXISTING SHELL FILES ---
PASS bash -n plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
PASS bash -n plugins/leadv2/scripts/tests/test-state-path-zsh-source.sh
--- PYTHON COMPILE CHANGED PYTHON FILES ---
PASS no changed Python files
--- DIFF CHECK ---
PASS git diff --check
```

### Changed-scope runner / live gate

The required Phase-8 E2E runner completed in the foreground with its 900s
bound. The two resolver suites were green, but the aggregate runner failed,
so no E2E sentinel was written and Phase 8 must not be forced.

```text
[TEST] RESULTS: 6 passed, 0 failed
[PASS] plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
[TEST] RESULTS: 4 passed, 0 failed
[PASS] plugins/leadv2/scripts/tests/test-state-path-zsh-source.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 5 passed, 1 failed, 0 known-red (allow-listed, non-blocking), 14 known-red-skipped (budget mode, still run by --scope all), 0 gone-green (remove from allow-list), scope=changed
e2e_gate task=518b42814626 verdict=fail elapsed_s=798 budget_s=900
```
