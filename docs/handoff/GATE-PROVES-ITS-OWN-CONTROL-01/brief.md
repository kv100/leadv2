# GATE-PROVES-ITS-OWN-CONTROL-01 — the machine applies the mutation, not the author

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-PROVES-ITS-OWN-CONTROL-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/lib/leadv2-control-prover.sh,plugins/leadv2/scripts/tests/test-control-prover.sh,tests/run-all.sh,docs/handoff/GATE-PROVES-ITS-OWN-CONTROL-01/

Main is `7927b0f` in `~/Projects/leadv2`. Branch from it.

**This is the systemic lane.** Everything else on the board is an instance of what it fixes.

## Why it exists

The rule "prove your negative control" exists today only as prose in briefs. Prose is satisfied
by shape. Measured over two sessions and roughly a dozen rounds, the only reliable detector of a
fake control has been a human applying the mutation by hand — every single time, one round at a
time. Eight distinct fake shapes have been catalogued, and three more landed today:

- **the mutation kills the wrong layer** — `test-arm-admission.sh` was 16/0; putting the
  hardcoded `--base-arm glm` back at `leadv2-dispatch-code.sh:1920` left it **still 16/0**,
  because the suite exercises fixture routing data and never the dispatcher's own call site;
- **half a guarantee is never the reason for any verdict** — `test-codex-broker-staleness.sh`
  was 3/0; dropping the `-d "$_session_dir"` test left it **still 3/0**, because the fixture
  pairs a swept directory with an already-dead pid, so the pid half decides alone;
- **something else kills your mutation first** — a law whose mutation is killed by `mypy`
  before `pytest` ever runs; the law's own suite can be deleted whole and the number does not
  move (observed in the V5 track on its `l4-no-v4-import`).

## [Critical] the gate applies the mutation itself and requires red

Build `lib/leadv2-control-prover.sh`: given a lane's diff and its declared suite(s), it applies
each declared mutation **inside the production function body on the real call path**, runs the
suite, and requires:

1. the suite exits **non-zero** — a `FAIL:` line with `$?` still 0 is not red;
2. **that suite alone** goes red. If any other gate (a type-checker, a linter, another suite)
   also fails on the mutation, the kill does not count — it proves nothing about this suite;
3. the mutation is reverted and the suite returns green, with the production file
   byte-identical to its pre-mutation state;
4. the whole cycle leaves the repo byte-identical — this is a hard failure, not a warning.

A round whose declared control does not satisfy all four is `blocked: control_not_diagnostic`,
never `pass`. The author's claim is not consulted; neither is the reviewer's.

## [Critical] product mutations are counted apart from detector self-tests

A catalog entry that mutates a test and is "killed" by a unit test importing the same function
is a tautology, not a kill — the V5 track found four such entries out of eight, giving a green
8/8 over two genuinely protected flows. Count product mutations and detector self-tests in
separate tallies, and put **only the product number** in the headline.

## [Medium] the count must match the catalog, not a literal

An acceptance that pins a number (`killed == 4`) goes red by construction the moment the
catalog grows — that exact defect turned a healthy catalog expansion into a critical in the V5
track. Assert the invariant instead: `killed == scored == len(catalog)`.

## Acceptance

Build `test-control-prover.sh` against fixture lanes — never a real lane, never a real state
root — covering:

1. a genuinely diagnostic control ⇒ passes;
2. a suite that stays green with the fix removed ⇒ `control_not_diagnostic`;
3. a suite printing `FAIL:` while exiting 0 ⇒ `control_not_diagnostic`;
4. a mutation also killed by a second gate ⇒ not counted as a kill;
5. a mutation applied to a fixture rather than the production call path ⇒ not counted;
6. a catalog where half the entries mutate tests ⇒ headline shows the product number only;
7. catalog grows by one ⇒ the invariant still holds with no edit to any script.

Add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Rules

- The prover must prove itself: a mutation removing any of the four requirements above turns
  `test-control-prover.sh` red, with the exit code following.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never run against the real repo; fixtures only, removed on every exit path including failure.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A fake control cannot pass the gate, and the gate's own fakeness is itself mutation-proven.
