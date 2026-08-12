# ONE-PATH-PLAN-RUN-01 — Build Summary

**Task:** dispatch-a88918ee  
**Date:** 2026-08-12  
**Lane:** ONE-PATH-PLAN-RUN-01  
**Status:** ✅ Engine + tests landed; one expected red (D3 — step-0 chore pending)

## Files Created

| File | Purpose |
|---|---|
| `plugins/leadv2/scripts/leadv2-plan-run.sh` | Sole-owner Plan + Diagnose engine (mirrors `leadv2-review-run.sh`) |
| `plugins/leadv2/scripts/lib/leadv2-context-merge.py` | Deterministic skeleton/arm merge — engine-owned keys always win |
| `plugins/leadv2/scripts/tests/test-plan-run-engine.sh` | Tests 1–7, 10, 12 + codemap parity (11 assertions) |
| `plugins/leadv2/scripts/tests/test-plan-arms-role-scoped.sh` | Test 6 standalone — DISPATCHABLE_PLAN_ARMS membership |
| `plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh` | Test 7 standalone — codex policy degradation |
| `plugins/leadv2/scripts/tests/test-diagnose-no-pe-constants.sh` | Test 10 standalone — no persona-engine constants |
| `plugins/leadv2/scripts/tests/test-diagnose-codex-disabled-degrades.sh` | Test 12 standalone — diagnose degradation parity |
| `plugins/leadv2/scripts/tests/test-workflows-copies-are-symlinks.sh` | Test 8 — symlink assertion (D3: red until step-0 chore) |

## Files Edited

| File | Change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | +`DISPATCHABLE_PLAN_ARMS = {"codex","sonnet","opus","fable"}` (line 47); role-scope the membership test at line 675; `job` parameter on `resolve_review_pool()`; plan-mode pool filtering; pass `args.job` through |

## Test Results

| Suite | Result |
|---|---|
| `test-plan-run-engine.sh` | **11 pass, 0 fail** |
| `test-plan-arms-role-scoped.sh` | **4 pass, 0 fail** |
| `test-plan-run-codex-disabled-degrades.sh` | **3 pass, 0 fail** |
| `test-diagnose-no-pe-constants.sh` | **2 pass, 0 fail** |
| `test-diagnose-codex-disabled-degrades.sh` | **4 pass, 0 fail** |
| `test-workflows-copies-are-symlinks.sh` | **0 pass, 2 fail, 0 skip** — expected per D3 |
| `test-arm-ladder-vocabulary-drift.sh` | **8 pass, 0 fail** (regression guard, unchanged) |
| `test-review-engine-pool-degrades.sh` | **2 pass, 0 fail** (regression guard) |
| `test-codex-quota-gate.sh` | **10 pass, 0 fail** (regression guard) |

## Design Decisions Resolved

- **C1/D1:** `DISPATCHABLE_PLAN_ARMS = {"codex","sonnet","opus","fable"}` — design wins over mission prose; glm/kimi excluded per PLANNER-MODELS-DECISION-01.
- **C2/D2:** Flag named `LEADV2_PLAN_ENGINE` (mirrors `LEADV2_REVIEW_ENGINE`), not design §5.1's `LEADV2_PLAN_RUN`. No `.claude/settings.json` in this repo — §5.1 env-block sync has no target.
- **C3/D5:** Tests 1–3 re-pointed from `_acceptance_guard` (off-limits in `leadv2-dispatch-code.sh`) to the engine's own acceptance path via `leadv2-acceptance-shape.sh validate`.
- **D3:** Test 8 (workflow symlinks) is **red by design** — `~/.claude/workflows/leadv2-{plan,diagnose}.js` are still copies, not symlinks. This is the step-0 chore (outside this repo). Lead's call to either run the chore or accept the red.
- **D4:** Tests 9, 11, 13 explicitly deferred to the wiring lane (need off-limits files: `leadv2-dispatch-code.sh`, `leadv2-iterative-recovery/SKILL.md`, `leadv2-task-judge.sh`).

## What This Lane Does NOT Touch

- `leadv2-review-run.sh` — read-only reference, zero edits.
- `leadv2-dispatch-code.sh` and all other dispatch scripts — off-limits.
- `workflows/leadv2-plan.js` — survives (mission item 5); existing codemap assertions unchanged.
- `routing.yaml` semantics beyond the role-scoped set addition.
- Any Supabase/Qdrant/Next.js surface.

## Critical Invariants Verified

1. **No bare `claude -p`** — the engine routes all model arms through `claude-subsession.sh --wait`. ✅
2. **Engine-owned keys always win** — skeleton writes `id`, `mission`, `reads`, `writes`, `lane_writes`, `acceptance.authored_at` BEFORE arm dispatch; merge helper discards any arm-supplied value. ✅
3. **No path from `provider_error`/`empty_response` to `pass`** — the gate writer has only blocked branches for these tokens. ✅
4. **Single validator** — the engine shells out to `leadv2-acceptance-shape.sh validate`; holds no second heuristic. ✅
5. **`DISPATCHABLE_BUILD_ARMS` unchanged** — regression guard green. ✅
