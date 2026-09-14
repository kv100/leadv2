# ASTRA-MUST-BE-SELECTABLE-01

Founder ruling, 2026-09-14: *«Астра точно должна быть, и запускай сразу на астра. Если астры нет,
добавить и чтобы на ней тоже запускалось всё что требует сильной модели.»*

## The measured gap

`gpt-6-astra` is a real model the account can serve — it is in `~/.codex/models_cache.json`
alongside `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, at **priority 1, above the entire 5.6
family** (sol 6, terra 7, luna 8). It is **not reachable from a dispatch today**, and neither is
sol. Measured this session, on the live dispatcher:

```text
--pin-arm codex           -> route_resolved arm=codex model=gpt-5.6-terra tier=standard reason=explicit_requested_capable
no pin, --kind plugin     -> route_resolved arm=sonnet model=sonnet tier=standard reason=cheapest_capable
--model gpt-5.6-sol       -> ERROR: unknown arg: --model      (not a top-level flag)
--arm-pool codex          -> ERROR: unknown arg: --arm-pool    (not a top-level flag)
```

So `--pin-arm` pins the **arm**, and the resolver takes that arm's standard tier. The matrix
declares three codex tiers (`leadv2-routing.yaml:315-317`: luna/volume, terra/standard,
sol/top `sizes:[heavy]`) and **no caller can select among them**. astra is not even a matrix row —
`CODEX-TIERS-COLLAPSED-ONTO-ASTRA` (2026-09-09) removed it because all three codex rows named
`gpt-6-astra` and every codex-shaped resolve collapsed onto one model whichever cell won. It has
lived since then only as the launcher's named fallback tail (`codex-task.sh` journals
`CODEX_FALLBACK_EVENT`).

**Read that decision before you touch anything** (`get_why`, or the comment block at
`leadv2-routing.yaml:294-312`). What it forbids is three rows collapsing onto one model. It does
not forbid astra existing as its own distinct, separately-named cell. Your change must not
re-create the collapse it was written to kill, and you must say in your report why it does not.

## What to build

1. **Make astra selectable by name.** Give it its own identity so a caller can ask for it and get
   it — `--pin-arm astra` must resolve to `gpt-6-astra`, not to a 5.6 tier. Decide whether that is
   a distinct `arm:` id or a tier selector threaded through the existing arm, and justify the
   choice against the collapse decision above. A distinct arm id is the shape I expect to be
   right, because the pin flag that already exists then works unchanged — but if the codebase
   disagrees with me, follow the codebase and say so.
2. **Make it win where a strong model is warranted, and only there.** The founder's words are
   «чтобы на ней тоже запускалось всё что требует сильной модели». Express that in the matrix the
   way every other row expresses it — kinds, sizes, capability — not as a branch in arbiter code.
   `sizes:[heavy]` is the existing vocabulary for "strategic/heavy only" (`SIZE_MAP` at
   `lib/leadv2-route-arbiter.sh:506` folds `strategic` into `heavy`). A row that also wins standard
   work would make astra the default for everything; that is not what was asked and it would be
   expensive.
3. **Make sol reachable too, while you are in here.** It is the same defect: a declared tier no
   caller can select. If your item-1 mechanism is general (a tier/model selector), sol comes free
   and you should show it resolving. If you chose distinct arm ids, say explicitly whether sol
   needs one and why you did or did not add it.
4. **Prove it end to end, not by reading the config.** A `--no-spawn` resolve showing
   `arm=... model=gpt-6-astra` is the acceptance artifact. Include the same probe for sol.

## Method — binding

- **A tier the account cannot serve must not be selectable.** That rule is already in the config
  comment and `test-codex-tiers-selectable.sh` already holds matrix-vs-cache consistency plus the
  tier→slug binding. Extend that suite; do not write a parallel one.
- **Negative control, run it:** make the new selector name something the cache does not serve, and
  show the dispatcher refusing at the door with a named reason — not falling back silently to
  terra or sonnet. A selector that cannot be proven to refuse an unservable model is not proven to
  select a servable one. This is the exact failure shape the collapse decision was written about.
- Report the resolve line verbatim for every claim. `route_resolved by=arbiter … model=…` is the
  evidence; the yaml diff is not.
- Name the surface of every count.

## Acceptance

1. `--pin-arm astra` (or whatever mechanism you justified) resolves live to `gpt-6-astra`, shown by
   a `--no-spawn` dispatch's own `route_resolved` line.
2. sol reachable, or an explicit statement of why it is not and what it would take.
3. astra does NOT win standard-sized work — shown by a paired resolve at standard size picking
   something else.
4. Negative control run: an unservable model name is refused at the door with a named reason.
5. `test-codex-tiers-selectable.sh` extended and green; registered so
   `tests/run-all.sh --scope changed` SELECTS it.
6. Still green: `test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`, `test-codex-drain-fit.sh`, `test-codex-lane-token-total.sh`.

## Off limits

- `router_v2.cost` — no price changes in this lane, of any kind.
- `reset_urgency`, the decision record schema, the launcher-refusal event, the judge parser.
- Hardcoding an arm preference in arbiter code. Routing intent lives in the matrix as rows; that is
  doctrine (`ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01`).
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
