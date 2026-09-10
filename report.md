# Refusal reason emitter

## Result

The visible emitter is the `print(...)` in the Python heredoc inside
`route_arbiter()` in `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`.
`_record()` is not a renderer: it appends a JSONL decision record and cannot
produce the observed stdout line. Discovery therefore falsified the premise
that a third, grep-hidden renderer existed.

The prior grep result was misleading because each refusal reason was duplicated:
one literal for `_record()` and another for `print(...)`. The two target paths
now use one `refusal_reason` assignment, supplied to both surfaces. There is no
second literal source for either `no_capable_cell` or `pool_empty_all_excluded`.

## Direct mutation evidence

The focused, registered `test-route-arbiter.sh` copies the real arbiter,
mutates each single-source assignment, sources that copy, and invokes
`route_arbiter()` directly. This is the raw green output:

```text
arbiter_under_test=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/54d478fb1263/plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh sha256=809e022a36dfabf5
MUTATION docs: arm=refuse model=none tier=none reason=emitter_probe_docs kind=docs chain= util_glm=13 util_codex=20 util_claude=45 util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=5.00h_default_full_period reset_freepool=n/a failure_memory=absent_key arb_rev=182b5e1428e3 matrix_rev=dc964ffefb99
MUTATION code: arm=refuse model=none tier=none reason=emitter_probe_pool kind=code chain= util_glm=13 util_codex=20 util_claude=45 util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=5.00h_default_full_period reset_freepool=n/a failure_memory=absent_key arm_excluded=glm:untrusted arb_rev=7fc600e32d81 matrix_rev=dc964ffefb99
PASS: refusal reason source mutations change the direct docs and code outputs
SUMMARY: pass=1 fail=0
```

This covers both required cases: `kind=docs` begins as `no_capable_cell`, and
the protected `kind=code` policy cut begins as `pool_empty_all_excluded`.

## Red and verification output

Before the fixture-only temporary-directory seam, the unmodified suite could
not start in this sandbox; raw output:

```text
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.CboS9nU3gE: Operation not permitted
```

After the seam, shell syntax and the focused direct acceptance are green:

```text
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
$ bash -n plugins/leadv2/scripts/tests/test-route-arbiter.sh
$ LEADV2_ROUTE_ARBITER_FOCUS=refusal-emitter timeout 30 bash plugins/leadv2/scripts/tests/test-route-arbiter.sh
SUMMARY: pass=1 fail=0
```

The repository changed-scope runner was also run in the foreground with a
120-second bound. It did not emit a selected-suite result before the bound:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/54d478fb1263/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit_code=124
```
