# E2E-GATE-BROKE-TODAY-01 — раунд 3, финишёр. Работа сделана, не хватает доказательств

Раунд 2 сделал ровно то, что просили, и обосновал построчно. Коммит `44174d48` (авточекпойнт при
выходе воркера, `run-core-offline.sh`, +59/−4): из 11 маркеров `|||SERIAL` **четыре сняты** —
`test-worktree-lane-safety.sh`, `test-fanout-classify-guard.sh`, `test-report-only-gate.sh`,
`test-prepass-resume-invalidate.sh`, каждый изолирован через mktemp/`LEADV2_STATE_ROOT`/
`LEADV2_PROJECT_ROOT` и отсутствует в `_CORE_OFFLINE_OWNED_SUITES`, поэтому песочница `$HOME`
внутри `run_check` их и так разводит. **Семь оставлены**, у каждого своя причина в одну строку;
пять из них пишут в настоящий `REPO_ROOT/docs/leadv2`, и проверка герметичности сравнивает тот же
самый рабочий каталог через `git status` — параллельный сосед приписал бы свою грязь чужой сюите.

Это грамотный разбор, переделывать нечего. **Не трогай сам разбор и не снимай оставшиеся семь
маркеров.** Не хватает только доказательств.

## Что сделать

1. **Живая проба, с нагрузкой рядом.** Прогони гейт на линии с одним изменённым файлом и покажи
   время вместе с `uptime` в тот же момент. Проба без нагрузки ничего не значит: сегодня гейт
   укладывался при load 17 и не укладывался при 49. Если уложился — назови обе цифры.
2. **Негативный контроль.** Верни любой из четырёх снятых маркеров обратно в последовательный
   хвост — время прогона обязано вырасти, сюита покраснеть. Доказательство — пара
   `baseline_rc`/`mutated_rc`, снятая с прогонов. **Не `diff_hash`** (он у нас врёт), **не вывод
   из вердикта инструмента**, и **не совпадение по тексту сообщения**: контроль обязан ломать
   последствие. Проверка проверки: убери ассерт на текст, оставь ассерт на состояние — контроль
   обязан остаться красным.
3. **Десять прогонов подряд**, все коды возврата. Раунд 1 честно написал, что не осилил это по
   бюджету; если и у тебя не выйдет — напиши так же прямо и приложи, сколько получилось. Один
   прогон вместо десяти не подходит: сегодня партия из десяти вскрыла настоящую гонку продукта,
   которую один прогон показал бы зелёной в 85% случаев.
4. **Отчёт — в `docs/handoff/dispatch-<sig>/developer.full.md`**, как раунды 1 и 2. Туда же
   таблицу: какие четыре маркера сняты, какие семь оставлены и почему.

## Границы

Правь `plugins/leadv2/scripts/tests/run-core-offline.sh`, свою сюиту, свой каталог handoff.
`tests/run-all.sh` НЕ трогай — файл общий, на нём сериализуются линии трёх сессий; строку
`EXTRA_SUITE_MAP` положи готовой в отчёт с прямой оговоркой, что CI её пока не отбирает.

Не трогать: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, ослабление ассертов.
Работа раунда 2 лежит коммитом на ветке — не переписывай её, дополняй.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3dd21396" "<question>" \
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