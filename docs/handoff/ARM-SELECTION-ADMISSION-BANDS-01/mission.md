# ARM-SELECTION-ADMISSION-BANDS-01 — §4.1 of the founder's proposal, config only

Founder order 2026-09-16: apply `docs/reference/arm-selection-proposal-2026-09-16.md` immediately.
This lane implements **§4.1 Admission and pool membership** and nothing else. Read the whole
proposal first, plus `docs/reference/arm-selection-logic.md` §1-§5.

Your only write into live behaviour is `plugins/leadv2/config/leadv2-routing.yaml`.

## The mechanism you are changing, stated correctly

Do not repeat the lead's two retracted errors — both are corrected in `arm-selection-logic.md` §5
and the reasons are in the proposal's §2:

- The `+100` `complexity_penalty` is **dead code on the live path**.
  `leadv2-route-arbiter.sh:1720` sets `complexity_penalty_rules = []` whenever `FIT_MODE == 'on'`,
  and it is on (`:1697`, from `capability_fit.enabled`). Do not "fix" the penalty, do not remove the
  tags to escape it, do not cite it as a cause.
- `price_ratio` in the journals is **a loser label, not a refusal** (`:2099-2104` assigns it to every
  arm that survived every gate and merely did not win). Do not treat its count as an exclusion count.

What actually demotes glm-flash is the fit bucket: `ok.sort(key=_fit_key)` at `:2066`, where the
bucket is roughly `ceil(required_capability - capability - slack)`. `capability: 2` puts flash one
bucket down on standard work and two down on complex. That integer is the lever.

## What to change

1. **Provisional ordinary-engineering band 4** for glm-flash, alongside glm, sonnet and codex/terra.
   The proposal is explicit about what this is and is not: *"a policy correction to coarse
   eligibility, NOT a derived benchmark number or a statement of equal quality."* Say exactly that
   in the yaml comment you leave behind. Do not invent a benchmark citation.
2. **Leave codex/luna at 3 and haiku at 2.** The proposal forbids equating flash with
   untrusted/freepool behaviour, and equally forbids promoting luna/haiku on this lane's evidence.
3. **Preserve every founder-approved flash declaration**: `kinds`, `sizes`, `review`,
   `protected: true`, and the ladder entry `when: [all]` with no `untrusted:`. These came from
   `GLM-FLASH-DOES-ANY-WORK-01` (founder, 2026-09-10). Touching them is out of scope and would be a
   rollback of a founder decision.
4. **No name-based ban on complex work.** Do not add one, and do not preserve one by another name.
5. **Recon eligibility** for flash and luna where those transports genuinely support read-only
   execution. Today recon is freepool/haiku-only, which keeps the intended cheap candidates out of
   the very role they suit best. If a transport cannot do read-only execution, say so in the report
   and leave it out — do not grant eligibility you cannot justify.
6. **Routine review pools** may include sonnet, glm, terra and flash. **Do not weaken any existing
   stronger-review gate.** Where policy requires a stronger reviewer today, it still does after this
   lane. An economics change must not silently become a review-quality change; if you find yourself
   removing a constraint to make a pool work, stop and report it instead.
7. **Keep the opus build exclusion** (`kinds` without `code`). Removing it is a separate product
   decision and is not needed to promote flash.
8. **Model identity**: `:364` declares `model: opus`, which is an alias. Resolve it to the actual
   Opus 5 model id. If 4.8 is retained anywhere, it needs its own explicit versioned route and a
   recorded exception reason. A failed Opus 5 launch must never silently fall back to 4.8.
9. **Fix the lying comment at `:251`.** It states that glm-flash and freepool "remain
   `protected: false`" and are `untrusted: true` in the ladder. Both halves are false in the live
   file: the matrix row is `protected: true` and `untrusted:` was removed. The comment survived the
   change it describes. Correct it or delete it — do not leave it.

## Acceptance — against the frozen baseline

Lane `ARM-SELECTION-DECISION-FIXTURES-01` freezes the pre-change decisions and provides
`plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh`. If it has not landed yet,
say so in the report and build your own minimal fixture rather than blocking — but reconcile against
it once it lands.

From the proposal's §6, the cases this lane owns:

1. A standard, concrete implementation task: flash is admitted and **can** win against glm under the
   documented cheaper-credit conditions. Show the fit buckets and the decisive comparator, not just
   the winner.
2. The same task with flash exhausted, cooling or reserved: an eligible alternative wins, with no
   loop and no forced quota bypass.
3. A complex, high-risk task: a suitable strong route still wins, and every mandatory risk/review
   gate is still intact.
4. `FIT_MODE=on`: the legacy `+100` is absent from the decision, and `FIT_MODE=off` behaviour is
   stated explicitly. Report the winning fit bucket and the actual decisive comparator.
9. The `opus` route resolves to a real Opus 5; any 4.8 exception is recorded with its reason and its
   availability checked; no silent alias downgrade.

**Each case needs its negative control.** For case 1 in particular: show flash winning under the
cheap-credit condition AND show it correctly losing when the task genuinely needs more capability —
a change that makes flash win everything is not the requested change, it is a different bug.

## Explicitly NOT in scope

- `scripts/lib/leadv2-route-arbiter.sh` — a sibling lane owns it. Do not edit it.
- Price numbers and cost provenance (§4.2), quota semantics (§4.3), rotation (§4.4), telemetry
  vocabulary (§5). All belong to the sibling lane.
- Any orchestration training, bandit or automatic policy learning. The founder ruled these out.

## Write set — FILES, never directories

```
plugins/leadv2/config/leadv2-routing.yaml
plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh
docs/handoff/ARM-SELECTION-ADMISSION-BANDS-01/report.md
```

## Before you finish

Run the suites that guard the FILE you changed, not only the ones your change targets:
`test-leadv2-routing-config.sh` and every suite whose name mentions routing, arbiter, balancer or
effort. Report each by name with its exit code. A suite that was red before your change must be
shown red before, not silently inherited.
