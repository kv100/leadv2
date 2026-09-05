# PREPASS-PROVIDER-FALLBACK-01-R10-TARGETED

Targeted continuation on the existing R9 worktree at `ae50455`. Do not run a new
full audit. Fix only the two reproducible High blockers from the native final
review:

1. EXIT cleanup must never delete a live GLM/Codex worker registry row during the
   interval after spawn and before slot disarm. Transfer/stamp worker ownership for
   every successful worker arm, or otherwise atomically disarm owner cleanup before
   a live worker can be exposed. Add an executable signal-window fixture.
2. SIGTERM must stop an active fallback promptly rather than waiting for the full
   architect timeout. Make provider execution independently interruptible and kill
   its process group immediately, then clean the disposable workspace. Add a
   bounded probe whose timeout is much larger than the expected signal latency.

Preserve all eight green R9 fixtures. Run bash-n and the focused fixture suite.
Commit both files and leave the worktree clean.

acceptance:
  surface: review_gate
  observable: Live GLM/Codex rows survive lead EXIT ownership cleanup, fallback SIGTERM returns promptly, and the focused executable suite passes.
  authored_at: 2026-08-24T21:37:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6a78c025" "<question>" \
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