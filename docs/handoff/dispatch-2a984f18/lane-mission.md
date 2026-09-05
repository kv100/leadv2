T16 FIX-ROUND-3, single Medium finding (reviewer: APPROVE WITH NOTES). Base lane-t16hyg @186ee7f. ONE commit.
Finding: plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh:65-73 — 'from leadv2_pid_birth import birth_matches, pid_birth_of' sits inside the same try/except as the yaml import and exits 3 on ImportError, so a drifted/missing lib/leadv2_pid_birth.py turns EVERY worktree-protection probe into control-plane-unreadable (rc 5, fail-closed). The module's own R4 import contract mandates degrade-not-crash. Fix: split the pid-birth import into its own try/except with the documented inline fallback (' '.join(str(v).split()) normalization + direct ps -o lstart= read), matching the existing pattern at leadv2-status-surface.sh:884-891. Add a regression test: remove/rename lib_dir's leadv2_pid_birth.py in the fixture -> prime call still degrades (liveness still computed) rather than returning control-plane-unreadable. Constraints: bash -n; run test-worktree-lane-safety.sh at the end, show counts; nothing beyond this finding.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2a984f18" "<question>" \
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