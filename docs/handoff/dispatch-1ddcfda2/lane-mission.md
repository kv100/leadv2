T16 FIX-ROUND (review BLOCK 2H/2M/2L, prescriptions verbatim). Base branch lane-t16hyg @94c9f67. One commit per finding; suites green; NCs per E2E-KILLRATE-01.

H1 hooks/leadv2-one-copy-drift.sh:110 — merged post-sync WARNING lost >&2 (repo convention: PostToolUse messages surface via stderr; original standalone hook had it). Fix: add >&2 to the final printf; fix test-one-copy-drift-hook-postsync.sh to capture stdout/stderr SEPARATELY and assert the WARNING is on stderr (its 2>&1 capture is a structural false green).

H2 scripts/leadv2-dispatch-ledger.sh::_lv2_terminal_unregister_lanes (~330-364) — deregistration keys on task_id/sig8 only; a delayed dead-write from a crashed attempt 1 deletes the RETRY attempt's live row and poisons sig8 as true-terminal (retry's landed then hits dedup, never recorded). Fix: tie deletion to the terminating attempt — compare the row's pid (or attempt field) with the value known at terminal-write time before removing; or hold the ledger lock across check+delete. Test: register attempt2 (live) -> deliver late dead for attempt1 -> row SURVIVES and attempt2's landed records.

M3 lib/leadv2-worktree-protected.sh::_lv2_wt_pid_alive — bare kill-0 liveness; PID reuse lets a stale registered PID look alive (reintroduces RESURRECTOR-02 in a race). Fix: cross-check process start-time (ps -o lstart=) or cmdline marker against registration-time value. Add a PID-reuse test case.

M4 hooks/leadv2-continuation-guard.sh + leadv2-promise-guard.sh — tail-window fallback branch never fires in cases 14/15 (padding leaves the user turn inside the 256KB window). Fix the tests: user turn near the START of a >256KB file, chatter appended after -> window misses it -> fallback fires -> verdict matches unpadded baseline.

L5 hooks/leadv2-codex-direct-exec-guard.sh:57-58 — c[o]dex/e[x]ec bracket obfuscation: add the one-line comment explaining it dodges self-scan, or simplify to the literal.
L6 stale references to deleted leadv2-plugin-sync-drift-warn.sh in leadv2-context-glossary-close.sh:12 and leadv2-skill-authoring-reminder.sh:8 — update the prose.

Constraints: bash -n; no scope beyond findings; commit on the lane branch.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-1ddcfda2" "<question>" \
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