# Verify: review-floor / _best_effort_floor_pool not filtered by DISPATCHABLE_PLAN_ARMS

## Verdict: UPHELD

## Evidence
- `leadv2-glm-policy-resolve.py:1092` (`_dispatchable = DISPATCHABLE_PLAN_ARMS if job == "plan" else DISPATCHABLE_BUILD_ARMS`) only filters the spill path inside `resolve_glm_policy`, and `resolve_review_pool`'s `order` filter (line ~427) only applies when `job == "plan"` is passed explicitly by the caller.
- The degraded/error paths (`resolver_error` in `_main`'s except block at ~line 853, and the top-level `__main__` except at ~line 869) call `_best_effort_floor_pool(argv)` for both `--review-pool` and `--plan-pool` (diff makes both trigger it).
- `_best_effort_floor_pool` (line 735) calls `_review_floor(author, rank_table)` where `rank_table` is built straight from `extract_dispatch_ladder(text)` over ALL ladder entries with a `review_rank` field — no job/`DISPATCHABLE_PLAN_ARMS` filtering anywhere in this function.
- `plugins/leadv2/config/leadv2-routing.yaml` lists `id: haiku` with `review_rank: 1` (line ~163), i.e. haiku is a legitimate member of the review-rank ladder used by `_review_floor`.
- Therefore: a plan job that hits the resolver-error/degraded path gets its arm from `_review_floor`, which can return `haiku`, `glm`, or `kimi` (any ladder entry) — none of which are in `DISPATCHABLE_PLAN_ARMS = {"codex","sonnet","opus","fable"}`, exactly the arm PLANNER-MODELS-DECISION-01 introduced the set to exclude from planning.

VERIFY_VERDICT: upheld


DELIVERABLE_COMPLETE
# auto-marker added by SOFT_FINISH fallback
