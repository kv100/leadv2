# SILENCE-READ-AS-FACT-CENSUS-01 — перепись мест, где отсутствие записи читается как факт о мире

Дата: 2026-09-04. Режим: только чтение и пробы, ни одной правки. Область: `plugins/leadv2/scripts/` (270 файлов), `scripts/lib/` (49), `hooks/` (97). Свидетельства: `~/Projects/persona-engine/docs/leadv2/tasks/*/journal.md` за 2026-09-04.

## 0. Выжимка

| | |
|---|---|
| Находок (мест в коде) | **44** отдельных места + 1 пучок из 14 хуков с одной и той же формой (`trap 'exit 0' ERR` вокруг «жёсткого блока»); 78 из 97 хуков несут такую ловушку |
| С доказанным последствием (строка журнала или сегодняшний инцидент с проверенным механизмом) | **11** мест, покрывающих все 5 инцидентов дня |
| Ведут к РАЗРУШИТЕЛЬНОМУ действию (kill / prune / reset / reclaim слота / удаление worktree) | **12** мест — они первые в таблице |
| Ведут к благоприятному ложному выводу (гейт пропущен, «чисто», «квота есть», «не заблокировано») | 30 мест (+пучок хуков) |
| Гипотезы (механизм подтверждён чтением кода, живого следа нет) | 33 |
| Правильная форма уже в дереве (образцы) | 4: `_phase_precondition_guard` → `phase_precondition_pass`; `lv2_lane_pid_alive` (EPERM ⇒ alive); `pid_state` в `lane-liveness.sh` (нет записи о рождении ⇒ `alive_unverified`, не dead); `_dispatch_terminal_ledger_state` (пусто ⇒ проваливается в следующую проверку, а не «landed») |
| Болезнь распадается на | **2 класса, одно правило с двумя обязанностями** (§3) |

**Общее правило (SILENCE-IS-NOT-A-VALUE-01):** *у каждой пробы и каждого гейта три исхода — `yes | no | unknown`; владелец писателя обязан записать исход на КАЖДОЙ ветке (включая успех) в ту же поверхность, откуда его читают; читатель на `unknown` (нет записи / чтение не удалось / проба не прошла) НИКОГДА не подставляет значение, ведущее к разрушительному действию или к пропуску гейта, а передаёт `unknown` выше.* Следствие: код возврата — тоже отметка; `exit 0` при вердикте «не сделано» запрещён.

## 1. Как искали

По поведению, не по строкам. Пять проходов: (1) каждый предикат живости (`kill -0`, `os.kill(pid,0)`, адаптеры статуса arm) — что делает с ошибкой сигнала и что потом ДЕЛАЮТ с вердиктом «dead»; (2) каждое вычисление «лента что-то сделала» (`git status --porcelain`, `git diff`, `merge-base`, `rev-list`) — отличима ли ошибка git от «реально пусто»; (3) каждое место, где вердикт печатается рядом с кодом возврата, — могут ли они разойтись; (4) каждый шаг «подтверждения» перед reclaim/prune/kill — сколько независимых источников на самом деле; (5) `2>/dev/null`, `|| true`, `|| echo <default>`, `trap … exit 0 ERR`, `except Exception`, `case … *)` — только там, где рядом присваивается переменная решения (verdict/state/alive/class). Прочитаны целиком: 34 файла lib/scripts + 19 хуков; `leadv2-dispatch-code.sh` (8970 строк) — все функции живости/вердиктов/reclaim; `leadv2-dispatch-product-close.sh` — блок вердикта no_work и разрешение базы диффа. Пробелы честно: `cmd_resolve` вне названных регионов, `leadv2-review-run.sh` (1941), `leadv2-phase8-close.sh` (877), ~75 хуков просмотрены только grep'ом на `trap … ERR` + «hard block».

Инструменты: индексы repowise/graph покрывают persona-engine, не `~/Projects/leadv2`, поэтому обход выполнен двумя sonnet-помощниками по поведенческим подшаблонам + мои собственные пробы на 9 ключевых местах (все цитаты ниже сверены `sed -n` с живым деревом).

## 2. Перепись, ранжированная по последствию

Подшаблоны: **(a)** успех молчит, отказ пишет; **(b)** писатель и читатель — разные поверхности; **(c)** глушение ошибки до «пусто»; **(d)** rc=0 при вердикте «не сделано»; **(e)** нет записи ⇒ благоприятное значение по умолчанию; **(f)** слово «подтверждено» при одной пробе.

Статус: **ДОКАЗАНО** = есть строка живого журнала или сегодняшний инцидент с проверенным механизмом; **ГИПОТЕЗА** = механизм подтверждён чтением кода, живого следа нет; **ИСПРАВЛЕНО** = образец.

### 2.1. Класс А — неверный вывод ведёт к разрушительному действию (12)

| # | Место | Подш. | Что делает код | Ложный вывод | Действие | Статус / свидетельство |
|---|---|---|---|---|---|---|
| A1 | `scripts/leadv2-lanes-snapshot.sh:605-611` `pid_alive` + `:870-872` + `:951-958` | (c)(f) | `except (…, PermissionError): return False` → `pid_issue_reason="pid dead"`; «corroborated» = **та же самая** проба, увиденная на двух последовательных опросах (`prev_dead_candidates`), не второй источник | EPERM (процесс жив, чужой uid/sandbox) = «pid dead»; повтор одной пробы подан как согласие источников | **prune** строки из active.yaml + tombstone | **ДОКАЗАНО** — инцидент 4: четыре вердикта «corroborated dead: pid dead» за час на линиях с ударом секундой раньше; журнал e9272511: `lane_liveness verdict=dead signal=none reason=no_pid_recent_commit finished:839s` (09:51:35Z), ещё 2 строки 09:55/10:03. Оракул `alive` (:951) обнуляет `reasons` только при явном `alive`; `silent:*`/`unknown` не защищает |
| A2 | `scripts/lib/leadv2-lane-state.sh:89-97` `alive(row)` | (c)(e) | `except OSError: return False`; и далее `return bool(recorded and observed and recorded == observed)` — **отсутствие** записи `pid_birth` в строке ⇒ `False` | нет записи о рождении = мёртв; EPERM = мёртв. Соседний `pid_state` в `lane-liveness.sh:197-235` при тех же входах отвечает `alive_unverified` — две библиотеки отвечают на один вопрос в противоположные стороны | `reconcile` (:183-184) штампует `dead_at` + `reconciled_dead`; вызывается из `cmd_resolve` (`dispatch-code.sh:7050`) на **каждом** диспатче; `register` (:116) после этого не видит живую строку и регистрирует вторую | **ДОКАЗАНО** по механизму (инцидент 4 + инцидент 2: «молчание прочитано как смерть»); строки `reconciled_dead` в сегодняшних журналах не искал — ГИПОТЕЗА на частоту |
| A3 | `scripts/leadv2-dispatch-code.sh:3098-3102` `_dispatch_worker_liveness` sonnet | (c) | `kill -0 "${handle}" 2>/dev/null; then alive; else dead` — без разбора текста ошибки | EPERM = dead. В том же дереве `lib/leadv2-lane-worker-alive.sh:186-193` уже делает правильно («только *no such process* = DEAD, всё остальное ALIVE») — этот вызов её не использует | питает A4/A5 | **ДОКАЗАНО** — инцидент 4 (sonnet-arm остаток, самодокументирован в `:5981-6009` как открытый) |
| A4 | `scripts/leadv2-dispatch-code.sh:3331-3363` `_dispatch_outcome_blocks` | (f) | при `liveness=dead` (из A3) без cutoff/terminal-строки одна проверка `_dispatch_evidence_exists` (`git log --grep` + mtime) — единственное «подтверждение» перед `dispatch_reclaimed … reason=unattributed_empty` | одна проба живости + одна проба следа = «строка брошена» | **reclaim** строки ledger у, возможно, живого воркера | ГИПОТЕЗА (механизм) |
| A5 | `scripts/leadv2-dispatch-code.sh:3376-3399` `_dispatch_sig_blocked` | (a) | rc1 из A4 ⇒ sig «свободен»; «не смог определить живость» неотличимо от «линия закончена» | нет живой заявки | **новый диспатч того же sig** поверх пишущего воркера | ГИПОТЕЗА |
| A6 | `scripts/leadv2-dispatch-code.sh:8881-8905` `cmd_retry_dead` | (f) | операторская команда «объявить мёртвым и очистить» — доверяет ровно одной пробе A3 как «provably dead» | одна `kill -0` = доказательство | **ручная очистка** строки | ГИПОТЕЗА (буквальная форма «corroborated dead» с одной пробой) |
| A7 | `hooks/leadv2-orphan-monitor-sweep.sh:11-24` | (b)(e) | докстринг обещает «или чья `CODEX_COMPANION_SESSION_ID` указывает на неживую сессию»; в коде фильтр **только** `etimes > 900` | «работает >15 мин» = «сирота мёртвой сессии» | `kill -KILL -"$pgid"` — вся группа процессов | ГИПОТЕЗА (проверено sed: проверки сессии в файле нет) |
| A8 | `hooks/leadv2-merged-worktree-sweep.sh:173-181` NEWBORN GUARD | (e) | `created_epoch` = `stat … \|\| stat … \|\| echo 0`; защита возраста включена только при `created_epoch > 0` | «не смог прочитать время создания» = «защита не применяется» (а должно быть «считать новорождённым») | проваливается к `git worktree remove` — ровно та гонка (stat vs создание), от которой guard построен после реального удаления линии через 7 с | ГИПОТЕЗА (сверено sed) |
| A9 | `scripts/leadv2-lane-salvage.sh:434-441` | (d) | все четыре вердикта (`salvaged_green/salvaged_red/conflict/nothing_to_salvage`) печатаются в stdout, `return 0` всегда; в журнал `SALVAGE_RESULT` не пишется (0 совпадений за день — писатель/читатель разошлись, подш. (b)) | цикл по `$?` видит «OK» | «17 OK» при нуле созданных веток; следующее действие цикла — считать линию спасённой и **удалить исходную** | **ДОКАЗАНО** — инцидент 5 (`verdict=conflict … carried=0/4`, rc 0). Автор считает это контрактом («вердикт — это данные»); контракт нарушает правило §3 |
| A10 | `scripts/lib/leadv2-lane-state.sh:274-275` `lead_alive` | (c) | `os.kill(lp,0) / except OSError: sys.exit(1)` на pid ЛИДА | лид, которому нельзя послать сигнал, = мёртв | все его линии выглядят осиротевшими для reconcile/adoption | ГИПОТЕЗА |
| A11 | `scripts/lib/leadv2-worktree-protected.sh:100-104` | (c) | `os.kill … except OSError: alive=0` по строкам сессий | EPERM = не защищено | сегодня приглушено: проба A (наличие строки) защищает независимо; единственное место, где рефакторинг «доверять только probe C» станет тихо небезопасным | ГИПОТЕЗА (near-miss) |
| A12 | `scripts/leadv2-dispatch-code.sh:7442-7448` (`log_path` = `pulse.md` по умолчанию на пути fanout finalize-register) | (b) | реальный поток воркера — `developer.stream.jsonl`, а живость читает `log_path` → почти немой `pulse.md` | живой воркер = «silent» | вердикт silent/dead → prune (через A1) | **ДОКАЗАНО** как исторический корень инцидента 2 (самодокументировано «cannot fix» для одного пути регистрации) |

### 2.2. Класс Б — благоприятный ложный вывод, ДОКАЗАНО живыми следами (6)

| # | Место | Подш. | Что делает код | Ложный вывод | Действие | Свидетельство |
|---|---|---|---|---|---|---|
| Б1 | `scripts/leadv2-dispatch-code.sh:4207-4310` `_phase_precondition_guard` | (a) | **ИСПРАВЛЕНО** сегодня (eb747f65): раньше писал только `_refused`; теперь `phase_precondition_pass` / `_bootstrap` на каждом проходе | «0 строк = гейт пропустил» | диспатч без plan/gate1 | Инцидент 1: 31 из 77 линий за сутки без единой строки; за 2026-09-04 в persona-engine: 2 `_warn`, 2 `_refused`, 1 `_bootstrap`, **0 `_pass`** при 4 терминальных линиях — свежий бинарь ещё не прошёл через живой диспатч, проверка после первого прогона обязательна |
| Б2 | `scripts/leadv2-dispatch-code.sh:1973-1987` `emit()` + `scripts/leadv2-journal.sh:11` | (b)(c) | `emit` → `journal.sh append … >/dev/null 2>&1 \|\| true`, затем `log` → **stderr** (:800). `journal.sh` сам под `trap 'exit 0' ERR`. Итог: удары `waiting_worker` (`product-close.sh:1385`) живут в журнале + stderr; **stdout диспетчера пуст по построению**, и провал записи в журнал неотличим от успеха (двойное глушение) | «stdout молчит» = «диспетчер мёртв»; «в журнале пусто» = «удара не было» | убиты два живых воркера (инцидент 2) | Журнал: `product_close task=593bc3e2 status=waiting_worker handle=55972 waited=1809s` (08:51:58Z), 40+ ударов по 3 линиям; убийство — со слов основателя, строки в журнале нет |
| Б3 | `scripts/leadv2-dispatch-product-close.sh:1460-1478` разрешение базы диффа + `:2105-2111` | (c)(e) | три попытки `merge-base … 2>/dev/null \|\| true`; `rev-list --count … \|\| true`; `git diff --name-only "${base}" … 2>/dev/null` — при неразрешённой/чужой базе список файлов пуст | «diff пуст» = «работы нет» → `:2500 _pc_terminal=no_work cause=empty_diff` | линия закрыта как no_work, ветка с сотнями вставок не рассматривается на review | Инцидент 3 (9 ложных из 14 — со слов основателя, не перепроверял). Журнал 593bc3e2 09:11:24Z: `terminal=no_work cause=empty_diff worker_reason="Committed on worktree-PROMPT-CAPTURE-HOOK-PROOF-01, nothing touched in ~/Projects/leadv2"` — работа совершена в одном корне, дифф измерен в другом (подш. (b)); c19c728f 11:36:06Z, e9272511 09:57:32Z — то же. Для «нельзя измерить» уже есть честный вердикт `refused cause=undiffable_write_set` (:1821-1822, журнал 4e975d5a) — но путь неразрешённой базы в него не ведёт |
| Б4 | `scripts/lib/leadv2-worker-epilogue.sh:96-101` | (c)(e) | `status_out="$(git status --porcelain … 2>/dev/null \|\| true)"`; пусто ⇒ `worker_exit=clean auto_committed=0` в progress.log/meta.yaml | ошибка git = «воркер ничего не менял» | питает Б3 | ДОКАЗАНО как звено Б3 |
| Б5 | `scripts/lib/leadv2-lane-guard.sh:50-57` `lv2_lane_dirty` | (c)(e) | `git status … 2>/dev/null \| grep …`; единственный тест `[[ -n "${status}" ]]` | ошибка = «чисто» | закрытие/landing как чистой | ДОКАЗАНО как звено Б3 |
| Б6 | `scripts/lib/leadv2-lane-guard.sh:80-87` `lv2_lane_containment_violation` | (e) | rc1 («нарушений нет») при пустом `writes_csv` или отсутствии `main-dirt.base` | «нет снимка» = «ничего не утекло» | лента, чью изоляцию нельзя оценить, идёт как проверенная | ГИПОТЕЗА, но та же цепочка |

### 2.3. Класс В — благоприятный ложный вывод, ГИПОТЕЗЫ (механизм подтверждён, следа нет) (27 + пучок)

| # | Место | Подш. | Суть | Ложный вывод → действие |
|---|---|---|---|---|
| В1 | `hooks/*.sh` — **пучок 14 файлов** (`bg-watchdog-gate/-enforce`, `blocker-drift-guard`, `close-ritual-guard`, `broken-signal-gate`, `codex-first-nudge`, `gate-artifact-guard`, `loop-detect-hook`, `read-dedup-hard`, `lead-read-guard`, `taskoutput-ban`, `read-gate`, `tool-blowup-gate`, `post-compact-reground`); всего `trap … exit 0 ERR` в **78 из 97** хуков | (a)(d) | каждый называет себя «HARD BLOCK», каждый обёрнут `set -euo pipefail` + `trap '…; exit 0' ERR` | крах гейта = «блок не нужен» → allow; 14 «обязательных» точек с одним слепым пятном |
| В2 | `hooks/leadv2-gate-artifact-guard.sh:1-11` | (a) | представитель В1: крах при проверке `context.yaml`/`.gate1-passed` | developer спавнится на задачу без Gate-1 |
| В3 | `hooks/leadv2-bg-watchdog-enforce.sh:26-29,270-272` | (a)(d) | «Contract: fail-open always» + `python3 "$CORE" … 2>/dev/null \|\| true` | баг 230-строчного детектора = «сирот нет» |
| В4 | `hooks/leadv2-close-ritual-guard.sh:30` | (e) | `grep -qE '^git\s+commit'` — не ловит `cd repo && git commit` | обычный close-commit минует блок |
| В5 | `hooks/leadv2-close-ritual-guard.sh:33-35` | (e) | сообщение вытаскивается только из `-m "…"`/`-m '…'`; иначе `MSG=""` → `exit 0` | нераспознанное = «не close» |
| В6 | `hooks/leadv2-monitor-cap-gate.sh:44-49` | (e) | transcript нечитаем → `exit 0`; `grep -c … \|\| echo 0` | «не могу посчитать» = 0 мониторов (низкая тяжесть: deny=1e6) |
| В7 | `hooks/leadv2-taskoutput-ban.sh:9-12` | (e) | неизвестный тип цели → warn-only по умолчанию | лид читает целый JSONL транскрипт |
| В8 | `scripts/leadv2-phase8-e2e-gate.sh:120-124` | (e) | `CLASSIFICATION="$(bash "$CLASSIFIER" … 2>/dev/null \|\| echo code)"` | крах классификатора = «не deploy» → deploy-verify пропущен |
| В9 | `scripts/leadv2-phase8-assert.sh:157-159` | (e) | тот же `\|\| echo code` в ветке, чей комментарий говорит «must hard-fail» | deploy-задача закрывается phase-8 зелёной без верификации |
| В10 | `scripts/lib/leadv2-quota-shape.py:139-141,150-153,185-189` | (e) | нечитаемый/пустой payload или все bucket `unknown` → `verdict=pass` | отказ читателя квоты = «запас есть» → спавн |
| В11 | `scripts/lib/leadv2-codex-circuit.sh:38-41` | (e) | путь маркера не разрешился → `closed` | «не нашёл маркер» = «цепь здорова» |
| В12 | `scripts/lib/leadv2-arm-cooldown.sh:171` | (e) | файл cooldown нечитаем (не отсутствует — нечитаем) → `clear` | «не могу прочитать память об отказе» = «отказа не было» |
| В13 | `scripts/lib/leadv2-arm-cooldown.sh:124-128`, `leadv2-watch-lifecycle.sh:124-128` | (e) | после 10 попыток захвата pidfile → `return 0` (spawn) | «не смог узнать владельца слота» = «слот свободен» → дубли-наблюдатели (тот баг, что lib чинит) |
| В14 | `scripts/lib/leadv2-route-arbiter.sh:3,20-31` | (e) | «non-zero means caller must fail open»; внутренние сбои 64-67 неотличимы от «отказано» | сломанный routing.yaml = «арбитр разрешил» |
| В15 | `scripts/lib/leadv2-lockout-classify.py:92-115,155-156` | (c)(e) | любое исключение → `("unclassified",0,"error")` → «ничего не записывать» | реальный отказ провайдера не оставляет lockout |
| В16 | `scripts/lib/leadv2-freepool-gate.sh:170-184` | (e) | исключение при чтении state-json → `sys.exit(0)` | битый файл = «нет улик о поломке arm» |
| В17 | `scripts/lib/leadv2-report-deliverable.sh:9` | (e) | «missing lib ⇒ no-op stub» | объявление `LANE_DELIVERABLE: report:` теряет enforcement без отметки |
| В18 | `scripts/leadv2-dispatch-code.sh:1826-1832,1866-1868` `_burn_gate` | (e) | пустой вывод governor → `return 0`; `case … *) return 0` | «нет сигнала» = «сжигание в норме» (документировано как fail-open) |
| В19 | `scripts/lib/leadv2-worker-output-gate.sh:116` | (c) | `git diff --name-only … 2>/dev/null … \|\| true` (некоммитнутая половина) | ошибка = 0 файлов; узко, второй дифф частично страхует |
| В20 | `scripts/lib/leadv2-refusal-classify.sh:60` | (e) | нераспознанный rc без маркера → `ran` | «упал непонятно как» = «не отказ» (двухступенчатая классификация смягчает) |
| В21 | `scripts/lib/leadv2-lane-state.sh:126-132` | (e) | `LEADV2_LANE_CAP` нечисло → 64 | опечатка = «широкий лимит» (низкая тяжесть) |
| В22 | `scripts/phase-record.sh` (уровни доказательств, строки 27-29) | (f) | «attested» = собственный `--reason` писателя, тот же класс статуса, что и проверенный sentinel | самоотчёт = подтверждение |
| В23 | `scripts/lib/leadv2-status-cache.sh:250-257` | (c) | ошибка чтения снимка = «кэш устарел, пересчитать» | безопасное направление, для полноты |
| В24 | `scripts/leadv2-journal.sh:11` (отдельно от Б2) | (a)(d) | `trap 'exit 0' ERR` на весь скрипт | любой вызывающий, не только `emit`, теряет запись молча |
| В25 | `scripts/leadv2-dispatch-code.sh:5981-6009` (исторический корень) | (b) | pid диспетчера как pid линии для async-arm | исправлено для glm/codex/kimi/freepool; sonnet — остаток A3 |
| В26 | `scripts/lib/leadv2-dod-gate.sh:400-410` (REVIEW-GATE-IS-MUTE-01) | (c) | **ИСПРАВЛЕНО**: вывод печатается из памяти, не через `mv \|\| true` | образец: не зависеть от успеха записи файла для собственного вердикта |
| В27 | `scripts/leadv2-dispatch-code.sh:3282-3288` `_dispatch_terminal_ledger_state` | (e) | **ПРАВИЛЬНАЯ ФОРМА**: пусто ⇒ проваливается в следующую проверку, не «landed» | образец для читателя |

## 3. Один общий фикс

Болезнь распадается ровно на два класса, и это две обязанности одного правила, а не два правила.

**SILENCE-IS-NOT-A-VALUE-01.** У любой пробы и любого гейта три исхода: `yes | no | unknown`.

1. **Обязанность писателя** (закрывает (a), (b), (d)): если ты владеешь отметкой, пиши её на КАЖДОЙ ветке — успех, отказ, «не смог» — и в ту поверхность, откуда её читают. Код возврата — тоже отметка: он обязан согласоваться с напечатанным вердиктом (0 только для `yes`; `no` и `unknown` — разные ненулевые коды).
2. **Обязанность читателя** (закрывает (c), (e), (f)): «нет записи», «чтение не удалось», «проба вернула ошибку» — это `unknown`, не значение. На `unknown` запрещено выбирать ветвь, которая (i) выполняет разрушительное действие или (ii) пропускает гейт; `unknown` передаётся выше как `unknown`. «Подтверждено» можно писать только когда ≥2 *разных* источника сказали `yes`/`no`; повтор одной пробы во времени — не второй источник.

Как правило закрывает найденное:

| Находки | Обязанность | Что меняется |
|---|---|---|
| A1, A2, A3, A10, A11 (EPERM/нет-записи-о-рождении ⇒ dead) | читатель | `pid_alive`/`alive()` возвращают `unknown` на `PermissionError` и на отсутствующий `pid_birth` — как уже делает `lane-worker-alive.sh:186-193` и `pid_state`; `unknown` не попадает в `reasons` для prune. Одна библиотека живости вместо трёх расходящихся |
| A1 «corroborated», A4, A6 | читатель | «corroborated» разрешено только при двух разных источниках (pid **и** mtime потока **и/или** ledger); повтор опроса переименовывается в `seen_twice` |
| A5, Б6 | читатель | «не смог оценить» ⇒ `refused cause=unassessable`, не «свободно/чисто» |
| A7, A8 | читатель | `stat` не удался ⇒ считать новорождённым; нет проверки сессии ⇒ не убивать (докстринг и код должны совпасть) |
| A9 | писатель | вердикт `conflict`/`salvaged_red` ⇒ rc 3, `nothing_to_salvage` ⇒ rc 4, и та же строка `SALVAGE_RESULT` идёт через `emit` в журнал |
| Б1 (образец), В1-В3, В24 | писатель | каждый гейт пишет `<gate>_pass` / `<gate>_refused` / `<gate>_unknown`; `trap 'exit 0' ERR` в «жёстком блоке» заменяется на `trap 'emit <gate>_unknown; exit 0' ERR` — allow остаётся (хуки не должны валить сессию), но след появляется, и «0 строк» снова различает «прошёл» и «не звали» |
| Б2 | писатель | `emit` не глушит провал журнала: `|| log_err "journal append failed"`; `journal.sh` снимает `trap 'exit 0' ERR` и возвращает ненулевой rc |
| Б3, Б4, Б5, В19 | читатель | неразрешённая база / ошибка git ⇒ `refused cause=undiffable_write_set` (уже существует, :1821) — никогда `no_work`; `no_work` требует положительного доказательства «база разрешена и дифф пуст» |
| В4-В9, В10-В18, В20-В22 | читатель | `unknown` ⇒ warn с отметкой в журнал, и для гейтов класса «safety/deploy/quota» — refuse, не pass (fail-open остаётся только там, где основатель явно выбрал его, и тогда в журнале обязана быть строка `<gate>_unknown_failopen`) |

Реализация — один общий helper (`scripts/lib/leadv2-verdict.sh`: `lv2_verdict emit <gate> yes|no|unknown …` + `lv2_unknown_guard`) и миграция двенадцати мест класса А; остальные закрывает гвард §4 по мере касания. Это **одна задача**, не тридцать.

## 4. Как удержать: гвард, который кусается

`tests/test-silence-is-not-a-value.sh` (саморегистрация через `# run-all-triggers: leadv2-dispatch-code.sh leadv2-lane-state.sh leadv2-lanes-snapshot.sh leadv2-lane-salvage.sh leadv2-journal.sh leadv2-dispatch-product-close.sh hooks` — так `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed` выбирает его при касании любого из этих файлов). Три части, каждая с объявленной мутацией, от которой она краснеет, и каждая мутация добавляется в `tests/mutations/catalog.yaml` (сейчас 3/3, станет 9/9; удалять записи нельзя).

**Часть 1 — парность вердиктов (статическая, обязанность писателя).** Реестр пар `tests/silence-verdict-pairs.txt`: `phase_precondition_refused:phase_precondition_pass`, `lane_liveness verdict=dead:lane_liveness verdict=alive`, `dispatch_reclaimed:dispatch_kept`, `review_gate status=blocked:review_gate status=passed`, `SALVAGE_RESULT verdict=conflict:emit … salvage_result`. Для каждой пары: если в дереве есть `emit` с левой частью и нет `emit` с правой в том же файле — FAIL. Суита также FAIL, если реестр пуст или в нём < 5 пар (инструмент обязан уметь ответить ненулём).
*Мутация M1:* удалить строку `emit decision "phase_precondition_pass …"` в `dispatch-code.sh:4303` → красный.

**Часть 2 — читатель на `unknown` (поведенческая, под `bash -c`).**
- `lane-state.sh alive()` и `lanes-snapshot.sh pid_alive` с pid 1 (существует, EPERM) → обязаны вернуть не-`dead`; строка без `pid_birth` → не-`dead`. *Мутация M2:* `except OSError: return False` — стоит сегодня в дереве, поэтому суита будет **красной с первого запуска**; это и есть доказательство, что она кусается; регистрируется в `tests/known-red-suites.txt` до миграции A1-A3 (red-first baseline, `lib/leadv2-red-first-baseline.sh`).
- `leadv2-lane-salvage.sh` на фикстуре с конфликтом → rc ≠ 0 **и** строка в журнале фикстуры. *Мутация M3:* `return 0` безусловный (текущее состояние) → красный.
- `leadv2-journal.sh append` в нечитаемый каталог → rc ≠ 0. *Мутация M4:* `trap 'exit 0' ERR` (текущее) → красный.
- `product-close` с `LEADV2_LANE_START_SHA=deadbeef` и веткой с 1 коммитом → терминал `refused cause=undiffable_write_set`, никогда `no_work`. *Мутация M5:* `|| true` на `merge-base` без проверки → красный.

**Часть 3 — след хуков.** Для каждого хука с `trap … exit 0 ERR` и словом «HARD BLOCK»/«mandatory» в шапке: запуск с намеренно битым JSON на stdin обязан оставить строку `<hook>_unknown` в журнале фикстуры (или на stderr). *Мутация M6:* убрать `emit` из trap → красный. До миграции — известно-красный.

**Отрицательный контроль на саму суиту:** она обязана упасть, если ни одна из проб не выполнилась (счётчик проб = 0 ⇒ FAIL). Проверка, которая молчит и когда хорошо, и когда плохо, — та же болезнь; поэтому суита печатает `PROBES=<n> RED=<m>` и падает при `n=0`.

**Свойство «кусается» доказывается так:** применить M1-M6 по одной в scratch-worktree (`leadv2-mutation-control.sh`), показать RED на каждой; снять — GREEN на M1 и M5 после миграции; M2-M4, M6 остаются RED до миграции, и это записано в known-red с датой.

## 5. Вне охвата (не делать)

- Не заводить 44 задачи; одна — helper + миграция класса А + гвард §4. Класс Б/В закрывается гвардом по касанию.
- Не менять семантику fail-open хуков (allow остаётся) — меняется только наличие следа.
- Не трогать `docs/leadv2/*` (симлинки контрольной плоскости) и не запускать полный `tests/run-all.sh`.
- Числа «9 ложных из 14», «363/480 вставок», «убиты два воркера» — со слов основателя; в журналах за день их нет, механизмы проверены по коду.

## 6. Источники

Таблицы помощников: scratchpad `sweep-A.md` (20 строк, 15 файлов прочитаны целиком) и `sweep-B.md` (23 строки, 19 файлов целиком); все места класса А и Б перепроверены мной `sed -n` по живому дереву 2026-09-04. Журналы: `persona-engine/docs/leadv2/tasks/dispatch-{593bc3e2,c19c728f,e9272511,4e975d5a,e3d372a1}/journal.md`. Образец правильной формы: `plugins/leadv2/scripts/leadv2-dispatch-code.sh:4285-4310` (коммит eb747f65).

DELIVERABLE_COMPLETE
