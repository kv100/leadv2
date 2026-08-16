# WHEN-TO-FORK-01 — report

Rule landed as `plugins/leadv2/docs/work-placement.md` (canonical), cited from
`plugins/leadv2/commands/leadv2.md` `# Routing summary`,
`plugins/leadv2/docs/phases.md` `§Spawn-hygiene`, and
`plugins/leadv2/docs/supervisor-role.md` `§What a supervisor session IS` item 2.
No hook, no script, no gate — per mission, enforcement is named in the doc
("If this needs teeth"), not built.

## Three worked examples, one per branch

### 1. Should have been a **fork** — dispatch-f7f1c2c8 (REPORT-ONLY-GATE-01 conflict resolution)

Mission: resolve the design conflict between the two in-flight REPORT-ONLY-GATE-01
branches (dispatch-5e57c5ff's original gate vs dispatch-4b7593fe's rebase/merge
round 2). The conflict itself was born in-session — *why* both branches existed,
which merge the session had already blessed, what the founder had said about
report-only gating. Journal evidence of the loss: the codex worker spawned
02:04Z died and a sonnet worker was re-spawned 03:05Z, with the deciding context
having to be rebuilt from mission text each time. Test 2 answers yes — the
decision needed earlier-this-session history that was only partially on disk —
so the branch is fork: one inherited context would have replaced two
context-reconstruction attempts.

### 2. Should have been a **fresh agent** — LANE-TRUTH-BATCH-01 premise-checks (dispatch-d3b09218 → dispatch-6dff3eaf → dispatch-fc1f3c3a)

The lane mission's own first instruction: "PREMISE-CHECK each row first against
the CURRENT tree … mark already-fixed rows with file:line evidence and skip."
Each premise-check is exactly the verification shape: "is this ledger row still
true?" — a closed-set answer (fixed / already-fixed / blocked), checkable
against disk without editing anything. The payoff proves the point:
`docs/handoff/LANE-TRUTH-BATCH-01/summary.md` Row 2
(LANE-REGISTRATION-ONLY-ON-FANOUT-PATH-01) came back **already-fixed, commit
`5d8c5a3` already on main** — a fact a fresh agent greps in ~70 seconds, no
worktree, no review gate. Test 3 (Test 1 fails — nothing produced, Test 2 fails
— answer is on disk) → fresh agent. The fix-work in those lanes did pass Test 1;
it is the premise-check half that this branch names.

### 3. Correctly a **lane** — dispatch-b0d05195 (E2E-GATE-ARCH-01)

Mission: make the e2e gate run suites against the LANE worktree, not main.
Test 1 answers yes on both prongs: the work ended in a committed diff *and* a
behavioral regression test another session will cite (mutation-gated: gate
pinned to main must FAIL). Landed as `5065e7b` + merge `98d3951` on the lane
branch — worktree isolation, review gate, and a close that records what landed,
all three things a lane buys actually bought.

## Verification

- `plugins/leadv2/docs/work-placement.md` states the three numbered branches
  (lane / fork / fresh agent), each introduced by a yes/no question about an
  observable property, plus §"Edge case (b): verification" (fresh agent, never
  a lane) and §"Edge case (a): report-only" (when such work belongs in a lane).
- Pointer lines verified present in all three citation sites (see diff).
- E2E gate: `tests/run-all.sh --scope changed` run from the lane worktree —
  docs/commands-only change, runner selects no per-stem suites beyond the
  offline core; result recorded below in the lane journal.
- Cross-provider review: executed by the dispatch close harness
  (`leadv2-dispatch-product-close.sh` review pool, base-arm codex ≠ author glm)
  after worker exit, per its `waiting_worker` contract.

DELIVERABLE_COMPLETE
