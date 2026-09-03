# RESEARCH-HERMES-AGENT-01 — что взять из hermes-agent в leadv2

Разбор https://github.com/NousResearch/hermes-agent (repo публичный, не пустой, проверено через
`gh api repos/NousResearch/hermes-agent` — 200, description "The agent that grows with you").
Читал напрямую: `hermes_state_registry.py`, `hermes_state.py`/`_common`/`_schema` (SQLite state
family), `hermes_cli/kanban_db.py` (12k строк — claim/reclaim/crash-detect kernel),
`hermes_cli/kanban.py` (dispatch tick + lock), `hermes_cli/kanban_diagnostics.py` (stranded/deadlock
rules), `gateway/kanban_watchers.py`, `docs/kanban/multi-gateway.md`,
`website/docs/user-guide/features/kanban-worker-lanes.md` (contract doc — самое близкое к нашей
lane-архитектуре), `hermes_cli/session_recovery.py`, `hermes_cli/update_restart_recovery.py`,
`hermes_cli/local_runtime/supervisor.py`, `tui_gateway/host_supervisor.py`.

Их **kanban worker lanes** subsystem — прямой структурный аналог линий leadv2: диспетчер клеймит
задачу, спавнит воркера (`hermes -p <profile> chat`), воркер обязан завершиться ровно одним из
`kanban_complete` / `kanban_request_review` / `kanban_block` / crash, а кернел
(`hermes_cli/kanban_db.py`) владеет claim TTL, детекцией краша и reclaim. Здесь есть с чем сверить
все четыре наши боли.

Наш контекст прочитан первым: `docs/leadv2/PLAN.md` (Wave 2 = `CONTROL-PLANE-HAS-NO-OWNER-01`,
D1-D6), `leadv2-route-arbiter.sh`, `leadv2-lane-state.sh`, `leadv2-routing.yaml`.

## Таблица решений

| Механизм у них | Их файл | Что решает | Есть ли у нас | Вердикт | Почему |
|---|---|---|---|---|---|
| PID-liveness reclaim с launch-window grace period (`_resolve_crash_grace_seconds`) — не reclaim'ить воркера, чей PID ещё не появился в `/proc` в первые секунды после spawn | `hermes_cli/kanban_db.py:detect_crashed_workers` (grace-проверка ~L8918-8925) | Ложные "линия мертва" в первые секунды жизни воркера | Частично: `leadv2-lane-state.sh:_lv2_lane_start_time`/`alive()` сверяет pid+lstart, но нет grace-окна на регистрации — гонка "проверили раньше чем процесс встал" теоретически возможна | **Взять** | Дешёвый фикс (одна проверка `now - started_at < grace`), прямое попадание в боль #1 ("линия умирает вместе с ведущей... спасается руками" — часть спасений это ложные срабатывания на старте) |
| Reclaim возвращает задачу на **source phase**, диспетчер сам её переспавнивает на следующем тике — не просто помечает "мертва" в ожидании человека | `hermes_cli/kanban_db.py:reclaim_task` (UPDATE ... SET status=retry_status) + `_dispatch_once_locked` подхватывает `ready`-строки | Мёртвая линия воскресает без участия ведущего | **Нет.** `lane_reconcile()` в `leadv2-lane-state.sh:117-145` только помечает `dead_at`/`reconciled_dead` и находит осиротевшие worktree-процессы (`recovered_orphan`), но не переставляет фазу так, чтобы что-то её подхватило — восстановление воркера остаётся ручным | **Взять** | Прямое попадание в боль #1: "никто её не поднимает; незакоммиченная работа спасается руками". Обнаружение у нас есть (полдела), авто-воскрешения нет |
| `_defer_reclaim_for_live_worker` — если PID жив, но воркер тормозит (долгий LLM-вызов), claim продлевается, а не убивается; убийство только для реально мёртвого PID | `hermes_cli/kanban_db.py:8342-8375` | Не убивать медленного-но-живого воркера вместо мёртвого | Нет прямого аналога — `lane_alive()` даёт boolean, нет ветки "продлить TTL, раз жив" | **Взять** | Снижает число ложных "линия умерла" — тот же корень боли #1 |
| `detect_crashed_workers` различает `crashed` (PID пропал) / `protocol_violation` (rc=0, но не было терминального вызова — "вышел молча") / `rate_limited` (EX_TEMPFAIL сентинел — не считается провалом, чтобы длинное окно квоты не взводило breaker) | `hermes_cli/kanban_db.py:8863-8960` | Три разных вердикта вместо одного "мертва/жива" | **Нет.** У нас нет различения "тихо вышел без committed work" vs "убит" vs "упёрся в квоту" — всё это читается как один и тот же статус "мертва" | **Взять** | Прямое попадание в боль #2 ("про живость врут все поверхности") — у них "мертва" — не один булев факт, а классифицированное событие с разным follow-up |
| Единственный владелец диспетчера на инсталляцию (`kanban.dispatch_in_gateway`, single-owner posture) + `_dispatch_tick_lock` — файловый лок вокруг тика диспетчера, чтобы два процесса не гонялись за одной задачей | `docs/kanban/multi-gateway.md`, `hermes_cli/kanban.py:1695 _dispatch_tick_lock` | Два диспетчера не спавнят одну и ту же задачу дважды | **Есть, похоже**: `active.yaml.lock` + `_lv2_lane_state_mutate` берёт `fcntl.flock` перед каждой мутацией (`leadv2-lane-state.sh`). Это защищает запись состояния, но не сам dispatch tick — отдельного "один и только один tick одновременно" замка на уровне арбитра у нас нет | **Уже есть** (частично) | Механизм для записи состояния уже присутствует и решает тот же класс гонок; расширение до dispatch-tick лока — не новая идея, а достройка существующего паттерна |
| Одна общая `SessionDB` на путь, refcounted, generation-aware (одно соединение-писатель на файл вместо N независимых — раньше это давало "потерянные/переставленные записи", issue #90837, 11+ инцидентов) | `hermes_state_registry.py` (весь файл, особенно докстринг L1-38: "Each bare SessionDB() mints its own writer connection... producing the lost/reordered-page-write signature") | 24 места пишут в 9 хранилищ без единого владельца записи | **Нет.** Наша боль #2 буквально описана их доком до фикса: "24 места, 9 хранилищ" — ровно та болезнь, которую `hermes_state_registry.py` лечит паттерном "acquire(path)/release(db), владелец — реестр, а не вызывающий" | **Взять** | Это архитектурный паттерн под саму боль #2, с датированным post-mortem (#90837), что бывает без него: гонки на запись, потерянные страницы. Наш `active.yaml` уже на flock+atomic-rename (хорошо), но нет единого reference-counted владельца соединения на путь для остальных 8 хранилищ |
| Contract-документ "lifecycle terminator": ровно один из `kanban_complete` / `kanban_request_review` / `kanban_block` / crash обязан завершить прогон; кернел это гарантирует, а не полагается на дисциплину воркера | `website/docs/user-guide/features/kanban-worker-lanes.md` (раздел "A lifecycle terminator") + кернел: `detect_crashed_workers` карает "вышел без терминального вызова" как protocol_violation | Фазы (план/гейт/сборка/ревью/закрытие) не проходят до конца | **Нет.** У нас фазы — дисциплина промпта (subagent должен дойти до ревью), без машинной гарантии на уровне кернела, что "не-ревью" — это ошибка, а не тихий пропуск | **Взять** | Прямое попадание в боль #4 (4 из 22 линий дошли до ревью). У них пропуск терминального вызова — заведённое событие с последствием (protocol_violation → влияет на retry budget), не молчаливая потеря |
| `stranded_in_ready` диагностика: задача, чей assignee ни разу не заклеймил её за `stranded_threshold_seconds` (30 мин), всплывает как warning/error/critical (эскалация x1/x2/x6) в `hermes kanban diagnostics` | `hermes_cli/kanban_diagnostics.py:958-1058, _rule_stranded_in_ready` | Опечатанный/удалённый assignee, простаивающий внешний пул воркеров — единым сигналом, без allowlist | **Нет прямого аналога** — у нас нет отдельной таблицы диагностик поверх `active.yaml`, "застряла в ready" не детектится как отдельный именованный кейс | **Взять** | Прямое попадание в боль #4: если линия не доходит до ревью, часть случаев — "фаза вообще не стартовала", а не "стартовала и упала". stranded_in_ready ловит именно первое |
| `review_dependency_deadlock` диагностика: родитель sticky-blocked с `review-required:`, пока дочерняя карта висит в `todo` — типовой deadlock ревью-графа, детектится и подсказывает разрыв, не трогая блок автоматически | `hermes_cli/kanban_diagnostics.py:753-, _rule_review_dependency_deadlock` | Ревью зависает не потому что никто не смотрит, а потому что граф противоречив | Нет — у нас нет графа зависимостей план→гейт→сборка→ревью→закрытие с детектором цикла/дедлока | **Не берём сейчас** | Похоже на боль #4, но решение специфично их parent/child review-графу (у нас фазы линейные, не DAG с родитель/потомок картами) — переносить структуру, которой у нас нет, менее приоритетно, чем простое воскрешение выше |
| Стоимостно-осведомлённый арбитр по нескольким провайдерам (загрузка провайдера как первичный, а не tie-break, сигнал выбора руки) | — | Боль #3: дешёвая рука никогда не выигрывает у Claude | **Не найдено.** `assignee` в kanban — это Hermes-профиль (одна модель на профиль), `model_override`/`provider_override` — статичный override per-task, а не арбитр, реагирующий на текущую загрузку/квоту нескольких провайдеров как основной критерий. Ни в `kanban_db.py`, ни в `kanban.py`, ни в конфиге диспетчера нет multi-provider cost-arbiter аналога `leadv2-route-arbiter.sh` | **Не берём (не у кого)** | Честный ответ: hermes не решает эту боль лучше нас — у него вообще нет мультипровайдерного арбитра, модель "одна модель на профиль" проще нашей. #3 разбираем своими силами (переписать `ecost()`/`util()` так, чтобы загрузка была первичным, а не tie-break сигналом) |

## Что взять первым

Первым берём связку **grace-period + defer-for-live-worker + auto-respawn-on-reclaim** из
`kanban_db.py` (`detect_crashed_workers`, `_defer_reclaim_for_live_worker`, `reclaim_task`) — это
самая дешёвая правка (три отдельных независимых условия внутри уже существующей
`_lv2_lane_state_mutate`/`lane_reconcile`) и бьёт прямо в боль #1: сегодня мы *обнаруживаем*
мёртвую линию (`reconciled_dead`, `recovered_orphan`), но не *воскрешаем* её — фикс здесь заменяет
"спасается руками" на "диспетчер подхватывает на следующем тике", как у `reclaim_task`. Вторым —
`hermes_state_registry.py` (Wave 2 / D1 "единый писатель состояния") ровно потому что это тот же
архитектурный паттерн, который наш собственный `PLAN.md` уже называет решением боли #2 (D1: "single
writer for lane state"), только с датированным post-mortem (#90837) как доказательством, что без
него бывает хуже, чем "просто неаккуратно". Боль #3 (арбитр) hermes не закрывает вообще — там нет
multi-provider cost routing — так что это остаётся нашей отдельной задачей, не заимствованием. Боль
#4 частично закрывается protocol_violation-детектом + stranded_in_ready: обе идеи дёшевы (по одному
правилу каждая) и сразу объясняют, почему из 22 линий ревью было у 4 — без машинной гарантии
терминального вызова "тихий пропуск фазы" неотличим от "фаза прошла и никто не спросил".
