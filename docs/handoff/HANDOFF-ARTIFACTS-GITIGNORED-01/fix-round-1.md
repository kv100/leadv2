# HANDOFF-ARTIFACTS-GITIGNORED-01 — round 2: the allowlist enumerates NAMES, so every new kind of document is invisible by default

LANE_WRITES: plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh, .gitignore, docs/handoff/HANDOFF-ARTIFACTS-GITIGNORED-01/

Do not redo round 1. Its four cases (`*.full.md` addable, `*.summary.md` addable, the non-allowlisted
sibling staying ignored, and a deleted tracked deliverable showing as `D`) stand, and the `*.full.md`
control that survived before must now bite. Keep all of it.

## What round 1 did not see

I hit this while filing my own report. `docs/handoff/<lane>/report-e4-round.md` **could not be
committed** — ignored. The allowlist matches exactly `report.md`, `brief*.md`, `*.full.md`,
`*.summary.md`, `round*-red`. It does not match `report-*.md`, `fix-round-*.md`, or `mission-*.md`.

Measured in `docs/handoff/D2-SINGLE-LIVENESS-VERDICT/`: `fix-round-2.md` and `mission-m0m1.md` are
**tracked** — but only because they entered the index before the rule existed. A new file of the same
kind, in the same directory, written today, is invisible. That is the census's own sentence — *"97
are tracked only because they predate the ignore rule"* — reappearing on a different class of
document. This is the third generation of one mistake: worker reports were generation two, lead
missions and fix-rounds are generation three, and generation four will be whatever we invent next.

## The requirement — a rule, not three more names

Do **not** simply append `!docs/handoff/*/mission-*.md` and two siblings. That patches this
generation and guarantees the next one. What the allowlist must express instead:

- **a lane's own documents are visible by default**, whatever they are named, and
- **the mirror still holds**: a sibling in the same directory that is not a lane document —
  `context.yaml`, `scratch.txt`, a stray tarball, an editor backup — must **stay ignored**.

The mirror is not optional and is the harder half. Without an assertion for it, the natural fix is to
widen the allowlist to everything, every existing case still passes, and the blanket rule that exists
to suppress dispatch noise is silently gone. Round 1 already proved that a rule with no assertion
behind it survives indefinitely; this is the same trap one level up.

Pick the mechanism you can defend — an extension-based rule, a documented naming convention enforced
by the test, or a narrowed ignore that lists what is excluded rather than what is permitted. Whatever
you choose, the test must state the property in the assertion, not restate the glob.

## Prove it

- The three names that motivated this — `report-e4-round.md`, `fix-round-1.md`, `mission-close.md` —
  each addable with a plain `git add` (no `-f`) in a fixture lane directory.
- The mirror, in the same fixture: `context.yaml` and `scratch.txt` stay ignored.
- **Negative controls, one per assertion class, through
  `plugins/leadv2/scripts/leadv2-mutation-control.sh`**: (a) revert the allowlist to the name-based
  form and show the lane-document case goes red; (b) widen it to `!docs/handoff/*/*` and show the
  **mirror** case goes red. Control (b) is the deliverable of this round — it is the one that proves
  the rule is scoped rather than a blanket unblind.
- Each control reports its `baseline_rc=0` / `mutated_rc=1` pair and the literal red line. A mutant
  that reddens the suite by **crashing** it is not a control: that happened on a lane tonight
  (`JSONDecodeError`), reads exactly like a pass, and was discarded and redone. If your mutant
  produces a stack trace rather than a failed assertion, the anchor is wrong — fix the anchor.
- Ten consecutive suite runs, all ten count lines pasted. Ten, not five.

## Constraints

- `tests/run-all.sh` — do not touch; the suite is already registered there.
- `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh` — held by other sessions.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.
- Fixtures assert filesystem post-state, never a return code, and verify their own setup.
- Do **not** use `git check-ignore` to decide anything: it exits **0** on a negation match too, so it
  reports an allowlisted path as ignored. Use `git add --dry-run` or a real `git add`.
- Do not merge to main. Leave the branch green with a report; merging is the other lead's.

## Report

Ten suite count lines, every control's `baseline_rc`/`mutated_rc` pair with its red line, and the
commit shas. Nothing else.
