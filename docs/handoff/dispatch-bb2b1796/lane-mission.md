CLOSE-GATE-CALLS-A-COMMITTED-LANE-no_work-01. The phase-8 gate measures a lane's work with
`git diff HEAD`, so a lane that did the right thing and COMMITTED is indistinguishable from a lane
that did nothing. Every finished lane is refused at the last inch.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T01:0xZ.

## The measurement

`leadv2-phase8-e2e-gate.sh:113-120` calls `lv2_lane_diff_is_empty` and, on rc0, deletes the
sentinel, writes `status: blocked / reason: no_work`, and exits 1 before running anything.

`leadv2-helpers.sh:2528-2551` is the predicate, and every branch of it compares the WORKING TREE
to `HEAD`:

    git -C "$repo" diff HEAD -- "$w"                     # tracked, uncommitted only
    git -C "$repo" ls-files --others --exclude-standard  # untracked only

A lane whose work is committed has no uncommitted diff. Reproduced on lane `f33ff575078f`
(P6a, commit `aa18b583`, a 300-line estimator plus its suite, lead-verified 5/5 with a control red
inside `_route_and_rounds`): the gate printed
`leadv2-phase8-e2e-gate: lane diff is empty (no_work) -- refusing to stamp sentinel` and exited 1.
The rc2 escape hatch ("undeterminable -> never block a real lane on a guess") shows the author's
intent was exactly the opposite of what the code does to a finished lane.

This is already on the board as `6801f5d3ba2a CLOSE-GATE-CALLS-A-FINISHED-LANE-no_work-01`
(observed on lane 6436a2e2). It is now blocking four parked lanes that hold verified work, and it
blocks every future close, because "commit your work before your turn ends" is what we tell every
worker to do.

## What to build

Make the predicate ask the question it documents — "did this lane produce any diff AT ALL?" —
against the lane's own **merge-base with the default branch**, not against `HEAD`:

- committed work counts (the diff from `git merge-base main HEAD` to `HEAD`),
- uncommitted work still counts (working tree vs `HEAD`), and
- untracked files still count.

Empty means all three are empty. Keep every existing behaviour that is right: the
`docs/leadv2` / `docs/handoff` exclusions, the declared-writes filter, the whole-tree fallback when
no writes are declared, and **rc2 for "not a git tree", which the caller must keep treating as
non-empty**. Do not change the caller's contract; `rc0 = empty` still means refuse.

Resolve the base defensively: if `main` does not exist or `merge-base` fails, fall back to the
HEAD-only comparison rather than returning "empty". Failing OPEN on an unresolvable base is
correct here — a lane wrongly allowed to run its suites loses minutes, a lane wrongly called
`no_work` loses the whole lane.

## Acceptance
acceptance:
  surface: command_output
  observable: `bash plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh <task_id>` run inside a lane
    worktree whose work is fully COMMITTED gets past the no_work refusal and actually runs the
    suites. Show it on a real parked lane, with the log line that used to say
    "lane diff is empty (no_work)" absent and a real verdict in its place. A lane with a genuinely
    empty tree AND no commits ahead of the base must still be refused — show that too, from the
    same run of the suite.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside `lv2_lane_diff_is_empty`'s body, drop the merge-base comparison and keep only
   `git diff HEAD`. The suite must go red on the RETURN CODE for the committed-work fixture — the
   value that has never varied — not on a log string.
2. Inside the same body, make an unresolvable base return 0 (empty) instead of falling back. The
   suite must go red on the fixture with no `main` branch. This is the dangerous direction: it
   turns every lane in a repo with an unusual default branch into `no_work` silently.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register with
`# run-all-triggers: leadv2-helpers` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- `leadv2-helpers.sh` is loaded by nearly everything. Change ONLY `lv2_lane_diff_is_empty`; do not
  touch another function in that file, and do not change its signature or its rc contract.
- Do NOT touch `codex-task.sh` or `leadv2-lane-worktree.sh` (sibling lanes own them),
  `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`.
- Never `git add -A`. **`git commit -- <path>` commits the WORKING TREE for that path, not the
  index.** Stage explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a gate log line, an rc, a suite output. Say "unverified" out
  loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/tests/test-lane-diff-counts-committed-work.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-bb2b1796" "<question>" \
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