# REVIEW-ENGINE-V3-CORE-01-R3-TARGETED

Targeted continuation on worktree `b4e2f354` at `11c82f0`. Fix only the three
reproducible High findings; do not run another broad redesign.

1. Keep the paid attempt/spawn cap per task across diff hashes. A changed diff may
   reset diff-specific findings/mode, but must not reset task-total attempts or
   spawns. The sequence remains one exhaustive pass plus at most one targeted
   blocker recheck. Preserve legacy/corrupt-state fail-closed behavior.
2. Load `leadv2_review_signals` in the parent shell before risk/security selection;
   do not rely on a function sourced inside command substitution. Protected/high-
   risk changes must automatically enable the security pass. Missing/broken risk
   signals fail closed rather than silently disabling escalation.
3. Critical/High findings from the security pass are blocking and participate in
   the terminal verdict exactly like critic High findings. A critic PASS cannot
   override a blocking security result.

Add the review probes as executable fixtures and restore all failing legacy
roundcap cases. Run focused v3 plus legacy roundcap/exhaustive/pool suites. Commit
the two authorized files and leave clean.

acceptance:
  surface: review_gate
  observable: A task cannot buy more than two review passes by changing diffs, protected changes run security automatically, and security High findings block the gate.
  authored_at: 2026-08-24T21:48:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-engine-v3-core.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b17ca58b" "<question>" \
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