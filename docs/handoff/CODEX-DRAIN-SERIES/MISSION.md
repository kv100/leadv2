# CODEX-HAS-TOKENS-BUT-NO-DRAIN-SERIES-01

## Measured

Pricing needs two halves: how many tokens a task spent, and how much of the provider's window that
period drained. For codex we now have the first half and none of the second.

**Tokens — fixed today** (`d0282f6a0d13`, merge `39bf586c`): 113 of 236 codex lanes resolved to a
real token total from their own rollout files.

**Drain — absent entirely.** The fit reads `~/.claude/burn/history.db`. Its `turn_events` table
contains, by model:

```text
3031  glm-5.3
2288  claude-opus-5
 498  claude-haiku-4-5-20251001
 426  claude-sonnet-5
 254  glm-5.3-flash
 210  claude-fable-5-1
   7  <synthetic>
```

Not one `gpt-5.6-*` row. That is why the per-model fit output has no codex column at all — a fact
I read past twice before checking it.

The cause is structural: that database is written from claude-code sessions. GLM appears in it
because GLM physically runs THROUGH claude-code with a redirected base URL. Codex runs under its
own CLI and never touches that writer.

**The raw material for the missing half already exists.** The arbiter reads codex quota live on
every decision, and those readings are sitting in the lane journals with their timestamps:

```text
361 occurrences of `util_codex=<N>` across ~/.claude/leadv2-state/*/tasks/*/journal.md
```

A time series of codex window consumption that has simply never been collected into one place.

## What to build

1. **A codex drain series.** Collect the timestamped `util_codex` (and `reset_codex`) readings into
   the same shape the fitter consumes for the other providers. Decide and state whether to
   backfill from the journals, to start a forward-only sampler, or both — and say why.
   Beware the obvious trap: `util_codex` is a percentage of a window that RESETS. A reset makes the
   number jump downward; an interval spanning a reset is not a drain, it is an artifact. The
   existing fitter already drops such intervals (`dropped_reset=30` on the 5h window) — reuse that
   logic rather than reinventing it, and report how many codex intervals it drops.
2. **Then fit codex.** With tokens on one side and drain on the other, report the weight, R²,
   `max_abs_corr`, `degenerate_pairs` and kept-count — the same evidence every other fit must carry.
   Codex has three real model slugs in the matrix (`gpt-5.6-terra`, `gpt-5.6-sol`, `gpt-5.6-luna`;
   `astra` is the LAUNCHER's default alias, not a fourth model — see `leadv2-routing.yaml:290-300`,
   CODEX-TIERS-COLLAPSED-ONTO-ASTRA). If all three appear in the data, the same collinearity trap
   that defeats Anthropic applies here; follow the sibling lane's amendment — look for a PUBLISHED
   relative weight between the tiers first, and only collapse if none exists.
3. **Test the founder's standing hypothesis, by name.** He has said more than once that codex
   requests on terra looked "almost free" and flagged his own uncertainty. Until now it was
   untestable. Answer it with a number: terra's fitted weight against sonnet's and glm's, or a
   plain statement that the data cannot separate them and why.

## Method — binding

- Report R², `max_abs_corr`, `degenerate_pairs` and kept-count on every fit you quote.
- A provider whose R² stays negative gets NO price. `null` plus the number that justifies it is a
  result; an invented number is the defect this whole thread exists to remove.
- Name the surface of every count. This lane exists because a missing column in a fit output went
  unread twice.

## Acceptance

1. A codex drain series exists and its construction is described, including the reset-spanning
   interval handling with the count dropped.
2. A codex fit with its full quality evidence, or a stated, evidenced impossibility.
3. The terra question answered with a number or an explicit "cannot be separated, because …".
4. Still green: `test-codex-lane-token-total.sh`, `test-arbiter-prices-by-provider.sh`,
   `test-reset-urgency.sh`, `test-arbiter-decision-record-inputs.sh`,
   `test-launcher-refusal-event.sh`, `test-leadv2-task-judge.sh`.
5. New suites registered so `tests/run-all.sh --scope changed` SELECTS them.

## Off limits

- `~/.claude/burn/history.db`'s existing writer — do not make codex fake a claude-code session.
- Writing a codex price that the fit does not support.
- `reset_urgency`, the decision record schema, the launcher-refusal event, the judge parser.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
