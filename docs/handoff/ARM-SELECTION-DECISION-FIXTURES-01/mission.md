# ARM-SELECTION-DECISION-FIXTURES-01 — the instrument, before any policy changes

Founder order 2026-09-16: apply `docs/reference/arm-selection-proposal-2026-09-16.md` immediately.
That proposal's §7 requires, in this order: **freeze the baseline decisions first, then show the
changed outcomes with reasons.** This lane builds that instrument and freezes the baseline. It
changes **no** policy — if this lane alters a single routing decision it has failed.

Read `docs/reference/arm-selection-proposal-2026-09-16.md` (all of it) and
`docs/reference/arm-selection-logic.md` §1-§5 before starting.

## Why this exists as its own lane

Two policy lanes follow this one and both need the same yardstick: one changes
`config/leadv2-routing.yaml` (capability bands, pools, opus identity), the other changes
`scripts/lib/leadv2-route-arbiter.sh` (cost keying, scoped quota, rotation, telemetry). Without a
frozen baseline neither can prove it changed what it meant to change and nothing else. Do not let
them each invent their own fixtures.

## What to build

A hermetic decision harness: given a fixed task description and a fixed fleet state, it prints the
arbiter's decision. No live provider calls, no live quota reads, no network, no spend.

The seam already exists and is used by the current suites — drive the arbiter through
`LEADV2_ROUTE_ARBITER_ROUTING_YAML`, `LEADV2_ROUTE_ARBITER_QUOTA_LIVE`,
`LEADV2_ROUTE_ARBITER_FREEPOOL_GATE`, `LEADV2_ROUTE_ARBITER_STATE_FILE` and `ROUTE_TEST_QUOTA`,
invoked as `bash -c 'source "$0"; route_arbiter worker "$1"'`. Copy the pattern from
`docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/probe.sh`, which already does exactly this.
Run bash libraries under `bash`, never `zsh` — zsh has no `BASH_SOURCE` and the arbiter probe reads
false under it.

For each scenario the harness must record, per decision: winning arm, winning model, effort,
`fit_bucket` of every candidate, `ecost` of every candidate, the full `arm_excluded` list with
reasons, `fit_mode`, `complexity`, `req_eff`, and which comparator was decisive.

## Scenarios to freeze

The proposal's §6 lists fourteen required acceptance cases. This lane freezes a baseline for the
twelve that are decision-shaped (1-13 excluding 14, which is a documentation task already done by
the lead). Write one fixture per case, named for the case. Cases 1-5 and 9 concern admission,
fit buckets, rotation and model identity; cases 6-8 and 10-13 concern price provenance, observed
rounds, scoped quota, weekly preservation and identity through fallback.

For each: a fixture yaml + quota state, and the recorded decision. Commit the recordings as the
baseline under `docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/`.

## The one thing that decides this lane

**A baseline nobody can regenerate is not a baseline.** The harness must be re-runnable and produce
byte-identical output on an unchanged tree. Prove it: run it twice, diff the two recordings, show
the diff is empty. If any field is nondeterministic (timestamps, elapsed times, random tie-breaks),
the harness must normalise it away and the mission report must name every field it normalised and
why — a harness that hides a real nondeterminism in the decision itself would make both following
lanes lie.

## Negative control, mandatory

Change one input that MUST move a decision — for example drop the winning arm's capability by two
in the fixture yaml — re-run, and show the recorded decision changes. A harness whose output never
moves is asserting a constant. Show this both ways: the mutation moves it, reverting restores the
frozen baseline byte-for-byte.

## Explicitly NOT in scope

- Any edit to `config/leadv2-routing.yaml` or `scripts/lib/leadv2-route-arbiter.sh`. None. This lane
  reads them and drives them; it does not change them.
- Any live provider call or any real quota read.
- Deleting, relaxing or "temporarily" skipping an existing test.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/report.md
```

Baseline recordings go under `docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/` and must be
committed with `git add -f` — `.gitignore` carries `docs/handoff/*/*` with an exception only for
`*.md`.

## Acceptance

`bash plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh` exits 0, and its
output shows: twelve scenarios recorded, the twice-run diff empty, and the negative control moving
the decision and then restoring it. Report the commands and their real output in `report.md`, not a
claim that they passed.
