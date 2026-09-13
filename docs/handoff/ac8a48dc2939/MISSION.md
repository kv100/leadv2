# ac8a48dc2939 + ca28025443a6 — make the quota telemetry able to price an arm

Two rows, one lane, because they touch the same files and the second is
meaningless without the first. Do **not** split them.

- `ac8a48dc2939` ACCOUNT-TRUTH-ACTIVE-IS-NOT-THE-METERED-ONE-01
- `ca28025443a6` QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01

This is the **foundation** under the arbiter/pricing work the founder ordered.
Nothing downstream can be measured until this lands. Treat it as strategic: the
full phase ladder, architect divergence included.

## The negative result that created this lane

2026-09-13, `scratchpad/drain-weights.py`: a dependency-free non-negative least
squares of Δquota-pct on per-model token counts, intervals with a window reset
dropped. Result:

```
5h window: kept=18 intervals, ALL weights 0.0000, R² = -0.743
7d window: kept=10, threshold 12 -> NOT ENOUGH DATA
```

R² below zero means the fit is worse than the mean — the weights are noise.
**The conclusion is not "the method is wrong". The conclusion is that the data
cannot carry the question yet.** Three measured holes:

1. **`rate_limit_history`, active account: 124 of 124 snapshots have
   `five_hour_pct` and `seven_day_pct` NULL.** The only account with real
   percentages (`eb6c5b97`) is flagged `active=false`.
2. **`turn_events` has no account key.** Columns are
   `id session_id ts cc cr input output model tools_json`. Tokens cannot be
   attributed to the window they burned, so 201 intervals were discarded as
   idle while real spend was happening.
3. **`cost_actual_recorded.tokens` is empty in all 32 rows.** Lane-worker spend
   is not recorded at all.

## The account-truth half (`ac8a48dc2939`)

Measured with `leadv2-quota-read.py anthropic --no-cache`, three keychain
records:

| record | plan | http | pct | active |
|---|---|---|---|---|
| `default`   | max 20x  | 401 | all null | **true** |
| `5a3c2328`  | team 5x  | 401 | all null | false |
| `eb6c5b97`  | max 20x  | 200 | 5h=1%, 7d=9% | false |

The session runs under `CLAUDE_CONFIG_DIR=~/.claude`, and
`sha256_8("~/.claude") = eb6c5b97`. So the metered account IS ours, and the
reader calls a different one active. The statusline number the founder sees
(«cc* 20x 91%») comes from an account marked `active=false`.

**Do not treat the 401s as dead credentials.** Repo memory
`reference_ccswitch_collapses_the_two_leadv2_slots` (measured 2026-09-07): a 401
from the usage endpoint never proves a token is dead; a team account 401s by
nature (`TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01`); the bare `default` record is
live and `ccswitch.sh` reads and writes it. **This is an accounting hole, not an
auth hole.** A re-login does not fix it and is actively dangerous:
`ccswitch --switch` collapses both leadv2 slots into one account. The lane must
not run any login, any `ccswitch --switch`, or any credential write.

Required:
- `active` is derived from `CLAUDE_CONFIG_DIR`, not from a stored flag.
- The team window is either parsed, or explicitly labelled unmetered — never
  silently null.
- The statusline shows the account the session is actually running under.
  Remember `remaining_pct` semantics: `~/.claude/burn/quota-fragment.sh` does
  `pct = d.get("remaining_pct")` — those numbers are REMAINING, not consumed.
  Whatever you change must not flip that meaning.

## The telemetry half (`ca28025443a6`)

Close the three holes so the regression becomes answerable:

1. Percentages must be recorded for the account the session runs under.
2. `turn_events` gains an account key, written at the point the turn is
   recorded — not backfilled by a guess.
3. `cost_actual_recorded` records real token counts for lane workers.

Then **re-run `drain-weights.py` and report the new R² and interval count.**
That number is this lane's result. If it is still below ~0.5, say so plainly —
a second honest negative is a real finding and is worth more than a fitted
number nobody can defend.

## What you may NOT do

- Do not invent prices. The current matrix (`glm-flash 0.33, glm 1, freepool 1,
  haiku 2, codex 3/4/7, sonnet 5, fable 8, opus 9`) has exactly one derived
  number — `glm-flash 0.33`, a measured Z.AI credit-weight ratio — and the
  commit that introduced the matrix (`d6179dff`) has an empty body. Do not add a
  ninth authored number to the pile. Your job is to make derivation *possible*.
- Do not change `leadv2-routing.yaml` capability or cost values in this lane.
  That is the next lane's work and it is gated on your R².
- Facts that matter and are easy to get wrong: **quota is metered per PROVIDER,
  not per model** (`leadv2-quota-read.py` has three buckets — glm, codex,
  anthropic; only glm has per-model attribution via `LEADV2_QUOTA_GLM_MODELS`).
  **Fable has TWO limits** — the shared `weekly_all` AND a `weekly_scoped` one
  scoped to Fable, in addition to, not instead of.

## Acceptance

Both rows carry a probe. Each probe must ship with **both readings** — red on
the live tree now, green on a scratch copy where the work is done — the same
rule the triage lanes run under (`docs/handoff/TRIAGE-BATCH-D1/ADDENDUM-2.md`).

Suites, rc 0:
- `~/Projects/leadv2/plugins/leadv2/scripts/tests/test-account-truth-active-is-metered.sh`
  — must contain a negative control: a fixture where the stored `active` flag
  and `CLAUDE_CONFIG_DIR` disagree, and the reader must follow the env.
- `~/Projects/leadv2/plugins/leadv2/scripts/tests/test-quota-telemetry-can-price-an-arm.sh`
  — must assert on a written row, not on a code path being reachable.

Plus, in the report:

| item | value |
|---|---|
| `drain-weights.py` 5h: kept intervals, R², before → after | |
| `drain-weights.py` 7d: kept intervals, R², before → after | |
| rows in `rate_limit_history` with non-null pct for the live account, before → after | |
| `turn_events` rows carrying an account key | |
| `cost_actual_recorded` rows with non-empty tokens | |
| both suites rc | |
| `run-all.sh --scope changed` selection proof | |
| second-model review verdict | |
| commit sha in `~/Projects/leadv2` | |

## Scope

Write set is executable code, so **e2e scoped to changed**, not the full suite.
Commit inside `~/Projects/leadv2` — an edit left in a worktree is live but not
durable, and the next checkout loses it.
