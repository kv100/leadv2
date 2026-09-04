# D2-E4-RESOLVES-THE-WRONG-DIR-01 — lead verification report

Branch `worktree-D2-E4-RESOLVES-THE-WRONG-DIR-01`, commits `18f0cc8c` (anchor), `7de54f50` (fix),
`d072d785` (fixtures). **Green and ready to land. Not merged by me** — merging into main belongs to
the other lead session.

## What this round fixes

`D2-UNBLIND-AND-THIRD-STATE-M0M1-01` (merged `8161030c`) added rung E4, so a worker that finished
without committing reports `finished_unlanded:<age>s` instead of `dead:no_log_artifact`. Measured
right after that merge, the rung was **inert on the live path**: `resolve()` searched
`docs/handoff/<tid>/`, while deliverables are written to `docs/handoff/dispatch-<sig8>/`. Every lane
the lead actually names — `--task-id` takes the founder id — searched a directory the report is
never written to. The fixtures passed because they built `dispatch-`shaped ids; production uses the
other shape.

The fix resolves the lane's real handoff directory from a closed candidate set. It deliberately does
**not** glob across `docs/handoff/`: attributing another lane's report to this one would be a false
`finished_unlanded` — the mirror mistake, and just as damaging as the original.

## Verification the lead ran

**Ten consecutive runs** of `plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`:

```
16 passed, 0 failed    (x10, all ten identical)
```

Ten and not five, because a defect elsewhere in this repo this week appeared 2-in-13 and only under
load.

**Negative control — written by the lead, semantic rather than a crash.** Applied inside
`deliverable_age_s`'s loop body through `plugins/leadv2/scripts/leadv2-mutation-control.sh`, dropping
`dispatch-` directories back out of the candidate set — i.e. restoring exactly the defect this round
removes:

```
mutation:   s|    for lane_dir in lane_dirs:|    for lane_dir in [d for d in lane_dirs if not os.path.basename(d).startswith("dispatch-")]:|
NC rc=0
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: Test 10: verdict=dead:no_log_artifact (must be finished_unlanded:<age>s — E4 resolved the wrong dir)
```

A first attempt at this control reddened the suite with a `JSONDecodeError` — the mutant crashed the
script instead of changing its behaviour. Red for the wrong reason reads as a pass and overstates the
evidence, so it was discarded; the pair above is the surgical replacement. Recording the discarded
attempt because it is the same class of weak evidence as a top-level insert.

## What I could NOT prove, and why — read before closing the row

The acceptance I wrote into `fix-round-2.md` demanded a **live-lane check**: run the liveness script
against a lane with a running worker and show the verdict is no longer `dead:*`, with the explicit
line *"If it still says `dead:*`, you are not done regardless of what the suite says."*

**That check did not flip. The fix is not the reason.** Measured during verification:

| lane | verdict | deliverables on disk |
|---|---|---|
| `dispatch-6134df79` | `dead:sentinel_finalized` | 1 |
| `D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01` | `dead:no_log_artifact` | 0 |
| `D1-HARDEN-THE-WRITER-M1M3-01` | `dead:no_log_artifact` | 0 |
| `D2-E4-RESOLVES-THE-WRONG-DIR-01` (live worker) | `dead:no_log_artifact` | 0 |

Rung E4 answers one question: *did this lane leave a deliverable?* Every live lane on this machine
has not written one yet, so E4 correctly finds nothing; and the single lane that does have one
carries a terminal sentinel that wins at an earlier rung. No live lane available right now can
discriminate the fix either way.

The remaining wrongness in that table is a **different rung**: a lane with a running worker and no
deliverable reports `dead:no_log_artifact` rather than alive. That is the process rung — D2 step M2
(process kind, EPERM vs ESRCH, and the recorded PID belonging to the lead session rather than the
lane's worker). It is out of this round's scope and must not be closed by it.

**Accept this lane on fixture evidence plus a biting semantic control, and do not read the unchanged
live verdict as a failure of the fix.** The live check becomes discriminating the moment M2 lands, or
as soon as any live lane writes its first `*.full.md`.
# bash-guard: allow

---

## CORRECTION, 2026-09-04 — the section above is wrong about D3, and the error is mine

I wrote that no live lane could discriminate the fix, and that the remaining wrongness belonged to
the process rung (M2). **That is wrong for `D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01`, and it was my own
measurement error, not a limitation of the machine.**

I counted D3's deliverables in `docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01/` and found none.
Its deliverable is in `docs/handoff/dispatch-57a94876/`: `developer.full.md` and
`developer.summary.md`. I made by hand exactly the mistake this lane exists to fix — resolved a lane
by its founder id and read the wrong directory. That row's "0 deliverables" should read 2.

**So D3 does discriminate, and E4 still fails on it, for a cause inside this rung rather than M2.**
The registry holds THREE rows for that lane (`docs/leadv2/active.yaml`): row 1 points at
`docs/handoff/dispatch-57a94876/developer.stream.jsonl`, row 2 at the `pulse.md` default, row 3 at
`None`. `sessions` is a dict keyed by task_id, so only the **last** row survives — `None`. The
pointer naming the real handoff directory is discarded before E4 runs. Every re-armed lane is still
blind, and re-armed lanes are precisely the population this rung was built for.

The merged fix is correct as far as it goes and stays: a single-row lane resolves. It is
**incomplete**, and the live acceptance I set — "if it still says `dead:*`, you are not done" — is
now met by a real lane and is failing. Follow-up: `E4-KEEPS-ONLY-THE-LAST-REGISTRY-ROW-01`, whose
acceptance is that lane, live — D3 must report `finished_unlanded:<age>s`.

Do not read the merge of `b57ec9ab` as closing the rung, and do not close M2 with it.
