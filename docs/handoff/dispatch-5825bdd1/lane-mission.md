BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01: the BROAD_STATUS_READY line stamps at= from the beat's wall clock instead of founder-status.md's own write stamp, so a stale file is relayed to the founder as current. Read TWO documents first: (1) docs/handoff/BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01/brief.md in THIS repo — root cause re-verified today at 2527dedc, it holds; (2) /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/handoff/BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01/lead-addendum.md, which CORRECTS two stale brief instructions and OVERRIDES the brief where they disagree. Corrections: do NOT append to EXTRA_SUITE_MAP (the block no longer exists — put a '# run-all-triggers: leadv2-broad-status.sh leadv2-single-lead-beat.sh' header in your suite, leave tests/run-all.sh alone); anchor every edit and mutation by REGEXP, the brief's line numbers drifted ~11. The negative control IS the deliverable: mutate inside the body of _emit_ready_line so at= returns to BEAT_AT, show the suite red on the staleness assertion specifically, revert, show green, artifact under mutation-control/ with anchor= baseline_rc= mutated_rc= red_line=. Never run the full tests/run-all.sh in this live checkout — it deletes control-plane symlink targets; run your one suite by name. Off-limits, owned by live sessions: lib/leadv2-route-arbiter.sh, config/leadv2-routing.yaml, leadv2-dispatch-code.sh, salvage/* branches. NOTE: a previous attempt at this row was killed after 81s because its worker was rooted in the wrong repository; verify your own cwd contains plugins/leadv2/scripts/leadv2-broad-status.sh before you begin, and stop and say so if it does not.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-5825bdd1" "<question>" \
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