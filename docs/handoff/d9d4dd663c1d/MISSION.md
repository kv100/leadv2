# THE-THINK-MODEL-NEVER-LEAVES-ANTHROPIC-01

Founder, 2026-09-14: *«думать надо соответствующей моделью… если задача heavy то думать может и
opus/codex terra а если strategic то astra/fable/sol — я думал что у нас вот так будет. А то
получается что думает часто слишком дорогая рука… сегодня идёт сильный перекос в сторону того что
всё на антропик и фейбл»*.

He is right, and the measurement is more absolute than he guessed.

## Measured, 2026-09-14 — every `think_model_resolved` line ever written

```text
375 resolutions total
    228  arm=fable       (Anthropic)
    147  arm=opus        (Anthropic)
      0  codex / glm / anything else

375  role=default
375  class=default
```

**Two facts, both total, no exceptions in the corpus:**

1. **The think model has never once left Anthropic.** Every one of 375 resolutions picked fable or
   opus. codex, glm and the rest have never been considered — and the think model runs on
   essentially every lane, which makes it the single largest systematic pull on the Anthropic
   bucket in the system.
2. **The task class has never reached it.** All 375 carry `class=default` and `role=default`. The
   seam exists in the resolver (`THINK_ROLE` / `THINK_CLASS`, `leadv2-router.sh`), so the tiering
   the founder assumed was in place has not been switched off — **it has never fired once.**

Two dated regimes, for context, so nobody re-diagnoses the old one:

```text
2026-09-11  env_pin/fable 163, env_pin/opus 71    — pinned by env, arbiter not consulted
2026-09-14  arbiter/fable 46, arbiter/opus 42,  fail_open/opus 30, fail_open/fable 15
```

The env pin is gone — that was fixed between those dates and is not what you are here for. But note
the third number: **45 of 133 resolutions today (34%) came out of a `fail_open` path**, not an
arbiter verdict. A third of "thinking" decisions are made by a fallback.

## What to build

1. **Feed the task class to the think resolver, and make the tier depend on it.** The founder's
   shape, in his words: heavy → opus / codex-terra; strategic → astra / fable / sol. Express this
   the way every other routing intent is expressed — as matrix rows with `kinds`/`sizes`, never as
   an `if class==` branch in resolver code (`ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01`). Find
   where `THINK_CLASS` should be populated from and why it currently is not; the seam existing but
   never being fed is the actual defect, and it may have one cause you can name.
2. **Let the think model leave Anthropic.** Nothing in the founder's shape says thinking is an
   Anthropic activity — `codex-terra` is in his heavy tier explicitly. If some constraint currently
   confines the candidate set to Anthropic arms, name it with the line that imposes it, and say
   whether it is deliberate. Do not assume it is a bug; do not assume it is intended.
3. **Cut the 34% fail_open rate, or explain it.** A third of think resolutions bypassing the
   arbiter verdict means any statement about "the arbiter chooses the think model" is only true for
   two thirds of cases. Name the reasons behind `fail_open_env_candidate_stakes_or_data_missing`
   (39) and `fail_open_last_resort_stakes_or_data_missing` (6) with counts — the reason strings say
   "stakes or data missing", so find out WHICH, and whether the missing input is the same one
   item 1 is about.

## Method — binding

- **Negative control, run it:** a heavy task and a strategic task must resolve to DIFFERENT think
  tiers, demonstrated by two live `--no-spawn` resolves; then show that removing your class
  plumbing collapses them back to one. A tiering you cannot demonstrate collapsing did not happen.
- Report the resolve line verbatim for every claim.
- Do not change `capability` numbers. The current order (6 astra/fable, 5 codex-sol/sol/opus,
  4 glm/terra/sonnet, 3 luna, 2 haiku/glm-flash/freepool) is a founder ruling of 2026-09-14 and it
  is load-bearing for the review rule "reviewer must be a different vendor OR strictly stronger".
  If the tiering you build needs a different axis than `capability`, add the axis; do not renumber
  this one.
- Name the surface of every count.

## Acceptance

1. `THINK_CLASS` populated from the real task class, with the cause of its never having been fed
   named.
2. Heavy and strategic resolve to different think tiers, shown by two live resolves; plus the
   collapse control.
3. The think candidate set is no longer Anthropic-only, or the constraint that confines it is named
   with its line and justified.
4. The `fail_open` share reported by reason with counts, and reduced or explained.
5. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.
6. Still green: `test-headroom-period-invariant.sh`, `test-quota-unknown-surfaces.sh`,
   `test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`, `test-codex-drain-fit.sh`, `test-codex-lane-token-total.sh`.

## Off limits

- Renumbering `capability`.
- `router_v2.cost` and the price machinery — that thread is closed.
- The headroom terms (`bfab5aac` just made them period-invariant; a sibling row owns the remaining
  glm-flash-share question).
- The review gate and phase ordering — a sibling lane (`7b7fb938bb30`) owns those.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
