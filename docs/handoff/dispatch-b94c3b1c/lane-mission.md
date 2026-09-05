# FABLE-THINK-TIER-01 — fix-round 9 (review FAIL high=2, both PRIOR findings unfixed)

## READ THIS FIRST — the rules that killed six rounds today
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** No Monitor, no `run_in_background`. Foreground
  with `timeout 900`.
- Nested agents are allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`, and
  you commit the child's output yourself.
- **Commit after every step.** Rounds today ended with work uncommitted and it had to be salvaged by hand.

**Lane:** worktree-FABLE-THINK-TIER-01 (resume; merge `main` FIRST).

## The two findings — both were reported before and both are still there
1. `plugins/leadv2/workflows/leadv2-diverge.js:146` — the judge-opus-fallback is a bare `await agent(...)`
   OUTSIDE `synthAgent`'s try/catch. An `agent()` rejection aborts the whole workflow before the
   `judged === n` reconciliation runs.
2. `plugins/leadv2/workflows/leadv2-po-feedback-loop.js:194` — same shape: the audit-opus-fallback is
   chained as `.then(r => ... agent(...))` with no `.catch` and no enclosing try/catch, so a rejection of
   either the primary audit or the fallback takes the workflow down.

## This is a pattern, not two bugs — so the round must close the pattern
The same finding shape has now survived multiple rounds. Do NOT fix only these two lines.

**Census first, in the report:** enumerate EVERY `agent(` call site across `plugins/leadv2/workflows/*.js`
and classify each as (a) inside a try/catch or carrying a `.catch`, or (b) unguarded. Paste the command
and the full table — file:line + verdict for each. Then fix every (b), not just the two the reviewer
happened to name. If a call site is deliberately unguarded because the workflow SHOULD abort there, say
so per line with the reason; that is an acceptable answer, silence is not.

## Do — one commit each
1. `## Review round 8 findings` in report.md: REAL/REFUTED per row with the evidence command.
2. The census table above.
3. Fix every unguarded call site. A fallback that exists to survive a primary failure must itself be
   inside the guard — a fallback that can take the process down is not a fallback.
4. Suite: for at least one workflow, prove the behaviour — a stubbed `agent()` that rejects on the
   FALLBACK path must leave the workflow reaching its reconciliation step, not aborting.
   **Negative control:** remove the guard in a mktemp FULL copy (including `lib/`) whose baseline is
   green → the case must go red. Paste both runs. A test that stubs the function it claims to cover
   proves nothing.
5. `tests/run-all.sh --scope changed` in the FOREGROUND with `timeout 900`; paste the tail. If it stalls,
   check `/tmp/leadv2-core-offline-*` for a lock whose holder pid is dead (`kill -0`), clear it, say so,
   re-run.
6. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main` merged.

## Done when
Both findings REAL→fixed, the census table is in the report with every call site classified, every
unguarded site is either fixed or defended per line, the rejection case passes with its negative control
pasted, and run-all's tail is present.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b94c3b1c" "<question>" \
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