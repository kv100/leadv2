# ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

Founder decision 2026-09-17: port leadv3's routing **policy** into the leadv2 arbiter. Not its code
— leadv3 is a separate 109-line module with a different shape. The policy is three properties.

## What is wrong today, measured

Lane `536aa904` was a plugin-hook fix. The arbiter picked **fable** as reviewer
(`route_resolved by=arbiter role=reviewer arm=fable reason=cheapest_capable`), the most capable arm
on the board, for a task that did not need it.

It did **not** pick fable because fable is cheap. It picked it because **nothing distinguishes the
Anthropic arms by price**: `router_v2.observed_cost.cost` is keyed by *provider*, and the entry is

```yaml
anthropic: null   # UNPRICED
```

so haiku, sonnet, opus and fable all fall through to the same median fallback. With price tied, the
only discriminator left is `capability`, and `capability` sorts **upward** — fable 6 beats opus 5
beats sonnet 4. `reason=cheapest_capable` is therefore a misnomer today: on the Anthropic side it is
*most-capable-at-a-guessed-price*.

Consequence the founder named: the most expensive model reviews the simplest diffs, and it drains
the shared weekly Anthropic window while doing it — a cost the arbiter cannot see and, per
`PRICE-THE-ARM-PER-PROVIDER-01` (founder ruling 2026-09-13, collinearity R² −0.32 / −0.73), cannot
be taught by per-model pricing.

## What to build — three properties, in this order

**1. A capability floor that comes from the TASK.** The arbiter already accepts `min_capability` as
a caller constraint (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:536`, enforced `:652-656`)
and already has `router_v2.capability_fit.cap_default`. What is missing is that ordinary callers do
not set it per task, so the default governs everything. Give the floor a per-task source —
task class, `protected_path`, `kind`, risk — and make it explicit in the decision line. leadv3's
name for this is `quality_floor`; use whichever name fits this codebase, but it must be **declared,
not inferred from the winner**.

**2. Smallest adequate wins, not most capable.** Among arms that clear the floor at equal cost, the
winner must be the one with the **least excess capability**. leadv3's sort key is
`adequacy = max(0, score − floor) + max(0, effort − min_effort) * 0.01`, ascending, after eligibility
and capacity. Port the ordering, not the literal formula.

The two properties must hold together, and they are what the controls prove:

- a task with a **low** floor gets a small arm (sonnet/haiku), never fable;
- a task with a **high** floor (`protected_path=1`, safety, adversarial review) still gets fable or
  astra — raising the floor must still reach the top of the ladder. **A change that makes hard work
  cheap is a worse bug than the one being fixed.**

**3. `astra` and `sol` must be reachable.** They exist in `capability_matrix` (capability 6 and 5)
but `router.dispatch_ladder` contains only `glm glm-flash kimi codex sonnet freepool haiku opus
fable`. The auction walks the ladder, so those two rows can never be selected — they are live
config that no code path can reach. Add them with the `when:` guard their sizes/think_tiers imply.
Do not widen anything else while you are in that list.

## Do not fix, but do report

`router_v2.cost` keys the Anthropic entry as `anthropic:` while `capability_matrix` rows carry
`provider: claude` (see the note at `leadv2-route-arbiter.sh:596`). If those two strings do not
resolve to each other, a real price written into that entry would be **silently ignored** and the
median fallback would keep governing. Establish which it is and state it in the report with the
evidence. Do not "fix" it by writing a price — the provider is honestly unpriced and a guess is
worse than a named null.

## Off limits

- Do **not** touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — another lane holds it. Your
  subject is `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` and
  `plugins/leadv2/config/leadv2-routing.yaml`.
- **The lead's own base model stays Opus** (founder, 2026-09-17). `LEADV2_MAIN_MODEL=opus`,
  `main-model.yaml main_model: opus`. The smallest-adequate rule governs *dispatched* arms —
  workers, reviewers, judges, planners. It must not reach the lead's own model and must not turn the
  lead into a cheaper arm under any floor. If your change can affect the lead's resolution at all,
  that is a defect in the change, and the report must show the lead resolving to opus before and
  after.
- No arm may be excluded by a hardcoded name. The floor decides; a hand-kept list is the anti-pattern
  this repo already banned.
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- The fail-CLOSED behaviour on safety/protected paths must survive unchanged.

## Install caveat — read before verifying

A fix to this library does not take effect from a real copy: the plugin is reached through a
symlink, and an arbiter lib installed as a real file was measured still returning rc=65. Verify the
live path, not your worktree copy, before believing a probe.

## Controls

Three independent claims → **three** negative controls, each RUN, all outputs pasted:

1. low floor → small arm: revert the ordering and confirm fable comes back;
2. high floor → top arm still reachable: mutate the floor plumbing and confirm the protected case
   stops reaching fable/astra (this is the control that catches the dangerous direction);
3. `astra`/`sol` selectable: remove them from the ladder again and confirm they become unreachable.

Apply each mutation inside the function body **in the lane worktree**, never a scratch copy. Assert
the mutation target string is present before running.

## Deliverable

`docs/handoff/ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01/report.md` — the floor's per-task
source and where it is declared, the new ordering with a before/after table of which arm wins for
(simple review, protected review, safety, heavy build), the verdict on the `anthropic` vs `claude`
key with its evidence, three controls with pasted output, and the suite that now guards
`leadv2-route-arbiter.sh` by name with how CI selects it on a change to that file.
