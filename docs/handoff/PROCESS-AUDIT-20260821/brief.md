# Audit: did four days of "make it faster and more accurate" fixes actually work?

You are auditing the leadv2 orchestration plugin in this repo (`~/Projects/leadv2`), not a product
feature. Be adversarial. The founder's complaint is specific and he is not asking to be reassured:

> Too many critic rounds. Too many bugs. Work is slow. The end results are arguable. And the tests
> prove only that the test suite passes — nothing more.

Between 2026-08-17 and 2026-08-21 a lot of plugin work shipped that was justified as making the
pipeline faster, catching bugs earlier, and cutting review rounds. The founder wants to know which
of it actually worked, which did not, and what to do instead. Your answer decides what gets
implemented next, so ground every claim in this repo's own artifacts.

## The evidence is in this repo — use it, do not theorize

1. **`git log --since=2026-08-17`** — the shipped fixes. The merge commits are unusually honest and
   state their own review history, e.g.
   - `6ae373a merge: V3-STOP-GATE-01 (review: opus-critic FAIL + codex r2 FAIL + codex r3 FAIL …)`
   - `585ad7f merge: V3-DISPATCHER-ACCEPTANCE-01 (codex r3 PASS after opus-critic FAIL + codex r2 FAIL …)`
   - `51aa2b2`, `215890e`, `89fe065` — each `codex r1 FAIL closed by <sha>`
   So the plugin's OWN lanes ran 1-3 FAIL rounds each, in the very repo that builds the
   anti-defect machinery. Measure this properly rather than trusting my summary: count rounds per
   landed lane over the window.
2. **`wip(...): auto-checkpoint on worker exit`, `worker died mid-task`, `worker exited
   uncommitted`** appear repeatedly on 08-20. Quantify how much wall-clock and how many rounds went
   to infrastructure death rather than to the work.
3. **The gates themselves**: `plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh`
   (falsification marker gate), `plugins/leadv2/scripts/leadv2-review-run.sh` (review engine,
   round-0 machine verdict, tiered review), `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
   (dispatch, scope gate, stop gate). Read what they actually enforce.
4. **`docs/handoff/dispatch-*/architect-prepass.md`** in `~/Projects/persona-engine` — the design
   pass that runs before a build.

## The four questions, in order of how much I care

**Q1. Which of the 08-17..08-21 fixes measurably worked, and which did not?**
Name each by commit. "Worked" must be observable in the artifacts (rounds dropped, deaths stopped,
a class of failure disappeared), not plausible-sounding. Say plainly where the evidence is
insufficient to judge — that is a valid answer and better than a guess.

**Q2. Why do review rounds keep multiplying?**
My own current hypothesis, which you should try to REFUTE rather than confirm: missions are written
as a list of findings ("fix H1, H2, H3"), the architect prepass then designs against that list
(one prepass literally opens "Design — three changes"), the builder implements exactly those, and
the reviewer — who looks at the whole mechanism — finds the next defect that was never in scope.
Rounds therefore discover a design one defect at a time. A concrete instance from today: a prepass
recorded the fact "the redraft loop retries only `check_voice_quality`; every other stage is
terminal", then designed a fail-closed path returning rc=2, which is terminal, which kills all post
drafting for that tenant. The fact was on the page and the consequence was not drawn.
If this hypothesis is wrong or incomplete, say so and give the better one.

**Q3. The tests prove only that the suite passes.**
This is the founder's sharpest point. There is a falsification gate requiring a
`RED-then-GREEN: <name> (pre_rc=1 -> post_rc=0)` marker. Judge honestly whether it produces real
evidence or a ritual that is easy to satisfy while proving nothing. Note two real observations from
today: (a) NO test in the persona-engine repo emits that marker, so the gate is unsatisfiable there
by convention and every lane trips it; (b) reviewers keep finding "tests that cannot fail" —
assertions comparing 9 of 11 lines, a byte-cap test that passes when the cap is doubled, a
"cross-check derived a second way" that is algebraically identical to the primary check. What
should the gate require instead so that passing it means something?

**Q4. Speed.**
Where does the wall-clock actually go — worker deaths, review rounds, prepass, dispatch overhead,
suite runtime? Rank by measured cost and say what to cut.

## Rules for your answer

- **Every claim carries its evidence**: a commit sha, a file:line, a count you derived, or a
  command whose output you paste. An untagged claim about how something behaves is exactly the
  defect class we are trying to kill, and it will be discarded.
- **Prioritize ruthlessly.** I would rather implement 3 changes that move the numbers than 15 that
  sound reasonable. Rank your proposals by expected effect on rounds-per-lane and wall-clock, and
  say what you would NOT bother doing.
- **Each proposal must be implementable**: name the file, the change, and how we would know a month
  later whether it worked (a query or a count, not a feeling).
- **Say what should be deleted.** Some of the last four days' machinery may be net-negative — a
  gate that blocks more real work than it catches defects. Naming that is more valuable than adding
  another gate.
- If you conclude some of the founder's complaint is not supported by the artifacts, say that too,
  with the evidence.

Write your answer to `docs/handoff/PROCESS-AUDIT-20260821/codex-findings.md`.
