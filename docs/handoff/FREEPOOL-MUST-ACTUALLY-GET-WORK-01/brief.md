# FREEPOOL-MUST-ACTUALLY-GET-WORK-01

Founder order 2026-09-03: "сделай так чтобы фрипул реально делал и мог получать эту работу."
The free arm must actually be handed work it is capable of, and must finish a round with a
commit instead of dying with the work uncommitted.

Nothing below is a guess: every claim carries the file:line or the run id it was measured on.

## Measured state — three separate causes, none of them a bug in the arm itself

**(1) `--protected` is a manual lead flag with no connection to the write-set.**
`leadv2-dispatch-code.sh:6646` is literally `--protected) protected=1; shift ;;`. It is never
derived from what the lane actually writes. Any `--protected` removes every untrusted arm
(`leadv2-dispatch-code.sh:2324` emits `arm_excluded by=router arm=freepool reason=protected_path`).
On the night of 2026-09-03 the lead passed `--protected` on every dispatch out of habit and so
banned the free arm from work it was fully capable of.

**(2) The turn cap kills it holding uncommitted work.**
`freepool-coder.sh:80,84`: `FREEPOOL_MAX_TURNS=120`, `FREEPOOL_TURN_LIMIT=120`. Run
`260903-030233-CI-SUITES-ARE-MACOS-ONLY-01-49db` reached 121 turns, produced a real diff
(10 modified files plus a new `plugins/leadv2/scripts/lib/mktemp-guard.sh`) and terminated with
`exit 80`, `LEADV2_LANE_OUTCOME outcome=died-with-work bound=turn_count work=yes`. It committed
nothing. A whole round of real work was left as loose worktree state.

**(3) Even when admitted, it loses to a paid arm.**
`leadv2-route-arbiter.sh:167-174`: the capability floor adds +100 to effective cost, and effective
cost is the sort's dominant key, so a floored freepool sorts after codex (3..7) and sonnet (5).
Measured 2026-08-30: with the flag removed, work still went to codex, `util_freepool=0`.

## What to change

**A. Derive protection from the write-set; keep the flag one-directional.**
A lane whose LANE_WRITES lie entirely under `tests/`, `plugins/leadv2/scripts/tests/` and
`docs/handoff/` is NEVER a protected path. The manual `--protected` flag may still ADD protection
for a caller that knows better; it must no longer be the only input. A caller's habit must not be
able to silently ban an arm from work it is capable of. Journal the derivation with the deciding
write-set so the reason is visible in one line.

**B. Make a round end in a commit, not in `died-with-work`.**
Raising the cap alone is not the fix — a bigger number just moves the cliff. The round must
checkpoint: when the turn budget is close to exhausted, the worker commits what it has in its own
lane before the cap ends it. Choose the mechanism that fits `freepool-coder.sh`'s existing
supervise loop; a bare `FREEPOOL_TURN_LIMIT` bump with no checkpoint is not an acceptable answer.

**C. Prove the floor's behaviour for test-only lanes — do not remove the floor.**
The +100 capability floor exists for a reason (FP-08: keeping strategic tasks off the cheap arm)
and must stay. What must be established, with a live log line rather than by reading the code, is
whether the floor applies to a Standard-size lane whose write-set is tests-only. If it does, that
class of lane needs to sit below the floor. If it does not, say so and leave it alone.

## Definition of done

1. A dispatch of a lane whose write-set is only `tests/` + `docs/handoff/`, with NO manual flag,
   shows `route_resolved ... arm=freepool` in the journal. Paste the line.
2. A negative control for A: name the mutation (make the write-set derivation always return
   "protected"), show the new suite goes red, revert it, show it goes green.
3. A negative control for B: name the mutation (disable the checkpoint), show the suite that
   asserts "a turn-capped round leaves a commit" goes red, revert it.
4. Suites you add are registered where CI selects them, and you show `run-all --scope changed`
   picking them up. A green test CI never runs is worth nothing.
5. Run only the suites you touched, individually, and paste each exit code. Do NOT run the full
   83-suite `run-core-offline.sh` — the machine is shared and a parallel run has already killed a
   worker on the core-offline lock today.
6. Commit in this lane before you finish.

Off limits: do not touch `main`, do not delete or weaken the capability floor, do not widen
`--protected` into anything that reduces safety on real protected paths (safety/publish/payments
keep every existing restriction).

