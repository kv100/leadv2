# QUOTA-PROBE-FAILS-CLOSED-01 — STALE PREMISE, do not dispatch

Premise-checked by the lead on 2026-09-06 against live code. **The defect this brief describes is
already fixed.** Dispatching it would burn a lane re-fixing solved code.

## What the brief claims

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:102` —

    if x.get('status')!='ok': return (100.0, True)

i.e. a probe that could not be read is rendered as a 100%-exhausted arm, so a broken *measurer*
looks identical to a burnt *quota* and the arm is excluded from selection.

## What the code does today

The line survives in spirit at `:311`, now returning `dict(empty, pct=100.0, unknown=True)` — but
`unknown` is no longer inert. `capped()` opens with:

    if unk.get(provider): return False

An unknown arm is therefore **not capped**: it stays in the candidate set and is demoted on
effective cost (`UNKNOWN_PROBE_PENALTY`) instead of being excluded. The fix is
ARBITER-REMEMBERS-FAILURES-01 edit B (founder, 2026-09-05), and its own comment records the damage
that motivated it: `util_codex=unknown_capped` in 122 of 143 decisions, codex out for a day, six
lanes killed by `reason=all_arms_capped` when what actually failed was the instrument.

Guarded by `test-route-arbiter.sh` and `test-route-arbiter-failure-memory.sh`.

## The one residual, filed separately

`_waited` is still computed from `over_ceiling(p)`, not `capped(p)`:

    _waited=[p for p in ('glm','codex','claude') if over_ceiling(p) and near_reset_wait(p)]

`over_ceiling` compares `u[provider] >= ceiling`, and an unknown probe carries `pct=100.0`, so an
unknown arm whose window happens to reset soon is reported as `wait_applied=<arm>` — "waiting for
quota to refresh" — when nothing was measured at all. This does not change which arm is chosen
(`capped()` already excludes it from exclusion); it makes the decision line say something untrue,
which is how three wrong verdicts started on 2026-09-05. Backlog row:
`WAIT-APPLIED-CAN-NAME-AN-UNMEASURED-ARM-01`.
