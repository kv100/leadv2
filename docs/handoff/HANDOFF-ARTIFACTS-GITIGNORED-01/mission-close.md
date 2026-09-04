# HANDOFF-ARTIFACTS-GITIGNORED-01 — close it: the deliverable allowlist has no assertion behind it

LANE_WRITES: plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh, docs/handoff/HANDOFF-ARTIFACTS-GITIGNORED-01/

## What is already done — do not redo any of it

Everything this row's report describes is on `main` already, and I verified it rather than trusting
the report:

- `.gitignore` carries `!docs/handoff/*/report.md`, `!docs/handoff/*/brief*.md`,
  `!docs/handoff/*/round*-red`, and (from `D2-UNBLIND-AND-THIRD-STATE-M0M1-01` M0)
  `!docs/handoff/*/*.full.md` and `!docs/handoff/*/*.summary.md`.
- `plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh` exists and is registered in
  `tests/run-all.sh`.
- The suite is `6 passed, 0 failed` over **ten consecutive runs** on main.
- The lane branch `worktree-HANDOFF-ARTIFACTS-GITIGNORED-01` holds **zero** unlanded commits and
  **zero** differing files against main.

So the row's implementation is complete. There is exactly one thing missing, and it is the thing
that matters most.

## The gap — measured, not suspected

I ran the allowlist lines as negative controls through
`plugins/leadv2/scripts/leadv2-mutation-control.sh`, one line per control:

| allowlist line removed | result |
|---|---|
| `!docs/handoff/*/report.md` | control **bites** — `baseline_rc=0`, `mutated_rc=1` |
| `!docs/handoff/*/round*-red` | control **bites** — `baseline_rc=0`, `mutated_rc=1` |
| `!docs/handoff/*/*.full.md` | **mutant survived** (`mutated_rc=0`) — nothing asserts it |

Delete the `*.full.md` allowlist and every suite in the repo stays green.

That line is not decorative. Its absence is the direct cause of this evening's incident: 184 of 281
worker deliverables were invisible to git, a worker that had finished without committing read as
"produced nothing", the lane was re-dispatched, and the re-dispatch erased the previous round's
report. Five workers were declared dead that way; none had died. On main those reports are now
tracked — 358 of them, in one commit — and the only thing standing between us and a silent
repetition is a line no test defends.

## Your task

Add cases to `plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh`, in the style of the
existing cases, asserting:

1. A `docs/handoff/<id>/developer.full.md` is **addable with a plain `git add`** (no `-f`) and shows
   up in `git status --porcelain -uall`.
2. The same for a `*.summary.md`.
3. **The mirror, and do not skip it:** a sibling file under the same directory that is *not* on the
   allowlist — say `docs/handoff/<id>/context.yaml` or `scratch.txt` — must **stay ignored**. Without
   this, the allowlist could be widened to everything and the first two cases would still pass, which
   would restore the noise the blanket rule exists to suppress.
4. A tracked `*.full.md` that is deleted must appear as `D` in `git status --short` — the same
   second-order property the report already claims for `round*-red`. A deliverable that can be
   removed invisibly is only marginally better than one that was never visible.

**Use `git add --dry-run` or a real `git add` to decide addability. Do NOT use `git check-ignore`:**
it exits **0** on a negation match as well, so `check-ignore && echo ignored` reports an allowlisted
path as ignored. That trap was hit twice in this repo this week.

## Prove it

- Ten consecutive suite runs, all counts pasted. Ten, not one — a defect elsewhere tonight appeared
  twice in thirteen runs and only under load.
- **Three negative controls, one per allowlist line you now defend** (`*.full.md`, `*.summary.md`,
  and the mirror case), each through `leadv2-mutation-control.sh`, each with its
  `baseline_rc`/`mutated_rc` pair and the literal red line. The `*.full.md` control must go from
  today's `mutant_survived` to `mutated_rc=1`; that flip is the deliverable of this lane.
- Re-run the two controls that already bite (`report.md`, `round*-red`) to show you did not weaken
  them.

## Constraints

- Do NOT edit `.gitignore` — the allowlist is correct as it stands; you are adding the assertions
  that defend it.
- Do NOT touch `tests/run-all.sh` — held by another session, and the suite is already registered.
- Do NOT touch `leadv2-dispatch-code.sh` or `leadv2-active-registry.sh` — held by another session.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.
- Fixtures assert the **filesystem post-state**, never a return code, and verify their own setup.
- Do not merge to main. Leave the branch green with a report; merging is done by the other lead.

## Report

Ten suite count lines, five control results with their pairs and red lines, and the commit shas.
Nothing else.
