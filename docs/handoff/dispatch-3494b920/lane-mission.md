# TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 — продолжение после падения

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` в этом же репозитории:
там общие правила приёмки, они обязательны.

## Задача

Оба Claude-аккаунта рабочие во всех локальных репо; диспетчер работает с обоими; арбитр учитывает квоты обоих и распределяет нагрузку. Приказ основателя. Учти измеренное: expiresAt в keychain протух на ВСЕХ шести записях, включая живую, — это не признак смерти слота; проверять надо способность получить рабочий токен, а не поле. Отдельно проверь предупреждение same_account: две записи реестра могут вести в один живой аккаунт, тогда двух независимых квот нет, а это несущая опора плана на 15 сентября.

## Приёмка

Красная сюита стала зелёной ИЛИ новая сюита ловит описанный дефект, с негативным
контролем (мутация внутрь тела функции, пара baseline_rc/mutated_rc, красная строка).
Сюита зарегистрирована в EXTRA_SUITE_MAP и раннер её выбирает на `--scope changed`.
Зелено на macOS И в linux-контейнере, оба кода возврата в отчёт.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3494b920" "<question>" \
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