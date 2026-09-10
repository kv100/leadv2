# Hook escalation evidence

## Scope

Changed the two tracked Bash blockers that match the incident: `leadv2-block-bash-heredoc.sh` and `leadv2-deny-floor.sh`. A private hook helper validates a one-command `LEADV2_HOOK_ESCALATE` reason, queries the journal path through `leadv2-journal.sh path`, and appends the event through that script. The new `test-hook-escalation.sh` self-registers through `run-all-triggers`.

The deny floor keeps `git reset --hard`, `git clean`, `git stash`, and `git worktree prune` closed when the new variable is present. The existing `CLAUDE_ALLOW_SHARED_GIT_DESTRUCTIVE` escape hatch was not changed.

Example recorded journal payload (the focused test asserts the full heredoc command and reason are present):

```text
- <UTC timestamp> [decision] hook_id=leadv2-block-bash-heredoc session_id=hook-escalation-test command=<full 2066-byte heredoc command> reason=recover blocked lane safely
```

## test-hook-escalation.sh — raw red output

```text
PASS  heredoc without escalation remains denied
FAIL  one-word reason rc=2 out=[leadv2-block-bash-heredoc] Bash command is 2066 bytes with a heredoc body.
Heredocs in Bash live in the transcript forever (~2066 chars × every future turn).

Use the Write tool instead:
  Write({ file_path: "/abs/path/file.md", content: "..." })

To override (rare): append "# bash-guard: allow" to the command.
FAIL  meaningful heredoc escalation rc=2 journal=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-hook-escalation.8bpwKK/docs/leadv2/tasks/hook-escalation-test/journal.md out=[leadv2-block-bash-heredoc] Bash command is 2066 bytes with a heredoc body.
Heredocs in Bash live in the transcript forever (~2066 chars × every future turn).

Use the Write tool instead:
  Write({ file_path: "/abs/path/file.md", content: "..." })

To override (rare): append "# bash-guard: allow" to the command.
FAIL  reset --hard rc=2 out=[leadv2-deny-floor] BLOCKED: command matches deny-floor rule 'git_reset_hard'.
git reset --hard is blocked — discards uncommitted work irreversibly. Use ask-lead.sh if this is intentional, or append '# deny-floor: allow' to override on a throwaway tree.

This floor applies even under Codex danger-full-access — it is not a review
heuristic, it is a hard pre-execution stop on irreversible operations.

If this is a genuine false positive:
  - append "# deny-floor: allow" to the command (rare, one-off), or
  - use ask-lead.sh to raise an off_limits/decision conflict for a durable fix.
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-hook-escalation.8bpwKK/mutant/hooks/lib/leadv2-hook-escalation.sh'
```

This was the intended pre-implementation red run; the missing helper also prevented the mutation fixture from being created.

## test-hook-escalation.sh — raw green output

```text
PASS  heredoc without escalation remains denied
PASS  one-word reason remains denied
PASS  meaningful heredoc escalation passes and is journalled
PASS  reset --hard remains a closed non-escalatable class
PASS  MUTATION RED: removing reason validation lets one word through

5 passed, 0 failed
```

The mutation is performed in a copied hook tree inside the suite: removing the marked reason-validation branch makes the one-word case pass, while the real helper keeps it denied.

## Changed-scope runner — raw output

```text
$ bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed
[CORE-OFFLINE] scope=changed running 3 of 95 suites (base=main@c694480528, 4 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=3 total=95 base=main@c694480528 changed=4 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] running 3 suites across 4 shards

[CORE-OFFLINE] all plugin shell syntax
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=1 fail=0 missing=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-hook-escalation.sh (scope-selected ad-hoc)
PASS  heredoc without escalation remains denied
PASS  one-word reason remains denied
PASS  meaningful heredoc escalation passes and is journalled
PASS  reset --hard remains a closed non-escalatable class
PASS  MUTATION RED: removing reason validation lets one word through

5 passed, 0 failed
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=1 fail=0 missing=0

[CORE-OFFLINE] tests/test-bash-pre-dispatch.sh (scope-selected ad-hoc)
PASS echo_hi dispatcher verdict matches all 13 originals (ALLOW)
PASS echo_hi expected verdict ALLOW
PASS echo hi is a silent exit 0
PASS echo hi trace invokes only the 2 ALWAYS guards
PASS heredoc dispatcher verdict matches all 13 originals (BLOCK)
PASS heredoc expected verdict BLOCK
PASS heredoc block forwards the guard message on stderr
PASS codex_exec dispatcher verdict matches all 13 originals (BLOCK)
PASS codex_exec expected verdict BLOCK
PASS codex exec matches the standalone direct-exec guard verdict
PASS close_push dispatcher verdict matches all 13 originals (BLOCK)
PASS close_push expected verdict BLOCK
PASS close-ritual/git-push-shaped command forwards deny JSON
TIMING echo_hi runs=5 dispatcher=1226ms_total/245.2ms_avg originals=5690ms_total/1138.0ms_avg
ALL TESTS PASSED
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=1 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=0 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=serial pass=0 fail=0 missing=0

[CORE-OFFLINE] suites passed=3 failed=0 missing=0 known_red_skipped=0 repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4e78ef0dfc51
```

## Syntax and diff hygiene — raw output

```text
$ bash -n plugins/leadv2/hooks/leadv2-block-bash-heredoc.sh plugins/leadv2/hooks/leadv2-deny-floor.sh plugins/leadv2/hooks/lib/leadv2-hook-escalation.sh plugins/leadv2/scripts/tests/test-hook-escalation.sh
$ git diff --check
# both commands produced no stdout or stderr and exited 0
```

---

## Preserved earlier report content

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


The runner was foregrounded with `timeout 600`; it exhausted that bound in
`run-core-offline.sh` before a verdict. This is a timeout, not a green claim.

---

# W18 closer throughput report

## Journal measurement

Source census (2026-09-10): terminal `e2e_gate status=ran verdict=...` records from `~/.claude/leadv2-state/{leadv2,persona-engine}/tasks/*/journal.md`. Each task path was resolved through `leadv2-journal.sh path <task>`; for example:

```text
$ LEADV2_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2 bash plugins/leadv2/scripts/leadv2-journal.sh path fb9df7f1
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/tasks/fb9df7f1/journal.md
```

```text
n=61 complete=6 censored_at_900=55 p50=900 p95=900 max=900
   1 120 timeout
   1 164 complete
   1 169 complete
   1 176 complete
   1 272 complete
   1 456 complete
   1 690 complete
  54 900 timeout
```

`p95=900` is right-censored: 55 of 61 observations reached a timeout ceiling. The fixed 900-second close budget is implicated. The new default is `min(3600, 1200 + 120 * (selected_suites - 1))`: 1200 is the censored 900-second p95 plus a 300-second reserve, and each additional selected suite adds 120 seconds. An explicit `LEADV2_PHASE8_E2E_TIMEOUT_S` remains authoritative.

Timeout artifacts now record selected suites, completed suites, and the last `[RUN]` suite.

## Git truth behavior

Before `no_work`, the closer checks the lane branch against the local default branch and independently checks `git diff --cached`. Commits become `refused/git_truth_commits` with the SHA journaled; staged-only work becomes `refused/git_truth_staged`; only an absent/clean lane remains `no_work`. Landing policy remains `leadv2-land.sh` and its merged-tree/`land_in_write_set` authority.

## Red then green

```text
# environmental preflight red (before product code):
mktemp: mkdtemp failed on .../tmp.s2gCHAwB6l: Operation not permitted
mkdir: /repo: Operation not permitted

# green, after redirecting no-argument mktemp to /private/tmp:
[TEST] PASS: committed branch without report is git_truth_commits and journals its SHA
[TEST] PASS: staged but uncommitted work is git_truth_staged, not no_work
[TEST] PASS: missing branch with no index/commits remains no_work
[TEST] 3 passed, 0 failed
[TEST] PASS: timeout artifact names selection/progress even when the custom entrypoint has no selector seam
[TEST] 10 passed, 0 failed, 0 not run

# syntax floor:
bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
bash -n plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh
bash -n plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
git diff --check
# all exited 0

# changed-scope runner, foregrounded with timeout 180:
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
```

The changed-scope runner produced no verdict in the tool's 30-second foreground window; it was not claimed green. No detached process was started.

## Mutation control

Task B control (artifact: `/private/tmp/w18-mutation-artifact-final/mutation-control/20260910T085424Z-86316.txt`):

```text
$ LEADV2_BUILDER_SELFCHECK=0 bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh \
  plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
  's/_PC_GIT_TRUTH_KIND="commits"/_PC_GIT_TRUTH_KIND="none"/' \
  /private/tmp/w18-mutation-artifact-final
suite=plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh
file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
anchor=s/_PC_GIT_TRUTH_KIND="commits"/_PC_GIT_TRUTH_KIND="none"/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: committed branch was misclassified (...)
diff_hash=ef70dab37636b9a1879b2f43a510ca65687d9d6343afa5d7df7098003c0b0aac
lane_diff_hash=c8e45965550dc5e711a5425da705e1b755adedbffa1a49f81895a7527a0118c7
```
