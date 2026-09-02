# BRAIN-CLASS-LIVE-01 — fix-round 4b (continue from committed WIP)

**Class:** Standard fix-round. **Lane:** worktree-BRAIN-CLASS-LIVE-01 (resume; merge `main` FIRST).

## Why this round exists
Round 4 worker spawned a nested developer with `isolation:"worktree"`, resumed it twice, then exited
"waiting" — the diff landed in a stray worktree, nothing was committed, no report section. The lead
salvaged the test diff onto the lane as `wip: BRAIN-CLASS-LIVE-01 R4 partial`. The original brief is
`docs/handoff/BRAIN-CLASS-LIVE-01/fix-round-4.md` — its two findings are still the whole job:

1. `tests/test-brain-class-live.sh` case (d): assert on the decision line on its OWN stream (the WIP
   adds `run_reentry_class` — finish it and make case (d) use it), plus a negative control that routes a
   wrong class while still logging "Heavy" elsewhere → red (show it in a mktemp copy).
2. Flake: cases (a)/(b) fail ~1 in 3. Root-cause the nondeterminism (shared tmp path, ordering,
   time-based wait, leftover lane state) and remove it. Prove with 10 consecutive green runs pasted.

## Hard rules for THIS worker
- **Do the work yourself in this lane.** Do NOT spawn nested agents, and never use `isolation:"worktree"`.
- **Commit after every step** (`git add <LANE_WRITES>; git commit`). ≤10 turns per step.
- Start with `git show --stat HEAD` to see the WIP; do not rewrite what already works.

## Do
1. `## R4 findings` rows in report.md: REAL/REFUTED + evidence command. Commit.
2. Fix 1 + negative control output pasted. Commit.
3. Fix 2 + `for i in $(seq 10); do bash …; done` tails, 10/10 green pasted. Commit.
4. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict. Commit.

## Constraints
- LANE_WRITES only: the suite + report.md. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
  `plugins/leadv2/scripts/docs/`, `critic.*`. Tree clean, `main` merged.

## Done when
- both findings REAL→fixed with evidence; 10/10 green; FALSIFIABLE; every step is its own commit.
