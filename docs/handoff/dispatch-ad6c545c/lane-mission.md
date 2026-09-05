# GLM-ARM-THROUGHPUT-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GLM-ARM-THROUGHPUT-01`
LANE_WRITES: plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh,plugins/leadv2/scripts/tests/test-glm-flash-handle.sh,tests/run-all.sh,docs/handoff/GLM-ARM-THROUGHPUT-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `de22dea` — the lead's
salvage of your round-1 work; you hit max_turns before committing). Run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Budget: commit after step 2, and again at the end — an uncommitted
exit is a failed round.

## Review verdict on round 1
`status=fail reason=suite_not_falsifiable suite=plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh`
```
baseline: rc=0
probe[assertion_tools_broken]: rc=0 shim_invocations=115
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
```
The gate replaced `jq`/`grep`/`python3` with always-failing shims (invoked 115 times) and the suite
STILL exited 0; it also exits 0 from an empty cwd and under `env -i`. So its PASS lines are not
evidence: assertions that cannot run resolve as pass. Both suites were green in the lead's run
(7/7 and 8/8) — that green is now worth nothing until this is fixed.

## Do
1. Reproduce the three probes yourself first: `PATH` with `jq grep python3` as `exit 1` stubs; an
   empty temp cwd; `env -i bash …`. Paste the three exit codes in report.md BEFORE changing anything.
   Then find the branch that swallows failure (a `|| true`, an `if cmd; then PASS` with no `else
   FAIL`, a helper that echoes PASS on an unparsable result, a `set -e` disabled by a pipeline).
2. Make the suite honest: every assertion reads the real outcome (`rc` of `bash glm-coder.sh bg`,
   the literal `LEADV2_DISPATCH_REFUSED: lock_busy` marker on stderr, the lock dir's `pid` file
   content) and FAILs on any state it cannot read; a missing tool, missing fixture, or empty output is
   FAIL, never skip. Then run
   `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh`
   and the same for `test-glm-flash-handle.sh`; paste both verdict lines (must read FALSIFIABLE).
3. Keep the mutation controls from round 1, RUN them again on the honest suite, and paste red.
4. `report.md`: "## Round 2 evidence" with the probe exit codes before/after, the two FALSIFIABLE
   lines, green runs, control red. Commit.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-ad6c545c" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.