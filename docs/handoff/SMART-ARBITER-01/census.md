# SMART-ARBITER-01 — перепись решений арбитра

Метод: два поисковых шаблона, наложенных на каждый вход каждого решения.
1. **Unknown→оптимизм**: что происходит, когда вход = null / пустая строка /
   `status != ok` / таймаут / отсутствующий файл — превращается ли это в
   благоприятное число вместо пессимистичного или явного отказа.
2. **Круговая зависимость**: решение B выведено из результата решения A,
   хотя должно выводиться из свойств задачи.

Источники: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` (далее
«arbiter»), `plugins/leadv2/config/leadv2-routing.yaml` («yaml»),
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` («dispatch»),
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` («resolver»).
Эвиденция живых решений: 569 строк `route_resolved by=arbiter` в
`docs/leadv2/tasks/*/journal.md` главного чекаута, из них 190 за
2026-09-03/04 (далее «24ч»).

## Калибровка метода: 3/3

Метод прогнан ДО сверки с известным списком. Результат сверки:

| калибровочная дыра | поймана? | как |
|---|---|---|
| #1 active-флаг claude-квоты → pct=0 (починено 217168a7) | **да** | шаблон unknown→оптимизм вышел на место фикса (arbiter:198-224, тест (h) зелёный, живое `util_claude=74`) и нашёл его живой остаток той же формы: arbiter:234 `return empty` при `status=ok` и всех null-pct отдаёт pct=0.0 («провайдер бесплатен») — см. дыру D4 |
| #2 effort по тегам победившего арма | **да** | шаблон круговой зависимости: effort_matrix ключуется на tags/kinds ячейки-победителя (arbiter:404-419, yaml:127-136); живое следствие `build → glm-flash effort=low`, 43 решения за 24ч |
| #3 «codex and claude have no ceiling reader at all» (yaml:33-37) | **да, с уточнением** | производный вопрос «кто ЕЙ enforcing на каждом пути» показал: комментарий полу-устарел — codex на fallback-лестнице имеет гейт (dispatch:7812-7822 codex_quota_gate), claude на лестнице не читается ВОВСЕ; внутри самого арбитра потолки читаются у всех трёх (:281-286). Живой остаток #3 = «нет потолка claude на лестнице»; последствие за 24ч не доказано (arbiter_broken=0 строк в 569) |

## Перепись решений

| # | решение | вход | откуда вход | когда вход неизвестен/сломан | файл:строка |
|---|---|---|---|---|---|
| D1 | кандидаты арма (capable-фильтр) | kind/work_kind, size/task_class, protected/safety/publish/ui_judgment, allowed_arms + matrix | descriptor от dispatch:7856-7862; matrix из yaml:59-114 | kind вне словаря → молча `code` (оптимистично, задокументировано); size вне словаря → `standard` + токен size_unmapped; allowed_arms отсутствует → ограничения нет | arbiter:80-116, 312 |
| D2 | «capable» = trust | require_trusted = safety∨publish∨ui_judgment ∨ (protected ∧ writes_prod) | флаги descriptor'а; writes_prod = kind∉(review,audit,plan,recon) | неявные входы → false → арм допускается (оптимистично, но защищено жёсткими флагами) | arbiter:108-114 |
| D3 | потолок квоты арма | util(provider) ≥ work_pct/review_pct | quota-live json + yaml:38-41 | потолок отсутствует в yaml → 100 → «свободен» (оптимистично: нет политики = нет лимита) | arbiter:281-286 |
| D4 | util(provider) | quota-live json | leadv2-quota-live.sh (по провайдеру) | `status!=ok` → 100 pessimistic (C3, ок). **ОСТАТОК ФОРМЫ #1**: `status=ok` + все pct null → `return empty` → pct=0.0, unknown=False — читается как «провайдер бесплатен» и не рендерится unknown_capped. UNVERIFIED живучесть: нужен живой json с ok и пустыми окнами; проверить контрактом leadv2-quota-read.py (ок-путь всегда пишет pct?) | arbiter:171-236, дыра на :234 |
| D5 | claude: какой аккаунт читается | accounts[].active, status, account_label | quota-live anthropic bucket | фикс 217168a7 на месте: active не-ok → fallback на ok-аккаунт того же label → любой ok → иначе 100 unknown | arbiter:198-224 |
| D6 | wait-vs-switch | hours_to_reset, period (WINDOW_PERIOD_HOURS или limit_window_seconds) | тот же json | reset нечитаем → полный период → «далеко» → switch; имя окна неизвестно → без wait (switch). Оба — switch-направление, wait никогда не фабрикуется | arbiter:159-170, 239-242 |
| D7 | capped(provider) | over_ceiling ∧ near_reset_wait | D3+D6 | над потолком + близкий reset → НЕ исключён (ждёт); иначе исключён | arbiter:294-298 |
| D8 | freepool gate | rc/`LEADV2_DISPATCH_REFUSED:` из gate | leadv2-freepool-gate.sh | gate отсутствует → free_rc=1 → 100 (пессимистично); arm_down рендерится словом `down` | arbiter:32-52, 186-188 |
| D9 | capability floor (freepool) | floor_mode (env>yaml>default), test_only | FREEPOOL_CAPABILITY_FLOOR / freepool-arm.yaml | неизвестное значение → следующий слой → default bulk_only (падение в сторону ограничения); живой режим bulk_only | arbiter:253-272, 352, 383 |
| D10 | complexity_penalty | complexity, duration_class | DC_COMPLEXITY/DC_DURATION_CLASS от task-judge (dispatch:7861) | **complexity=unknown → ни одно правило не матчится → штраф 0** — неизвестная сложность трактуется как «простая» (оптимистично, та же форма, что #1). За 24ч решений с complexity=unknown среди worker-строк: 0 (входит только в 1 reviewer-строку) — последствие не доказано | arbiter:310-311, 361-383 |
| D11 | effort | effort_matrix: tags/kinds/protected ПОБЕДИВШЕЙ ЯЧЕЙКИ | yaml:127-136 | нет матрицы/нет матча → medium. **КРУГОВАЯ (калибровочная #2)**: сначала выбран дешёвый арм, потом его теги cheap/mechanical выводят effort=low для написания кода. Живое: 43× `glm-flash effort=low` на build за 24ч (включая CACHE-TRUTH-01 — реальный скрипт-код), 130× effort=high через protected/теги безотносительно формы задачи | arbiter:404-419 |
| D12 | anti-sticky ротация | state-file arm | route-arbiter-last-arm json | битый/legacy файл → last='' → без ротации (безопасно) | arbiter:388-403 |
| D13 | отказ no_capable_cell | пустой capable | D1 | rc=68 → dispatch падает в лестницу (config-drift ≠ отказ) | arbiter:336-339, dispatch:7924-7935 |
| D14 | отказ all_arms_capped | ok пуст | D7 | rc=3 → dispatch exit 4 (жёсткий отказ). За 24ч: 6 строк, все с util_freepool=0/100 при полностью unknown_capped пробах — гейт здоров, но арм не в allowed_arms (см. D15) | arbiter:340-344 |
| D15 | **v1-роутер ДО арбитра** (не решение арбитра, но решает его вход) | signals: protected_path, safety_touched, … | protection_derived от write-set скана (dispatch:7846-7855); sonnet_exceptions | **устаревшая политика**: строка `safety_gate_publish_payments when: protected_path` (yaml:403-405) младше приказа основателя GLM-DOES-ANY-WORK-01 (2026-09-04 «любая работа») и всё ещё форсирует sonnet-primary + glm_excluded=True (resolver:722-733, exc-гейт :743-744) — glm не попадает в кандидаты protected-задач вовсе, матричная ячейка protected:true мертва на этом пути. 84 решения sonnet (cost 5) за 24ч при util_glm=13-31; прямые строки arm_excluded в dispatch-07401216 | dispatch:7860, resolver:722-744, yaml:403-405 |
| D16 | reason-токен журнала | arbiter-строка → sed | dispatch:7886 | жадный `.*reason=` крадёт `floor_reason` в `reason=`: 23 строки за 24ч с `reason=standard/code` вместо cheapest_capable — запись решения искажена | dispatch:7886, 7921 |
| D17 | review author-exclusion | author, review_rank таблица | dispatch_ladder review_rank (yaml:268-283) | D3-механизм полный: автор вне таблицы → ранг -inf → максимальный ранг доступных; <2 записей → явная ошибка, не пустой пул | resolver:320-350 |
| D18 | запись решения (_record) | decisions.jsonl | arbiter:319-335 | все ошибки записи молча проглатываются (`except: pass`) — решение могло не быть журналировано без следа | arbiter:319-335 |

## Ранжирование по живому последствию (24ч, 190 решений)

| ранг | дыра | неверных решений/24ч | действие |
|---|---|---|---|
| 1 | D15 устаревший protected_path→sonnet (glm не в кандидатах) | 84 (sonnet cost 5 при простаивающем glm cost 1) | **чиню** (FIX-2: удалить строку из канонического yaml — резолвер сам не сможет её применить) |
| 2 | D11 effort следует арму, не задаче | 43 (build на low) + 130 (high безотносительно задачи) | **чиню** (FIX-1: task-keyed строки effort_matrix имеют приоритет над arm-keyed; build ⇒ medium, review/plan/audit ⇒ high, docs/recon ⇒ low) |
| 3 | D16 reason затёрт floor_reason | 23 | **чиню** (FIX-3: якорь `[[:space:]]reason=` в sed) |
| 4 | D4 status=ok+null pct → pct=0.0 | 0 доказанных (форма жива, вхождения не пойманы) | отчёт, заводить задачей |
| 5 | codex-проба unknown 147/190 (кластер T17-T20 09-03 + флейк-базлайн) | направление пессимистичное (безопасное) | отчёт: надёжность пробы (ops), не логика |
| 6 | D10 complexity=unknown → штраф 0 | 0 worker-решений за 24ч | отчёт |
| 7 | D18 _record проглатывает ошибки | не измерено | отчёт |
| 8 | #3-остаток: потолок claude на fallback-лестнице не читается | arbiter_broken=0 в 569 строках — лестница не включалась | отчёт |
| 9 | D3 потолок отсутствует в yaml → нет лимита | 0 (все три провайдера описаны) | отчёт |
| 10 | D14 отказ при здоровом freepool (allowed_arms без него) | ≤6 | закрывается частично FIX-2 (protected-путь); общий вопрос «два мозга» — отдельной задачей |

## Находки фазы верификации (добавлено после правок)

- **D4 уточнён**: leadv2-quota-read.py передаёт upstream-значения как есть
  (:203 `l.get("percentage")`, :505-508 `fh.get("utilization")`) — контракт НЕ
  гарантирует не-null pct при status=ok, так что путь `:234 return empty`
  (pct=0.0, unknown=False) достижим при дрейфе схемы апстрима. Живого вхождения
  не поймано (UNVERIFIED); ловится живым `quota-live.sh json` в момент дрейфа.
- **D19 (новая)**: у test-route-arbiter.sh НЕ БЫЛО строки `# run-all-triggers:` —
  правка lib/leadv2-route-arbiter.sh выбирала под changed-scope все прочие
  арбитражные сюиты (effort-routing, quota-reset-arbiter,
  route-arbiter-symlink-install), кроме ЕГО СОБСТВЕННОЙ первичной. Доказано
  выводом `[SELECT]` до правки (46 сюит, test-route-arbiter.sh отсутствует).
  Починено в этой же линии: строка триггеров добавлена.
- **codex-проба**: гистограмма unknown_capped за 24ч — кластер T17-T20
  2026-09-03 (79 вхождений за 4 часа — вечерний отказ пробы) плюс флейк-базлайн
  1-6/час остальное время; на момент снятия живого прогона проба здорова
  (`windows: primary 0%, secondary 92%`, арбитр видит util_codex=92). Направление
  unknown→capped пессимистично (безопасно) — надёжность пробы есть ops-вопрос,
  не логическая дыра.
- **D16 корреляция**: все 23 испорченные reason-строки за 24ч содержат
  floor_reason — ровно та форма, что ловится пробой floor-мутации в
  test-freepool-gets-work.sh (кейс красный на ДО-фиксном коде, зелёный после).
- **Фикстура контроля D (пре-существующая, не дыра арбитра)**: негативный
  контроль D в test-freepool-gets-work.sh копировал диспетчер в $TMP; диспетчер
  читает dispatchable-arms через importlib ОТНОСИТЕЛЬНО СВОЕГО пути — копия в
  $TMP деградирует до fallback-списка армов и отказывает `all_arms_capped`
  (rc=4), контроль вечно красный независимо от своей мутации. Доказано на
  HEAD-байтах (без правок этой линии): копия HEAD-диспетчера в $TMP → rc=4;
  та же копия в scripts-директории с мутацией → rc=0, arm=codex, строка
  override подавлена. Починено переносом копии в SCRIPTS_DIR (как у контроля A).
