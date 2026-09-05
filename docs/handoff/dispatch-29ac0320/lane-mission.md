ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01: the lead is asked to bury lanes that have FINISHED. Read the full mission FIRST — it is at /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/handoff/ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01/mission.md — it carries the measurement, the target file:line, the negative control you must produce, and three ways lanes died today. Summary so you know what you are doing: leadv2-lanes-snapshot.sh:1078 emits 'Task <id> corroborated dead: ... Escalate.' with answers inspect/restart/abandon; two of those destroy delivered work. Four escalations in one hour on 2026-09-04 were ALL finished lanes with commits and deliverables. The liveness ladder already computes finished: via git_commit at leadv2-lane-liveness.sh:817, and this path never asks. CRITICAL: leadv2-lanes-snapshot.sh ALREADY vetoes escalation on commit age elsewhere in itself (the check Test 5b in test-lane-finished-state.sh mutates) — find why the escalation path bypasses it and reach that same rule. Do NOT add a second parallel finished-check: adding a duplicate of exactly this rule today took test-lane-finished-state.sh from 10/10 to 9/10 by making Test 5b's mutation vacuous. One rule, one implementation, one control. Deliverable is the negative control: fixture lane with a commit inside the window and a gone pid must produce NO escalation at baseline; mutate the finished consultation by REGEXP anchor inside the function body (assert it matched exactly once, never use line numbers) and the suite must go red on the assertion that a finished lane was offered abandon/restart. Suite self-registers with '# run-all-triggers: leadv2-lanes-snapshot.sh'; do NOT touch tests/run-all.sh. Print a line to stdout at least every 10 minutes or the watchdog kills you at 1800s idle. Never background anything — for a worker, backgrounding ends the round. Never run the full tests/run-all.sh here; it deletes control-plane symlink targets. Verify your cwd contains plugins/leadv2/scripts/leadv2-lanes-snapshot.sh before you begin and stop if it does not.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-29ac0320" "<question>" \
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