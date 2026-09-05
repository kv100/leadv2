# CODE-INTEL-SKIPPED-FIFTEEN-TIMES-01 — sonnet-линии работали вслепую: причина найдена, fail_open стал громким

## 1. Замер и его происхождение

Замер из брифа (ведущая, 2026-09-04): за день в журнале —
`code_intel_preamble arm=glm mode=attached` ×1, `arm=glm-flash mode=attached` ×2,
`arm=sonnet mode=skipped reason=fail_open` ×15. Я не смог пере-посчитать эти строки
в своём worktree: исторические строки лежат в журнале основного чекаута
(`docs/leadv2/tasks/*/journal.md`), в изолированном lane-worktree их нет — grep по
`docs/leadv2/` этого worktree даёт только `arm=glm mode=attached` ×1. Цифры в этом
отчёте — цитата брифа, не мой повторный замер.

## 2. Причина: структурная асимметрия гейтов, а не флак

Путь сборки преамбулы: `leadv2-dispatch-code.sh:_spawn_worker_body` вызывает
`worker_mcp_preamble_for_arm()` (`plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:221`),
которая для каждой arm решает, собирать ли преамбулу, по СВОЕМУ гейту:

| arm | гейт | default | результат 2026-09-04 |
|---|---|---|---|
| glm / glm-flash / kimi / freepool | `LEADV2_WORKER_MCP` | **1** (`:-1` в lib) | attached 3/3 |
| sonnet | `LEADV2_SUBSESSION_SLIM_MCP` | **0** (`claude-subsession.sh:543` — `if [[ "${LEADV2_SUBSESSION_SLIM_MCP:-0}" == "1" ]]`) | skipped 15/15 |

`LEADV2_SUBSESSION_SLIM_MCP` — opt-in флаг лаунчера `claude-subsession.sh` (default 0
нужен LEAD-пути эскалации, где дочерняя сессия наследует полный дефолтный MCP-набор и
role-scoped конфиг не собирается). Но этот же флаг lib использует как гейт для arm=sonnet,
и **никто никогда не выставлял его для диспатч-воркеров** — диспетчер sonnet-линию
запускал без преамбулы всегда, не иногда. Отсюда 15 против 3: у glm гейт default-1
закрывает всю популяцию, у sonnet гейт default-0 не был выставлен ни для кого.

Молчание усугубляло: каждый rc!=0 в lib возвращал голый код, диспетчер писал
`mode=skipped reason=fail_open` без единого байта о том, ЧТО именно не собралось —
гейт выключен, resolve упал или файл преамбулы отсутствует, было неотличимо.

## 3. Фикс

### 3a. Sonnet-гейт для диспатч-воркеров = default 1

`plugins/leadv2/scripts/leadv2-dispatch-code.sh:5303-5305` — один локальный `_ci_slim`,
посчитанный ДО вызова, гоняет ОБЕ точки (prediction-вызов lib и строку spawn
`:5535`, её prefix-присваивание `LEADV2_SUBSESSION_SLIM_MCP=...:-1`), так что
предсказание и реальный spawn не могут разойтись:

```bash
local _ci_slim="${LEADV2_SUBSESSION_SLIM_MCP:-}"
if [[ "${arm}" == "sonnet" && -z "${_ci_slim}" ]]; then
  _ci_slim=1
fi
```

Фикс в диспетчере, НЕ в `claude-subsession.sh`: default-0 лаунчера остаётся для
LEAD-пути, диспатчнутый sonnet-воркер получает гейт 1. Явный env по-прежнему
побеждает: `LEADV2_SUBSESSION_SLIM_MCP=0` возвращает старый spawn — громко (см. 3b).

### 3b. Громкий fail_open

Каждый rc!=0-бранч lib печатает ровно одну машиночитаемую строку в stderr
(`plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:224,236,248,261,276,295`):

```
[worker-mcp] preamble_skip_cause=<token>
```

таксономия: `codex_no_mcp_wiring` (rc=4) · `gate:LEADV2_SUBSESSION_SLIM_MCP=<v>` ·
`gate:LEADV2_WORKER_MCP=<v>` · `mktemp_scratch_failed` · `resolve_role_mcp_config_rc=<N>`
(11 no-allowlist / 12 ничего не зарезолвилось / 13 malformed / 14 нет python3 / 15 write
failure) · `preamble_file_missing:<path>`. stdout на скипе пуст, как и раньше — cause
это метаданные, не текст, который видит воркер.

Диспетчер (`:5311-5319`) капчурит stderr вызова в temp-файл, извлекает токен и пишет
его в журнал: `... mode=skipped reason=fail_open cause=<token>`. Пустая причина сама
себя выдаёт: `cause=no_cause_reported` — тишина больше не является приемлемым
объяснением скипа.

### 3c. Политика НЕ перевёрнута

`fail_open` остался fail_open: ни один скип не блокирует линию. Отдельное предложение
в отчёте (не реализовано, требует решения ведущей): сделать `cause=` метрикой —
если за день копится N≥10 строк `cause=resolve_role_mcp_config_rc=*` по одному репо,
поднимать вопрос, а не глотать; блокировку линий я не вводил сознательно.

## 4. Приёмка

### 4.1 Негативные контроли (мутации ВНУТРИ тел функций, пары rc, НЕ diff_hash)

Сюита `plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh`, вывод прогона:

```text
[TEST] PASS: NC1 lib body: baseline_rc=0 mutated_rc=1 — RED, cause-less skip cannot return silently
[TEST] PASS: NC2 dispatcher body: baseline_rc=0 mutated_rc=1 — RED, default-attach cannot silently vanish
[TEST] PASS: NC3 dispatcher body: baseline_rc=0 mutated_rc=1 — RED, bare fail_open cannot return
```

- **NC1** (обязательный контроль «сборка преамбулы падает → в журнале видна причина,
  не голое fail_open»): из тела sonnet-бранча lib удалён `printf ... preamble_skip_cause=gate:...`
  → проверка «stderr несёт cause-токен» красная (baseline_rc=0 / mutated_rc=1).
- **NC2**: из тела `_spawn_worker_body` удалён sonnet-default `_ci_slim=1` →
  D1 (default-attach: journal `mode=attached`, spawn-env `SLIM_MCP=1`, mission несёт
  преамбулу) красная.
- **NC3**: из emit-строки вырезан `cause=${_ci_cause}` → D2 (громкий скип с
  `cause=gate:LEADV2_SUBSESSION_SLIM_MCP=0`) красная — ровно то молчание
  2026-09-04, возвращённое на место.

### 4.2 Десять прогонов подряд

```text
run 1: rc=0 (TOTAL: PASS=17 FAIL=0) 16s
run 2: rc=0 (TOTAL: PASS=17 FAIL=0) 18s
run 3: rc=0 (TOTAL: PASS=17 FAIL=0) 20s
run 4: rc=0 (TOTAL: PASS=17 FAIL=0) 16s
run 5: rc=0 (TOTAL: PASS=17 FAIL=0) 18s
run 6: rc=0 (TOTAL: PASS=17 FAIL=0) 22s
run 7: rc=0 (TOTAL: PASS=17 FAIL=0) 23s
run 8: rc=0 (TOTAL: PASS=17 FAIL=0) 20s
run 9: rc=0 (TOTAL: PASS=17 FAIL=0) 16s
run 10: rc=0 (TOTAL: PASS=17 FAIL=0) 15s
```

10/10 rc=0, PASS=17 FAIL=0 в каждом.

### 4.3 Затронутая существующая сюита

`test-worker-mcp-all-arms.sh` (обновлён только needle её мутационного контроля под
новую строку вызова): `rc=0`, `TOTAL: PASS=49 FAIL=0`.

### 4.4 Регистрация сюиты

`tests/run-all.sh` не трогал (граница миссии). Сюита выбирается self-select конвенцией
стемов: изменённый `scripts/lib/leadv2-worker-mcp.sh` даёт кандидата
`test-leadv2-worker-mcp.sh` (совпадение по стему), плюс любой изменённый
`plugins/leadv2/scripts/tests/test-*.sh` выбирает себя сам. Живая проверка:

```text
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep -E 'SELECT.*worker-mcp|selected'
[SELECT] .../plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh
run-all: 36 selected, scope=changed, select_only=1
```

### 4.5 Falsification-сет

```text
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh; echo $?
0
$ /bin/bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh; echo $?   # macOS 3.2 floor
0
$ bash -n plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh; echo $?
0
$ /bin/bash -n plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh; echo $?
0
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh; echo $?
0
```

Python-файлы этой ланией не менялись — `py_compile` не применим (в сюите bash 3.2-floor
на все три файла включён как постоянные проверки).

## 5. Changed-scope раннер

<!-- RUNNER-OUTPUT: вставляется после завершения прогона, до коммита -->

## 6. Изменённые файлы

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — sonnet-default гейт + громкий cause= в emit
- `plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh` — `preamble_skip_cause` на каждом rc!=0
- `plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh` — новая сюита (17 проверок, 3 NC)
- `plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh` — needle мутационного контроля
- `report.md` — этот отчёт (перезаписал чужой артефакт PHASE-BOOTSTRAP-DEADLOCK-01,
  унаследованный от main в lane-анкере; миссия требует report.md в корне)
