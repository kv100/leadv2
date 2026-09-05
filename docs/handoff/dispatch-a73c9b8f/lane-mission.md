# TEST-FALSIFICATION-GATE-01 + stop-gate untracked leg (~/Projects/leadv2, base main 215890e)

Two items, shared files (builder-selfcheck + tests). FOREGROUND everything, suites strictly
SOLO, COMMIT before ending.

## 1. TEST-FALSIFICATION-GATE-01 (row exists)
Machine rule «a test must have failed once»: extend lib/leadv2-builder-selfcheck.sh (which
now also carries the SCOPE bounce + diff_hash stamp — do not regress either) to REFUSE a diff
that adds/changes a test file without falsification proof: selfcheck.md must carry per-test
raw RED output against a pinned pre-fix baseline or mutant (pattern already coded in
test-review-gate-scope-evidence.sh red-first harness; GREEN_PRE_FIX>0 = non-zero exit).
Kill-switch env (same idiom). Root cause: 3 lying-green tests in 3 lanes within 24h.
Red-first suite legs.

## 2. Stop-gate untracked-timeout test leg (codex r3 ask, currently live-probe-proven only)
tests/test-stop-gate.sh: red-first leg — worker timeout with an UNTRACKED declared file →
review.diff contains it AND the checkpoint commit includes it. Red leg: assert against a
mutant that reverts pc_stop_gate_capture_diff to plain `git diff HEAD`.

## Acceptance
Both suites green with red legs shown · full run-core-offline FOREGROUND SOLO green ·
bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-code.sh; leadv2-review-run.sh (beyond reading); routing; supervise*.

## Terminal artifact
Commit sha + red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a73c9b8f" "<question>" \
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