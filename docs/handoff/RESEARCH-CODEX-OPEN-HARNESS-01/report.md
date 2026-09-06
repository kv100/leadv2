# RESEARCH-CODEX-OPEN-HARNESS-01 — что даёт открытая часть codex — 2026-09-06

Разведка, поведение не менялось. `V=~/.claude/plugins/cache/openai-codex/codex/1.0.4`
(версия 1.0.4). Найденные дефекты заведены строками, не починены.

## 1. Точки расширения, которые он реально даёт

```
ls $V                    # commands/ agents/ skills/ prompts/ schemas/ hooks/ scripts/lib/
cat $V/hooks/hooks.json  # SessionStart, SessionEnd (lifecycle) + Stop (review gate, timeout 900)
```

| поверхность | что там | берём ли |
|---|---|---|
| хуки | SessionStart/SessionEnd + Stop-гейт ревью | нет: Stop-гейт у нас не зарегистрирован |
| подкоманды companion (10) | setup, review, adversarial-review, task, task-worker, status, result, task-resume-candidate, cancel | берём 6 |
| skills (3) | все `user-invocable: false`, включая `gpt-5-4-prompting` | нет |
| agents | `codex-rescue` | да, через свой роутинг |
| schemas | `review-output.schema.json` | нет |
| `scripts/lib` (15 модулей) | state, job-control, tracked-jobs, broker-* | читаем файлы, модули не зовём |

**Окружение точкой расширения не является** — во всём вендорском коде четыре переменных
(`grep -rhoE "process\.env\.[A-Z_][A-Z0-9_]*" $V/scripts --include=*.mjs | sort -u` →
`CLAUDE_ENV_FILE CLAUDE_PROJECT_DIR CODEX_TIMING_V2 SHELL`). Значит всё, что мы настраиваем
через `LEADV2_*`/`CODEX_*`, наше по необходимости, а не дублирование.

### Не берём, а стоило бы — два конкретных

**`task-resume-candidate`** (`codex-companion.mjs:885`) ищет последнюю возобновляемую задачу
ТЕКУЩЕЙ сессии Claude (`filterJobsForCurrentClaudeSession` → `findLatestResumableTaskJob`).
Мы её не зовём ни разу — `grep -c "task-resume-candidate" …/codex-task.sh` → `0`. Прямо про ту
ночь, когда пять воркеров умерли, уже написав код: путь «подобрать свою же незавершённую
задачу» есть, а мы передиспатчиваем с нуля.

**`.in_use/<pid>` — счётчик живых сессий, который вендор не читает.** Каталог ведёт ХОСТ:

```
ls $V/.in_use/                       # 10746 34102 38424 6635 8525  -- пять живых сессий
grep -rl "in_use" $V                 # пусто: вендор его не читает НИГДЕ
```

То есть `handleSessionEnd` рвёт брокер безусловно, хотя рядом лежит готовый ответ на вопрос
«держит ли плагин кто-то ещё». Заведено строкой (§5), не чинил.

## 2. Что у нас есть по незнанию и может быть выброшено

Список короткий, и я не буду его раздувать.

**Прямое чтение хранилища заданий вендора.** `codex-task.sh:545` разбирает питоном
`"$_state_root"/*/jobs/"$_jid".json`, тогда как `lib/job-control.mjs` отдаёт это готовым:
`readStoredJob`, `buildSingleJobSnapshot`, `buildStatusSnapshot`, `enrichJob`.

```
grep -nE "^export (async )?function" $V/scripts/lib/job-control.mjs
sed -n '545,552p' ~/Projects/leadv2/plugins/leadv2/scripts/codex-task.sh
```

Цена не в строках, а в связанности с их форматом на диске. Выбрасывать поспешно нельзя: их
модули — ESM под node, наш слой — bash; переход стоит отдельной линии.

**Больше ничего.** Гипотеза «наш Stop-гейт дублирует вендорский» проверена и неверна:
вендорский односессионный и не знает ни про квоты, ни про армы.

## 3. Чего он не умеет — наше по необходимости

**Уборка мёртвых заданий — её у вендора нет вообще:**

```
grep -rnE "stale|reap|orphan|zombie|timeout" $V/scripts/lib/tracked-jobs.mjs $V/scripts/lib/job-control.mjs
# пусто
```

Задание, чей pid умер, остаётся `running` навсегда. Наш `_codex_reap` и
`~/.claude/hooks/codex-cleanup-stale` — не дублирование, а единственный, кто это делает.

**Ещё, и всё это отсутствует у вендора по построению:** квотные потолки и выбор арма; таймауты
на задание; отображение «уровень → модель»; журнал линии; изоляция по рабочему дереву; доставка
миссии; проверка брокера перед запуском (`_codex_validate_broker`, он же переименовывает
протухшую запись в `broker.json.stale-*`); пин `TMPDIR` (линия
`CODEX-TRANSPORT-DIES-ROOT-CAUSE-01`).

Отдельно: ключ состояния брокера у них — `basename(gitRoot)+sha256(realpath(gitRoot))[:16]`
(`lib/state.mjs:30-44`), то есть один брокер на РЕПОЗИТОРИЙ, а не на задание. Пока мы гоняем
десятки заданий в одном корне (102 на ключе `leadv2`), развязка concurrency остаётся нашей.

## 4. Заведённые строки (не чинил)

- `CODEX-SESSIONEND-IGNORES-THE-INUSE-REFCOUNT-01` — хост ведёт счётчик живых сессий, вендорский
  SessionEnd его не читает и рвёт брокер при живых соседях.
- `CODEX-RESUME-CANDIDATE-UNUSED-01` — есть путь возобновления незавершённой задачи, мы
  передиспатчиваем с нуля.

## 5. Границы

Не запускала вендорские подкоманды ради замера: запуск `task`/`review` диспатчит, а это
разведка. Поэтому «мы не зовём X» доказано по коду вызывающего, а не по логам вендора; модули
`lib/*.mjs` читались, но не импортировались. Поведение не менялось, вендорские файлы только
читались. Общее дерево: без `git add -A`, `reset --hard`, `clean`, `stash`, push.
`SD-CODEX-TMPDIR-PIN-VERDICT-01` в поле зрения: приговор пину через сутки при ≥20 отказов.
