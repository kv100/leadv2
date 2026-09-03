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

## Цена недостижимости, измеренная 2026-09-02

За один день лида это правило обошлось так. Диспатчи по армам:

| арм | диспатчей |
|---|---|
| sonnet | **17** |
| glm-flash + glm | 9 |
| codex | 5 |
| refuse (все армы закрыты) | 2 |
| freepool | 2 |

Живая квота GLM в тот же день: **5h=1%, weekly=6%** (проба `leadv2-glm-quota-gate.sh`,
порог 80%). То есть самый дешёвый арм простоял на 94% свободным, пока дефицитный расходовался.

Механизм подмены: лид десять раз передал `--interactive` — единственный достижимый путь к sonnet, —
потому что правило `glm_failed_twice` недостижимо и заменить его больше нечем. Исключение стало
умолчанием, что и предсказуемо: когда правило нельзя выразить, человек выражает его флагом, а флаг
не знает про квоту.

Худший случай дня: раунд `DRIFT-GUARDS-TO-CANON-01` получил `route_resolved arm=refuse
reason=all_arms_capped util_glm=6 util_codex=100 util_claude=unknown_capped util_freepool=0` —
линия встала «за неимением армов» при GLM, свободном на 94%. Отказ был формально корректен и
фактически абсурден.

Отсюда дополнительное требование к задаче: сделать правило достижимым НЕДОСТАТОЧНО. Маршрутизатор
обязан отказываться от арма только когда закрыты все армы С УЧЁТОМ квоты, и `all_arms_capped` не
имеет права появляться, пока хоть один арм ниже своего порога. Негативный контроль: подсунуть
состояние «codex=100, claude=capped, glm=6» -> маршрут обязан выбрать glm, а не refuse; вернуть
старое поведение -> проба краснеет.
