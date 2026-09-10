# STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01

## Outcome

The resolver refuses before path derivation when `BASH_SOURCE[0]` is unavailable. The refusal is non-zero, emits no stdout, and names `not_file_backed_bash` plus `BASH_SOURCE[0]`. Executed bash and sourced-from-file bash probes retain the explicit state-root result. No registry caller was changed; `leadv2-active-registry.sh` remained off limits.

The obsolete zsh-dependent suite was replaced with `test-state-path-fails-closed.sh`. Its unset-context probe uses `bash -c` plus `eval`, and its mutation control restores the cwd/repo-relative fallback in a scratch copy.

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

## Round 1 red mutation artifact

Raw artifact: `round1-red.txt`. The resolver copy had the refusal guard removed, `set -u` deferred, and `SCRIPT_DIR` restored to `$PWD`; the changed suite returned `rc=1` because the unset-BASH_SOURCE assertion observed the old successful repo-relative path.

```text
[TEST] FAIL: unset BASH_SOURCE did not refuse closed: rc=0 out='/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/state-path-fails-closed.4qHAz0/eval-refusal/project/docs/leadv2/active.yaml' err=''
[TEST] PASS: diagnostic names the unavailable location mechanism, not a sibling lookup
[TEST] PASS: executed bash still resolves the explicit state root
[TEST] PASS: sourced from a real bash file context still resolves normally
[TEST] SKIP: resolver override is already guard-mutated; external negative-control run
[TEST] PASS: bash -n clean
[TEST] ----------------------------------------
[TEST] RESULTS: 4 passed, 1 failed
[TEST] FAIL: unset BASH_SOURCE did not refuse closed: rc=0 out='/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/state-path-fails-closed.4qHAz0/eval-refusal/project/docs/leadv2/active.yaml' err=''
```

The external mutation command asserted `negative_control_rc=1`.

## Falsification commands

Pending the final changed-scope runner transcript before commit.
