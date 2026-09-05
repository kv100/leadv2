T16 FIX-ROUND-2 (re-review BLOCK 2H/1M/1L; prior 6 findings confirmed fixed — do NOT touch them beyond these corrections). Base branch lane-t16hyg @86dcde4. One commit per finding; suites green.

H1b plugins/leadv2/hooks/leadv2-one-copy-drift.sh:107 — the fix moved the ENTIRE $report to stderr, but the hook is wired at BOTH SessionStart and PostToolUse:Bash (hooks.json:68/497) and always exits 0; for SessionStart, stdout is what folds into session context, so a drifted tree now surfaces NOWHERE. Fix: only the post-sync warn string goes to >&2; the base $report (SessionStart drift block) stays on stdout. Fix test T3 in test-one-copy-drift-hook-postsync.sh:104-111 to assert stdout carries the plain drift report AND the post-sync WARNING is on stderr.

H2b plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh:99-113 — case_p13 computes live_birth but never uses it; only mismatch→not-alive is tested. Add the positive-match assertion: register with pid_birth: "$live_birth" (the real ps -o lstart= of a live pid) → _lv2_wt_pid_alive returns alive. This is the dangerous direction (false not-alive unprotects a live worktree from the sweeper); Darwin lstart trailing-space quirk is documented at leadv2-active-registry.sh:560-566 — normalize the same way.

M1b plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:118-122 — empty attempt currently hard-returns 0 (no deregistration at all). Real callers (leadv2-fanout.sh:1666, leadv2-fanout-lane-launcher.sh:126) pass attempt="" and rely on a separate unregister — unenforced invariant. Fix: when attempt is empty, fall back to delete-by-task_id but ONLY for rows whose own attempt field is also empty/absent. Regression test for the empty-attempt path.

L1b plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh:177,188-192 — third inline copy of pid-birth read+normalize. Reuse the shared lib/leadv2_pid_birth.py (birth_matches) as leadv2-status-surface.sh / leadv2-lanes-snapshot.sh do, or _lv2_pid_birth from leadv2-active-registry.sh if sourcing is clean. No new inline copy.

Constraints: bash -n; no scope beyond these 4; run test-one-copy-drift-hook-postsync.sh, test-worktree-lane-safety.sh, and the ledger suite at the end and show PASS/FAIL counts; commit on the lane branch.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-dccb1996" "<question>" \
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