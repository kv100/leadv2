verdict: APPROVE
next_action: review_round_2

Implemented MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 per architect design: multi-repo aggregation, terminal grace-window retention, argv-corroborated codex census, name/phase resolution.

- `render_single_lead()` rewritten in `plugins/leadv2/scripts/leadv2-status-surface.sh`.
- 6 new fixture cases (T-term×2, T-lead×2, T-multi, T-unverifiable, T-name×2) + 1 bash32 case (T7).
- All 3 required suites green: single-lead 23/23, bash32 12/12, legacy test-status-surface.sh 81/81 (9 pre-existing unrelated failures, confirmed identical before/after via diff-swap).

Full: full.md
