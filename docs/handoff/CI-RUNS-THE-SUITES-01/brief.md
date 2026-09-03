# CI-RUNS-THE-SUITES-01 — one CI job that actually runs the test suites

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.**

**Class:** Standard. **Repo:** leadv2 plugin.

## The fact
`.github/workflows/` contains exactly one file, `validate-skills.yml`, which lints SKILL.md front-matter.
**No workflow references `tests/` at all** (`grep -rl 'run-all\.sh\|tests/' .github/workflows/` → empty).
The repo has **315 suites**. Nobody runs them automatically, and as a result **15 of 83 suites inside
`run-core-offline.sh` are currently red** and nobody knew — measured by the lead on 2026-09-02 in a lane
worktree: `[CORE-OFFLINE] suites passed=68 failed=15 missing=0`.

## Why this is first in the plan
Measured the same day: four lanes sat 30/64/76/120 minutes with no commits because each worker was
running `tests/run-all.sh --scope changed` in its own lane, four copies of the same work, contending for
the machine-wide suite lock. A full run is ~40 minutes. Until the run lives in CI, every worker must
re-earn the same green by hand, every round, forever.

## Deliver
1. **A workflow that runs the suites.** On push and pull_request: `tests/run-all.sh --scope changed`
   (note the path — `tests/run-all.sh` at the repo ROOT, not `plugins/leadv2/scripts/tests/run-all.sh`,
   which does not exist). On a schedule (daily is fine): `--scope all`.
2. **The report must name what failed**, not just a count. A red job whose output is `15 failed` sends
   the reader back to reproduce locally, which is the cost we are removing. List the failing suite names
   in the job summary.
3. **Red blocks merge.** Say plainly in the report how that is enforced and whether it needs a repo
   setting you cannot make from here — if it does, name the setting rather than claiming it is done.
4. **Handle the current reality honestly.** 15 suites are already red on `main`. A job that is red from
   birth teaches everyone to ignore it. So: the changed-scope job must be green on a clean branch, and
   the known-red set goes into an explicit, dated allow-list file with one line per suite naming why it
   is there. The allow-list may only shrink — add a check that fails if it grows. Do NOT fix the 15 here;
   that is `FIFTEEN-RED-SUITES-01`, a separate task that depends on this one.
5. **Timeouts and cost.** A 40-minute job on every push is its own tax. State the measured wall time of
   `--scope changed` on a typical diff, and pick the timeout from that measurement, not from a guess.

## Prove it
- Break one suite deliberately in a scratch branch → the job goes red and names that suite. Paste the
  run URL or the local `act`/script equivalent output.
- Fix it → green. Paste both.
- **Negative control:** remove the `run-all` step from the workflow in a mktemp copy → the broken-suite
  case must stop being detected. Paste it.
- Verify the allow-list guard: add a fake entry → the guard fails. Paste it.

## Constraints
LANE_WRITES: `.github/workflows/`, `tests/`, the allow-list file, and this task's handoff dir. Never
commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`, `critic.*`.
Tree clean, `main` merged.

## Done when
The workflow exists and is proven to catch a broken suite with a pasted run; the allow-list holds exactly
the currently-red suites with reasons and a guard that refuses growth; the measured wall time and the
chosen timeout are both in the report.
