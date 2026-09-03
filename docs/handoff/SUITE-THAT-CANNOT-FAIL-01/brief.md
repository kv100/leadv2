# SUITE-THAT-CANNOT-FAIL-01 — a suite that cannot go red must not be accepted as evidence

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-THAT-CANNOT-FAIL-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-suite-falsifiable.sh,plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-suite-falsifiable.sh,tests/run-all.sh,docs/handoff/SUITE-THAT-CANNOT-FAIL-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why this exists — measured, not theorised

A lane was asked to fix `--resume-lane` and to prove it with a suite. It produced commit `0d61b3c`
with a real production change and a 59-line test file. The suite:

```
$ bash plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh; echo $?
... All tests completed
0
$ grep -cE '^(PASS|FAIL)' output      -> 0
$ grep -cE 'exit 1|return 1' suite    -> 0
```

Zero assertions, zero failure paths, exit 0 always. It cannot go red for any input, so it proves
nothing — and it looked like a delivered, tested task. The lead only caught it by hand.

This is the disease the whole review regime exists to kill, and today it walked straight through.
The gate cannot depend on a lead noticing.

## [Critical] 1 — a falsifiability check every lane must pass

Build `leadv2-suite-falsifiable.sh <suite-path>`. Given a suite file it must decide, **from
behaviour, not from source text**, whether that suite is capable of failing:

- run the suite as-is and record its exit code;
- apply a **generic** failure injection that any honest suite must notice, and run it again;
- a suite whose exit code is unchanged under injection is **not falsifiable** and must be reported
  as such, naming the suite.

You choose the injection mechanism; it must not be a grep of the suite's source (that is the same
class of non-assertion this task is removing), and it must not require the suite to follow any
particular naming convention. Explain the mechanism you chose in `report.md`, including how it
avoids false accusations against an honest suite that legitimately has nothing to assert.

Exit codes: 0 = falsifiable, non-zero = not falsifiable, with a distinct code for "could not
determine" — an undetermined result must never read as a pass.

## [Critical] 2 — wire it where the lying green actually enters

`leadv2-review-run.sh` is the sole owner of the review verdict. A lane whose new or changed suite is
not falsifiable must not be able to reach `status: pass`. Determine from the code which suites a
given review round is responsible for, and say in `report.md` what you keyed it on.

Two things it must not do:

- **never block on a suite the lane did not touch** — this is a gate on new evidence, not a
  repo-wide audit that would fail every lane on pre-existing debt;
- **never silently skip.** If it cannot evaluate a suite, the verdict says so; "could not determine"
  is a visible state, never an implicit pass.

## [Medium] 3 — make the failure legible to the worker

When the gate refuses, the message must tell the worker exactly what is missing: that the suite's
exit code did not change under injection, and that a printed `FAIL:` line leaving `$?` at 0 is not
an assertion. A refusal a worker cannot act on produces another round of the same thing.

## Acceptance

Build `test-suite-falsifiable.sh` against fixture suites — never a real lane, never the real review:

1. an honest suite with real assertions ⇒ reported falsifiable (exit 0);
2. a suite that prints `FAIL:` but always exits 0 ⇒ reported NOT falsifiable;
3. `test-resume-lane-arg-shapes.sh`'s exact shape (prints, no assertions, exit 0) ⇒ NOT falsifiable;
4. a suite that exits non-zero for an unrelated reason (e.g. missing dependency) ⇒ "could not
   determine", not a pass and not a false accusation;
5. review-run with a lane whose changed suite is not falsifiable ⇒ verdict is not `pass`;
6. review-run with a lane whose changed suite is falsifiable ⇒ verdict path unchanged from today;
7. a lane that changed no suite ⇒ gate does not fire.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the gate must turn this suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion. This suite of all suites must obey its own
  rule — it will be run against itself.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A suite that cannot go red cannot carry a lane to `pass`, the check runs against the suites the lane
actually changed, an undetermined result is visible rather than silently green, and this suite
passes its own check.
