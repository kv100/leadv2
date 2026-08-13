# Verify: resolve_review_pool `elif rank_table:` vs new `(None, True)` case

Finding: [High/correctness] `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:527`
— `resolve_review_pool`'s `elif rank_table:` was not updated for the new
`_review_floor(ok=True, arm=None)` post-filter-empty case, so it misclassifies as
`pool_floor_table_degenerate` instead of `all_review_arms_unavailable`.

## Evidence (docs/handoff/PLAN-FOLLOWUPS-01/build-attempt-2.diff)

- diff:223-226 — new post-filter: `if dispatchable is not None: rank_table = {…}` then
  `if len(rank_table) < 2: return None, True`. Also diff:229-231 changes the
  no-candidates return from `(None, False)` to `(None, True)`.
- diff:240-244 — `resolve_review_pool` now passes
  `dispatchable=DISPATCHABLE_PLAN_ARMS if job == "plan" else None`.
- diff:264-273 — only the *other* caller, `_best_effort_floor_pool`, is corrected:
  `return "", [], "pool_floor_table_degenerate" if not ok else "all_review_arms_unavailable"`.
- No hunk in the diff touches `resolve_review_pool`'s `elif rank_table:` /
  `refusal = "pool_floor_table_degenerate"` block (grep for `elif rank_table` over the
  diff returns nothing).

## Failure scenario

`job="plan"` (signature confirmed at resolve-py:396, `job: str = "review"`;
`DISPATCHABLE_PLAN_ARMS = {"codex","sonnet","opus","fable"}` at :51), preferred pool
exhausted (`reviewer == ""`), ladder rank_table `{"sonnet": 1, "haiku": 2}`, author
`sonnet`. Filter drops `haiku` → 1 entry → `(None, True)`. `if floor_ok and floor_arm`
is False; `elif rank_table:` sees the **original** non-empty table → refusal is set to
`pool_floor_table_degenerate`, i.e. a hard resolver/config error, for a perfectly valid
ladder that simply has no plan-dispatchable floor. The documented contract (diff:204-207)
says this case must degrade to `all_review_arms_unavailable`.

## Required fix

Mirror the `_best_effort_floor_pool` correction: gate on `floor_ok`, not on
`rank_table` — e.g. `elif rank_table and not floor_ok:` (leaving
`all_review_arms_unavailable` from line 509 in place otherwise).

VERDICT: upheld (CONFIRMED).
