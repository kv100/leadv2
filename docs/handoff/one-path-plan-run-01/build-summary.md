# ONE-PATH-PLAN-RUN-01 — Build Summary

**Task:** dispatch-54aaa0bf
**Date:** 2026-08-12
**Status:** DELIVERABLE_COMPLETE

## What was built

### 1. `plugins/leadv2/scripts/leadv2-plan-run.sh` — sole-owner Plan + Diagnose engine

Mirrors `leadv2-review-run.sh` structure: self-contained (no lane sourcing), callable
from a bare bash session. Three modes:

- **`--mode plan`**: N-arm fan-out architect pass + critic pass, merge into
  `context.yaml` with real `leadv2-acceptance-shape.sh validate` + `assert-precedence`.
  One retry on validation failure.
- **`--mode prepass`**: single-arm architect pass, critic skipped (cheaper, lane-inline).
- **`--mode diagnose`**: root-cause analysis, writes `root-cause.md`. No acceptance check
  (acceptance: skipped). No persona-engine constants.

Key invariants:
- Engine writes skeleton `context.yaml` (deterministic fields + `authored_at`) BEFORE any
  arm runs. Arms never write `context.yaml` — they emit `PLAN_YAML:` fenced blocks.
- Engine-owned keys (`id`, `mission`, `reads`, `writes`, `lane_writes`,
  `acceptance.authored_at`) are always restored after merge.
- Exit codes: `0` pass · `2` usage · `7` fail · `9` blocked (mirrors review engine).
- Gate format: `mode:`, `status:`, `reason:`, `arms:`, `artifact:`, `acceptance:`.
- Never-silent-pass: `provider_error`, `empty_response`, `body_lost` → blocked, never pass.
- No bare `claude -p` anywhere — all model arms go through `claude-subsession.sh`.

### 2. `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` — additive change

- Added `--plan-pool` CLI flag (beside existing `--review-pool`).
- When set, calls `resolve_review_pool` with `job="plan"` (already filtered by
  `DISPATCHABLE_PLAN_ARMS` at line 427). No author exclusion.
- `DISPATCHABLE_BUILD_ARMS` and `--review-pool` path byte-identical (regression-proven).

### 3. `plugins/leadv2/scripts/lib/leadv2-context-merge.py` — fix

- `check_required()` now only flags absence (`None`), not empty lists/strings.
  Empty `reads: []` is a valid engine-owned value; semantic emptiness is the
  acceptance-shape validator's job.

### 4. Test suites (6 files, 27 assertions total)

| Suite | Design tests | Cases |
|---|---|---|
| `test-plan-run-acceptance-real.sh` | 1, 2, 3 | empty observable, internal-contract phrasing, fenced-only acceptance — all against the real validator |
| `test-plan-run-contract.sh` | 4, 5, acc | context.yaml validates after prepass; engine self-contained in bare bash with stub arms; **empty-body arm → blocked empty_response (acceptance observable)** |
| `test-plan-run-arms-role-scoped.sh` | 6 | DISPATCHABLE_PLAN_ARMS membership via importlib; --plan-pool pool filters glm/kimi |
| `test-plan-run-codex-disabled-degrades.sh` | 7 | codex_skipped_by_policy → arm_unavailable; end-to-end m3-market degrade → status=pass |
| `test-plan-run-diagnose-mode.sh` | 10, 12 | no persona-engine constants; diagnose_run verbs; exit 9 for blocked; acceptance: skipped |
| `test-plan-run-codemap.sh` | 14 | BANDIT-WIRE-01 invariants; engine syntactically valid; reasonable size |

### 5. Fixtures

`tests/fixtures/plan-run/`: `stub-architect.sh`, `stub-codex-disabled.sh`,
`stub-quota-ok.sh`, `README.md`.

## Test results

### Plan-run suites (all pass)
```
test-plan-run-acceptance-real.sh:       4 pass, 0 fail  rc=0
test-plan-run-arms-role-scoped.sh:      4 pass, 0 fail  rc=0
test-plan-run-codemap.sh:               4 pass, 0 fail  rc=0
test-plan-run-codex-disabled-degrades:  4 pass, 0 fail  rc=0
test-plan-run-contract.sh:              5 pass, 0 fail  rc=0
test-plan-run-diagnose-mode.sh:         6 pass, 0 fail  rc=0
```

### Regression suites (all pass)
```
test-arm-ladder-vocabulary-drift.sh:    8 pass, 0 fail  rc=0
test-router-v2-retired-arm.sh:          FAIL=0          rc=0
test-leadv2-review-routing.sh:          3 pass, 0 fail  rc=0
test-leadv2-codemap.sh:                12 pass, 0 fail  rc=0
test-acceptance-shape.sh:               8 pass, 0 fail  rc=0
```

## Deferred to follow-up lane (4 of 13 assertions)

| # | Assertion | Reason |
|---|---|---|
| 8 | `~/.claude/workflows/*.js` are symlinks | Mutates founder's home dir; coupled to plan.js deletion |
| 9 | `LEADV2_PLAN_RUN=0` → byte-identical journal | Flag gates the lane call site in dispatch-code.sh (off-limits) |
| 11 | iterative-recovery/SKILL.md routes through engine | Requires editing SKILL.md (off-limits doc flip) |
| 13 | `work_kind=diagnose` from task-judge.sh reaches engine | Requires editing dispatch-adjacent script (off-limits) |

These are exactly the follow-up lane's diff (plan.js deletion + dispatch-code.sh swap + doc flip).

## Files changed

- **Created:** `plugins/leadv2/scripts/leadv2-plan-run.sh` (rewritten from skeleton to match design spec)
- **Modified:** `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` (additive `--plan-pool`)
- **Modified:** `plugins/leadv2/scripts/lib/leadv2-context-merge.py` (relaxed `check_required`)
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-acceptance-real.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-contract.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-arms-role-scoped.sh`
- **Modified:** `plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-diagnose-mode.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-codemap.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-architect.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-codex-disabled.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-quota-ok.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/README.md`
- **Removed:** `plugins/leadv2/scripts/tests/test-plan-run-engine.sh` (consolidated suite replaced by named suites)
