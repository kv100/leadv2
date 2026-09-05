# SUPERVISOR-RESIDUE-FOLLOWUP-FINISH-01 — finish items 3+4 (~/Projects/leadv2)

Lane checkpoint 517bc13 already carries items 1-2 (3 orphan supervisor hook files deleted, L3
dates → 2026-08-17, broad-status-duty test updated). Full original mission:
docs/handoff/dispatch-02e9baba/lane-mission.md. Two items remain:

1. L4: make plugins/leadv2/scripts/leadv2-fanout.sh refuse at entry (echo refusal citing the
   founder order 2026-08-17 «supervisor never returns» + exit 2 — same stub pattern the sweep
   used for supervise), align the /leadv2 fanout doc/command row with the stub.
2. T2-critic N3 (report docs/handoff/dispatch-9c027877-review/critic.final.md): in the
   builder-selfcheck suite, case_4_diff_golden builds its baseline via `git archive HEAD`,
   which in-worktree makes live==pre — the comparison arm is tautological. Parameterize the
   baseline ref (pre-gate ref or synthesized pre-tree) so the arm can genuinely fail; primary
   assertion untouched.

## Acceptance
Both changed suites green FOREGROUND solo · full run-core-offline FOREGROUND solo green ·
bash -n + shellcheck -S warning on touched scripts · COMMIT on lane branch (uncommitted exit
= incident; note the STOP-GATE irony).

## Off_limits
leadv2-dispatch-product-close.sh; leadv2-dispatch-code.sh; claude-subsession.sh; hooks.json.

## Terminal artifact
Commit sha + raw suite output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9685bf28" "<question>" \
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