# PROMISE-GUARD-TURN-IT-ON-01 — the guard exists, is measured, and has never blocked once

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh,tests/run-all.sh,docs/leadv2/scheduled-decisions.md,docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The situation, measured 2026-09-01

`plugins/leadv2/hooks/leadv2-promise-guard.sh` is 702 lines, correctly wired into `Stop` for every
adopted repo, and ships **log-only**: `LEADV2_PROMISE_GUARD_BLOCK` defaults to `0`. Its journal
`~/.claude/leadv2-promise-guard.jsonl`:

```
1868 turns evaluated
 423 verdict=fired      <- "would have blocked"
1445 verdict=suppressed_action
   0 actually blocked
```

22.6% of turns announced work that did not start, and the founder caught every one of them by hand.
The mechanism was built, it works, and it is switched off. That is the whole defect.

The flip is blocked by its own GO-condition in `docs/leadv2/scheduled-decisions.md`: *the last 20
consecutive `fired` rows must have zero false positives*. Split the 423 by `primary_promise_kind`
and the reason it has never been met is obvious:

```
UNCLASSIFIED 402    dispatch 17    test 2    commit 1    write 1
```

Hand-checked quotes, and they split cleanly:

- **classified fires are real**, across 21 distinct sessions: `"Диспатчу воркера на задачу"`,
  `"I'll commit the fix now"`, `"Сейчас поправлю конфиг"`;
- **the unclassified bucket is where the false positives live**: `"Комиссию закрываю — вопрос снят"`
  and `"I'll show it"` are reports and conversation, not promises of work.

So the guard cannot be turned on wholesale without training itself off on day one — the exact
failure its own header warns about.

## [Critical] 1 — block on classified kinds, keep unclassified log-only

Gate blocking a second time on whether the promise kind was classified. An unclassified promise
still writes its journal row (that row is the evidence for widening the taxonomy later) but does not
block. Widening `PROMISE_KIND_PATTERNS` then widens the blocking set deliberately, which is the
correct coupling.

Provide a one-step opt-in to the old behaviour (`LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`) so the
decision is reversible without a code change.

**This changes a tested contract.** `test-promise-action-binding.sh` and
`test-promise-guard-morphology.sh` are GREEN on main (measured: 2 and 10 red→green, 0 failed) and go
RED under this change, because they assert that an unclassified promise blocks. Update those
assertions **deliberately**, and state in `report.md` exactly which assertion changed and why —
never by tweaking a test until it passes. The lead deliberately did NOT hand-edit them; that is this
task's job to do openly.

## [Critical] 2 — actually flip it on

Set `LEADV2_PROMISE_GUARD_BLOCK=1` where the Stop hook runs, per the FLIP line already written in
`docs/leadv2/scheduled-decisions.md`. A change that leaves the guard off has not fixed anything.
Update that ledger row to record what was flipped, on what evidence, and the one-step rollback.

## [Medium] 3 — close the taxonomy gap the journal exposes

402 unclassified fires is not noise to discard — it is a list of promise shapes the taxonomy does
not model. Sample them, name the recurring shapes in `report.md`, and add the ones that are
unambiguous commitments of a modelled action kind. Do not invent kinds with no action-side
counterpart: a promise kind that no action kind can satisfy would block forever.

## Acceptance

Build `test-promise-guard-classified-block.sh` against fixture transcripts — never the real journal,
never the real `~/.claude`:

1. classified promise (`dispatch`) + no action of that kind ⇒ blocks;
2. classified promise + a matching action ⇒ does not block (regression guard);
3. **unclassified** promise + no action ⇒ does NOT block, but the journal row is still written;
4. same, with `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1` ⇒ blocks;
5. `LEADV2_PROMISE_GUARD_BLOCK=0` ⇒ never blocks, whatever the kind;
6. a past-tense report carrying a sha or a probe result ⇒ never blocks;
7. two Stop events in one turn ⇒ blocks at most once (existing sentinel, regression guard).

Both pre-existing suites must be green again after their assertions are updated. Add the
`EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the classified gate must turn the new suite red.
- A kill counts only if the suite was green first — the lead verified both existing suites are
  green on main before this brief was written.
- Never write to the real `~/.claude/leadv2-promise-guard.jsonl` from a test.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A classified unkept promise blocks the turn in every adopted repo, an unclassified one is recorded
but not blocked, the ledger row states what was flipped and how to roll it back in one step, and the
taxonomy has grown by the shapes the journal actually shows.
