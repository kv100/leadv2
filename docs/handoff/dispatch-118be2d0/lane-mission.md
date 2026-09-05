T12 FIX-ROUND (review BLOCK 2C/1H/1M). Base branch lane-t12prof @f6c580d (leadv2 repo). One commit per finding; test-claude-profile-select.sh (61/0) must stay green + grow.

C1 plugins/leadv2/scripts/leadv2-claude-profile-select.sh:307-311 — dir-fallback triggers only on the literal "unknown/na". Two slots with resolvable subscriptionType but UNRESOLVED email (missing/unreadable .claude.json, valid credential) both derive e.g. "pro/na" and merge into ONE quota bucket — the exact incident class this task exists to kill. Fix: fall back to the config-dir-derived key whenever the email failed to resolve (id_cj != 1), not only on the exact "unknown/na" string.

C2 tests — no fixture covers two distinct slots both missing .claude.json. Add it: two dirs, different credentials, no .claude.json → distinct buckets + the same-account warn NOT fired.

H1 negative control — the declared mutation was never actually run red. Apply the mutation (break the identity-derivation line in a scratch copy via LEADV2_TEST_SELECT_BIN), run the suite, show the red output in the close notes, restore. The suite must contain the NC as an executable case, not a comment.

M1 bucket-key migration note — this commit silently splits the old shared "identity-unknown_na" bucket per-dir. Add a one-line compat note in the script header + commit message (no code needed unless trivial: if the old bucket dir exists and exactly one slot maps to it, keep using it).

Constraints: bash -n; ordering/selection logic stays untouched; no secrets in output; run the suite at the end, show counts.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-118be2d0" "<question>" \
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