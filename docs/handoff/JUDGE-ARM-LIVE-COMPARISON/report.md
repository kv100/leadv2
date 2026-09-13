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
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.73oYtG LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}
```
### docs_single_deliverable — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.D9QhBz LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### docs_single_deliverable — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.kFCMWo LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}
```
### docs_single_deliverable — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.PiwHj8 LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/LEAD-BURN-MECHANISM-01/MISSION-astra.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### policy_amendment — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.gqk2FX LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "trivial", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}
```
### policy_amendment — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.cBYsJi LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 3, "work_kind": "build"}
```
### policy_amendment — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.l3ehUD LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "trivial", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}
```
### policy_amendment — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.WuQqRM LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/dispatch-b22dc98b/MISSION-AMENDMENT.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### shared_quota_gauge — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.JU7nyZ LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "5b752e70", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "data", "subsystems_touched": 1, "work_kind": "build"}
```
### shared_quota_gauge — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.YVQtz6 LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "5b752e70", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 4, "work_kind": "build"}
```
### safety_guard — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.EmqE1h LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ee0eaf69f3e8/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "line_count", "duration_class": "medium", "estimate_id": "a7d8080a", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 1, "work_kind": "review"}
```
### safety_guard — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.4FCTQL LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ee0eaf69f3e8/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "a7d8080a", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "build"}
```
### telemetry_foundation — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.jzY5Ij LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ac8a48dc2939/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "line_count", "duration_class": "medium", "estimate_id": "d53b73b6", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}
```
### telemetry_foundation — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.IABERI LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ac8a48dc2939/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "d53b73b6", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "data", "subsystems_touched": 7, "work_kind": "build"}
```
### provider_pricing — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.E5WuAl LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/cc4557feef48/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "line_count", "duration_class": "medium", "estimate_id": "30458958", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### provider_pricing — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.JE7oFi LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/cc4557feef48/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "30458958", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 7, "work_kind": "build"}
```
### arbiter_inputs — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.WSss2P LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/48b8297b4cc1/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "line_count", "duration_class": "medium", "estimate_id": "c8bdd749", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 4, "work_kind": "build"}
```
### arbiter_inputs — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.vZzVVY LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/48b8297b4cc1/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "c8bdd749", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 7, "work_kind": "build"}
```
### decision_record — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.eCcDMK LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ARBITER-DECISION-RECORD/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "1f0af9a4", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "data", "subsystems_touched": 2, "work_kind": "build"}
```
### decision_record — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.Iaq2Ux LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/ARBITER-DECISION-RECORD/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "long", "estimate_id": "1f0af9a4", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 6, "work_kind": "build"}
```
### close_gate_repair — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.eNB0xm LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0efe4bcc", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### close_gate_repair — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.XAc05d LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "safety_publish_payments", "subsystems_touched": 3, "work_kind": "diagnose"}
```
### close_gate_repair — requested `glm`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.7odExq LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0efe4bcc", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### close_gate_repair — requested `haiku`, repeat 2

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.NPBk1I LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/83577d79c310/MISSION-R2.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "complex", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 8, "work_kind": "diagnose"}
```
### judge_measurement — requested `glm`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=glm LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.dhhh9q LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/9d368a385d9d/MISSION.md
```
Return code: `0`; observed `judge_arm`: `None`.

stdout:
```json
{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "02e650b5", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}
```
### judge_measurement — requested `haiku`, repeat 1

Invocation:
```bash
LEADV2_JUDGE_ARM=haiku LEADV2_JUDGE_CACHE_DIR=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-judge-compare-cache.yPndzn LEADV2_JUDGE_TIMEOUT_SEC=90 LEADV2_ROUTER_V2=0 timeout=210s bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/plugins/leadv2/scripts/leadv2-task-judge.sh --mission-file /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9d368a385d9d/docs/handoff/9d368a385d9d/MISSION.md
```
Return code: `0`; observed `judge_arm`: `haiku`.

stdout:
```json
{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "02e650b5", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 4, "work_kind": "build"}
```

## Reliability

- `glm`: 13/13 failures (100.0%). A failure is a non-zero exit, unparsable output, fallback envelope, or a `judge_arm` other than the requested arm.
- `haiku`: 0/13 failures (0.0%). A failure is a non-zero exit, unparsable output, fallback envelope, or a `judge_arm` other than the requested arm.

**NOT REACHED: GLM produced no real judge envelope in 13/13 requests.** Its observable error artifact is the preserved `estimate_source: fallback`, absent `judge_arm`, and empty stderr on every invocation above. The judge deliberately redirects child transport stderr, so this run cannot honestly name a provider-side error beyond that envelope-level failure; it does not infer agreement from the deterministic fallback.

## Self-consistency before cross-arm interpretation

- `docs_single_deliverable` / `glm`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}`, run 2 = `{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}`.
- `docs_single_deliverable` / `haiku`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}`, run 2 = `{"complexity": "complex", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "1cf7df9f", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 3, "work_kind": "diagnose"}`.
- `policy_amendment` / `glm`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "trivial", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}`, run 2 = `{"complexity": "trivial", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 1, "work_kind": "build"}`.
- `policy_amendment` / `haiku`: consistent; run 1 = `{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 3, "work_kind": "build"}`, run 2 = `{"complexity": "simple", "complexity_basis": "judge", "duration_class": "short", "estimate_id": "0f812430", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`.
- `close_gate_repair` / `glm`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0efe4bcc", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`, run 2 = `{"complexity": "simple", "complexity_basis": "line_count", "duration_class": "short", "estimate_id": "0efe4bcc", "estimate_source": "fallback", "estimate_v": 1, "flag_source": "title", "needs_live_verification": true, "risk_class": "none", "subsystems_touched": 2, "work_kind": "build"}`.
- `close_gate_repair` / `haiku`: INCONSISTENT OR NOT REACHED; run 1 = `{"complexity": "standard", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": false, "risk_class": "safety_publish_payments", "subsystems_touched": 3, "work_kind": "diagnose"}`, run 2 = `{"complexity": "complex", "complexity_basis": "judge", "duration_class": "medium", "estimate_id": "0efe4bcc", "estimate_source": "judge", "estimate_v": 1, "flag_source": "judge", "judge_arm": "haiku", "needs_live_verification": true, "risk_class": "safety_publish_payments", "subsystems_touched": 8, "work_kind": "diagnose"}`.
- Complexity self-consistency: 1/6 requested arm/mission pairs.

Interpreted by arm: GLM is **NOT REACHED** for all 0/3 valid self-consistency pairs; Haiku is complexity-consistent on 1/3. The two Haiku class changes (`standard→complex`) mean cross-arm agreement would not be meaningful even if GLM had returned a real envelope.

## Cross-arm agreement

- Comparable baseline pairs: 0/10 (both requested arms produced a real judge envelope).
- Material complexity-class disagreements: 0/0.
- Other-envelope disagreements with the same complexity: 0/0.
- Confidence-only disagreements: 0/0. The current TaskEstimate schema emitted no `confidence` key where it was absent; all present fields remain in the raw envelopes above.

No material complexity-class disagreement was observed among comparable pairs.

## Decision

**Measured default: `haiku`.** Set the default to haiku: GLM has not demonstrated reliable equivalent complexity classification across this corpus.

Evidence: GLM failure rate 13/13; Haiku failure rate 0/13; complexity disagreements 0/0; self-consistency 1/6.

The fallback path is not counted as an arm success: a GLM request with `judge_arm=haiku_fallback` is a GLM transport failure, while the emitted fallback envelope remains preserved above for diagnosis.

## Falsification and regression output

Initial harness preflight (red, before the manifest validation fix):

```text
incomplete corpus entry: {'id': 'shared_quota_gauge', 'mission': 'docs/handoff/QUOTA-GAUGE-COUNTS-GLM-AS-ANTHROPIC-01/MISSION.md', 'rationale': 'Shared production quota accounting with canonical-copy and sync constraints.', 'expected_complexity': 'standard', 'self_consistency': False}
```

Initial judge-suite result after changing the measured default but before updating its default-arm assertion (red):

```text
[TEST] FAIL: T16: expected GLM default only, arm=haiku glm=       0 haiku=       1
=== Results: 30 passed, 1 failed ===
```

Green after both fixes:

```text
bash -n plugins/leadv2/scripts/leadv2-judge-arm-live-comparison.sh plugins/leadv2/scripts/leadv2-task-judge.sh plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
=== Results: 31 passed, 0 failed ===
```

Changed-scope runner (foreground, `gtimeout 900 bash tests/run-all.sh --scope changed`) ended red for ambient-suite reasons, while still running both judge suites green:

```text
[CORE-OFFLINE] scope=changed running 93 of 93 suites (base=main@32775565ed, 3 changed files, 1 unmapped -> full-set fallback: unmapped_files (1 of 3 changed files selected no suite) — cannot prove the diff is covered)
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling (killed by run-all; counted as a blocking failure with a named cause)
[TEST] PASS: T16: default arm=haiku; valid Haiku answer does not invoke GLM
=== Results: 31 passed, 0 failed ===
[TEST] PASS: bash -n syntax OK on leadv2-task-judge.sh
=== Results: 7 passed, 0 failed ===
exit_code=124
```

The broad failure predates and is outside this lane's changed judge surfaces: its raw transcript named missing `leadv2-broad-status.sh`, test-fixture paths rooted at `/fixtures`, and unrelated shared-sink/hook failures. The focused judge regression proof above is green.
