# CODE-INTEL-SKIPPED-FIFTEEN-TIMES-01 — sonnet-линии сегодня работали вслепую

## Замер (2026-09-04, ведущая)

| строка в журнале за сегодня | сколько раз |
|---|---|
| `code_intel_preamble arm=glm mode=attached` | 1 |
| `code_intel_preamble arm=glm-flash mode=attached` | 2 |
| `code_intel_preamble arm=sonnet mode=skipped reason=fail_open` | **15** |

У GLM код-интеллект (repowise + граф MCP) подключается, а пятнадцать sonnet-линий сегодня
получили преамбулу «пропущено» и пошли работать без индекса — при том, что оба MCP в этом
репозитории живые и отвечают.

`fail_open` — сознательное решение не блокировать линию, когда преамбулу собрать не удалось.
Оно правильное как политика и катастрофическое как молчание: линия уходит вслепую, отчёт об
этом не говорит, и ведущая не узнаёт, что пятнадцать раз за день работа шла без карты.

## Задача

1. **Найти, почему для `arm=sonnet` преамбула не собирается**, тогда как для glm собирается.
   Цифра 15 против 3 не случайна, у неё есть причина в коде.
2. **`fail_open` обязан быть громким**: строка в журнале с ПРИЧИНОЙ (какой вызов упал, с каким
   кодом), а не одно слово.
3. Причину чинить, если она в нашем коде. Если внешняя — описать в отчёте и оставить громкий
   отказ.

## Приёмка

1. **Негативный контроль на каждое изменённое требование**, мутация ВНУТРИ тела функции,
   доказательство — пара `baseline_rc`/`mutated_rc` и красная строка, НЕ `diff_hash`.
   Обязателен контроль: «сборка преамбулы падает» → в журнале видна причина, не голое
   `fail_open`.
2. **Десять прогонов подряд**, все коды возврата в отчёт.
3. Не превращай `fail_open` в `fail_closed` без отдельного предложения в отчёте: молчаливая
   смена политики заблокирует линии там, где сегодня они просто теряют качество.

## Границы

Правь путь сборки код-интеллект-преамбулы и свою сюиту в `plugins/leadv2/scripts/tests/`.
Не трогать: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, `tests/run-all.sh`,
ослабление ассертов. Отчёт — `report.md`.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-1cba2dfa" "<question>" \
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