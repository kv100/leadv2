# PREPASS-PROVIDER-FALLBACK-01-R11-TARGETED

One targeted High fix on the existing dispatcher worktree at `b062092`.

Close the fallback supervisor registration gap: no detached provider process
group may become live before the parent can identify and terminate it. Publish
the runner PID atomically before exposure, or launch through a registration
handshake whose child cannot start the provider until the parent has armed its
signal cleanup. SIGTERM at every point in that handshake must kill/reap the
runner and provider group and remove the disposable workspace.

Add an executable barrier fixture that stops immediately before/at registration,
sends SIGTERM, and proves no provider remains. Preserve the 10 existing cases.
Run bash-n, diff-check and focused suite. Commit the two files and leave clean.

acceptance:
  surface: review_gate
  observable: SIGTERM during fallback runner registration leaves no provider process or disposable workspace, and all focused cases pass.
  authored_at: 2026-08-24T21:58:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-07138570" "<question>" \
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