# PROMISE-GUARD-BIND-01 — the guard is suppressed by any tool call (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/tests/test-promise-guard.sh,tests/run-all.sh,docs/handoff/PROMISE-GUARD-BIND-01/

Founder-ordered on 2026-08-30 as `PROMISE-GUARD-SUPPRESSED-BY-ANY-TOOL-CALL-01`.

The guard exists to stop the lead ending a turn on a promise — saying "I'll dispatch X" and then
stopping without dispatching it. The founder has raised this repeatedly, in his words: *"снова ты
говоришь что сделаешь что-то и после этого ход кончается"*. The mechanism is supposed to be the
answer, and it does not fire.

## The defect

The guard is satisfied by **any** tool call in the turn, not by a tool call that actually performs
the promised action. So a turn that promises a dispatch and then reads a file is indistinguishable,
to the guard, from a turn that promises a dispatch and dispatches. In practice every turn contains
some tool call, so the guard is permanently suppressed and has never fired in anger.

Binding is the whole point: the promise must be matched against an action of the promised **kind**,
not against activity.

## The work

1. **Fix the extractor first.** Before binding can work, the guard has to identify what was
   promised. Establish what it currently extracts and where that is wrong — a binder built on a
   broken extractor will look like it works and bind the wrong thing.
2. **Fix `ACTION_BASH_RE`.** This is the pattern that decides whether a Bash call counts as the
   promised action. Make it recognise the action kinds the lead actually promises (a dispatch, a
   commit, a file write, a suite run) and reject unrelated calls.
3. **Roll out log-only.** Ship behind `LEADV2_PROMISE_GUARD_BLOCK=0` — the guard journals what it
   would have blocked, and blocks nothing. A guard that starts out blocking will fire on false
   positives on day one and get disabled forever, which is worse than the current state. Collect
   evidence first; flipping to blocking is a later, separate decision.
4. **Record the flip as a scheduled decision** in `docs/leadv2/scheduled-decisions.md` with a
   GO-condition expressed as a query over the journal (e.g. N consecutive turns where the
   would-have-blocked set contains no false positive), the exact flip, and the one-step rollback.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body, RED, revert, GREEN. A
  top-level insert makes everything red for the wrong reason and reads as a pass. Logs in
  `docs/handoff/PROMISE-GUARD-BIND-01/red/`.
- A control is a behavioural assertion on real output: feed the guard a turn transcript and assert
  on its verdict. Never `grep` against script source, and never a negated command as the assertion
  — `set -e` does not trip on it, so it can never fail.
- Include the two cases that matter as fixtures: **promise + matching action** must pass, and
  **promise + unrelated tool call** must be flagged. The second one is the entire defect; if your
  suite has no such fixture, you have not tested this.
- Bash 3.2.57 only: no `read -N`, no bash-4 array idioms, no unbound array under `set -u`.
- Prove `--scope changed` selects the promise-guard suites; paste the output.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

The extractor's failure named and fixed, `ACTION_BASH_RE` binding promises to actions of the
promised kind, both fixtures above passing with a mutation-proven control each, the guard shipping
log-only under `LEADV2_PROMISE_GUARD_BLOCK=0`, a scheduled-decision row for the flip, and a
`report.md` showing a real journal line where the guard would have caught a promise that this
session actually broke.
