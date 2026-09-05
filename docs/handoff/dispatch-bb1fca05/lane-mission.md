E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01

Список известных красных сюит не может разблокировать НИ ОДНУ линию: e2e-гейт видит только имя
обёртки run-core-offline.sh, а все 15 записей списка называют вложенные сюиты.
Проверка: `grep -v '^#' tests/known-red-suites.txt | grep -c run-core-offline` → 0.
Обёртки в списке нет и быть не должно — она разрешила бы все 83 вложенные разом.

Задача: гейт должен сопоставлять записи списка с ВЛОЖЕННЫМИ именами сюит, которые реально
падают внутри обёртки, а не с именем обёртки. Разблокировка — только точечная, по вложенному имени.

Негативный контроль: добавь вложенное имя в список, покажи, что линия разблокирована; убери —
покажи, что заблокирована. Плюс: обёртка в списке НЕ должна разблокировать вложенные (докажи).

Запрещено: main; ослабление ассертов; добавление обёртки в known-red-suites.txt.
Перед финишем: git diff --stat main..HEAD — восстанови файлы, которые линия удаляет из-за раннего ветвления.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-bb1fca05" "<question>" \
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