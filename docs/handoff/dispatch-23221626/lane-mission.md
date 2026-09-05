# LANE-WRITES-IS-EMPTY-98-PERCENT-01 — одно пустое поле гасит пять механизмов

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` — общие правила приёмки.

## Замер, с которого всё начинается

`LEADV2_DISPATCH_LANE_WRITES` — набор путей, которые линия собирается писать. Он пуст
почти всегда. Перепись по всей истории диспатчей (сессия fb, 2026-09-03):

```
237  protection_derived by=router ... writes=<none>
  3  writes=tests/freepool-probe.sh,docs/handoff/FREEPOOL/report.md
всего 241 -> пусто в 98,3%
```

Второй источник того же факта пуст полностью: строк `Reads:` / `Writes:` / `Touches:`
нет ни в одной из 324 миссий линий.

## Что от этого поля зависит — пять мест, все ломаются молча

1. **Защита задачи по путям записи.** Решение основателя от 2026-09-03 (см.
   `docs/handoff/SMART-ARBITER-01/brief.md` §10): защищённость определяется путями, а не
   прозой. При пустом поле `flag_source=path` не сработает НИ РАЗУ, защита деградирует
   обратно к прозе — к матчеру с 18 ложными срабатываниями из 19.
2. `pc_precheck_writes` (`leadv2-dispatch-product-close.sh:1803`) —
   `[[ -n "${WRITES_CSV:-}" ]] || return 0`: выходит сразу, оставив `_PC_SCOPE_WRITES_CSV` пустым.
3. `pc_stop_gate_autocommit` (`:1911`) — `[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0`:
   выключается тем, что предыдущая функция ему не заполнила. **Автокоммит не запускается вообще.**
   Пункты 2 и 3 — каскад: одно пустое поле гасит весь путь чекпоинта.
4. `_dl_derive_lane_state` — проба на грязное рабочее дерево ограничена pathspec по
   `lane_writes`, поэтому `dirty` не выставляется никогда и линия проваливается в `dead`
   без спасения.
5. `leadv2_writeset_missing` (`lib/leadv2-mission-writeset.sh:134`) —
   `[[ -n "${required}" ]] || return 0`: проверка набора записи молча пропускается.

Класс этих отказов описан отдельной строкой `GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01`:
страховка, молча выключающая себя на пустом входе, неотличима от страховки, которая
отработала и ничего не нашла. Эта задача чинит их ПИТАНИЕ, а не сами страховки.

## Задача

Сделать так, чтобы набор путей записи линии реально заполнялся на диспатче. Источник
выбери сам и обоснуй: объявление в миссии, вывод из брифа, вывод из области задачи, или
комбинация с явным полем происхождения. Требования:

- происхождение набора — **явное поле**, а не зашитое поведение, чтобы приоритет
  источников менялся списком в одном месте;
- пустой набор должен оставаться выразимым и означать «неизвестно», а НЕ «ничего не пишем»:
  страховки выше обязаны на нём переходить к неограниченной проверке или громко отказывать,
  но никогда к тихому пропуску;
- заполнение не должно требовать, чтобы автор миссии помнил про синтаксис: 324 миссии из
  324 его не содержат — это доказательство, что правило, которое надо помнить, не работает.

## Приёмка

1. Доля строк с непустым `writes=` на НОВЫХ диспатчах выше 90% (сегодня 1,7%). Покажи
   замер до и после одной и той же командой.
2. Фикстура: миссия, пишущая `agent/safety/pre-execute.sh`, даёт `flag_source=path` и
   защищённый маршрут. Сегодня она уходит недоверенной руке — это измеренный ложный
   отрицательный результат основателя.
3. Фикстура пустого набора: страховки НЕ пропускаются молча — либо неограниченная
   проверка, либо явный отказ с причиной в журнале.

Негативный контроль: мутация ВНУТРЬ тела функции, заполняющей набор (вернуть пустую
строку), — приёмочные фикстуры 1 и 2 обязаны покраснеть. Доказательство — пара
baseline_rc/mutated_rc и красная строка, НЕ diff_hash.
Сюиту зарегистрировать в EXTRA_SUITE_MAP и доказать `--scope changed`, что раннер её
выбирает. Зелено на macOS И в linux-контейнере.

## Границы

`leadv2-dispatch-code.sh` держит лид: в нём сейчас две чужие очереди правок (замена цепочки
`lead_session_id` и эта задача). Если твоё решение требует правки этого файла — опиши
точное место и текст в отчёте, правку сделает лид. Всё остальное пиши сам.
Не трогать: `main`, `tests/known-red-suites.txt`, ослабление ассертов, `.gitignore`
(решение принято: список не расширяем, норма — `git add -f` плюс проверка `git ls-files`).

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-23221626" "<question>" \
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