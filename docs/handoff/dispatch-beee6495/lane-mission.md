# SUITES-MUTATE-LIVE-CONTROL-PLANE-01 — волна 1

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` в этом же репозитории:
там общие правила приёмки, они обязательны.

## Задача

Не меньше четырёх сюит делают `git init` во временном каталоге в подоболочке, но сам тест-процесс туда никогда не переходит. В результате они работают по ЖИВОМУ состоянию линий машины — общему `~/.claude/leadv2-state/leadv2/` — вместо своей песочницы. FOREIGN-PROJECT-ROOT-GUARD-01 (leadv2-dispatch-code.sh:299-323) делает этот провал тихим, поэтому сюита выглядит зелёной, пока портит состояние соседних линий. Подозревается как причина части сегодняшних странностей с линиями.

Дополнительная улика того же дня: подсчёт отказов арбитра дал 1773 `all_arms_capped`, и это оказались строки ПЕСОЧНИЦЫ e2e-гейта, попавшие в общий журнал. На живых данных 430 решений из 450. То есть песочница сюит уже загрязнила измерение, на котором лид строил вердикт. Найди, какие ещё измерения она загрязняет.

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
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-beee6495" "<question>" \
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