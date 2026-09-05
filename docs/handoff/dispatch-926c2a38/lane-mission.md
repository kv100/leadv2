Round 2 landed b480f334 and 7d784022 with two real mutation controls (leadv2-dispatch-code.sh continuation-handle normalization, and leadv2-dispatch-product-close.sh finalizer completion) — both show baseline_rc=0 mutated_rc=1 with a named FAIL line. Keep them. Do NOT redo them. Three things are still missing and they are your whole job. FIRST: a mutation control for the THIRD fix, the finalizer_pid recorded in claude-subsession.sh — it has none, so that fix is still unproven. SECOND: the test the brief demands that a worker with a recorded terminal state is GONE within a bounded time; name the bound and justify it. THIRD: green in a Linux container as well as macOS with exit codes pasted, and proof that --scope changed selects the suite on a change to each of the three scripts. Also note a defect in your own evidence format and fix it while you are here: the diff_hash field in docs/handoff/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01/mutation-control/*.txt is e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 in BOTH records, which is the SHA-256 of the empty string — the field hashes nothing and is identical no matter what the mutation was, so it is false assurance. Make it hash the actual applied diff, and add an assertion that two different mutations cannot produce the same diff_hash. The lead already restored the files this lane branched before (commit c8753fcd) — do not revert that. Commit in this lane.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-926c2a38" "<question>" \
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