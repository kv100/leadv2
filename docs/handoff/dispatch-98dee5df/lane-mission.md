Round 1 already committed b574d982 in this lane and its worker then died without proving anything. Do NOT redo that work. Read docs/handoff/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/brief.md and satisfy only its unproven items: 2 and 4 (argue in the report what a timeout should do to the lane, and say in one line why the sweep timed out), 5 (negative control BOTH directions: a gate command exiting 124 classifies as a timeout and the round's work survives; revert, a genuinely failing test still classifies as a regression), 6 (green on macOS AND in a Linux container, exit codes pasted, prove --scope changed selects the suite). CRITICAL: git diff main..HEAD currently DELETES docs/handoff/CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01/brief.md, docs/handoff/INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01/brief.md and 17 lines of docs/leadv2/scheduled-decisions.md because this lane branched before they landed. Restore all three from main or the merge silently reverts them. Commit in this lane.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-98dee5df" "<question>" \
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