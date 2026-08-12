# ONE-PATH-PLAN-RUN-01 — followups (judge verdict ACCEPT_WITH_CAVEATS, 0.88, 2026-08-12)
All four are BLOCKING preconditions of the doc-flip lane (plan-JS deletion + phases.md
§Phase 2 flip). The flip must not land until each is fixed and re-verified against real
arm output, not a mock.
1. [high] leadv2-plan-run.sh:436 — consume refused_quota/refused_peak_hours/refused_channel_down, spill to next :ok: arm.
2. [high] leadv2-plan-run.sh:373 — align extract_plan_yaml marker/fence order with mission prompt (or accept both).
3. [high] lib/leadv2-context-merge.py:36 — reject non-dict acceptance: nonzero exit; preserve acceptance.authored_at.
4. [high] lib/leadv2-glm-policy-resolve.py:511 — filter review-floor/_best_effort_floor_pool by DISPATCHABLE_PLAN_ARMS (no haiku in planning pool).
