# PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01 — отказ по фазам занимает линию навсегда

## Замер

Диспатч сначала **регистрирует** линию в `docs/leadv2/active.yaml`, потом упирается в гейт фаз
и выходит с отказом — а на выходе освобождение **пропускается**. Из живого лога:

```
ERROR: dispatch refused: missing mandatory phases: diverge,plan,gate
active_lane_release_skipped ... where=exit_trap reason=not_owner_row_intact
```

Строка остаётся в реестре навсегда. Каждый следующий диспатч получает `lane_is_live`, причём
счётчик растёт (`starting:60`, `starting:163`, …), а не истекает. Ожидание не помогает никогда.

**Механизм точнее, чем «не считает себя владельцем».** Проверка владения на пути освобождения
(`leadv2-dispatch-code.sh:4555`) начинается так:

```python
rows = [row for row in data["sessions"] if row.get("task_id") == task_id]
if len(rows) != 1:
    sys.exit(2)          # -> active_lane_release_skipped reason=not_owner_row_intact
```

У заблокированной линии было **две** строки. При двух строках сравнение session/pid до второго
условия даже не доходит: освобождение невозможно НИКОГДА, независимо от того, кто владелец.
Измерено 2026-09-03 на `CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01`: две строки,
`pid_role=lead_durable`, обе с `pid: 79117` — pid **интерактивной сессии**, не воркера.
Разблокировали вручную через `leadv2_active_unregister`; 33 воркерские строки не пострадали.

## Задача

Три требования. Первое — обязательное, остальные два вытекают из механизма.

1. **Путь отказа по фазам обязан освобождать линию.** Линия, зарегистрированная этим же
   диспатчем и отказанная до подъёма воркера, не должна оставаться в реестре.
2. **Дубликат строк для одной линии — сама по себе ошибка.** Сейчас он молча превращает линию
   в вечную. Он обязан быть виден: журнальная строка с числом найденных строк, а не тихий
   `exit 2`, неотличимый от «строка чужая».
3. **Живость нельзя решать одним «PID жив».** Записанный PID может принадлежать интерактивной
   сессии (`claude --dangerously-skip-permissions`), а не воркеру (`claude -p`) — именно это и
   случилось. К паре (PID, время старта) добавь признак ВИДА процесса.

Решай сам, освобождать ли на отказе или не регистрировать до прохождения гейта — но обоснуй
выбор в отчёте. Второй вариант выглядит чище, у него могут быть последствия для гонки за слот.

## Приёмка

1. **Негативный контроль на КАЖДОЕ изменённое требование, и ты их прогоняешь.** Не «есть
   контроль», а контроль на каждую изменённую функцию: линия D3 сегодня показала, что дифф на
   две функции с одним контролем оставляет половину без единого утверждения за спиной.
   Мутация вставляется ВНУТРЬ тела функции, не на верхний уровень файла. Доказательство — пара
   `baseline_rc`/`mutated_rc` и красная строка, НЕ `diff_hash`.
2. Сюита зарегистрирована в `EXTRA_SUITE_MAP` в `tests/run-all.sh` и раннер её ВЫБИРАЕТ.
   Доказывай дампом плана раннера (`LEADV2_RUN_ALL_SELECT_ONLY=1`) на НАСТОЯЩЕЙ правке с
   последующим откатом — не через `touch`, его git не видит вовсе.
3. Ни один живой воркер не должен освобождаться этим кодом. Отдельный контроль: строка с
   `pid_role=worker` и живым процессом обязана пережить путь освобождения.

## Границы

Правку `tests/run-all.sh` делай ТОЛЬКО дописыванием строки; не переформатируй и не двигай
существующие — другие линии дописывают туда же. Файл подменяй через временный и `mv`, а не
правкой на месте: bash читает скрипт по мере выполнения.

Помни: правка плагинного скрипта внутри линии **не влияет на живой диспетчер** — кэш плагина
это отдельный настоящий файл. Значит твою починку нельзя проверить «на работающей системе»
изнутри линии; проверяй сюитой на своей копии и скажи это прямо в отчёте.

Не трогать: `main`, `docs/leadv2/` (реестр, шина, замки, очередь слияний — правка изнутри линии
откатывает чужую работу), `tests/known-red-suites.txt`, ослабление ассертов.
Отчёт клади в `docs/handoff/PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01/report.md` — под этим
именем `.gitignore` его пропустит; любое другое имя исчезнет молча.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b7432c91" "<question>" \
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