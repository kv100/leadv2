# FABLE-THINK-TIER-01 — round 10 (judge verdict REVISE, confidence 0.90)

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 900`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.**

**Lane:** worktree-FABLE-THINK-TIER-01 (resume; merge `main` FIRST).

## Standing: the judge closed the original findings — do not redo them
Both round-8 findings are FIXED and verified by the judge (positive cases pass live, `node --check`
clean, the `agent(` census is complete). **Do not touch `leadv2-diverge.js` or
`leadv2-po-feedback-loop.js` again this round** unless a blocker below forces it.

## The two blockers

### B1 — the suite you added in round 9 is RED right now and still exits 0
`PASS=3 FAIL=3`, `rc=0`. A suite that prints `FAIL` and returns success is not a test; it is a claim.
This is precisely the condition our own falsifiability checker refuses rounds for.

Two separate things to fix, and the report must distinguish them:
1. **Make the failures real:** a failing case must change the process exit code. No `|| true` around a
   checked command; either `exit 1` on failure or let the failing command propagate.
2. **Make the 3 failing cases pass** — or, if a case is failing because it asserts something wrong,
   say so per case and delete it with the reason. Do not "fix" a case by weakening its assertion; that
   converts a red test into a green lie, which is the disease this whole task exists to kill.

**Root cause the judge named:** the negative control anchors to `HEAD`, so it drifts as the lane
commits. Anchor the mutant to a fixed base (the lane's merge-base, or a pinned copy), not to a moving
ref. State in the report which anchor you chose and why it cannot drift again.

### B2 — `report.md:482` holds a literal placeholder where the run-all tail belongs
The report asserts a run that its own evidence block does not contain. This is the SECOND lane today
with exactly this defect (`WORKER-MCP-ALL-ARMS-01` has the same), so treat it as a habit, not a slip:

- Run `tests/run-all.sh --scope changed` from the LANE ROOT — note the path: `tests/run-all.sh` at the
  repo root, **not** `plugins/leadv2/scripts/tests/run-all.sh` (that path does not exist; it cost the
  lead 35 minutes today). FOREGROUND, `timeout 1800`.
- Paste the real tail. If the run does not finish, say that plainly and paste what it did produce —
  "did not complete" is an acceptable report line; a placeholder is not.
- Then grep your own report for leftover placeholder tokens before you commit
  (`grep -nE '[A-Z_]{6,}_PLACEHOLDER|<[A-Z_]+>|TODO|TBD' docs/handoff/FABLE-THINK-TIER-01/report.md`)
  and paste the grep output showing it is empty.

## Do — one commit each
1. `## Judge verdict round 9` in report.md: the two blockers, each with what you changed.
2. B1 exit-code fix + the three failing cases resolved (fixed or deleted with a stated reason).
3. B1 anchor fix, with the chosen anchor named.
4. Negative control for the exit-code behaviour: in a mktemp FULL copy (including `lib/`) whose baseline
   is proven green, restore the swallowed exit code → the suite must go red. Paste BOTH runs.
5. B2 run-all + the placeholder grep, both pasted.
6. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main`
merged. Add no new feature this round.

## Done when
The suite is green AND its failures change its exit code (both shown); the anchor cannot drift; the
run-all tail is real; the placeholder grep is empty; the negative control is pasted red against a green
baseline.
