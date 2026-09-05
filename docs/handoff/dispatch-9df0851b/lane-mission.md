# ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01 — сложность не выводится, а угадывается в пользу слабого режима

## Замер (2026-09-04, ведущая)

Фазовый режим зависит от класса допуска (`leadv2-dispatch-code.sh:4079`): при неустановленном
`LEADV2_REQUIRE_PHASES` класс `Standard` и выше даёт `enforce`, `Light` — только `warn`.
Каркас рабочий, проверено на двух живых линиях. Но класс берётся так:

    HANDOFF-ANALYSIS-DIES-UNTRACKED-01   task_class: Standard  source: flag
    INVISIBLE-DELIVERABLES-CENSUS-01     task_class: Light     source: fallback

`source: flag` — класс назвала ведущая руками. `source: fallback` — **класс не выведен ни из
чего**, взят умолчанием. И умолчание — `Light`, самый слабый фазовый режим.

Отсюда дефект: **задача, о сложности которой система ничего не знает, автоматически
объявляется простой и пропускается мимо обязательных фаз.** Умолчание обязано быть в сторону
строгости, либо класс обязан выводиться.

## Задача

1. **Вывести класс из наблюдаемых признаков задачи**: размер задания, число и вид затрагиваемых
   путей (`lib/` и диспетчер против `tests/` и `docs/`), признаки safety/publish, оценка
   стоимости — всё это уже лежит рядом в каталоге handoff (`cost-estimate.yaml`, `brain.yaml`).
2. **`source: fallback` обязан стать редкостью, а когда случается — вести к строгому режиму,
   не к слабому.** Смена умолчания — отдельное осознанное изменение, назови его в отчёте.
3. `source` обязан остаться в файле класса: возможность отличить выведенный класс от
   назначенного руками — то, чем поймали этот дефект.

## Приёмка

1. **Негативный контроль на каждое изменённое требование**, мутация ВНУТРИ тела функции,
   доказательство — пара `baseline_rc`/`mutated_rc` и красная строка, НЕ `diff_hash`.
   Обязателен контроль: задача, правящая `lib/` и диспетчер, НЕ должна получать `Light` —
   сломай классификатор, сюита обязана покраснеть.
2. **Десять прогонов подряд**, все коды возврата.
3. **Явный флаг ведущей (`source: flag`) обязан побеждать вывод.** Ручное назначение класса —
   решение человека, автоматика его не перебивает. Прогони контроль и на это.

## Границы

Правь `_admission_classify` и `lib/leadv2-lane-guard.sh`, свою сюиту в
`plugins/leadv2/scripts/tests/`, свой каталог handoff.
Не трогать: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, `tests/run-all.sh`,
ослабление ассертов. Отчёт — `report.md`.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9df0851b" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.