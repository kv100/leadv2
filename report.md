# PLUGIN-PAPERCUTS-01 Analysis Report

## Decision: Main is right

After analyzing the code and the deliberate design choice documented in the commit history, I conclude that **main is correct**: an unknown-reader pass must never stop the beat loop.

### Why Main's Decision is Correct

The commit message explicitly states:
> "That removal was deliberate: a loop that dies on reader-error passes goes quiet, and the silence this loop exists to prevent comes back. So `P1` asserts a contract that main removed on purpose."

The fundamental purpose of the single-lead beat loop is to prevent founder-blindness - ensuring that when at least one lane is live, the founder receives regular status updates via `founder-status.md`. 

If the loop were to stop on reader errors (when the heartbeat script fails to execute or returns unparseable output), we would create exactly the failure mode the loop is designed to prevent:
- Monitor becomes blind (heartbeat errors)
- Loop stops beating 
- No updates to `founder-status.md`
- Founder sees no new data and assumes everything is fine
- Founder's blindness persists and worsens

This is precisely what fix-round H4 sought to address, and why the `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` stop was intentionally removed.

### Addressing Resource Concerns

While the lane's concern about unbounded loops in test/dead environments is valid, main's version already includes appropriate bounds:
1. **Hard lifetime cap** (`LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S`, default 24 hours)
2. **Project root monitoring** (exits if project root disappears)
3. **Owner-based self-reap** from WATCHER-LIFECYCLE-LEAK-01 (when explicitly configured)

These bounds ensure that even in permanently broken environments, the loop will not run indefinitely - it will either:
- Exit when the project root is removed (test fixture teardown)
- Self-reap when an owner process dies (if owner is explicitly set)
- Hit the 24-hour lifetime cap as a final safety net

The 24-hour cap is a reasonable balance: long enough to avoid prematurely stopping during transient monitor issues, but short enough to prevent permanent resource leaks in abandoned test environments.

### The Flaw in P1's Assumption

Test case P1 assumes that the loop should stop after `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` consecutive reader-error passes. This assumption is incorrect because:
- It confuses "reader error" (temporary monitor blindness) with "permanently dead environment"
- Implementing this stop would re-introduce the founder-blindness failure
- The existing lifetime cap and project-root monitoring already provide sufficient bounds for test scenarios

## Test Replacement Strategy

Since P1 tests a retired contract, it must be replaced with a test case that validates main's actual contract:
> "The loop stops on ZERO_MAX consecutive REAL zeros (where zero means heartbeat successfully parsed and reported zero live lanes), and does NOT stop on reader errors."

The replacement test will:
1. Verify the loop stops when presented with ZERO_MAX consecutive real zero lane counts
2. Verify the loop continues running when presented with reader errors (unknown passes)
3. Demonstrate that mutating the zero-stop rule (e.g., setting ZERO_MAX=0 or removing zero-stop logic) causes the test to fail

This approach maintains the backlog's purpose of preventing regressions while aligning with main's correct design decision.

---

# B2-GATE-BUDGET — blocked before implementation

No implementation change, merge, or push was performed. Acceptance is NOT met.
The lane started clean at `f0ee0c90`; branch `worktree-B2-GATE-BUDGET`.
The merge base with main was `fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982`.
Initial `git diff --stat main...HEAD` was empty.

## Write-set mismatch

The mission permits two runner/allowlist paths that do not exist in this checkout:

```text
$ cat plugins/leadv2/scripts/tests/run-all.sh
cat: plugins/leadv2/scripts/tests/run-all.sh: No such file or directory
$ cat plugins/leadv2/scripts/tests/known-red-suites.txt
cat: plugins/leadv2/scripts/tests/known-red-suites.txt: No such file or directory
$ ls tests/test-lane-truth-batch-01.sh plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh
ls: tests/test-lane-truth-batch-01.sh: No such file or directory
plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh
```

Reading `tests/run-all.sh` and `tests/known-red-suites.txt` succeeded. The latter
contains 14 `core:` entries, including lane truth batch; it is not a one-entry
allowlist. The bash32 suite is at `tests/test-status-surface-bash32.sh`.
Creating the absent authorized paths would not change the existing entrypoint.

## Related allowlist issue

Read `docs/tasks.yaml` row `24cc139cc4fb`, titled
`E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01`. Its note describes nested suite failures
being obscured by the core wrapper. The actual `tests/run-all.sh` already parses
`[CORE-OFFLINE] FAILED:` labels and classifies them with `is_known_red`.
This is source inspection only; no behavioural proof or subsumption is claimed.

## Async authorization attempt — raw output

```bash
bash /Users/kostiantyn.vlasenko/.claude/scripts/leadv2-ask.sh dispatch-62ec970a 'Pinned B2 checkout lacks both authorized plugins/leadv2/scripts/tests/run-all.sh and known-red-suites.txt. Actual files are tests/run-all.sh and tests/known-red-suites.txt. May I substitute those two write paths and add report.md with evidence (keeping the named new suite path)?' --option 'a|Stop implementation and commit a blocker report only' --option 'b|Authorize actual tests paths plus report.md and evidence artifacts' --default-option a --timeout 60
```

```text
/Users/kostiantyn.vlasenko/.claude/scripts/leadv2-state-path.sh: line 350: /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/.state-path-migrate.lock: Operation not permitted
[leadv2-state-path] WARN: migration lock busy after 5s -- skipping migration this invocation (path still resolved).
Traceback (most recent call last):
  File "<stdin>", line 42, in <module>
PermissionError: [Errno 1] Operation not permitted: '/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/questions/.write.lock'
[leadv2-ask] control-plane write failed (sandbox EPERM?); falling back to legacy handoff store
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.IxlttJxhB7: Operation not permitted
```

Command exited 1. No answer or recorded timeout default was received. Redirecting
the question into a private test state would not reach the lead; retrying its
legacy fallback would target the forbidden runtime-state handoff directory.

## Falsification and remaining work

No shell or Python files changed, so changed-file `bash -n` and `py_compile` have
no inputs. No timing runs, changed-scope execution, selection proof, mutation
controls, or real close-gate verdict were obtained. No red/green claim is made.
These requirements remain outstanding, including repeated suite timings and
internal bash32 profiling. No background job was started.

BLOCKED: authorize the actual tests/run-all.sh and tests/known-red-suites.txt write paths and restore a writable async question channel.
