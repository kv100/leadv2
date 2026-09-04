# BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01 — census (Step 1, до правки)

Дата: 2026-09-04. Все ссылки file:line — по worktree линии (branch
`worktree-BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01`, anchor f354a6ba), если не сказано иное.
Файлы persona-engine читались read-only в `~/Projects/persona-engine` (main checkout).

## Посылка миссии — проверена, живая

`leadv2-phase8-close.sh` (738 строк, весь файл прочитан) не содержит НИ ОДНОГО вызова
репо-нативного `scripts/task-close.sh`: единственные упоминания — комментарии зеркальной
гарды (`plugins/leadv2/scripts/leadv2-phase8-close.sh:81` и `:99`). Скрипт эмитит
ledger-событие `task_close` (`:468-476`, payload на `:473`) и останавливается. Механизм
закрытия строки существует и работает на другой стороне: `scripts/task-close.sh`
(persona-engine) пишет в Supabase RPC `public.human_close_work_items`
(`~/Projects/persona-engine/scripts/task-close.sh:1-9`), строка исчезает из зеркала
`docs/tasks.yaml` при следующем `scripts/task-sync-yaml.sh`. Дыра ровно одна и ровно там,
где сказала миссия. Продолжаем.

## Q1 — откуда phase8-close узнаёт ИМЯ задачи основателя

`TASK_ID` приходит аргументом 1 или из `LEADV2_TASK_ID`
(`plugins/leadv2/scripts/leadv2-phase8-close.sh:51`).

Пути закрытия и вид `TASK_ID` на каждом:

1. **Диспатченная линия.** `spawn_worker` запускает session-runner с
   `--task-id "dispatch-${sig8}"` (комментарий-контракт:
   `plugins/leadv2/scripts/leadv2-dispatch-code.sh:242`, повторено `:3172`; живой вызов
   `:4019`). Runner экспортирует его как `LEADV2_TASK_ID`
   (`plugins/leadv2/scripts/leadv2-codex-session-runner.sh:25`, `:44`; kimi-аналог
   `:369-373`). Значит фазу-8 воркер закрывает под сигнатурой `dispatch-<sig8>`, а строка
   бэклога заведена на имя основателя. Посылка миссии подтверждена.
2. **Интерактивный лид.** Лид гонит фазы 0..8 сам
   (`plugins/leadv2/codex-skills/source-command-leadv2/SKILL.md:29`, `:49`) и зовёт
   `leadv2-phase8-close.sh <task_id>` с тем именем, под которым задача заведена, — здесь
   `TASK_ID` сам и есть имя задачи основателя.

Где связка `sig8 → founder_task` доступна НА МОМЕНТ ЗАКРЫТИЯ (все кандидаты):

| Источник | Что несёт | Доступен на каждом пути закрытия? |
|---|---|---|
| Журнал линии | строка `dispatch_task_bound task=<sig8> founder_task=<ID>` | **ДА** — пишется при каждой привязке диспатча (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:7186`) в `${PROJECT_ROOT}/${leadv2_dir}/tasks/dispatch-${sig8}/journal.md` (`plugins/leadv2/scripts/leadv2-journal.sh:42-43`; `leadv2_dir` из state-paths override, `:21-23`) |
| `HANDOFF_DIR` (`docs/handoff/${TASK_ID}`, `:59`) | только фазовые артефакты линии (flags, e2e-логи); founder-имени в машиночитаемом виде нет | нет |
| Переменные окружения воркера | только `LEADV2_TASK_ID=dispatch-<sig8>`; `DISPATCH_FOUNDER_TASK_ID` живёт в процессе диспатчера (`dispatch-code.sh:7190-7192`) и уходит в ledger-строку, в env воркера не попадает | нет |
| `active.yaml` | строка key'ed на `task_id`; для ensured-линий это founder-имя, для диспатченных — `dispatch-<sig8>` (живой пример обоих: строки `BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01` и `dispatch-c4c38811` в `~/.claude/leadv2-state/leadv2/active.yaml`); отдельного поля founder нет | нет |
| dispatch-ledger | `founder_task_id` в терминальной строке (`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:19`) | нет — пишется терминалом ДИСПАТЧА, на интерактивном пути отсутствует |

**Тонкость корня (проверено живьём):** журнал пишет ДИСПАТЧЕР в СВОЙ `PROJECT_ROOT`
(main checkout), а закрытие бежит в lane worktree, названном по founder-задаче
(`dispatch-code.sh:3220-3223`), т.е. `PROJECT_ROOT` ≠ main. Живой замер по ЭТОЙ линии:
binding лежит в `~/Projects/leadv2/docs/leadv2/tasks/dispatch-96d97702/journal.md`
(`dispatch_task_bound task=96d97702 founder_task=BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01`),
в worktree линии файла `docs/leadv2/tasks/dispatch-96d97702/` НЕТ; `git rev-parse
--path-format=absolute --git-common-dir` из worktree даёт main checkout. Поэтому чтение
журнала обязано пробовать ДВА корня: `PROJECT_ROOT`, затем git-common-dir root — тот же
durable-root приём, которым скрипт уже пользуется для learn-counter
(`leadv2-phase8-close.sh:492-504`, MEM-WRITE-PATH-FIX-01).

**Решение Q1:** `TASK_ID` без префикса `dispatch-` → founder = сам `TASK_ID`.
`dispatch-*` → последняя строка `dispatch_task_bound` из журнала (два корня; последняя
побеждает — ретраи перепривязывают, тот же "newest wins", что в
`plugins/leadv2/scripts/leadv2-lane-detail.sh:81-105`). Нет binding — лог, строку не
трогаем.

## Q2 — имя задачи → fingerprint строки

- Строка зеркала: `id` = короткий id (первые 12 символов `work_items.fingerprint`;
  `~/Projects/persona-engine/scripts/task-sync-yaml.sh:93`), `intent` начинается с имени
  задачи основателя, отделённого двоеточием (живой пример: `intent: 'E2E-GATE-…-01:
  список…'` в `docs/tasks.yaml` persona-engine).
- Резолвер «name → строка» УЖЕ существует как общий модуль плагина:
  `plugins/leadv2/scripts/leadv2_tasks_yaml_common.py` — `row_matches()` (`:57-76`,
  colon-anchored prefix, «never a substring»: `V5-M1` не матчит `V5-M10:`),
  `load_tasks_items()` (`:79-102`, толерантен к mapping-форме
  `{"total_open": N, "tasks": [...]}`). Его `resolve_task()` (`:105-127`) неоднозначность
  НЕ считает — мой код считает сам через `row_matches`: **0 совпадений и ≥2 совпадений —
  оба не закрывают ничего и оба логируются**; ровно 1 → берём `id`.
- Второй рубеж уже в репо-нативном скрипте: `task-close.sh` резолвит shortid серверно
  (`fingerprint=like.<shortid>*`; 0 → `not_found`, ≥2 → `ambiguous`, ни одно не закрывается;
  `~/Projects/persona-engine/scripts/task-close.sh:27-37`, код `:153-180`).

## Q3 — пути закрытия и какие исходы имеют право снять строку

- `leadv2-phase8-close.sh` — единственный скрипт закрытия линии; его исход —
  `OUTCOME = LEADV2_OUTCOME`, дефолт `completed_success` (`:66`). Канонический набор
  «успехов» уже определён в системе: `SUCCESS_OUTCOMES = {"completed_success",
  "completed_with_warnings"}` (`plugins/leadv2/scripts/leadv2-daemon.sh:480`; фиксация
  `completed_success` как success-значения — `leadv2-phase8-assert.sh:265-285`).
- **refused** и **no_work** — исходы ДИСПАТЧ-терминала, не phase8: enum терминалов
  `landed|pass_unlanded|parked|refused|dead|dead_with_unlanded_work|no_work`
  (`leadv2-dispatch-ledger.sh:19`); `no_work` рождается в канале kimi
  (`kimi-coder.sh:587`, контракт `dispatch-code.sh:6009`). На этих терминалах воркера нет —
  phase8-close не вызывается. Но защита обязана стоять В phase8-close: `LEADV2_OUTCOME`
  приходит из env (`:66`), и задача мутационного контроля (б) требует красного на
  refused.
- **Правило:** строка закрывается ТОЛЬКО при `OUTCOME ∈ {completed_success,
  completed_with_warnings}`; любой другой исход — лог, строка не тронута. Закрытие
  неуспехом сделало бы бэклог врущим в другую сторону.

## Q4 — что уже пыталось это делать и почему не сработало

- `git log -S "task-close.sh" -- plugins/leadv2/scripts/leadv2-phase8-close.sh` — ровно
  ОДИН коммит: `d8fce274` (CLOSE-GATE-BYPASSABLE-BY-ENV-01). Он добавил зеркальную гарду
  (refuse close, если diff трогает `docs/tasks.yaml`; строки `:76-102`) и в КОММЕНТАРИИ
  назвал правильный путь — «close via scripts/task-close.sh» (`:81`, `:99`) — но вызова не
  добавил. Попытку не снимали: её не было. Причины снятия нет.
- На стороне persona-engine: HUMAN-CLOSE-RPC-01 построил `task-close.sh` (RPC-обёртка,
  `--reopen`, shortid-резолвер) и РУЧНОЙ процесс — `docs/leadv2/scheduled-decisions.md`
  учит закрывать строки руками («close the dead ones with `scripts/task-close.sh
  --from-file`»). Автоматизации на закрытии линии нет нигде: grep по плагину даёт только
  комментарии, вызовов нет. Ручной путь и есть наблюдаемый «closing is manual».
- **Попутная находка (риск, вне скоупа):** в persona-engine есть устаревшая РЕАЛЬНАЯ
  git-tracked копия `scripts/leadv2-phase8-close.sh` (разошлась с каноном — в ней нет
  exit-5-обработки). Живой путь исполнения — симлинк
  `persona-engine/.claude/scripts/leadv2-phase8-close.sh` → канон плагина (проверено
  `ls -la`), копия в корне репо — мёртвый остаток. Но если её когда-нибудь вызовут из корня
  репо, строка там закрываться не будет. Чинить копию не входит в writeset этой линии.

## Решение по шву (Шаг 2, сводка)

Вызов ставится сразу после ledger-эмитa `task_close` (`:468-476`), тот же
fire-and-forget контракт: провал закрытия строки НЕ валит закрытие линии (`log_error`,
продолжаем). Условия: success-outcome → `scripts/task-close.sh` существует и исполняем в
`PROJECT_ROOT` (иначе тихий `log_info`-скип — в m3-market, respiro-ios и самом leadv2 его
нет) → резолв founder-имени (Q1) → резолв строки через общий модуль (Q2) → вызов
`task-close.sh <shortid> --reason "<линия> …"`. Зеркало `docs/tasks.yaml` не пишется.
Правило реализовано ровно в одном месте (проверка после правки: grep по якорю блока).
