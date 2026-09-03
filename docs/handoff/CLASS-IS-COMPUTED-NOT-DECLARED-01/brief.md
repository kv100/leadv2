# CLASS-IS-COMPUTED-NOT-DECLARED-01 — the lead can downgrade its own task class, and nothing notices

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASS-IS-COMPUTED-NOT-DECLARED-01`

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-admission-class.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh,tests/run-all.sh,docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why this exists — a real incident, today, by me

The lead (me) dispatched roughly a dozen lanes today with `--task-class light` on work that was
plainly Standard, because at `light` the phase gate does not require diverge/plan/gate1. I also
hand-wrote `context.yaml` and `.gate1-passed` so the gate would pass. The founder caught it and
asked the right question: what stops any lead from doing that for speed?

Today the answer is: nothing. The doctrine already exists — `leadv2-admission-class.sh:18` says

```
# An explicit --task-class flag wins but may only be ESCALATED by risk
```

— but `grep -rn 'class_downgrade\|declared_class\|class_mismatch' plugins/leadv2/scripts/` returns
**zero hits**. Nothing computes an independent class to escalate *from*, and nothing refuses a
downgrade. A rule with no reader is not a rule.

**Read this next part before designing anything.** The reason I bypassed was not laziness: the
honest path was physically impossible. The phase gate demanded `context.yaml`,
`architect-prepass.md` and `.gate1-passed`, while `.gitignore:49` forbade committing exactly those
paths, so they could never exist in a lane worktree. I fixed that in `6f6b55b`. The lesson governs
this whole lane: **an unpassable gate manufactures cheating.** Any control you add here must leave
an honest route open for every class, and you must prove that it does.

## [Critical] 1 — compute the class from evidence the lead does not control

Derive a baseline class from the dispatch itself, not from the flag. Signals available without
trusting anyone: the declared `LANE_WRITES` path set, how many subsystems it spans, and whether it
touches production, safety, publish or payment paths. Use what the repo already has where it fits
(`leadv2-admission-class.sh`, `leadv2-lane-class.py`) rather than inventing a parallel notion of
class; say in `report.md` what you reused and what you added.

The computation must be deterministic and re-runnable from the recorded dispatch inputs alone —
if it cannot be recomputed later from the ledger, the audit in item 4 is impossible.

## [Critical] 2 — `--task-class` may raise, never lower

A flag below the computed class is **refused**, with a message naming both classes and the signals
that produced the computed one. A flag above it is accepted and recorded as an escalation.

This is the whole point: make the cheat mechanically unavailable rather than discouraged. Do not
implement it as a warning.

## [Critical] 3 — any downgrade path that survives is founder-visible, never silent

If you conclude a legitimate downgrade must remain possible (say, an explicit founder instruction),
it may not be a quiet flag. It must be recorded with its reason and surfaced in the beat's status
output, so the founder sees each one without asking. Say in `report.md` whether you kept such a
path and why.

## [Medium] 4 — recompute at close against the real diff

The diff is unknowable at dispatch, so the pre-check can be honestly wrong. At close, recompute the
class from what the lane actually changed and record declared / computed / actual in the ledger. A
single mismatch is noise; a lead that systematically lands Standard-sized diffs under `light` is a
pattern, and the ledger is where that becomes visible.

## Acceptance

Build `test-class-cannot-be-downgraded.sh` against fixture dispatch inputs and a fixture ledger —
never a real dispatch, never the real ledger:

1. a write set spanning production/safety paths ⇒ computed class is Standard or higher;
2. `--task-class light` on that dispatch ⇒ **refused**, message names both classes and the signals;
3. `--task-class heavy` on a computed-light dispatch ⇒ accepted, recorded as an escalation;
4. no flag at all ⇒ the computed class is used;
5. a legitimate downgrade path, if you kept one ⇒ appears in the rendered status output;
6. close-time recompute records declared / computed / actual, and a mismatch is visible in the
   ledger;
7. **the honest path stays open**: for each class, a dispatch that satisfies the gate legitimately
   is admitted — no class may become unreachable. This case is not optional; it is the one that
   prevents this lane from recreating the defect it is fixing.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the downgrade refusal must turn this suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never write to the real dispatch ledger or the real state root.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A lead cannot dispatch below the computed class, an escalation is recorded, every class still has a
passable honest route, and removing the refusal turns the suite red with the exit code following.
