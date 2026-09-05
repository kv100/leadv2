# PREPASS-PROVIDER-FALLBACK-01-R7

Final bounded recovery. Do not rediscover the implementation.

Source worktree:
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PREPASS-PROVIDER-FALLBACK-01-R6`

Recover exactly as follows:

1. Cherry-pick committed base `36fb25d`.
2. Apply its uncommitted dispatcher diff.
3. Copy its focused test as a starting point.
4. Delete/ignore every `.ppf-debug*`, `.test-dispatch-ppf-*`, `repo/`, and
   runtime artifact.

The current focused test is invalid because its end-to-end dispatcher call is
contaminated by the shared/global active registry (`dispatch-test0008`) and led
R5/R6 into unrelated liveness debugging. Replace that E2E section with an
isolated unit/structural fixture that never calls the real dispatcher, never
touches the canonical registry, and cannot launch a worker. It must still
falsify the four reviewed contracts:

- fallback launch cwd is a disposable isolated git workspace, never the shared
  project checkout;
- preregistration cleanup is owner-token/PID safe and cannot delete a foreign
  row;
- a disarmable cleanup trap covers every no-spawn exit while successful spawn
  hands off without deleting the live worker row;
- auth/rate/quota and Codex/GLM output parsing are fixture-backed, with any
  remaining external assumption explicitly tagged `UNVERIFIED`.

Write only:

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh`

Run only the focused test plus the five bounded checks from R5. Commit both
files and finish with a clean worktree. No broad suites, no real dispatch, no
extra research.

acceptance:
  surface: review_gate
  observable: The four High fixes and an isolated no-spawn regression test are committed cleanly, and all six bounded checks pass without global-registry interference.
  authored_at: 2026-08-24T20:27:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
