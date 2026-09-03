# PROMISE-GUARD-BIND-01 — round 4: the new rule fires on ordinary status sentences

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/tests/test-promise-guard.sh,tests/run-all.sh,docs/handoff/PROMISE-GUARD-BIND-01/

Full report: `docs/handoff/PROMISE-GUARD-BIND-01/review-r3.md`. HEAD is `57bf893`.

**Round 3 genuinely worked, verified independently — keep it.** All eleven promises from
`review-r1.md:88-98` now fire **through the real hook**; the pre-fix fixture reproduces the five
previously-silent ones exactly; the `допишу/перепишу/обновлю/смерджу/добавлю` family fires in both
orders; and the reviewer's own mutation reproduced `round3-red/shape-mutation-RED.log` line for line
(3 passed / 7 failed), so that artifact is honest. The journal sandbox held across all three suites
plus the mutation.

Two things remain, and the first would make the guard unusable.

## [Critical] the marker-first rule fires on ordinary status sentences

The new alternative at `plugins/leadv2/hooks/leadv2-promise-guard.sh:219` matches **six of ten**
ordinary Russian status clauses that were correctly silent before — for example:

- `Сейчас работу делают два воркера`
- `Сейчас задачу держит лейн A`

These are statements about the present, not commitments. The lead writes sentences like these
constantly in status updates, so the guard would flag a large share of perfectly good turns.

That is not merely noisy: every false `fired` row lands in the journal that the
`PROMISE-GUARD-BLOCK-FLIP-01` GO-condition counts, so it **poisons the decision to switch the guard
from log-only to blocking** — the same way 84 synthetic test rows did before the sandbox fix.

Tighten the rule so a marker followed by a *third-person / present-tense statement* does not match,
while a marker followed by a **first-person future commitment** does. The pinned negative at
`test-promise-guard-morphology.sh:276` is the one sub-case adjacency already handles, so it proves
nothing — replace it with all ten status clauses from the review as negative fixtures, and add the
eleven promises as positives. Both sets must be asserted together, so tightening cannot silently
break the positives.

## [High] the morphology suite never executes the hook

It re-implements the decision in Python from regexes lifted out of the script. So it tests a copy of
the logic, and the copy will drift from the hook the moment either changes — the suite can be fully
green while the real hook does something else entirely.

Drive the **real hook** with each fixture and assert on its journal output. That is what makes the
`10 passed(red->green)` number mean something; today it measures a Python re-implementation.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round4-red/`, and each
  artifact must assert its own outcome — another lane today shipped a green run under a RED header.
- Do not weaken a fixture to make a fix pass; if a fixture is wrong, say why in the commit message.
- Keep the rollout log-only under `LEADV2_PROMISE_GUARD_BLOCK=0`.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

All ten status clauses silent and all eleven promises firing, asserted together through the **real
hook** (paste the run); the morphology suite driving the hook rather than a Python copy of it; a
control that goes RED when the marker-first rule is reverted; and a note in `report.md` saying how
many journal rows the tightening removes, so the flip GO-condition can be judged on clean data.
