# ONE-PATH-PLAN-RUN-01 — followups

## Round 1 (judge ACCEPT_WITH_CAVEATS 0.88, 2026-08-12) — ALL FIXED
Fixed by PLAN-FOLLOWUPS-01 (merged 23df16a, 2026-08-13; r1 GLM + r2/r3 Codex,
17/17 mutation-gated, review r3 critical=0, judge stop-rule ACCEPT_WITH_CAVEATS):
1. ~~[high] leadv2-plan-run.sh:436 refusal consumption/arm spill~~ FIXED
2. ~~[high] leadv2-plan-run.sh:373 extract_plan_yaml both marker/fence orders~~ FIXED
3. ~~[high] leadv2-context-merge.py:36 non-dict acceptance hard error~~ FIXED
4. ~~[high] leadv2-glm-policy-resolve.py:511 plan pool filtered from review floor~~ FIXED

## Round 2 (review r3 residue, 2026-08-13) — ALL FIXED by PLAN-FOLLOWUPS-02
Fixed cb81ebe + r2 2339a65 (order-B first-fence latch); review PASS_WITH_NITS
(diff 6cd7f449, arms opus,opus,sonnet); 21/21 mutation-gated; edge cases
lead-probed live. Doc-flip UNGATED and executed (0.3.0).
Original findings (all were lead-verified real):
1. [high] leadv2-glm-policy-resolve.py:545 — `elif not floor_ok` reclassifies EMPTY
   rank_table (feature-not-adopted) as pool_floor_table_degenerate instead of
   all_review_arms_unavailable (behavior change vs pre-lane HEAD).
2. [high] leadv2-glm-policy-resolve.py:785 — _best_effort_floor_pool identical
   regression: `if not ok` replaced `if rank_table`; empty rank_table now hard
   degenerate error instead of unavailable fallback.
3. [high] leadv2-plan-run.sh:371 — order-A pass disabled by ANY ``` fence appearing
   before PLAN_YAML: (e.g. a prose code block), falls through to `cat <whole file>`;
   pre-lane HEAD handled this. Lead repro: prose fence + marker→fence YAML → whole
   file returned.

Doc-flip (plan-JS deletion + phases.md §Phase 2 flip + 0.3.0) remains gated on
Round-2 items. Judge stop rule from PLAN-FOLLOWUPS-01: no round 4 in that lane —
these go to a FRESH lane PLAN-FOLLOWUPS-02 with its own review cap.
