# BRAIN-CLASS-LIVE-01 — fix-round 5

**Class:** Standard fix-round. **Lane:** worktree-BRAIN-CLASS-LIVE-01 (resume; merge `main` FIRST).
**Do the work yourself in this lane; no nested agents; commit after every step.**

## Why this round exists
R4 review (opus, committed diff from 59af062b): `FAIL critical=1 high=2`. Rows:
`docs/handoff/BRAIN-CLASS-LIVE-01/review-findings.json`.

1. **Critical** `tests/test-brain-class-live.sh:324` — MUTATION (a) and (d) negative controls are
   vacuous: the mutant copy has no `lib/`, so `leadv2_brain_record` is never defined and both controls
   pass identically whether the mutation is present or not (reviewer proved it empirically).
2. **High** `leadv2-dispatch-code.sh:3939` — the `leadv2_brain_record` call is wrapped in
   `2>/dev/null`, so `class_escalated` / `class_floor_held` / `brain_decision` never reach stderr and are
   lost entirely when `JOURNAL_TASK` is unset or the journal append no-ops. The lane's headline output
   is silently droppable — the exact "rule without a reader" shape.
3. **High** `tests/test-brain-class-live.sh:97` — the (a)/(b) flake was "fixed" by polling in the TEST,
   not in the product. The stated root cause (async journal append) is contradicted by `emit()` being
   synchronous. 10 green runs cannot show a ~1-in-19 flake is gone (P≈0.58 of 10 clean runs untouched).

## Do — one commit each
1. `## R5 findings` rows in report.md: REAL/REFUTED + evidence command. No command = REAL.
2. Fix 1: the mutant copy must be a FULL copy of `plugins/leadv2/scripts` (incl. `lib/`) in mktemp, and
   each negative control must FIRST prove the unmutated copy passes, THEN prove the mutated copy fails.
   Paste both outputs for (a) and (d).
3. Fix 2: drop the `2>/dev/null`; the decision line must reach stderr on every path (journal on/off).
   Suite case: run with `JOURNAL_TASK` unset and assert the decision line on stderr; negative control
   (re-add the redirect in the mktemp copy) → red.
4. Fix 3: find the REAL nondeterminism. Reproduce it first: run the ORIGINAL (a)/(b) 40× in a loop and
   paste the failure count; then instrument (which assertion, what the output was on the failing run).
   Fix it in the product or in the test's setup (shared tmp path, leftover cache dir, PID reuse, ordering),
   never by retry/poll. Prove with 40/40 green AND explain the mechanism in one paragraph. Remove the poll.
5. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
- LANE_WRITES: the suite, `leadv2-dispatch-code.sh` (only the :3939 redirect), report.md. Never commit
  `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`, `critic.*`.
- Mutants/fixtures in mktemp only. Tree clean, `main` merged.

## Done when
- 3 findings REAL→fixed with pasted runtime evidence; 40/40 green with mechanism explained; FALSIFIABLE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b4d13413" "<question>" \
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