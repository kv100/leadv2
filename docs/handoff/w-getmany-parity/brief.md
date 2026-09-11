# getmany-followup-bot: довести плагин до нашего уровня, с живыми codex и glm

Основатель 2026-09-10: «хочу чтобы там плагин работал так же хорошо как у нас. И там работал и
кодекс и глм». Работу в том репо он закончил, дерево свободно.

## Что уже измерено лидом — не переизмерять, на это опираться

**Маршрутизация там ЖИВАЯ.** Реальный `--no-spawn` диспатч из
`~/Projects/getmany-followup-bot` дал `route_resolved by=arbiter role=worker arm=glm
model=glm-5.3 tier=standard effort=high reason=capability_fit`, с полной телеметрией утилизации
(`util_glm=27 util_codex=47 util_claude=65`) и прогнозом. Codex рассмотрен и отклонён по ЦЕНЕ
(`arm_excluded=codex:price_ratio`), а не по поломке. То есть арбитр, матрица и лестница там
работают, и «codex не работает» — неверная посылка.

**Разрыв по хукам оказался в основном мнимым.** У persona-engine 42 файла в `.claude/hooks/`, но
это **35 собственных файлов репо и лишь 6 симлинков** на канон; сотня канонических хуков
приезжает из самого плагина через `plugins/leadv2/hooks/hooks.json` и действует везде без
установки в репо. Три «устаревших» хука getmany (`leadv2-compress-tool-output`,
`leadv2-phase8-gate.sh`, `leadv2-reflect-enforcer.sh`, все от 2026-05-04) канонического двойника
**не имеют** — это файлы того репо, и трогать их не надо.

**Репо теперь в реестре** (`cross-repo-paths.yaml`), страж одной копии его видит,
`diverged=4 -> 0`, четыре оверрайда объявлены (commit `0751dd93`).

## Подход — ровно три работы, ничего сверх

### 1. Перебазировать трёх агентов (ряд `627824083b9b`)

`.claude/agents/{architect,critic,security-auditor}.md`: mtime 2026-05-06 против канонических
2026-08-25, короче канона (96/109, 69/83, 58/80). Они несут НАСТОЯЩУЮ специфику репо — пути
`docs/PRD.md` и `docs/projects/followup-system/ARCHITECTURE.md`, набор интеграций (Pipedrive
REST, Snov.io/Grinfi Postgres, Anthropic с кешем промпта, Gmail OAuth, Grinfi API, Telegram),
project id графа codebase-memory. Симлинк это уничтожит — не симлинчить.

Взять канонический frontmatter целиком (описание, списки инструментов repowise/graph MCP, `model`,
`effort`) и канонические общие разделы, сохранив специфическую половину тела. После этого файл
остаётся объявленным оверрайдом — строки в `one-copy-exceptions.txt` не трогать.

### 2. Поставить недостающие ПЛАГИННЫЕ хуки

В `.claude/hooks/` у persona-engine шесть симлинков на канон; у getmany из них есть один
(`leadv2-immune-intake-inject.sh`). Поставить симлинками и зарегистрировать в
`.claude/settings.json` два, и только два:

- `plugin-scripts-drift-session-warn.sh` — SessionStart;
- `plugin-scripts-drift-guard.sh` — по тому же событию, что у persona-engine.

Это ровно те стражи, которые не дают плагину разойтись, то есть цель основателя.

**`leadv2-supervisor-mode-reinject.sh` НЕ ставить.** Супервизор снят навсегда (единый режим лида,
приказ 2026-08-17); persona-engine держит его по инерции, и тиражировать мёртвый путь нельзя.
`leadv2-pulse-json.sh` — по решению линии: поставить, если пульс в том репо вообще вооружён; если
нет, не ставить и написать почему.

### 3. Доказать живым диспатчем ИЗ того репо

Не сюитой. Настоящий диспатч из `~/Projects/getmany-followup-bot`, который **спаунит воркера**, и
в журнале видно `route_resolved` и `worker_spawned`. Отдельно показать прогон, где арбитр берёт
**codex** — поднять его долю можно только законно (класс задачи/сложность), а НЕ хардкодом арма
мимо маршрутизации: список исключений руками у нас запрещён.

## Приёмка

- три агента несут И канонические списки инструментов, И специфику репо; страж по-прежнему
  `diverged=0`;
- `plugin-scripts-drift-session-warn.sh` реально срабатывает в новой сессии того репо — показать
  строку вывода, а не факт наличия файла;
- живой диспатч из того репо с `worker_spawned`, и отдельный прогон с `arm=codex`;
- ничего из перечисленного не сломало persona-engine: `leadv2-one-copy-convert.sh --check`
  по-прежнему `diverged=0 regression=0 badlink=0 rc=0`.

## Write set

- `~/Projects/getmany-followup-bot/.claude/agents/*.md`, `.claude/hooks/`, `.claude/settings.json`
- `docs/handoff/w-getmany-parity/report.md`

Не трогать: `one-copy-exceptions.txt`, `cross-repo-paths.yaml`, три собственных хука того репо,
и НИЧЕГО в persona-engine.

Отчёт короткий: по строке вывода на каждый пункт приёмки.
