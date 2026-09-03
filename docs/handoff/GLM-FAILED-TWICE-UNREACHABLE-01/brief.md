# GLM-FAILED-TWICE-UNREACHABLE-01 — the "GLM failed twice → Sonnet" rule has no reader

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 09:35Z by the persona-engine lead.

## Symptom
`.claude/leadv2-overrides/extensions.md §Model routing v2` and `docs/model-effort-matrix.md` list
"GLM failed twice" as a legitimate Sonnet exception. In `leadv2-dispatch-code.sh` (~:7078-7092) the
only channel for that count, `--glm-failures N`, is deliberately capped to 0 for N≥2
(`glm_failures_flag_ignored reason=unverified_caller_input_not_ledger_backed`) because "no real
GLM-failure ledger backs it yet". Result: the rule is unreachable from any caller. A rule without a
reader is not a rule (persona-engine memory `feedback-rule-without-reader-is-not-a-rule`).

Live cost 2026-09-02: GLM-EFFICIENCY-01 (GLM failed R1+R2 on the same class-map finding) and
WORKER-MCP-ALL-ARMS-01 (GLM failed R2+R3 on the same grep-only-test shape) could not be routed to
Sonnet; `--provider` is not a flag; the lead had to use `--interactive` as an interim channel and
journal why.

## Required
1. The dispatcher derives the GLM failure count for a task from its OWN ledger
   (`leadv2-dispatch-ledger.sh record-review --verdict … --reviewer …` already records verdicts per
   task/diff-hash): count `verdict=FAIL` reviews whose author arm was glm for this task id.
2. `glm_failed_twice` rule fires from that derived count; the caller flag stays capped (spoof-proof).
3. Journal line `arm=sonnet rule=glm_failed_twice source=ledger count=N` on the routed dispatch.
4. Suite: ledger with 0/1/2 glm FAIL rows → arm glm/glm/sonnet; negative control (rule body deleted
   in a mktemp copy) → red; EXTRA_SUITE_MAP row proven with `--scope changed`.

## Evidence
`dispatch-GLM-EFFICIENCY-01-r3.log` (`ERROR: unknown arg: --provider`), dispatch-code.sh:7078-7092,
review-gate.md of both lanes (author=glm verdict=FAIL ×2 each).
