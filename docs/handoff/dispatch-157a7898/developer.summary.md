verdict: APPROVE
next_action: review_round_2

Un-collapsed the codex tier table: top/standard/volume now resolve to sol/terra/luna (not all-astra), with named fallback + journaling; registry made them addressable. New offline suite, 17/17 green, both negative controls have teeth.

- codex-task.sh: single `_tier_model_effort()` (was duplicated) resolves sol/terra/luna per tier, falls back down the ladder to astra, journals every substitution via `CODEX_FALLBACK_EVENT`. Header comment fixed to match.
- leadv2-launch-registry.py: added `CODEX_MODEL_TIER_TUPLES`, widened `check()`/`lookup()` for codex, `--effort` now flows independently of `--tier` for kind=="code".
- Live-verified: real `codex-task.sh task --wait` runs at all 3 tiers resolved sol/terra/luna and reached `completed`.

Full: full.md
