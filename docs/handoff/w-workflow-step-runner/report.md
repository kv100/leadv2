# Workflow step runner — executable boundary (`run_step`), §4 phase 1 (row 4afa0ee2525a)

Источник решения: `docs/handoff/SMART-ARBITER-DESIGN-20260907/dynamic-workflow-report.md`
(persona-engine), раздел "The smallest seam that actually executes". Брифы не тронуты:
арбитр, хуки, `leadv2-dispatch-code.sh`, `codex-task.sh`, читатели конфига маршрутизации.

## Что построено

`plugins/leadv2/scripts/leadv2-workflow-step.py` — `run_step(request)`: запрос шага →
консульт арбитра через его СУЩЕСТВУЮЩИЙ CLI и строковый протокол (арбитр не менялся) →
сверка решения с реестром запуска → запуск через объявленный executor → полная квитанция
(всегда пишется в jsonl-журнал и возвращается; шаг без квитанции не завершился).

`plugins/leadv2/scripts/lib/leadv2-launch-registry.py` — `resolve_decision(decision,
step_context)`: точное совпадение arm/model/tier/effort с собственным дескриптором реестра,
без ре-ранжирования; несовпадение — отказ с названием разошедшегося поля; арм вне реестра
(glm/freepool → adapter_scope=external) — отказ с названием арма, никогда подстановка
соседа; неприменимый effort — отказ, никогда тихий даунгрейд. `lookup()` для существующих
вызовов не изменён.

## Форма квитанции

```json
{"schema_version": 1, "boundary": "leadv2-workflow-step/run_step",
 "workflow_run_id": "...", "step_id": "...", "round": 1, "attempt": 1,
 "decision_id": "9c14c08376070f3c",
 "decision": {"arm": "haiku", "kind": "recon", "model": "haiku", "tier": "standard",
               "effort": "low", "reason": "cheapest_capable"},
 "requested": {"arm": "haiku", "model": "haiku", "tier": "standard", "effort": "low"},
 "observed": {"arm": "haiku", "model": "haiku"}, "observed_source": "executor_report",
 "outcome": "ok", "status": "ok", "launched": true, "refusal": null,
 "schema_validation": {"schema_id": "answer-v1", "valid": true, "error": null},
 "raw_result": {"path": ".../step-<decision_id>/raw-output.txt", "sha256": "...", "bytes": 30},
 "arbiter": {"decision_line": "arm=haiku kind=recon model=haiku ..."},
 "quota_evidence": {"source": "live-probe", "sampled_at_epoch": 1789042..., "age_s": 0.4,
                     "limit_s": 60, "refreshed": false},
 "usage": {"input_tokens": 18, "output_tokens": 4}, "elapsed_s": 1.9,
 "receipt_persisted": true, "ts": "...", "ts_epoch": ...}
```

Замкнутый набор исходов: `ok | invalid_output | transport_failed | cancelled |
unknown_completion`. Отказы до запуска — тоже квитанции (`status=refused`, `launched=false`,
`refusal.field` называет причину): валидационные отказы дают `invalid_output` (невалидный
вход на границе), недоступность арбитра — `transport_failed`. Классификация завершения:
rc=0 → схема решает ok/invalid_output; rc=75 или маркер `LEADV2_STEP_TRANSPORT_FAILED` в
stderr → `transport_failed`; смерть по сигналу (включая таймаут-килл границы) →
`cancelled`; любой другой ненулевой rc → `unknown_completion` — граница не выдаёт
незнание за отказ транспорта.

Свежесть: `quota_evidence.sampled_at_epoch` обязателен; старше 60с — отказ с названной
свежестью (после максимум одного bounded-обновления через `quota_refresh_cmd`). Известный
край назван в самом отказе, не замаскирован: параллельные шаги могут видеть одну и ту же
свободную квоту — граница проверяет свежесть, не эксклюзивность; резервирования — отдельная
работа координатора. Строгая валидация входа: неизвестные kind/size/provenance/capability,
пустой явный `launchable_arms`, отсутствующая квота-свидетельство — отказ, никогда
«разрешить по умолчанию» (неизвестный kind отсекается ДО коэрсии арбитра unknown→code).

## Зелёный прогон сюиты (главная фикстура)

`plugins/leadv2/scripts/tests/test-workflow-step-runner.sh` — 28 проверок, арбитр в
фикстурах заменён исполняемым стабом (сюита проверяет ГРАНИЦУ, не маршрутизацию):

```text
PASS: py_compile: boundary + registry
PASS: main: outcome ok
PASS: main: requested arm == observed arm
PASS: main: requested model == observed model
PASS: main: decision_id + launched
PASS: main: schema validated
PASS: main: receipt persisted + usage
PASS: main: one receipt line
PASS: paired: refused, outcome not ok
PASS: paired: refusal names field=model
PASS: paired: diverged values named
PASS: paired: nothing launched
PASS: paired: one receipt line
PASS: schema: invalid_output after a real launch
PASS: schema: error names the missing property
PASS: schema: receipt still written
PASS: stale: refused
PASS: stale: refusal names freshness
PASS: stale: age > limit, nothing launched
PASS: stale: one receipt line
PASS: glm: refusal names the arm
PASS: glm: external adapter scope, no substitute
PASS: glm: nothing launched
PASS: glm: one receipt line
PASS: empty: empty set is a refusal, never pool-widening
PASS: empty: one receipt line
PASS: kind: unknown work_kind refused at the boundary
PASS: kind: one receipt line
---
PASS=28 FAIL=0
```
(suite_rc=0; полный лог: /tmp/wfs-suite.log на машине прогона.)

Парный случай отличается от главного ТОЛЬКО подменой `model=haiku→sonnet` в строке
решения между арбитром и запуском.

## Красный прогон (мутация, артефакт)

`leadv2-mutation-control.sh` удалил сверку arm/model из тела `resolve_decision`
(sed `for _field in ("arm","model","tier","effort")` → `("tier","effort")`, маркер
`decision-match-mut` в теле функции). Артефакт:
`docs/handoff/w-workflow-step-runner/mutation-control/20260910T121613Z-48922.txt`
(MUTATION-CONTROL ok, diff_hash=0549892..., lane_diff_hash=a10666e...). Красная строка —
под мутантом подменённая модель проскакивает ЗЕЛЁНЫМ и парная фикстура ловит именно это:

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-workflow-step-runner.sh \
  file=plugins/leadv2/scripts/lib/leadv2-launch-registry.py \
  red_line=FAIL: paired: refused, outcome not ok -> {'decision': {'model': 'sonnet', ...},
  'outcome': 'ok', 'status': 'ok', 'requested': {'model': 'haiku', ...}, ...}
```

## Живая строка run_step с настоящим армом

Реальный вызов: `python3 plugins/leadv2/scripts/leadv2-workflow-step.py --request` с
арбитром ПО УМОЛЧАНИЮ (настоящий `lib/leadv2-route-arbiter.sh` CLI), настоящим
`config/leadv2-routing.yaml` и настоящим `resolve_decision`. Швы: квота/freepool —
hermetic-стабы (те же, что в test-arbiter-seam-plugin-kind.sh); executor — фикстура
(реальный вызов модели — не эта линия). Сырой вывод:

```text
live_rc=0
decision_line: arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku ... arb_rev=da79bea0368a matrix_rev=98ea29eec857 ...
decision_id: 9c14c08376070f3c outcome: ok status: ok
requested: {'arm': 'haiku', 'effort': 'low', 'model': 'haiku', 'tier': 'standard'}
observed: {'arm': 'haiku', 'model': 'haiku'} (source: executor_report)
schema_validation: {'error': None, 'schema_id': 'answer-v1', 'valid': True} usage: {'input_tokens': 18, 'output_tokens': 4}
receipt_persisted: True
arbiter journal row: {'arm': 'haiku', 'model': 'haiku', 'tier': 'standard', 'work_kind': 'recon', 'reason': 'cheapest_capable'}
```

Арбитр-журнал (`leadv2-route-arbiter-decisions.jsonl`) подтверждает, что консульт был
настоящим: строка реестра и строка решения совпали, квитанция ok.

## Фальсификационный набор

- `bash -n` всех изменённых shell-файлов: `BASH_N_OK` (сюита + tests/run-all.sh, вывод выше
  в транскрипте прогона: `bash -n plugins/leadv2/scripts/tests/test-workflow-step-runner.sh
  && bash -n tests/run-all.sh` → rc=0).
- `python3 -m py_compile` изменённых Python-файлов: `PY_COMPILE_OK`
  (leadv2-workflow-step.py + lib/leadv2-launch-registry.py; повторяется первой строкой
  сюиты: `PASS: py_compile: boundary + registry`).
- Changed-scope раннер: см. следующий раздел.

## Changed-scope раннер

`timeout 1800 bash tests/run-all.sh --scope changed` → `runall_rc=1`,
`run-all: 9 passed, 5 failed, scope=changed`.

Эта линия: сюита `test-workflow-step-runner.sh` выбрана и ЗЕЛЁНА внутри того же прогона
(`[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-workflow-step-runner.sh
(scope-selected ad-hoc)` → PASS-строки выше); родная сюита реестра
`test-launch-registry-argv.sh` (выбрана потому, что менялся `leadv2-launch-registry.py`)
— `[PASS]`. Оба мутанта моих правок не находят.

Все 5 провалов — наследованные, ни один не от диффа этой линии:

1. `tests/test-run-all-self-registration.sh` — 6 legs падают с
   `bash: <scratch>/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh: No such file
   or directory`: scratch-репо фикстуры копирует run-all.sh, но НЕ копирует lib-файл,
   от которого run-all зависит с f206d3ed (C5, в main с 2026-09-10 14:56, до моего
   коммита). Мой edit run-all.sh лишь ВЫБРАЛ эту сюиту в changed-scope.
2. `plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh` — тот же корень
   (scratch без discovery-lib; пустые out/rc=2 у вложенных запусков run-all).
3. `tests/test-run-all-carrier-map.sh` — тот же корень (все FAIL-строки — то же
   `No such file or directory`).
4. `plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh` — 25/26, падает leg
   `g5: live-matrix check wrong: refuse`: сюита ожидает «live all-astra matrix», а
   живой конфиг несёт trio gpt-5.6-sol/terra/luna с f5be241d (2026-09-10 14:25, до
   моего базового якоря 80102143 — в `git show 80102143:...routing.yaml` уже 5 упоминаний
   trio; проверено `check()` по всем трём строкам → ok, astra вне канонических).
5. `run-core-offline.sh` — контейнер, красный только из-за 1–4.

Чинить чужие сюиты (файлы линий f206d3ed/f5be241d, ещё живых) здесь не стал — вне write
set этой линии; фикс — либо C5 докладывает discovery-lib в свои scratch-фикстуры, либо
guard-строка в известном red-списке.

## Изменённые файлы

- `plugins/leadv2/scripts/leadv2-workflow-step.py` — новый: граница `run_step` + CLI.
- `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` — `+resolve_decision`
  (73 строки, `lookup()` и существующие вызовы не тронуты).
- `plugins/leadv2/scripts/tests/test-workflow-step-runner.sh` — новая сюита (28
  проверок), self-registered: `# run-all-triggers: leadv2-workflow-step
  leadv2-launch-registry`.
- `tests/run-all.sh` — 2 строки belt-and-braces в EXTRA_SUITE_MAP (те же стемы).
- `docs/handoff/w-workflow-step-runner/` — этот отчёт + артефакт mutation-control.
