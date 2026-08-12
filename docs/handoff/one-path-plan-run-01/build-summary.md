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

### 4. Test suites (8 files, 35 assertions total)

| Suite | Design tests | Cases |
|---|---|---|
| `test-plan-run-acceptance-real.sh` | 1, 2, 3 | empty observable, internal-contract phrasing, fenced-only acceptance — all against the real validator |
| `test-plan-run-contract.sh` | 4, 5, acc | context.yaml validates after prepass; engine self-contained in bare bash with stub arms; **empty-body arm → blocked empty_response (acceptance observable)** |
| `test-plan-run-arms-role-scoped.sh` | 6 | DISPATCHABLE_PLAN_ARMS membership via importlib; --plan-pool pool filters glm/kimi |
| `test-plan-run-codex-disabled-degrades.sh` | 7 | codex_skipped_by_policy → arm_unavailable; end-to-end m3-market degrade → status=pass |
| `test-plan-run-diagnose-mode.sh` | 10, 12 | no persona-engine constants; diagnose_run verbs; exit 9 for blocked; acceptance: skipped; **D1: diagnose stub → root-cause.md + gate pass; D2: empty-body → blocked empty_response** |
| `test-diagnose-codex-disabled-degrades.sh` | 12 | diagnose_run verbs; root-cause.md artifact; no parked; **codex-disabled diagnose → non-codex arm produces root-cause.md** |
| `test-diagnose-no-pe-constants.sh` | 10 | engine source (non-comment lines) has no persona-engine constants or journalctl calls |
| `test-plan-run-codemap.sh` | 14 | BANDIT-WIRE-01 invariants; engine syntactically valid; reasonable size |

### 5. Fixtures

`tests/fixtures/plan-run/`: `stub-architect.sh`, `stub-codex-disabled.sh`,
`stub-quota-ok.sh`, `README.md`.

## Test results

### Plan-run + diagnose suites (all pass)
```
test-plan-run-acceptance-real.sh:       4 pass, 0 fail  rc=0
test-plan-run-arms-role-scoped.sh:      4 pass, 0 fail  rc=0
test-plan-run-codemap.sh:               4 pass, 0 fail  rc=0
test-plan-run-codex-disabled-degrades:  4 pass, 0 fail  rc=0
test-plan-run-contract.sh:              5 pass, 0 fail  rc=0
test-plan-run-diagnose-mode.sh:         7 pass, 0 fail  rc=0
test-diagnose-codex-disabled-degrades:  5 pass, 0 fail  rc=0
test-diagnose-no-pe-constants.sh:       2 pass, 0 fail  rc=0
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
- **Created:** `plugins/leadv2/scripts/tests/test-diagnose-no-pe-constants.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-diagnose-codex-disabled-degrades.sh`
- **Created:** `plugins/leadv2/scripts/tests/test-plan-run-codemap.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-architect.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-codex-disabled.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/stub-quota-ok.sh`
- **Created:** `plugins/leadv2/scripts/tests/fixtures/plan-run/README.md`
- **Removed:** `plugins/leadv2/scripts/tests/test-plan-run-engine.sh` (consolidated suite replaced by named suites)

## Fix round (2026-08-12 ~17:30Z) — 1 Critical + 6 High resolved

Commit `5957df5`. All 8 suites green (35 pass, 0 fail).

| Finding | Severity | Fix |
|---|---|---|
| Diagnose mode dispatches PLAN_YAML prompt but validates root_cause+confidence → always blocked | Critical | Architect prompt branches on MODE==diagnose (emits root_cause/confidence/evidence/fix_hint/alternates); extract_plan_yaml applied before validation so yaml.safe_load sees clean keys |
| `planner` unbound under set -u in diagnose mode | High | Initialise `planner=""` before diagnose block; extract from resolver output (`reviewer=\|planner=`) |
| Retry appends to mission file that run_planner_arm truncates with `>` | High | Retry writes `.retry-overlay` file; run_planner_arm appends it after writing base mission |
| Critic reads hardcoded `plan-arm-codex.yaml` fallback | High | `_ARCHITECT_DRAFT_ARM` global set before critic pass; critic reads architect's actual arm output |
| Skeleton clobbers pre-existing valid context.yaml | High | Skeleton stays as `.skeleton`; merge writes context.yaml only on success |
| Both diagnose suites grep-on-source only | High | Added execution tests (D1: stub→root-cause.md+pass; D2: empty→blocked) to both diagnose suites |
| test-diagnose-no-pe-constants trips on engine comment | High | grep non-comment lines only; engine comment rephrased |
| Regex `claude  +-p` requires 2+ spaces | High | Fixed to `claude[[:space:]]+-p` |
