# GLM vs Haiku live judge comparison

## Re-run command

```bash
bash plugins/leadv2/scripts/leadv2-judge-arm-live-comparison.sh --output-dir docs/handoff/JUDGE-ARM-LIVE-COMPARISON --overwrite
```

The harness invokes the real judge, never a stub. It allocates a fresh temporary cache per call, so repeat 2 cannot be a cache hit. `results.jsonl` records each command, return code, stdout, stderr, parsed full envelope, and the envelope's audited `judge_arm`.

## Corpus

| ID | Mission | Why included | Reader baseline | Self-consistency |
| --- | --- | --- | --- | --- |
| docs_single_deliverable | `docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md` | Docs-only, one-file proposal with no code write; the deliberately trivial end of the corpus. | trivial | true |
| policy_amendment | `docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md` | Short policy amendment that changes a default while fencing a prior design. | simple | true |
| shared_quota_gauge | `docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md` | Shared production quota accounting with canonical-copy and sync constraints. | standard | false |
| safety_guard | `docs/handoff/ee0eaf69f3e8/MISSION.md` | Safety/protected guard path with real escape reproduction and mutation controls. | complex | false |
| telemetry_foundation | `docs/handoff/ac8a48dc2939/MISSION.md` | Multi-subsystem account-truth and quota-telemetry foundation work. | complex | false |
| provider_pricing | `docs/handoff/cc4557feef48/MISSION.md` | Measured provider-pricing decision with routing and quota evidence dependencies. | complex | false |
| arbiter_inputs | `docs/handoff/48b8297b4cc1/MISSION.md` | Strategic arbiter-input work spanning decision scoring and protected constraints. | complex | false |
| decision_record | `docs/handoff/ARBITER-DECISION-RECORD/MISSION.md` | Cross-cutting observability needed to replay routing decisions honestly. | standard | false |
| close_gate_repair | `docs/handoff/83577d79c310/MISSION-R2.md` | Focused regression repair where prior work died before proving its own suite. | standard | true |
| judge_measurement | `docs/handoff/9d368a385d9d/MISSION.md` | This multi-transport measurement lane itself, including the default-arm decision. | standard | false |

## All live verdicts

### docs_single_deliverable — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.AjciPK LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "docs"}
```
### docs_single_deliverable — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.1IFwjs LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### docs_single_deliverable — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.NE0ogc LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "docs"}
```
### docs_single_deliverable — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.ksEq8q LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### policy_amendment — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.Ekq4ca LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### policy_amendment — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.yy4RbH LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### policy_amendment — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.ltPRsa LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### policy_amendment — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.HibPZO LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 3, "work_kind": "build"}
```
### shared_quota_gauge — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.uevkTr LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "5b752e70", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 4, "work_kind": "build"}
```
### shared_quota_gauge — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.TjX66R LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "5b752e70", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 5, "work_kind": "build"}
```
### safety_guard — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.nkG1s8 LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ee0eaf69f3e8/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "a7d8080a", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "build"}
```
### safety_guard — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.6vHVtx LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ee0eaf69f3e8/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "a7d8080a", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "safety_publish_payments", "subsystems_touched": 3, "work_kind": "build"}
```
### telemetry_foundation — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.rJBCcw LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ac8a48dc2939/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "d53b73b6", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "data", "subsystems_touched": 6, "work_kind": "build"}
```
### telemetry_foundation — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.ZOqpBt LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ac8a48dc2939/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "d53b73b6", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 7, "work_kind": "build"}
```
### provider_pricing — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.vIpRwb LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/cc4557feef48/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "30458958", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 6, "work_kind": "build"}
```
### provider_pricing — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.znqrdc LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/cc4557feef48/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "30458958", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 7, "work_kind": "build"}
```
### arbiter_inputs — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.ufW3qM LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/48b8297b4cc1/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "c8bdd749", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 7, "work_kind": "build"}
```
### arbiter_inputs — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.eFubtO LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/48b8297b4cc1/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "c8bdd749", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 9, "work_kind": "build"}
```
### decision_record — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.L09nWk LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ARBITER-DECISION-RECORD/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "1f0af9a4", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "data", "subsystems_touched": 5, "work_kind": "build"}
```
### decision_record — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.iFcj6Y LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/ARBITER-DECISION-RECORD/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "1f0af9a4", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 6, "work_kind": "build"}
```
### close_gate_repair — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.CDkReq LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 5, "work_kind": "diagnose"}
```
### close_gate_repair — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.a4CwXx LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 8, "work_kind": "diagnose"}
```
### close_gate_repair — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.d96pJz LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 4, "work_kind": "build"}
```
### close_gate_repair — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.UlPFYn LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 7, "work_kind": "build"}
```
### judge_measurement — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.RszAxg LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/9d368a385d9d/MISSION.md
```
Return code: `0`; observed `judge_arm`: `glm`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "02e650b5", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### judge_measurement — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.7aAndX LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0acd5a5e2540/docs/handoff/9d368a385d9d/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "02e650b5", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 5, "work_kind": "diagnose"}
```

## Reliability

- `glm`: 0/13 failures (0.0%). A failure is a non-zero exit, unparsable output, fallback envelope, or a `judge_arm` other than the requested arm.
- `haiku`: 0/13 failures (0.0%). A failure is a non-zero exit, unparsable output, fallback envelope, or a `judge_arm` other than the requested arm.

## Self-consistency before cross-arm interpretation

- `docs_single_deliverable` / `glm`: consistent; run 1 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "docs"}`, run 2 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "docs"}`.
- `docs_single_deliverable` / `haiku`: consistent; run 1 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}`, run 2 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}`.
- `policy_amendment` / `glm`: consistent; run 1 = `{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`, run 2 = `{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`.
- `policy_amendment` / `haiku`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`, run 2 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 3, "work_kind": "build"}`.
- `close_gate_repair` / `glm`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 5, "work_kind": "diagnose"}`, run 2 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "glm", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 4, "work_kind": "build"}`.
- `close_gate_repair` / `haiku`: consistent; run 1 = `{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 8, "work_kind": "diagnose"}`, run 2 = `{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 7, "work_kind": "build"}`.
- `glm` complexity self-consistency: 2/3 requested repeat pairs.
- `haiku` complexity self-consistency: 2/3 requested repeat pairs.
- Combined complexity self-consistency: 4/6 requested arm/mission pairs.

## Cross-arm agreement

- Comparable baseline pairs: 10/10 (both requested arms produced a real judge envelope).
- Material complexity-class disagreements: 0/10.
- Other-envelope disagreements with the same complexity: 10/10.
- Confidence-only disagreements: 0/10. The current TaskEstimate schema emitted no `confidence` key where it was absent; all present fields remain in the raw envelopes above.

No material complexity-class disagreement was observed among comparable pairs.

## Decision

**Measured default: `haiku`.** Retain the existing haiku default: reliability and complexity self-consistency tied, so this re-run supplies no evidence to switch arms.

Evidence: GLM failure rate 0/13; Haiku failure rate 0/13; complexity disagreements 0/10; GLM self-consistency 2/3; Haiku self-consistency 2/3.

The fallback path is not counted as an arm success: a GLM request with `judge_arm=haiku_fallback` is a GLM transport failure, while the emitted fallback envelope remains preserved above for diagnosis.
