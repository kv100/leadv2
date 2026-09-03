# PHASE-BOOTSTRAP-DEADLOCK-01 — round 2: the fix is committed, now prove it and close

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.** Round 1's worker exited with 43 lines of suite work uncommitted; the
  lead salvaged it as `5e1bf5a1`. Do not repeat that.
- Suite path is `tests/run-all.sh` at the repo **ROOT**.

## What already exists on this lane — read before writing anything

```
5e1bf5a1 test(phase): salvage uncommitted bootstrap-precondition suite work
fdaa9352 fix: admit phase bootstrap before classify
14c037b2 docs: record bootstrap deadlock reproduction
```

The fix and the reproduction are committed. **Do not rewrite them.** Round 1 died before proving
them. Your job is the proof and the close, not a redesign. If you believe the committed fix is
wrong, say so with the failing case — but the default assumption is that it stands.

## Why this is now the blocking task

Measured 2026-09-02, live: a fresh Heavy dispatch (`ARBITER-ESTIMATES-BLIND-01`) refused at
`lane_plan_missing reason=source_absent`, after `class_escalated ... to=Heavy
because=subsystems_touched:5` routed it through the full phase chain. So the deadlock is not
theoretical any more — it is stopping real work from starting, today. Until it is closed, every
first-time Standard-or-higher dispatch either dies here or attests its way past with `--reason`.
The latter is already 29% of dispatches over 30 days, against 19% that took the real path.

## Deliver

1. **The two cases, both pasted.** A brand-new task id at class Standard passes the phase gate on
   its first dispatch. A task id that falsely claims a verified plan still refuses. Say which case
   still refuses and why that refusal is correct — a gate that admits everything is not a fix.
2. **Negative control.** Restore the original ordering in a mktemp FULL copy of the tree (including
   `lib/`) whose baseline is proven green → case 1 must go red. Paste baseline and mutant runs.
   Insert the mutation INSIDE the function body; a top-level insert makes every suite red for the
   wrong reason and reads as a pass.
3. **The Heavy path too, not just Standard.** The live failure above was a Heavy escalation
   (`subsystems_touched:5`) demanding `classify,diverge,plan,gate1,...`. Show what a first-time
   Heavy dispatch must now produce before build. If the answer is still "a plan record it cannot
   have", the fix is incomplete and this round is not done — say so plainly rather than closing on
   the Standard case alone.
4. **Answer with a number:** after the fix, how many artifacts must a first-time dispatch produce,
   and which of them can the dispatcher generate itself rather than demand? Prefer making the right
   path cheap over adding enforcement.
5. `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND, `timeout 1800`. Paste the real
   tail. A placeholder token where run output belongs fails this round outright.
6. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Known-red note
If a suite named in `tests/known-red-suites.txt` blocks you — `run-core-offline.sh` in particular —
it is a pre-existing flake under concurrent machine load, not yours. Run it standalone, paste the
result, and move on. Do not fix it here.

## Out of scope
Redesigning the phases, changing what Phase 2 produces, the review gate.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main`
merged.

## Done when
Both cases are pasted; the negative control is red against a green baseline; the Heavy first-time
path is answered honestly (fixed, or explicitly still broken); the artifact count from item 4 is in
the report.
