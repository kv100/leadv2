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

## AMENDMENT (2026-09-14): the constraint is FOUND — do not spend a round re-deriving it

Item 2 asked you to name the line that confines the think model to Anthropic. I found it while
answering a founder question; take it as given and go straight to the decision.

**`plugins/leadv2/config/model-capability.yaml:34`, contract `FABLE-THINK-TIER-01`:**

```yaml
fable:
  role: think            # FABLE-THINK-TIER-01: default arm for every thinking role
  fallback: opus
```

and the header block at `:22-28` states the contract in full: *"model-capability.yaml is now READ by
one consumer — leadv2-router.sh think_model(), which routes every THINKING role to fable with opus
as the fallback."* The fable row may carry `unavailable: true`, in which case `think_model()`
returns opus.

So the two-arm outcome (fable 228 / opus 147 / nothing else, across all 375 resolutions) is not an
accident and not a bug — it is that contract doing exactly what it says. **It is deliberate, and it
is the thing the founder is now overriding.** Your job is to replace a fixed default+fallback pair
with class-dependent tiering, not to hunt for a defect.

## AMENDMENT: GLM is a legitimate think arm, and needs nothing wired

Founder: *«думающая модель может быть глм… у глм есть deepthinking mode и он крутой»*. He is right
that it qualifies, and there is nothing to enable:

`DEEPTHINK-MODE-IS-NOT-WIRED-01` (2026-09-04, `glm-coder.sh:123-130`) established deliberately that
there is **no `GLM_THINK` flag**, because at Z.AI thinking intensity IS the effort vocabulary —
glm-5.3 and glm-5.3-flash **always reason**, `thinking.type` only supports `enabled`, and it
collapses into effort. So GLM already thinks on every call. Adding a second flag was rejected then
and stays rejected; putting GLM in the think candidate set costs nothing and unlocks the cheapest
reasoning arm we have. Do not re-open the deepthink flag question — read that report first if
tempted.

## AMENDMENT: effort — what is real, and the one thing worth changing

Founder: *«у кодекс и клода есть эффорт и он реально влияет на аутпут и кол-во токенов»*. Measured,
so you do not have to:

```text
effort across all journals:  high 685 | unknown 107 | medium 56 | max 32 | low 22
```

Effort is NOT decoration — it reaches the provider: `claude-subsession.sh:641` appends
`--effort "$EFFORT"` to the Claude args. But note how differently the two providers treat it:

- **Claude**: effort is a free parameter, passed through per call.
- **Codex**: effort is WELDED TO THE TIER (`codex-task.sh:21-33`, EFFORT-RECAL 2026-07-10):
  `top -> gpt-5.6-sol/high`, `standard -> gpt-5.6-terra/medium`, `volume -> gpt-5.6-luna/low`, and
  the comment says effort stays per tier even on fallback. So "terra at high effort" is currently
  **inexpressible** — asking for more thinking on codex necessarily changes the model too.

That is the founder's *«heavy задачи тоже не все одинаковые»* in mechanical terms, and it is a real
limit worth naming in your report.

**What is worth doing, and what is over-engineering.** He asked directly whether this is
over-complication. Treat the cheap half as in scope and the expensive half as explicitly NOT:

- IN SCOPE: `effort=high` is 685 of 902 — 76%, plus 107 `unknown`. The default sits at the
  expensive end, and for Claude that is maximum token spend on three quarters of all work. Report
  what the default is, where it is set, and what a lower default would cost in quality terms that
  you can actually evidence. A default that is high because nobody chose it is a quota leak.
- OUT OF SCOPE: building a per-task effort inference model. Do not. If the class-based tiering of
  item 1 carries an effort with each tier, that is enough granularity; anything finer needs
  evidence that it changes outcomes, and we do not have that evidence today.

## AMENDMENT (founder correction, 2026-09-14): the constraint was INVERTED, and he never asked for it

*«Бля я точно не мог сказать что "думать" только на фейбл или опус. А вот то что фейбл только думает
а не пишет код я такое мог сказать. Думать могут и глм и кодекс и клод.»*

This is the key sentence in the whole lane, so read it twice. The founder's rule was a constraint on
**fable** — *fable thinks, fable does not write code*. What landed in the config is a constraint on
**thinking** — *thinking's arm is fable*. Those are not the same statement, and the second does not
follow from the first: "fable only thinks" says nothing about who else may think.

The implication got inverted somewhere between the ruling and `FABLE-THINK-TIER-01`
(`model-capability.yaml:34`, implemented from a row dispatched 2026-09-01, `dispatch-b94c3b1c`).
The inverted form is what produced 375 of 375 think resolutions landing on exactly two Anthropic
arms, and it is the whole of the founder's «перекос на антропик и фейбл».

**The rule to implement, in his words, both halves:**

1. **Thinking is open to glm, codex and claude alike.** No provider owns it. The candidate set for a
   thinking role is chosen by class and by the normal arbiter terms — capability, headroom,
   quota — exactly like any other role. GLM is explicitly included and needs nothing wired
   (see the deepthink amendment above).
2. **fable thinks and does not write code.** That half stands and is already true in the matrix —
   fable's `kinds:` carry `plan, audit, review` and no `code`. Do not weaken it.

Note what this does NOT authorise: removing fable from the think candidate set. It stays a
candidate, on merit, under whatever tier its capability (6) and the task's class justify. The defect
is that it was the ONLY candidate, not that it was a candidate.

**Carry this forward as a finding, not just a fix.** A rule stated as a constraint on an ARM was
implemented as a constraint on a ROLE, and nothing in 375 resolutions made the inversion visible —
every line looked like a normal resolution. Say in your report what, if anything, would have caught
it earlier; that is worth more to us than the config diff.
