# Founder asks audit — 2026-09-02 / 2026-09-03

Source: Claude Code JSONL transcripts in
`/Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/*.jsonl`
(8 session files touched 2026-09-02/03). Cross-checked against `docs/tasks.yaml` (persona-engine),
`~/Projects/leadv2/docs/leadv2/scheduled-decisions.md`, and `git log` in both repos.

Legend: **ПОТЕРЯНО** = no backlog row, no scheduled-decision row, no commit/handoff evidence.
**ЕСТЬ СТРОКА** = a `docs/tasks.yaml` intent, scheduled-decision row, or handoff doc exists.
**СДЕЛАНО И ПРОВЕРЕНО** = a commit/artifact closes the loop.

## ПОТЕРЯНО

| Дата/время | Что просил | Состояние | Доказательство |
|---|---|---|---|
| 2026-09-02 14:34–14:35 | Почему воркер (тот, кто пишет код) — только Sonnet? Хотел бы, чтобы Opus/Fable/GLM-flash/разные тиры Codex тоже могли быть воркером, когда лучше подходят | ПОТЕРЯНО | нет intent в `docs/tasks.yaml`, нет строки в `scheduled-decisions.md`; модель-роутинг покрывает выбор ревьюера/арбитра, но не "воркер = любая подходящая модель" |
| 2026-09-02 01:03:27 | Формат лида "минимум усилий/максимум результата + слежение" — должен работать на уровне ПЛАГИНА, во всех репо и у всех, кто его поставит | ПОТЕРЯНО | нет intent/SD-строки; это отдельная архитектурная просьба про to-all-installers observability, не покрыта существующими задачами о конкретном репо |
| 2026-09-03 01:27:22 | "Когда мы в гите создадим тот рул, о котором говорили?" (git-правило, упомянутое ранее в разговоре) | ПОТЕРЯНО | нет intent/SD-строки; предмет правила не идентифицируется ни в одном найденном коммите/бэклоге |
| 2026-09-03 17:56:58 | Все 3 фоновые сессии упали из-за краша Antigravity — "было бы найс чтобы такого не было" (просьба про устойчивость к падению внешнего приложения) | ПОТЕРЯНО | `git log --all --since=2026-09-01` в обоих репо не содержит ничего про "antigravity"; нет intent/SD-строки |
| RESEARCH-HERMES-AGENT-01 (разбор github.com/nousresearch/hermes-agent) | intent есть, папка `~/Projects/leadv2/docs/handoff/RESEARCH-HERMES-AGENT-01/` **пустая** (0 файлов) | СМ. ПРИМЕЧАНИЕ | intent строка в `docs/tasks.yaml`, но `findings.md` отсутствует — результат не сдан |
| RESEARCH-CODEX-OPEN-HARNESS-01 (разбор открытого харнеса Codex) | intent есть, есть только `brief.md` (техзадание), финального `findings.md` нет | СМ. ПРИМЕЧАНИЕ | `~/Projects/leadv2/docs/handoff/RESEARCH-CODEX-OPEN-HARNESS-01/brief.md` (9578 байт, 2026-09-03 21:27) — постановка задачи, не разбор |
| RESEARCH-TEN-REPOS-FROM-REEL-01 (10 репо из рилса) | intent есть, есть только `repos.md` (извлечённый список репозиториев), разбора "взять/не взять" нет | СМ. ПРИМЕЧАНИЕ | `~/Projects/leadv2/docs/handoff/RESEARCH-TEN-REPOS-FROM-REEL-01/repos.md` (3830 байт, 2026-09-03 20:43) — только список, не вердикт |

**Примечание про три явно названные основателем "потерянные" задачи**: все три УЖЕ имеют intent-строку
в `docs/tasks.yaml` (кто-то завёл их после того, как основатель это заметил). Артефакты почему-то лежат
в `~/Projects/leadv2/docs/handoff/`, а не в `persona-engine/docs/handoff/` — сам этот разброс путей стоит
отдельно проверить. Формально это не "строка потеряна", а "работа не сдана": ни у одной из трёх нет
итогового `findings.md` со списком "взять/не брать/почему", как требовал сам intent. Технически статус —
"ЕСТЬ СТРОКА, но НЕ ВЫПОЛНЕНО"; перечислены здесь отдельно, т.к. основатель прямо просил их проверить и
прямо назвал потерянными.

## ЕСТЬ СТРОКА

| Дата/время | Что просил | Идентификатор |
|---|---|---|
| 2026-09-02 09:21:48 | Сравнить Codex $200 vs GLM Max vs текущий Max 20x подписки | `SUBSCRIPTION-MIX-DECISION-01` (tasks.yaml) |
| 2026-09-01/02/03 (много раз) | Оба Claude-аккаунта рабочие во всех локальных репо, диспетчер/арбитр учитывает оба | `TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01` (tasks.yaml) |
| 2026-09-02 10:34:57 | Скилы/скрипты плагина используются не полностью — разобраться глубоко | `SKILL-USAGE-IS-UNMEASURED-01` (tasks.yaml) |
| 2026-09-02 10:50:35 | m3-market "не существует на диске" — разобраться | закрыто по факту, см. commit `46c0ce17` (CAPABILITY-TRUTH-AUDIT-01, leadv2 repo) — путь скорректирован на `~/MythicalGames` |
| 2026-09-02 11:34:36 | Агенты плодят подагентов вместо работы — разобраться | `docs/handoff/NESTED-AGENTS-AND-FORKS-01/` (leadv2 repo, commit `4ec6693f`) |
| 2026-09-02 11:55:18/30 | Сделать анализ вида "v5 verdict" | `PLUGIN-VERDICT-01` (упомянуто в tasks.yaml:339,595,1783) |
| 2026-09-02 12:07:14 | Поднять сторож дрейфа (drift guard) в канон плагина | `DRIFT-GUARDS-TO-CANON-01` (tasks.yaml) |
| 2026-09-02 13:56 / 18:05 | GLM недогружен после перехода на Max, задача про GLM-эффективность неясно выполнена | `GLM-EFFICIENCY-01` (упомянуто многократно в tasks.yaml) |
| 2026-09-02 14:08:17 / 17:38 / 17:41 / 09-03 01:23–01:26 | Арбитр должен быть умным (маршрутизация по квоте, не по флагам); лид не должен подменять арбитра | `GLM-NEVER-WINS-THE-ARBITER-01`, `ARBITER-FLOOR-MODE-SILENTLY-OVERRIDES-GLM-FIRST-01`, `CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01`, `ARBITER-ESTIMATES-BLIND-AND-NEVER-LEARNS-01` (все в tasks.yaml) |
| 2026-09-02 16:14:52 | Воркфлоу на GitHub Actions падают/перегружают бесплатную квоту | `CI-COST-CEILING-IS-A-TEMPLATE-RISK-01` (tasks.yaml:1807) |
| 2026-09-02 17:23:37 | Почему promise guard не сработал — почему лид сказал "сделаю", но не сделал в тот же ход | `PROMISE-GUARD-BLOCK-FLIP-01` / `PROMISE-GUARD-TURN-IT-ON-01` (scheduled-decisions.md leadv2, flip landed 2026-09-01) |
| 2026-09-02 22:31:21 | Хуки/гарды нужны во всех локальных репо на компе | `MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01` (tasks.yaml) + commit `665806bd` (HOOKS-PARITY-ACROSS-REPOS-01, leadv2 repo) |
| 2026-09-02 23:09:23 / 23:54:06 | Ревью 4-5 дней работы плагина, слить незакрытые линии до основной задачи "владелец состояния линий" | `FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01`, `SALVAGE-UNMERGED-LANES-01`, `STATE-OWNER-WRITE-GATE-01` (tasks.yaml) |
| 2026-09-03 08:45:33 | 8 названных дефектов: LANE-REGISTRY-STAMPS-THE-LEAD-PID-01, CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01, PHASE-PLAN-PROOF-IS-FILENAME-BASED-01, PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01, STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01, LEAD-DOES-MACHINE-WORK-01, SKILL-USAGE-IS-UNMEASURED-01, CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 | все 8 присутствуют как intent-строки в `docs/tasks.yaml` |
| 2026-09-03 00:39:59 | "13 строк скрытой очереди" — что это и зачем | `STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` (tasks.yaml) |
| 2026-09-03 01:13:37 / 01:14:42 | SD-FREEPOOL-UNPROTECTED-TRIAL-01 разобрать; фрипул должен реально получать работу | `FREEPOOL-MUST-ACTUALLY-GET-WORK-01`, `FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01` (tasks.yaml) |
| 2026-09-03 01:34:42 | leadv2-laptop-load-ticket-for-dima-2026-09-01.md, снизить нагрузку от лида | commit `cc6870c0` (STATUS-CHURN-01, "load ticket items 2-3", leadv2 repo) |
| 2026-09-03 09:57:29 / 09:58:51 | Лид сам пишет брифы вместо архитектора — прекратить | `LEAD-DOES-MACHINE-WORK-01` (tasks.yaml) |
| 2026-09-03 13:18:04 / 13:21:18 | Repowise и graph MCP реально используются и экономят токены — доказать | `CODE-INTEL-IS-INSTALLED-AND-UNUSED-01` (tasks.yaml) |
| 2026-09-03 15:56–16:14 | Разобраться с второй Claude-сессией по вопросу двух аккаунтов; научить остальные репо (getmany-followup-bot, m3) работать с обоими аккаунтами | `TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01`, `LEAD-SESSION-CANNOT-SWITCH-ACCOUNTS-MIDFLIGHT-01`, `TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01` (tasks.yaml) |
| 2026-09-03 17:12:01 | Динамический автосвитч аккаунтов | покрыто теми же `TWO-ACCOUNTS-*` строками (нет отдельной суб-задачи "найти готовое решение на GitHub" — не выделяю в отдельный лост-пункт, входит в общий scope) |
| 2026-09-03 18:02:32 | Приоритет 96: диспатч standard без --protected должен давать arm=glm | `ARBITER-FLOOR-MODE-SILENTLY-OVERRIDES-GLM-FIRST-01` (tasks.yaml:1159) |

## СДЕЛАНО И ПРОВЕРЕНО

| Дата/время | Что просил | Доказательство |
|---|---|---|
| 2026-09-01 18:30 / 18:33 | Проверить, что второй Claude-аккаунт залогинен и селектор работает | подтверждено в той же сессии по логам селектора (профильный лог `same_account label=personal…`, задокументировано как `TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01`, уже найденная и заведённая проблема) |
| Регулярные статус-таблицы ("таблицей, что в работе / что нет / провайдер / оценка") | Формат закреплён как стандартное поведение | памятка `feedback_supervise_broad_status_format.md`, `feedback_status_as_markdown_table.md` — соблюдался в каждой сессии по транскриптам |
| 2026-09-02 23:54:06 | 4 готовые ветки лежат не слитыми (FABLE-THINK-TIER-01 и др.) — слить по одной | FABLE-THINK-TIER-01, WORKER-DOD-GATE-01 подтверждены смерженными: `git log` leadv2 repo содержит `ed4a8beb merge: WORKER-DOD-GATE-01` |

---

## Итог

Из ~55 отдельных пунктов, извлечённых из транскриптов 2026-09-02/03, подавляющее большинство уже
имеет backlog-строку в `docs/tasks.yaml` или scheduled-decision в leadv2. Явно ПОТЕРЯНЫ (без какой-либо
строки/доказательства) **4 пункта** + **3 явно названных основателем research-задачи**, у которых
строка есть, но результат (`findings.md`) не сдан на диск.

Итого пунктов всего: **~55**. Потеряно (без строки вообще): **4**. Плюс 3 research-задачи со строкой,
но без сданного результата (основатель явно называл их потерянными — технически не "потеряна строка",
а "не сдан результат").
