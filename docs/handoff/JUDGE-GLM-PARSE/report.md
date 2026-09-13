# GLM noisy-envelope repair report

## Evidence

The reader now selects the last complete JSON object in a GLM `--out` capture,
then extracts the estimate from that terminal envelope's `result`. This avoids
mistaking a valid-JSON `unrecognized_model` warning for the terminal envelope.
Fallback envelopes carry `fallback_reason`; transport diagnostics include a
bounded, literal-token-redacted stderr tail.

## Red then green

### Red — prior live baseline

The prior comparison recorded a GLM request as a fallback instead of a judge
verdict:

```json
{"complexity":"simple","complexity_basis":"line_count","duration_class":"short","estimate_source":"fallback","estimate_v":1,"flag_source":"title","judge_arm":null}
```

### Green — this re-run

The repaired live GLM path returned a judge envelope:

```json
{"complexity":"standard","complexity_basis":"judge","duration_class":"short","estimate_source":"judge","estimate_v":1,"flag_source":"judge","judge_arm":"glm","needs_live_verification":false,"risk_class":"none","subsystems_touched":2,"work_kind":"docs"}
```

## Falsification output

```text
bash -n plugins/leadv2/scripts/leadv2-task-judge.sh
bash -n plugins/leadv2/scripts/leadv2-judge-arm-live-comparison.sh
bash -n plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
python3 -m py_compile: no changed Python files

test-leadv2-task-judge.sh: 36 passed, 0 failed
test-arbiter-decision-record-inputs.sh: 6 passed, 0 failed
test-reset-urgency.sh: 10 passed, 0 failed
test-arbiter-prices-by-provider.sh: 7 passed, 0 failed

run-all --scope changed --select-only: 8 selected, including
test-leadv2-task-judge.sh, test-judge-parses-its-own-answer.sh, and
test-judge-complexity-path.sh
```

## Live comparison

The real comparison re-run is recorded in
`../JUDGE-ARM-LIVE-COMPARISON/results.jsonl` and its report. Both GLM and
Haiku produced 13/13 real envelopes with 0/13 failures. Complexity
self-consistency was GLM 2/3 and Haiku 2/3; there were 0/10 material
complexity disagreements. The evidence therefore retains the existing Haiku
default: GLM is not more consistent on this corpus, and a tie is not evidence
to flip the default.
