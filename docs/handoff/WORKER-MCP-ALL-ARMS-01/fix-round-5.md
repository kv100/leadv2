# WORKER-MCP-ALL-ARMS-01 — round 5 (review FAIL high=1; the lead ran the suite and it is RED)

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.**

**Lane:** worktree-WORKER-MCP-ALL-ARMS-01 (resume; merge `main` FIRST).

## What happened
The reviewer's single High finding was that `report.md:247` asserts a full
`tests/run-all.sh --scope changed` run ("full run, 2026-09-02, state-file reset beforehand") while the
evidence block holds the literal token `RUNALL_PLACEHOLDER`. Rather than spend a fifth round on a
worker re-pasting a claim, **the lead ran the suite from this lane's root.** The real result:

```
[CORE-OFFLINE] suites passed=68 failed=15 missing=0
[FAIL] plugins/leadv2/scripts/tests/run-core-offline.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 3 passed, 1 failed, scope=changed
```

Full log: `/tmp/mcp-runall.log` (2,284 lines) — copy the relevant sections into the report yourself,
do not cite the path as if it were evidence.

Note for your own run: the suite lives at `tests/run-all.sh` in the repo ROOT, **not** at
`plugins/leadv2/scripts/tests/run-all.sh`. That wrong path cost the lead 35 minutes today; it fails
instantly with "No such file or directory".

## The one question this round must answer
**Are those 15 failures pre-existing on `main`, or caused by this lane?** They are completely different
problems and must not be reported as one.

Method, and it must be this method:
1. Run `plugins/leadv2/scripts/tests/run-core-offline.sh` at this lane's **merge-base with main**
   (`git worktree add` a scratch checkout in mktemp at `$(git merge-base main HEAD)`, or `git stash`-free
   equivalent — do NOT reset this lane). Record `passed=/failed=` and the list of failing suite names.
2. Run it again at this lane's HEAD. Record the same.
3. Produce a three-column table in the report: suite name | red at merge-base | red at HEAD.
   - Red in BOTH → pre-existing, not this lane's debt. List it and stop there; it belongs to
     `FIFTEEN-RED-SUITES-01`, already filed.
   - Red only at HEAD → **this lane broke it.** Fix it in this round, one commit per suite, or state
     per suite why it cannot be fixed here.
4. Replace the `RUNALL_PLACEHOLDER` at `report.md:247` with the real tail, and grep your own report for
   leftovers before committing:
   `grep -nE '[A-Z_]{6,}_PLACEHOLDER|<[A-Z_]+>|TODO|TBD' docs/handoff/WORKER-MCP-ALL-ARMS-01/report.md`
   — paste the grep output showing it is empty.

## Do not
- Do not "fix" a red suite by weakening its assertion. A red test turned green by deleting the check is
  worse than the red test; that is the exact disease this repo is fighting.
- Do not add any new feature or check this round.
- Do not claim a run you did not perform. That is what put this lane in round 5.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Scratch checkouts in mktemp only. Tree clean, `main` merged.

## Done when
The three-column table exists with all 15 classified; every HEAD-only failure is fixed or defended per
suite; the placeholder is gone and the grep is empty; the pasted run-all tail is the real one.
