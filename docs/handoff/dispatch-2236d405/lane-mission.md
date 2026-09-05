# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01 — мёртвый арм неотличим от занятого

## Замер (2026-09-04, ведущая)

Фрипул не брал ни одной линии сутки. Причина оказалась не в арме:

    bash plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh   -> [freepool-gate] refused: arm_down
    curl http://127.0.0.1:8317/health                         -> 000, слушателя на порту нет

После `freepool-proxy.sh start` арбитр сразу выбрал фрипул: `arm=freepool chain=freepool,glm
util_freepool=0`, а `/v1/models` отдал **1041 модель** (kimi-k3, nemotron-3-super-120b,
gemini-3.7-flash, gpt-oss-120b).

**Дефект не в том, что прокси упал, а в том, что падение выглядело как загрузка.** Арбитр
получил `util_freepool=100` — то же число, что и у арма, исчерпавшего квоту. Одно число несёт
два разных факта, и ведущая сутки читала «занят» там, где было «мёртв». Ровно та же болезнь,
что и `require_trusted` — один булев на два смысла.

## Задача

1. **Развести «арм не отвечает» и «арм исчерпан» в РАЗНЫЕ наблюдаемые значения** на выходе
   арбитра. Мёртвый арм обязан называться мёртвым в строке решения, а не приезжать числом 100.
2. **Сюита живости прокси фрипула**: порт слушает, `/health` = 200, `/v1/models` непустой.
   Красная, когда прокси лежит.
3. **Громкая строка в журнал при `arm_down`** — сегодня отказ шлюза виден только тому, кто
   вручную запустит шлюз.

Не поднимай прокси автоматически без разрешения — вопрос этой линии в наблюдаемости, а не в
автозапуске. Если считаешь автоподъём правильным, опиши его в отчёте отдельным предложением.

## Приёмка

1. **Негативный контроль на КАЖДОЕ изменённое требование** — правило принято 2026-09-04 после
   линии, где два изменения прикрывались одним контролем. Мутация вставляется ВНУТРЬ тела
   функции, доказательство — пара `baseline_rc`/`mutated_rc` и красная строка, НЕ `diff_hash`.
   Обязателен контроль: «прокси отвечает 000» → сюита живости краснеет и называет причину.
2. **Десять прогонов подряд, не один** — дефект в соседней функции проявлялся 2 раза из 13 и
   только под нагрузкой. Приложи все десять кодов возврата.
3. Сюита обязана быть ВЫБРАНА бегуном: покажи `LEADV2_RUN_ALL_SELECT_ONLY=1` с её именем в плане.

## Границы

Правь `plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh`, `lib/leadv2-route-arbiter.sh`,
свою новую сюиту в `plugins/leadv2/scripts/tests/` и свой каталог handoff.
Не трогать: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, `tests/run-all.sh`,
ослабление ассертов. Отчёт — `report.md`.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2236d405" "<question>" \
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