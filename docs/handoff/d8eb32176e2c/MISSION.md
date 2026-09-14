# EFFORT-IS-NOT-A-FUNCTION-OF-CLASS-ALONE-01

Founder, 2026-09-14: *«там где надо архитектор иногда может надо [верхняя ступень] для задачи
класса Standard, иногда low + fable на стратегической и тд. Надо всё продумать»*.

He is right, and the current state is more degenerate than he guessed.

## Measured — today, on main, after the class tiering landed (`2a715fc3`)

Live resolves, both classes, verbatim:

```
class=Heavy      arm=codex  effort=high
class=Strategic  arm=astra  effort=high
```

Effort is attached to the tier, and **the tier's effort is the same for both**. So the class tiering
that landed this morning gave us different ARMS per class and identical EFFORT per class — which is
exactly the half the founder is now naming.

Across every journal on this machine:

```
high 696 | unknown 107 | medium 59 | max 32 | low 22
```

76% of all work runs at the top rung, and the share went UP today (685 → 696). A default that is
high because nobody chose it is a quota leak, and for Claude it is maximum token spend on three
quarters of everything.

## What to build

**Effort must depend on ROLE and class together, not on class alone.** The founder's two worked
examples, in his words: an architect prepass on a `Standard` task may deserve the top rung; a
`Strategic` task may be fine at `low` with fable. Those two cases alone falsify any pure
class→effort mapping.

Express it the way every other routing intent is expressed — as matrix rows carrying the axis, never
as an `if role ==` branch in resolver code (`ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01`).

## Vocabulary — do not invent one

The real values are **`low` / `medium` / `high` / `xhigh`**, and `max` appears in journals (32
times). **There is no `ultra`** — grepped, it does not exist anywhere in scripts or config. If you
need a name for the top rung, use the one the code already uses; if `max` and `xhigh` turn out to be
two spellings of one thing, say so, that is worth knowing on its own.

## Known limits — name them, do not re-derive or fix them

- **Codex welds effort to the tier** (`codex-task.sh:21-33`, EFFORT-RECAL 2026-07-10):
  `top → gpt-5.6-sol/high`, `standard → gpt-5.6-terra/medium`, `volume → gpt-5.6-luna/low`, and the
  comment says effort stays per tier even on fallback. So **"terra at high effort" is inexpressible**
  — asking codex for more thinking necessarily changes the model too. Report this as a limit on what
  the role axis can achieve for codex; do NOT rewrite the codex tier mapping in this lane.
- **Claude takes effort as a free parameter** and it reaches the provider —
  `claude-subsession.sh:641` appends `--effort "$EFFORT"`. So the role axis is fully expressible for
  Anthropic arms.
- **GLM has no separate knob and never will**: `DEEPTHINK-MODE-IS-NOT-WIRED-01` (2026-09-04,
  `glm-coder.sh:123-130`) — at Z.AI thinking intensity IS the effort vocabulary, glm-5.3 and
  glm-5.3-flash always reason, `thinking.type` only supports `enabled`. Do not re-open it.

## Acceptance

1. Name **where the `high` default is set** and why it is high — a line, not a guess. If nobody
   chose it, say that in those words.
2. Two live resolves of the **same class with different roles** produce **different** effort.
3. Negative control, run it: removing the role axis collapses those two back to one effort. A
   dependency you cannot demonstrate collapsing did not happen.
4. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.
5. Report the codex weld as a named limit, with counts.

## Method — binding

- Report the resolve line verbatim for every claim. Name the surface of every count.
- Any quota/journal number must be scoped to ONE repo directory — `~/.claude/leadv2-state/*/` spans
  repos that run under different account slots, and mixing them produced a wrong number for the lead
  earlier today.

## Off limits

- `capability` numbers — founder ruling 2026-09-14, load-bearing for the review rule.
- `router_v2.cost` and the price machinery — that thread is closed on measured evidence.
- The class→arm think tiering itself (`2a715fc3`) — it just landed and is verified; you are adding
  an axis beside it, not replacing it.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
