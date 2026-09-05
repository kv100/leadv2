# LANE-WRITESET-REGISTRY-01 — RESUME (round 2). Work already exists on disk.

Repo root for this lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.

## First thing you do: `git status` and `git diff --stat`. Do not start over.
Round 1 hit its turn cap (`error_max_turns`) with real, UNCOMMITTED work in the tree:

- `plugins/leadv2/scripts/leadv2-active-registry.sh` — ~+202 lines
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — ~+31 lines
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — ~+35 lines

Nothing was committed and no tests were run. Your job is to FINISH and LAND this, not to
re-implement it. Read the existing diff first and keep what is correct.

## The binding plan is present now (it was missing in round 1 — that is fixed)
`docs/handoff/LANE-WRITESET-REGISTRY-01/context.yaml` — decisions D1–D9, 9 plan steps,
off_limits, verification.live_signal, test_plan. `docs/handoff/LANE-WRITESET-REGISTRY-01/mission.md`
is the full original mission. Both are in THIS worktree. Read the plan before judging the diff.

## Note a scope deviation and decide honestly
Round 1 touched `leadv2-dispatch-product-close.sh`, which is NOT among the plan's 9 steps
(step 8 names `leadv2-phase8-close.sh`). Either justify it against D8/step 8 in one line, or
revert it. Do not leave an unexplained file in the diff.

## Still owed, in this order
1. Steps 6 and 7 of the plan if round 1 did not reach them: the `writes` + `peer` columns and
   `--peers-json` on `leadv2_active_list`, and the `/leadv2 sessions` procedure rewrite in
   `plugins/leadv2/commands/leadv2.md`.
2. Step 8: the close-time peer notify, wrapped so it can never fail a close.
3. Step 9: the new suite `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh` AND
   its selection row in `plugins/leadv2/scripts/tests/run-core-offline.sh`. A suite CI never
   selects is worth nothing.
4. Run `verification.live_signal` from the plan verbatim. Paste the output. PASS requires all
   three: rc=5, the `writeset conflict: other=LANE-A` line, and LANE-B NOT appended.
5. The declared negative control: flip the overlap predicate to never match, INSIDE the
   function body, in a scratch worktree. Show the suite goes RED. Paste it.
6. Commit. Report the SHA.

## The one line that matters most
Intersect and append happen in ONE flock acquisition inside the registry's `register` op (D3).
If round 1 implemented a shell-level check-then-register in `leadv2-dispatch-code.sh`, that is
a TOCTOU race and must be moved inside the lock — it is the whole point of the task.

## Budget
You are the second and final round on this lane. If you cannot finish everything, commit what
is verified, and return `PARTIAL` naming exactly what remains and what you proved. Do not
return a green claim you did not run.

Return `PASS|PARTIAL|FAIL|BLOCKED` + changed paths + commit SHA + raw test output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c00defe0" "<question>" \
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