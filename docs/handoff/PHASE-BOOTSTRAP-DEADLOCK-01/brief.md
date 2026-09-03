# PHASE-BOOTSTRAP-DEADLOCK-01 — a first-time Standard+ dispatch can never pass the phase gate

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 900`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.** Rounds died today with work uncommitted.

**Class:** Standard. **Repo:** leadv2 plugin.

## The defect, reproduced live 2026-09-02
`leadv2-dispatch-code.sh`: the dispatcher's own `classify` write, performed inside `cmd_resolve`,
disqualifies the same call's bootstrap admission **before** the guard checks it. The consequence is not
a corner case — **100% of first-time Standard-or-higher dispatches are refused.** Relevant lines
~3984 and ~6930; confirm the exact sites yourself before editing, the numbers are from a diagnosis run
and may have moved.

The refusal presents as `phase_precondition_refused ... missing=diverge,plan,gate1`, and its remedy line
points at `leadv2-phase-record.sh` — but recording those phases without the underlying artifacts stamps
`proof=unverified` and the assert refuses again. So the remedy does not work either, and the honest
description is a deadlock, not a missing step.

## Why this matters more than its size
Measured over 75 dispatches in 30 days: **14 (19%) took the real phase path with a verified plan and
Gate-1; 22 (29%) attested their way past it with `--reason`; 39 (52%) have no plan record at all.**
The 29% is the corrosive number — the mechanism exists, it is impassable, so people route around it with
a formal excuse, and every reader downstream believes the phases ran. A gate that cannot be passed
honestly does not protect anything; it manufactures false attestations.

## Do — one commit each
1. `## Reproduction` in the report: reproduce the refusal for a brand-new task id in a scratch worktree
   BEFORE changing anything, and paste the exact output. If you cannot reproduce it, stop and say so —
   do not fix a bug you have not seen.
2. The fix: order the bootstrap admission check before the `classify` write that invalidates it, so a
   first-time dispatch is admitted on its own terms. Keep the guard's protection for the case it was
   built for (a lane claiming phases it never ran) — the goal is a passable gate, not a removed one.
   State in the report which case still refuses and why that is correct.
3. Suite: a brand-new task id at class Standard passes the phase gate on its first dispatch; a task id
   that falsely claims a verified plan still refuses. Both cases, both pasted.
   **Negative control:** restore the original ordering in a mktemp FULL copy of the tree (including
   `lib/`) whose baseline is proven green → the first case must go red. Paste baseline and mutant runs.
   Insert the mutation INSIDE the function body; a top-level insert makes everything red for the wrong
   reason and reads as a pass.
4. Then answer, in the report, with a number: after the fix, what does a first-time Standard dispatch
   actually have to produce before build? List the artifacts and say which of them the dispatcher can
   generate itself rather than demand. Prefer making the right path cheap over adding enforcement.
5. `tests/run-all.sh --scope changed` from the LANE ROOT — the path is `tests/run-all.sh` at the repo
   root, **not** `plugins/leadv2/scripts/tests/run-all.sh` (that path does not exist). FOREGROUND,
   `timeout 1800`. Paste the real tail. A placeholder token where run output belongs fails this round
   outright — that defect was found in two other lanes today.
6. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Out of scope
Redesigning the phases, changing what Phase 2 produces, or touching the review gate. This round makes
the existing gate passable and nothing else.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main` merged.

## Done when
The refusal is reproduced and pasted; a first-time Standard dispatch passes; a false claim still refuses;
the negative control is red against a green baseline; the artifact list from step 4 is in the report.
