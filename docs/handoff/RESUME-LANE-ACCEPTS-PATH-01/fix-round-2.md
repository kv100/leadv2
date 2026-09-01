# RESUME-LANE-ACCEPTS-PATH-01 round 2 — 21 green assertions, none of which touch the fix

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RESUME-LANE-ACCEPTS-PATH-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,tests/run-all.sh,docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured by the lead before merging, 2026-09-01

The suite is honest-looking: 21 passed, 0 failed, exit 0, with 12 real assertion calls — not a
tautological suite by any of the usual smells. It still proves nothing about this lane's change.

The lane's production change adds absolute-path handling to `--resume-lane` in
`leadv2-dispatch-code.sh`:

```bash
if [[ "${_LV2_PIN_VALUE}" == /* ]]; then
  _LV2_PIN_CANDIDATE="${_LV2_PIN_VALUE}"
else
  _LV2_PIN_CANDIDATE="${LEADV2_WORKTREE_DIR:-...}/${_LV2_PIN_VALUE}"
fi
```

Replacing that condition with `if false` — the mutation was confirmed present in the file — leaves
the suite at:

```
test-resume-lane-arg-shapes: 21 passed, 0 failed
MUTANT_EXIT=0
```

So the branch this lane exists to add is **not exercised by the suite that ships with it**. Merging
on green would have put an unverified change on main behind a wall of passing assertions. That is
the `SUITE-THAT-CANNOT-FAIL-01` disease in its most convincing form: not a fake suite, a real suite
aimed slightly to the side of the change.

## [Critical] 1 — make the suite depend on the branch

At least one case must reach the absolute-path branch on the real call path and fail when it is
removed. Drive it the way production does — through `leadv2-dispatch-code.sh` with
`--resume-lane <absolute path>` — not by calling a helper in isolation.

Then re-run the same mutation and show, in `report.md`, both outputs: green before, red after.

## [Critical] 2 — the second branch too

The change also touches a `ref` path check further down. Determine whether any case covers that one,
with the same technique (mutate, observe), and report per-branch coverage honestly. If a branch
cannot be reached from a test, say why rather than leaving it silently uncovered.

## [Critical] 3 — do not pad the suite

The failure here is not "too few assertions" — 21 is plenty. Do not add more assertions to the
things already covered. Add exactly the cases that die when the fix dies, and say in `report.md`
which assertion is the one that kills.

## Acceptance

1. `--resume-lane <absolute path>` through the real entry point ⇒ pins that worktree;
2. `--resume-lane <bare name>` ⇒ still resolves under the worktrees dir (regression guard);
3. `--resume-lane <nonexistent path>` ⇒ refuses, naming the accepted shapes;
4. mutating the absolute-path branch to `if false` ⇒ the suite goes RED, non-zero exit;
5. the 21 existing cases still pass.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- Measure a suite's exit code WITHOUT a pipeline: `cmd > log 2>&1; echo $?`.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

The suite goes red when the absolute-path branch is removed, and the lane can be merged on evidence
rather than on a green number that was measuring something else.
