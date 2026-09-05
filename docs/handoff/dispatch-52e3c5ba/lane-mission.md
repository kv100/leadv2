# DARK-SUITES-UNREACHABLE-BY-RUNNER-01 — волна 1

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` в этом же репозитории:
там общие правила приёмки, они обязательны.

## Задача

Из 23 сюит, на которые опирается план, раннер `tests/run-all.sh` видит только 9. Остальные 14 существуют, часть из них красные, и CI их не увидит никогда. Нужны строки в EXTRA_SUITE_MAP и доказательство через `--scope changed`, что раннер ВЫБИРАЕТ каждую из них на изменение соответствующего файла.

Приёмка не «строка добавлена», а «на изменение файла X раннер выбрал сюиту Y» — покажи вывод `--scope changed` по каждой из 14. Зелёная сюита, которую CI не запускает, стоит ноль: `tests/contract/publish-end-to-end.sh` неделями убивала мутацию публикации, пока у раннера вообще не было отображения на `tests/contract/`.

## Приёмка

Негативный контроль: мутация ВНУТРЬ тела функции (не на верхний уровень файла),
сюита красная, откат, зелёная. Доказательство — пара baseline_rc/mutated_rc и
красная строка, НЕ diff_hash.
Сюита зарегистрирована в EXTRA_SUITE_MAP и раннер её выбирает на `--scope changed`.
Зелено на macOS И в linux-контейнере, оба кода возврата в отчёт.

## Сохранность работы

Файл считается сохранённым не когда он записан в `docs/handoff/`, а когда он виден
в `git ls-files`. `.gitignore:49` игнорирует `docs/handoff/*/*`, разрешающий список
пропускает только `report.md`, `brief*.md` и `round*-red`; всё остальное `git add`
глотает МОЛЧА — коммит проходит, файла в нём нет. Поэтому: `git add -f`, и потом
проверь `git ls-files` глазами, а не кодом возврата `git add`.
Коммить часто, маленькими шагами: незакоммиченная работа — единственное, что
падение может отнять.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-52e3c5ba" "<question>" \
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