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

## R3 findings

**Finding (opus R2, committed-tree diff f19d16d9):** `test-brain-class-live.sh:202` (case (d)
re-entry call) was the one dispatch invocation in the suite that did not blank
`CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` / `LEADV2_PROJECT_ROOT`, so the suite goes
deterministically RED whenever `CLAUDE_PROJECT_DIR` is exported. Every other call site went
through `run_classify()`, which does blank them; only the standalone
`_resolve_class_with_brain_floor` re-entry call bypassed it.

**Reproduced RED (before fix), `CLAUDE_PROJECT_DIR=/tmp/x` exported:**
```
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
FAIL: (d) re-entry floor did not enforce Heavy: Light
...
=== test-brain-class-live.sh: 18 PASS, 1 FAIL ===
```

**Fix:** extracted a `blank_project_root_env()` helper (blanks the same three vars via `env`,
same rationale as the existing comment in `run_classify`) and routed both `run_classify`'s
inline blanking and the case (d) re-entry `bash -c` call through it — no per-case copy-paste,
every dispatch invocation in the suite now blanks consistently.

**Green run 1 — WITH `CLAUDE_PROJECT_DIR=/tmp/x` exported** (`env -i PATH="$PATH" HOME="$HOME"
CLAUDE_PROJECT_DIR=/tmp/x bash plugins/leadv2/scripts/tests/test-brain-class-live.sh`):
```
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
PASS: MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor

=== test-brain-class-live.sh: 19 PASS, 0 FAIL ===
```

**Green run 2 — WITHOUT `CLAUDE_PROJECT_DIR` exported** (`env -i PATH="$PATH" HOME="$HOME" bash
plugins/leadv2/scripts/tests/test-brain-class-live.sh`):
```
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
PASS: MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor

=== test-brain-class-live.sh: 19 PASS, 0 FAIL ===
```

**`leadv2-suite-falsifiable.sh` verdict** (run from lane root as cwd):
```
leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01/plugins/leadv2/scripts/tests/test-brain-class-live.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=40
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

**Pre-existing flake found, left alone (out of scope for this mechanical round):** cases (a) and
(b) intermittently FAIL (`missing class_escalated/class_floor_held line`) in ~1-in-3 to ~1-in-4
runs, **reproduced identically on unmodified HEAD (commit 9805bdd2, before this round's edit)** —
confirmed by running `git show HEAD:.../test-brain-class-live.sh` copied in place, in a clean
`env -i` shell, with no `CLAUDE_PROJECT_DIR` involved at all. This is unrelated to the (d)
env-blanking bug this round targets. Likely cause: this worktree shares `docs/leadv2/bus.jsonl` /
active-registry state with other concurrently running lanes on this machine (see gitStatus at
session start — those files were already modified by other sessions), and the dispatch script's
journal/emit path may contend on shared state under concurrent load. Not touched here; flagged for
a separate task if it needs fixing.