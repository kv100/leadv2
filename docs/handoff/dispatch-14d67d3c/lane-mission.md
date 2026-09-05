# Fix round 3 — last blocker is a PRE-EXISTING main test breakage, not our regression

State: watcher-lifecycle suite fully green (8/8, negative control RED, 0 residue).
The e2e gate now fails ONLY on run-core-offline.sh →
`test-t13-slice2.sh` case4a: "CLI dispatch table exposes an undocumented subcommand".

Lead verified on CANONICAL MAIN (not the lane): main's leadv2-dispatch-code.sh CLI
exposes `mission-writeset-check` and `close-gate`, and main's test-t13-slice2.sh:390
allowed list does NOT contain them — so this test fails on main too. Our lane never
touched dispatch-code.sh (commits 904cf2d, e6452b0 touch only watcher scripts).

Task:
1. Verify `mission-writeset-check` and `close-gate` are legitimate phased-path
   subcommands, not worker-spawn bypasses: confirm neither reaches spawn_worker
   without a phase record (case4b logic must still hold for them). Cite file:line.
2. If legitimate (expected): add both to the `allowed=(...)` list in
   test-t13-slice2.sh:390 with a one-line comment naming their origin. If either
   actually spawns a worker bypassing phases — STOP and report; do not whitelist.
3. Re-run run-core-offline.sh in the lane: must be fully green.
Do NOT touch the watcher scripts — they are done and green.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-14d67d3c" "<question>" \
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