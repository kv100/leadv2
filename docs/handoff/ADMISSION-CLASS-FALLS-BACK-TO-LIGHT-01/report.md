# ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01 — класс допуска выводится из признаков; фолбэк строг

## Дефект (замер ведущей, подтверждён в коде)

Цепочка: `leadv2-task-judge.sh::_fallback_estimate` выводит complexity ТОЛЬКО из
числа строк миссии (`<=30 → trivial`, `<=100 → simple`), `leadv2_admission_map_class`
мапит `trivial|simple → Light`, а `Light` на фазовой двери (`_phase_precondition_guard`,
`leadv2-dispatch-code.sh:4079`) даёт режим `warn` вместо `enforce`. Итог: миссия,
правящая `lib/` и диспетчер, но уложившаяся в 100 строк и без ключевых слов,
получала `task_class: Light source: fallback` — задачу, о которой система ничего
не знает, автоматика объявляла простой и пропускала мимо обязательных фаз.

## Изменение

### 1. Вывод класса из наблюдаемых признаков — `lib/leadv2-admission-class.sh`

Новая `leadv2_admission_derive_floor <mission-file> <cost-yaml>` → `floor<TAB>basis`:

| Сигнал | Признак | Пол |
|---|---|---|
| `path:core` | миссия (вне строк-исключений «Не трогать/Do not touch») называет `lib/`, `leadv2-dispatch*` или `hooks/` — runtime control plane | ≥ Standard |
| `cost:class=<X>` | `docs/handoff/<id>/cost-estimate.yaml` прошлой клетки записал свою `classification` (re-entry) | floor = записанный класс |
| `size:<n>` | размер миссии — ЕДИНСТВЕННЫЙ сигнал, который один оправдывает Light (≤100 строк, те же тиры, что у самого фолбэк-оценщика); >100 строк → ≥ Standard | — |

`leadv2_admission_class <explicit> <flagged> <estimate> [<mission-file> <cost-yaml>]`:
при `estimate_source=fallback` сначала выводит пол; класс = max(мап, пол); если
наблюдаемые признаки были (`basis` непуст) — `source=derived`, отличим и от
назначенного руками (`flag`), и от слепого умолчания.

### 2. Смена умолчания — ОСОЗНАННОЕ ИЗМЕНЕНИЕ (именовано по требованию задачи)

`source: fallback` теперь означает «не нашлось НИ ОДНОГО наблюдаемого признака»
(миссия нечитаема, файла стоимости нет) и ведёт к СТРОГОМУ режиму: такой фолбэк
даёт **Standard**, никогда Light. До изменения такой случай давал Light. `fallback`
стал редкостью: почти у каждой миссии есть хотя бы размер (`size:<n>`), и тогда
источник — `derived`, а не `fallback`.

### 3. `source` остаётся в файле класса

Квитанция (`admission-receipt.yaml`) и task-keyed `task-class.yaml` несут
`source:` как раньше; новый словарь источника: `judge | fallback | derived | flag |
task_record | classifier_error`. Тест-лок: derived-квитанция читается обратно,
`source: derived` лежит в обоих файлах.

### Проводка

- `_admission_classify` (`leadv2-dispatch-code.sh`): файл миссии доживает до
  вызова либы; в либу передаётся и путь `docs/handoff/<founder_task_id:-sig8>/cost-estimate.yaml`
  (то же выражение ключа, что пишет `leadv2-cost-estimate.sh` ниже по потоку).
- `_pump_classify` (`leadv2-backlog-pump.sh`): та же передача (без неё строгий
  дефолт либы грубо перевернул бы КАЖДЫЙ pump-фолбэк, а не только знающий-ничего).
- `lib/leadv2-lane-guard.sh` правок не потребовал: `_lv2_class_rank/_canonical`
  уже покрывают словарь классов; карта D1 живёт в `leadv2-admission-class.sh`,
  который его сорсит.
- Явный флаг (`source: flag`) бьёт вывод равного ранга и не деэскалируется;
  вывод может только ПОДНЯТЬ флаг (эскалейт-онли, та же доктрина, что у judge).

## Сюита: `plugins/leadv2/scripts/tests/test-admission-class.sh` (+14 кейсов)

Юнит-уровень либы: lib/-миссия, диспетчер-миссия, малая чистая, строка-исключение,
>100 строк, строгий фолбэк, cost-пол Heavy/Light, judge не трогается выводом,
флаг Standard/Heavy против вывода, флаг Light эскалируется выводом, source=derived
в файлах класса. Door-уровень: проводка `_admission_classify` (fallback-стаб
judge), изолированные корни; task-record пол на re-entry не сломан.

## Десять прогонов подряд

Артефакт: `run-10x.log` (этот каталог). Все 10 — rc=0, pass=42 fail=0.

## Негативные контроли (мутации ВНУТРИ тела функции)

Артефакты: `mutation-control/<run-id>.txt` (этот каталог; пары baseline_rc/mutated_rc
и красная строка — НЕ diff_hash).

| # | Мутация | Файл | Убиваемое требование |
|---|---|---|---|
| M1 | core-path матчер → `if False:` | lib | задача, правящая lib/ и диспетчер, не получает Light |
| M2 | строгий флип `mapped="Standard"` → `"Light"` | lib | knows-nothing фолбэк строг |
| M3 | `floor = max(floor, min(rank, 2))` → `pass` | lib | cost-классификация — пол |
| M4 | escalate-only `>` → `>=` | lib | явный флаг бьёт вывод равного ранга |
| M5 | дверь перестаёт передавать `${mfile}` | dispatch | вывод доходит до двери, а не только до либы |

RESULT-MUTATIONS-PENDING

## Фальсификационный набор

- `bash -n` всех изменённых shell-файлов: DISPATCH_OK / PUMP_OK / LIB_OK / SUITE_OK.
- Встроенный python либы проверен прогонами (py-файлов не менял — `python3 -m py_compile` неприменим; см. ниже).

RESULT-SELF-CHECK-PENDING

## Соседние сюиты

- `test-admission-safety-pin.sh` rc=0, `test-phase-precondition-bootstrap.sh` rc=0,
  `test-brain-class-live.sh` rc=0 (гоняет `_admission_classify` напрямую).
- `test-backlog-pump.sh` — ПРЕДСУЩЕСТВУЮЩИЙ КРАСНЫЙ: суржная копия HEAD без моих
  изменений падает тем же составом имён (артефакт `baseline-pump.log` рядом);
  сюита негерметична — читает живые квота-эндпоинты (`live=1 glm=1% ...`) и
  персистит refusal-state (SUITES-MUTATE-LIVE-CONTROL-PLANE-01, известный класс).
- `tests/run-all.sh --scope changed`: RESULT-RUNALL-PENDING

## Границы

Правил: `lib/leadv2-admission-class.sh`, `_admission_classify` в
`leadv2-dispatch-code.sh`, `_pump_classify` в `leadv2-backlog-pump.sh` (та же
дверь того же дефекта — выход за две названные точки, назван здесь), сюита,
свой каталог handoff. Не трогал: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`,
`tests/run-all.sh`, ассерты не ослаблены (старые кейсы C3b и D1/D2/D6 зелёные без правок).
