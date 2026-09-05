# V3-DISPATCHER-ACCEPTANCE-FIX2-01 — foreign-root guard now refuses legit --resume-lane (~/Projects/leadv2)

Lane worktree HEAD 029ce01 + your predecessor's UNCOMMITTED edits to leadv2-dispatch-code.sh /
claude-subsession.sh / tests (closing critic blockers — report:
docs/handoff/dispatch-b4042501-review/critic.full.md). One real regression remains,
`tests/test-lane-placement-pin.sh` solo FOREGROUND = red:

- P-a/P-b: dispatch exited 5 (expected 0); worker cwd='' != RESUME=<fixture worktree>
- P-h(a): prompt pin line MISSING with --resume-lane

Mechanism: the Fault-2 foreign-root guard went default-ON (correct per critic) but now fires on
the legitimate case the pin tests exercise — dispatch with --resume-lane into a worktree whose
root differs from the caller-env-derived root. The guard must refuse ONLY a genuinely foreign
CLAUDE_PROJECT_DIR/PROJECT_ROOT leaking over the cwd-derived repo — never a cwd-consistent
--resume-lane/--worktree placement. Root-cause the ordering (guard vs lane-placement
resolution), fix so cwd-derived root + explicit lane pins win, keep the guard's refusal for the
truly-foreign case (test-foreign-project-root-guard.sh must STAY green with its Case-2
inversion intact).

FOREGROUND solo, in order:
1. tests/test-lane-placement-pin.sh — fully green.
2. tests/test-foreign-project-root-guard.sh — green (guard still refuses foreign roots).
3. tests/test-no-work-terminal.sh — green (was contention-red at the gate; confirm).
4. The other 3 DA test files green.
5. plugins/leadv2/scripts/tests/run-core-offline.sh full FOREGROUND solo green.
COMMIT on the lane branch (uncommitted exit = incident).

## Off_limits
leadv2-dispatch-product-close.sh; routing order/ceilings; supervise*.

## Terminal artifact
Commit sha + raw green output for suites 1-2 + core-offline summary + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-084729d9" "<question>" \
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