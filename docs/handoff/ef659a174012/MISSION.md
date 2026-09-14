# THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-BUCKET-01

Founder, 2026-09-14, defining what the cost machinery is actually FOR: *«понимать что условно не надо
все задачи на квоту глм или одного из кодекс аккаунтов чтобы не положить его в ноль количеством
работы»*. That is a **spread constraint**, not a price objective — and by that standard the balancer
is failing right now.

## Measured, 2026-09-14

Arm picks across real dispatches (`arbiter_pick=` in `~/.claude/leadv2-state/*/tasks/*/journal.md`):

```text
glm       229   (61% of 383)
codex      76
sonnet     54
glm-flash  14   (3.7%)
fable       6
freepool    3
sol / haiku 1 / 1
```

Live quota at the same moment (`leadv2-quota-live.sh json`):

```text
glm    status=ok  window=weekly  pct=83  hours_to_reset=36.8
codex  status=ok  (primary window; util_codex=17 in the arbiter's own decision line)
```

**Six picks in ten go to the bucket that is 83% burned with 36.8h to refill, while a capable
neighbour sits near 17%.** That is precisely the failure the founder named.

Second measured waste, on the same bucket: **glm-flash costs 0.33 of glm and drains the same
meter** — the only price in this system with a defensible origin (Z.AI's published credit-weight
ratio, `leadv2-routing.yaml:178`, founder ruling q-bba84179). It is chosen **3.7%** of the time.
Moving capable work from glm to glm-flash stretches the same quota roughly threefold and requires
no new measurement at all.

## Do NOT assume the cause

The arbiter already has the inputs: `headroom_weight`, `reset_urgency`, and live `util_*` per
provider. So the question is not "add balancing" — it is **why the balancing it already has did not
prevent this**. Establish that with evidence before changing a line. Candidates, not a checklist:

- Was headroom consulted at all on those 229 picks, or did capability+price settle it first?
- All providers price at 1.0 today except glm-flash (`codex: null` and `anthropic: null` both fall
  through to `_COST_MEDIAN` = 1.0). If price ties everywhere, what actually breaks the tie, and is
  that tiebreak headroom-aware or arbitrary (row order, capability, first match)?
- `util_codex` was `unknown_capped` for ~12h on 2026-09-14 because the codex quota reader was
  returning `refresh http 401`, and an unknown arm is DEMOTED by design
  (`lib/leadv2-route-arbiter.sh:1110-1124`). How much of codex's low share is that outage rather
  than a balancing defect? Separate the two with dates — the reader recovered at 08:41Z.
- glm-flash is `protected: false`, so it is excluded from tasks writing production code on
  safety/protected paths. How much of its 3.7% is that rule correctly firing versus the balancer
  never considering it? A number, not an impression.

## What to build

1. **State the cause with a number**, per the above.
2. **Make the spread constraint real**, in the matrix and the existing headroom terms — not as a new
   hardcoded preference for any arm. Doctrine: routing intent lives in rows, never in arbiter
   branches (`ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01`), and no arm is ever hardcoded out
   (`ARBITER-DECIDES-01`). The target behaviour is: as a provider's binding window approaches
   exhaustion, capable work migrates to providers with headroom — and it must be visible in the
   decision line WHY it migrated.
3. **Raise glm-flash's share where it is genuinely capable**, by the same mechanism — its published
   0.33 should already be winning those cells. If it is not winning them, that is a finding about
   how the price term combines with capability, and it is probably the same defect as item 1.
4. **Do not let the fix drain the other bucket instead.** Anthropic is a shared bucket (lead,
   fable's scoped ceiling, sonnet, opus, haiku all draw from it) — pushing overflow there
   mechanically is how we get the same incident with a different name.

## Method — binding

- **Negative control, run it:** construct a quota state where one provider is near-exhausted and
  show the pick MOVING; then the same task with that provider healthy and show it staying. A
  balancing change you cannot demonstrate flipping in both directions did not happen.
- Every claim carries its resolve line (`route_resolved by=arbiter … util_… reset_…`) verbatim.
- Separate the codex-reader outage window from the balancing question by date, explicitly.
- Name the surface of every count.

## Acceptance

1. The 61%-on-glm concentration explained with a number, with the reader-outage contribution
   separated out.
2. Spread behaviour demonstrated by paired resolves that flip both ways.
3. glm-flash's low share explained (correct `protected:false` exclusions vs. never considered),
   with the counts, and raised where the exclusion does not apply.
4. No arm hardcoded; the change lives in matrix rows and existing headroom terms.
5. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.
6. Still green: `test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`, `test-codex-drain-fit.sh`, `test-codex-lane-token-total.sh`,
   `test-codex-tiers-selectable.sh` (this one is PRE-EXISTING RED, 3 FAIL / 6 PASS, measured
   identically on untouched main — do not be alarmed by it and do not fix it here; just do not
   make it worse).

## Off limits

- Fitting a price. That thread is closed: four attempts, negative R² in every shape, cause
  diagnosed. Use the published glm-flash ratio and the live headroom; invent nothing.
- Writing a value into `router_v2.cost`.
- Hardcoding an arm preference or exclusion in arbiter code.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.

## AMENDMENT (2026-09-14): a named tie-break candidate, cheap to confirm or kill

While answering a founder question about reviewer strength I measured something that bears directly
on your item 1. **Seven of twelve matrix rows share `capability: 4`** — glm, codex/terra, codex/sol,
sol, sonnet, opus, fable — and every provider except glm-flash prices at 1.0 today. So on a large
class of tasks BOTH discriminators tie simultaneously.

And glm is the **first** capability-4 row in the matrix, in file order.

That yields a specific, falsifiable hypothesis for the 61% concentration: when price ties at 1.0 and
capability ties at 4, the tie may be broken by matrix row order rather than by headroom. Confirm or
kill it cheaply — reorder the rows in a fixture and see whether the pick follows the order. If it
does, that is the cause, and it is also why headroom never got a vote. If it does not, say what
actually broke the tie and move on.

Treat this as a lead, not a finding: I did not test it.
