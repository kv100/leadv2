# V3-STOP-GATE-FIX3-01 — close the codex review findings (~/Projects/leadv2)

Lane worktree e93d9162, HEAD 6eee731 (all committed; run-core-offline solo 57/0 green).
Codex adversarial review returned FAIL with 4 findings — READ THE FULL REPORT FIRST:
docs/handoff/dispatch-e93d9162-review/codex.r2.md

1. HIGH: the checkpoint commit includes whatever is ALREADY STAGED in the index, even outside
   the declared write-set — a parallel actor's staged out-of-scope change gets laundered into
   the wip commit. Commit ONLY the in-write-set paths (build the commit from the parsed
   in-scope list with an explicit pathspec / temporary index), never `commit` with a dirty
   foreign index.
2. HIGH: `git status --porcelain` C-quotes paths with spaces/UTF-8 (`"a b.sh"`); the parser
   does not unquote them, so those files are mis-addressed or skipped. Unquote (printf '%b' or
   git -z NUL-parsing — prefer `--porcelain -z`).
3. MEDIUM: the timeout-reap checkpoint paths advance HEAD without preserving review.diff first
   (the 6eee731 preservation only covers the normal path) — apply the same preserve-then-commit
   ordering there.
4. MEDIUM: cross-repository write-sets (paths in another repo) are silently ignored by the
   gate — either checkpoint per-repo or journal a loud stop_gate_skipped_foreign_repo line.

Extend tests/test-stop-gate.sh with red-first legs for 1-3 (leg 4 may be a journal-line
assertion). FOREGROUND solo: test-stop-gate.sh, test-no-work-terminal.sh, then full
run-core-offline — all green; suites strictly solo, on a fail rerun solo once before treating
it as yours. COMMIT on the lane branch (uncommitted exit = incident).

## Off_limits
leadv2-dispatch-code.sh routing block; supervise*; builder-selfcheck internals.

## Terminal artifact
Commit sha + red/green raw output + core-offline summary + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-855da00f" "<question>" \
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