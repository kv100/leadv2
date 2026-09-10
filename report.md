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

---

# Eight-level effort scale

`router_v2.effort_scale` is the sole ordered vocabulary: `none, minimal, low,
medium, high, xhigh, max, ultra`; `effort_ceiling` defaults to `ultra`. The
arbiter validates names, caps by scale index, and applies arm-local provider
projections. GLM's partial `low|high|max` projection rounds `xhigh` down to
`high`. The thinking journal now carries `effort=`.

## Arbiter raw output

```text
PASS: ultra safety effort is capped at high and names capped_from=ultra
PASS: high effort below an ultra ceiling remains uncapped
PASS: glm low|high|max projection rounds internal xhigh down to provider high
PASS: an unknown effort name rejects config and names the bad level
PASS: mutation control: string comparison reddens the xhigh-under-ultra projection case
SUMMARY: pass=31 fail=1
FAIL: (g-red) mutation did not flip the outcome — the control is not falsifiable
```

`(g-red)` is the pre-existing dispatcher fail-open negative control; every
effort-scale case above passed.

## Thinking and dispatch raw output

```text
PASS: both think_model_resolved lines include role, class, arm, model, reason, and effort
SUMMARY: 14 pass, 0 fail
PASS: standard build projects internal medium to glm provider low regardless of glm-family winner
PASS: codex arm receives --effort high in its own launch args (distinct from --tier)
PASS: sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)
PASS: the glm-family arm receives the resolved effort as a launcher flag, and does not crash
SUMMARY: pass=13 fail=0
```

## Mutation-control raw output

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-think-through-arbiter.sh file=plugins/leadv2/scripts/leadv2-router.sh
red_line=FAIL: journal lines missing/incomplete: think_model_resolved ... reason=arbiter_cheapest_capable
```

## Syntax checks

```text
PASS: bash -n changed shell files and effort suites
```
