# MAIN-CORE-SUITE-RED-01 — красные сюиты на main плагина

## Почему эта линия важнее своего размера

Пока main красный, КАЖДАЯ соседняя линия ловит `e2e_regression` за поломку, которую она не
вносила. `WATCHER-LIFECYCLE-LEAK-01` сжёг на этом три раунда починки: линия честно чинила чужую
красноту. Леджер (`SD-MAIN-CORE-SUITE-RED-01`, просрочен, одобрен основателем 2026-09-01) называет
**16 красных из 85** — это число ты обязана перепроверить, а не унаследовать.

## Порядок

1. **Снять честное число ДО одной процедурой.** `bash plugins/leadv2/scripts/tests/run-all.sh`,
   полный прогон, в переднем плане. Запиши команду и её вывод — не пересказ.
   Ноль здесь ничего не значит без ненулевого контроля: в том же прогоне должна быть хотя бы одна
   PASS-сюита. Если раннер сам падает — это отказ ПРИБОРА, и он записывается как отказ прибора, а
   не как «сюиты зелёные».
2. **Разложить каждую красную ровно на три кучи**, письменно, по одной строке на сюиту:
   - **сюита врёт** — утверждает то, чего продукт никогда не обещал, или проверяет строку вместо
     поведения;
   - **сюита не герметична** — зависит от живого пульта, домашнего каталога, времени, сети,
     чужой линии;
   - **продукт сломан** — настоящий дефект. Такие НЕ чинить здесь: завести строку и назвать её.
   Четвёртая куча разрешена и обязательна, если честно: **не смогла определить**.
3. **Судить неслитую ветку ПО СОДЕРЖИМОМУ.** `salvage/SD-MAIN-CORE-SUITE-RED-01` — 2 коммита,
   2 файла: `plugins/leadv2/scripts/leadv2-review-run.sh` (+10-3),
   `plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh` (+8-1).
   `git diff main...salvage/SD-MAIN-CORE-SUITE-RED-01`. Сегодня уже был случай, когда ветка
   выглядела недоделкой, а на деле была УСТАРЕВШЕЙ, и слияние вернуло бы снятый дефект. Ответь
   по каждому из двух файлов: новее или старше main по существу, и что именно вернётся.
4. **Чинить.** `tests/known-red-suites.txt` и `known-failures.txt` могут только СОКРАЩАТЬСЯ —
   добавить туда сюиту вместо починки запрещено.
5. **Число ПОСЛЕ — тем же раннером, из одной процедуры**, не из реконструкции.

## Границы, объявляемые ДО замера

Назови их в отчёте прежде чисел: какие сюиты раннер вообще не выбирает, что ты считаешь одной
сюитой, что делаешь с зависшей (таймаут — это тоже исход, а не «медленно»).

## Запреты

Никогда `git add -A`, `git reset --hard`, `git clean`, `git stash` — дерево общее, по нему идут две
другие сессии. Не пушить в origin. Не трогать `lane-pulse-watch` и `single-lead-beat-loop` — идёт
окно наблюдения. Не трогать `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` (владелец — s1) и
`plugins/leadv2/config/leadv2-routing.yaml` (владелец — s2).

## Результат

`docs/handoff/MAIN-CORE-SUITE-RED-01/report.md`: число до и после из одной процедуры, объявленные
границы, таблица трёх куч по каждой красной сюите, вердикт по ветке пофайлово.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-77919011" "<question>" \
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