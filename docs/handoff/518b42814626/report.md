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
