verdict: APPROVE
next_action: continue

Per-provider fit built and run; collinearity dropped (max_abs_corr 0.934→0.670 at 5h, 0.913→0.659 at 7d) but R² stayed negative for every provider, so `router_v2.cost` is left unchanged (anthropic/codex stay `null`) — no defensible price exists yet.

- `leadv2-drain-weights.py` gained `--group provider|model` (default `provider`): collapses claude-haiku/opus/sonnet→anthropic, glm-5.3→glm (glm-flash stays its own bucket, per GLM-EFFICIENCY-01), drops the zero-token `<synthetic>` rows.
- codex: zero rows in turn_events ever (verified live against `~/.claude/burn/history.db`) — not "doesn't fit", there is no data for it in this corpus at all.
- Negative control included (wrongly folding glm-flash into glm): R² only got worse (-0.2988→-0.2990) and glm-flash's one non-zero weight was erased.
- All 6 required regression suites green (68 assertions total). No new test-*.sh suite added (left alone — see full.md).

Full: developer.full.md
