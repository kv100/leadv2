Read docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/brief.md in full. Deliver D0 ONLY — the baseline and census correction, section 4's first row — then stop and report. Do NOT start D1 or touch any production file: D0 is measurement, it changes no behaviour. Concretely: run the existing suites the D0 row names on macOS AND in the Linux container and paste both exit codes; resolve every open question U1-U8 from section 8 against a live active.yaml row or a file:line, never against the brief's own prose - section 8 exists because the architect marked those as things to re-derive rather than trust; and write docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/census.md carrying your corrections to section 2's table of 24 code paths across 9 stores. Where your measurement CONTRADICTS the architect's census, say so plainly with the evidence — a correction is the most valuable thing D0 can produce, not a failure. Where a named suite does not exist or does not run, say that too rather than silently skipping it. Commit census.md in this lane before you finish. Off limits: main, tests/known-red-suites.txt, any production script, and committing inside a MythicalGames repo.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-d6ea40ae" "<question>" \
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