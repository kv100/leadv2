verdict: APPROVE
next_action: review_round_2

# CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 — dispatch-6fccc10d (round 3)

No `docs/handoff/dispatch-6fccc10d/context.yaml` existed for this dispatch —
proceeded from the full lane mission text and the task's own existing
report at `docs/handoff/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01/report.md`,
which already carried a thorough round-2 pass (items 1-4, 6-9, 11 partial,
committed at `232bb9ee`). This round's job was to close what round 2 left
open, not repeat it.

## What round 2 left open (its own "What is still missing" list)

- Item 5's script existed but was wired to nothing — "surface someone reads"
  was not actually true.
- Item 10's paired A/B: blocked by no MCP permission grant in that session.
- Item 11: `m3` wiring blocked by writing outside the worktree.
- Item 4's negative finding: real, not a gap.

## What this round did

**Item 5 — closed.** Added the leadv2-status-collector.sh repo_facts hook
(`.claude/leadv2-overrides/status-collector-facts.sh`) this repo never had.
It shells out to `leadv2-code-intel-rate.sh` and folds the summary line +
per-arm breakdown into `docs/leadv2/status-snapshot.json`'s `repo_facts`
section — the same path `render_repo_facts()` (leadv2-status-surface.sh)
prints on every `--mode all`, which is what `founder-status.md` reads. Full
verification, both direct-call output and the negative-control
before/after-mapping proof for `tests/run-all.sh --scope changed`, plus the
macOS/Linux green runs and the cross-platform bug found and fixed along the
way, are in `docs/handoff/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01/report.md`
under "## Round 3".

**Item 10 — reconfirmed, not re-guessed.** Ran an independent second attempt
at `mcp__repowise__get_answer` from this session (a fresh subagent, in case
grants differ session to session): `Permission to use
mcp__repowise__get_answer has been denied.` Same failure as round 2 on a
different attempt — this is a real, reproducible reachability gap for a
developer-role /leadv2 session, not a fluke. The paired single-task A/B
stays withdrawn.

**Item 11 — deliberately not reattempted.** `m3`'s `.mcp.json` is outside
this lane's writable scope by the mission's own "Writable scope — $WRITE_ROOT"
rule (main-repo and other-repo paths are off-limits during worktree tasks).
Round 2 already produced the exact JSON to apply and a `LEAD_ACTION` for a
session with that permission. Re-attempting from here would be a protocol
violation, not a permission accident to route around — left as-is.

## Commits this round (on the lane branch, not main)

- `2ae19e0f` feat(code-intel): surface the attach rate on founder-status
  (item 5)
- `b732d51a` fix(code-intel): stop relying on prefix-assignment persistence
  in the facts-hook test (cross-platform bug found by the Linux gate)
- `6ea57ec7` docs(code-intel): round 3 report

## Self-check evidence (also in the task report)

```
$ bash -n .claude/leadv2-overrides/status-collector-facts.sh; echo $?
0
$ bash -n plugins/leadv2/scripts/tests/test-status-collector-facts.sh; echo $?
0
$ bash -n tests/run-all.sh; echo $?
0
$ bash plugins/leadv2/scripts/tests/test-status-collector-facts.sh   # macOS
=== SUMMARY: 10 passed, 0 failed ===  (exit 0)
$ docker run ... python:3.12-slim bash plugins/leadv2/scripts/tests/test-status-collector-facts.sh   # Linux
=== SUMMARY: 10 passed, 0 failed ===  (exit 0)
$ bash plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh   # pre-existing, no regression
=== SUMMARY: 10 passed, 0 failed ===
$ bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh   # pre-existing, no regression
TOTAL: PASS=49 FAIL=0
```
No Python files touched this round.

## Diff scope

`git diff --stat main..HEAD` after this round's commits shows only files
under `.claude/leadv2-overrides/`, `plugins/leadv2/scripts/`, `tests/`, and
`docs/handoff/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01/` — no
`docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` path
touched by any commit made this round (the pre-existing dirty runtime-state
files visible in `git status` predate this session and were left untouched,
per the DoD gate and the repo's own boundaries).

## Left alone, deliberately

- The `sonnet` arm's `LEADV2_SUBSESSION_SLIM_MCP` default (named as the real
  fail-open cause for that arm in round 2, item 2) — out of the brief's
  stated scope, not touched.
- `pf3-backend`/`environment-platform`'s bare `repowise` command gap (no
  `which repowise` resolution) — pre-existing, unrelated to this task's
  wiring, noted for the record in round 2 only.
- Index-freshness automation (no cron/LaunchAgent reindexes today) — named
  in round 2, designing a fix was out of the brief's scope.

DELIVERABLE_COMPLETE
