# W1-QUOTA-DAEMON-01 — квоты по моделям и живой демон (§1 пп. 1.1-гранулярность, 1.5)

Коммит: 2e95c5ef (worktree-w1-quota-daemon). Артефакты: `docs/handoff/w1-quota-daemon/mutation-control/`.

## Что измерено у провайдеров до строки кода (живые пробы 2026-09-09, все артефакты в транскрипте линии)

- **GLM** `GET https://api.z.ai/api/monitor/usage/quota/limit`: ровно два `TOKENS_LIMIT` окна
  аккаунт-уровня (5h 24%, weekly 16%) + `TIME_LIMIT` с per-`modelCode` usageDetails (search-prime /
  web-reader / zread — это кредиты инструментов, НЕ чат-модели). Параметр `?model=glm-5.3` и
  `?model=glm-5.3-flash` игнорируются — payload идентичен. Кандидаты `/token/detail`, `/quota/limit/list`,
  `/quota/details`, `/usage/details`, `/statistics`, `/quota/usage` — все 404. Документация
  docs.z.ai/devpack/overview: «Each plan is subject to both a 5-hour usage limit and a weekly usage
  limit… All plans support GLM-5.3, GLM-5.3-Flash» — **один общий пул на план**, потребление
  взвешивается множителями по модели. Вывод: провайдер НЕ считает квоту по моделям; честная
  модельная гранулярность — АТРИБУЦИЯ расхода.
- **Codex** `GET https://chatgpt.com/backend-api/wham/usage` (после refresh): `rate_limit.primary_window`
  — единственное окно (604800 c = 168ч), `secondary_window: null`; `additional_rate_limits[]` — по
  metered_feature, не по тирам; `model_usage` — флаги доступности. Вывод: провайдер меряет АККАУНТ,
  per-tier квоты не существует (наш тир — концепция диспатча: volume=gpt-5.6-luna/cost 3,
  standard=gpt-5.6-terra/4, top=gpt-5.6-sol/7 из leadv2-routing.yaml).
- **Anthropic-совместимый endpoint GLM** (`POST /api/anthropic/v1/messages`, обе модели, 200):
  ratelimit-заголовков нет — второго источника модельной гранулярности тоже нет.
- Источник атрибуции — наш собственный burn DB `~/.claude/burn/history.db`, таблица `turn_events`
  (ts/model/input/output; живые строки: glm-5.3 — 3668, glm-5.3-flash — 341).

## Часть A — гранулярность (leadv2-quota-read.py, leadv2-quota-live.sh)

Агрегатные ключи провайдеров НЕ изменены — арбитр (`_uraw[provider]`) и гейты читают прежние поля.
Аддитивно:

- `glm.models` — по каждой модели (`glm-5.3`, `glm-5.3-flash`; env `LEADV2_QUOTA_GLM_MODELS`):
  СВОИ окна с настоящими периодами (копии реальных 5h/weekly окон пула) + `attributed.five_hour/weekly`:
  `utilization_pct` = доля модели в измеренном расходе × процент пула, `share_pct`, `tokens`,
  `basis=burn-db-turn-events`. Нет burn-данных → `null` + `basis=burn-db-unavailable`, никогда не 0 и
  никогда не выдумано. Окно атрибуции = [reset − период, now] по каждому окну.
- `codex.tiers` — volume/standard/top: каждый ключ несёт ЕДИНСТВЕННОЕ реальное аккаунтное окно,
  `window_shape="weekly"` (именовано по ИЗМЕРЕННОМУ `limit_window_seconds`, словарь {18000:five_hour,
  604800:weekly} — 5h окно НИКОГДА не выдумывается), `shared_account_pool: true`, model/cost ти́ра.
- `normalize_payload` переобогащает вложенные окна при чтении из кэша (hours_to_reset живой).
- `leadv2-quota-live.sh` report рисует строки атрибуции и тиров; json проносит granularность как есть.

## Часть B — живой демон (новый файл: `plugins/leadv2/scripts/leadv2-quota-daemon.py`)

Расширенный существующий компонент, словами: **проб-слой скорера** — `leadv2-quota-read.py`, который
`leadv2-claude-profile-select.sh` вызывает на каждый профиль и чьи payloads скорит
`lib/leadv2-claude-profile-pick.py` (binding window `usable_now = remaining_pct / hours_to_reset`,
five_hour vs seven_day, без max()). Ни селектор, ни скорер, ни арбитр не правились — ридер теперь
сначала консультирует снапшот демона (`LEADV2_QUOTA_DAEMON=0` отключает), и пробы скорера становятся
мгновенными чтениями снапшота без логина на каждый запрос. Ключи консульта повторяют формы проб
селектора: `anthropic:service:<svc>` (env ACTIVE_SERVICE), `anthropic:file:<path>`
(--credential-file), дефолтная перечисление — `anthropic`.

Демон: singleton (pidfile+unix socket), поллит каждый источник через ТОТ ЖЕ ридер (единый источник
правды: ротация+write-back codex, кейчейн-перечисление anthropic — всё в quota-read.py), каденции
45/45/55 c (env), снапшот `snapshot.json` — атомарный data-plane, сокет — control-plane
(status/shutdown/query). `query --max-age 60` — ЕДИНАЯ команда приёмки №1. Реестр профилей
(claude-profiles.tsv) пересканируется — новые слоты подхватываются без рестарта. Ошибка источника —
последний реальный payload + растущий возраст, число не выдумывается.

**Codex login-once:** `quota-read.py` переиспользует access-токен с диска
(`LEADV2_QUOTA_CODEX_ACCESS_REUSE_S`, 45 мин) — поллинг хоть каждые 45с, ротация ~1/час; перед
ротацией файл перечитывается (не затираем параллельный refresh codex CLI); 401/403 на переиспользованном
токене → ровно одна ротация + один ретрай. Живая проверка: `refreshed=False access_reused=True`.

**Честный предел (записан заранее, а не обнаружен потом):** демон НЕ решает проблему собственного
окна лида — интерактивную сессию нельзя переключить на другую учётку на лету; это §3 плана, отдельная
работа. Демон закрывает измерение и маршрутизацию диспатченных рук.

## Приёмка

1. **Одна команда**: `plugins/leadv2/scripts/leadv2-quota-daemon.py query --max-age 60`. Живой прогон
   2026-09-09T19:39Z, rc=0 (полный вывод):

```
leadv2-quota-daemon started (pid 11342)
anthropic                                  max_20x/five_hour            remaining=?% resets_in=?h (age 8.8s)
anthropic                                  max_20x/seven_day            remaining=?% resets_in=?h (age 8.8s)
anthropic                                  max_5x/five_hour             remaining=0.0% resets_in=0.67h (age 8.8s)
anthropic                                  max_5x/seven_day             remaining=73.0% resets_in=143.34h (age 8.8s)
anthropic                                  max_20x/five_hour            remaining=97.0% resets_in=2.67h (age 8.8s)
anthropic                                  max_20x/seven_day            remaining=38.0% resets_in=50.34h (age 8.8s)
anthropic:service:Claude Code-credentials-5a3c2328 max_5x/five_hour    remaining=0.0% resets_in=0.67h (age 9.4s)
anthropic:service:Claude Code-credentials-5a3c2328 max_5x/seven_day    remaining=73.0% resets_in=143.34h (age 9.4s)
anthropic:service:Claude Code-credentials-eb6c5b97 max_20x/five_hour   remaining=97.0% resets_in=2.68h (age 9.2s)
anthropic:service:Claude Code-credentials-eb6c5b97 max_20x/seven_day   remaining=38.0% resets_in=50.34h (age 9.2s)
codex                                      primary                      remaining=62.0% resets_in=129.71h (age 9.1s)
codex                                      tiers standard/top/volume share one account window (shape=weekly)
glm                                        five_hour                    remaining=67.0% resets_in=1.22h (age 9.5s)
glm                                        weekly                       remaining=82.0% resets_in=146.29h (age 9.5s)
glm                                        model glm-5.3        attributed 5h=27.04% weekly=15.23% (share 81.95%)
glm                                        model glm-5.3-flash  attributed 5h=5.96% weekly=2.77% (share 18.05%)
query_rc=0
```

   Оба окна у GLM и каждого anthropic-счёта, единственное недельное у codex, возраст ≤ 9.5с,
   интерактивного логина нет: codex `refreshed=False access_reused=True wrote_back=False` — ноль
   ротаций за прогон. `?` у unmetered-счётов — честный fail-open (usage-endpoint не отдаёт окна
   этому классу счёта), никогда не 0.
2. **Сюита**: `T1 glm-models-distinct-attributed-utilization` — фикстуры с расходом 9000/1000 →
   attributed 36.0 vs 4.0 (разные), агрегатный ключ `"glm"` читается прежними полями (`T2`).
3. **Сюита**: `T4 codex-tiers-weekly-only-no-invented-five-hour` — five_hour отсутствует у всех тиров,
   window_shape=weekly, limit_window_seconds=604800.
4. **Негативный контроль**: мутант `for m in names[:1]:` (модели схлопнуты в один ключ ВНУТРИ тела
   `build_glm_models`) → сюита красная rc=1, в т.ч. названный T1 (`glm-5.3-flash=None`);
   `leadv2-mutation-control.sh` артефакт `20260909T194109Z-62478.txt`: baseline_rc=0,
   red_line=`glm-models-both-keys-present -- ['glm-5.3']`, rc=0 (ok). Лид прогоняет мутацию независимо.
5. Полные зелёный/красный прогоны ниже.

### Зелёный прогон (test-quota-model-tier-granularity.sh, rc=0)

```
[TEST] PASS: glm-status-ok
[TEST] PASS: glm-models-both-keys-present
[TEST] PASS: T1 glm-models-distinct-attributed-utilization
[TEST] PASS: glm-models-distinct-weekly-too
[TEST] PASS: glm-attribution-basis-named
[TEST] PASS: T2 glm-aggregate-key-backcompat
[TEST] PASS: T3 glm-model-keys-carry-real-window-periods
[TEST] PASS: T7 glm-attribution-unavailable-fail-open
[TEST] PASS: T6 codex-access-reuse-login-once
[TEST] PASS: codex-rotation-writeback
[TEST] PASS: T4 codex-tiers-weekly-only-no-invented-five-hour
[TEST] PASS: codex-tier-identity-matches-routing-matrix
[TEST] PASS: T5 codex-aggregate-backcompat
[TEST] PASS: T8 normalize-payload-upgrades-nested-granularity
[TEST] PASS: normalize-payload-upgrades-codex-tiers
[TEST] python part: 0 failure(s)
--- leadv2-quota-live.sh json (fake reader) ---
[TEST] PASS: T9 quota-live-json-arbiter-contract -- aggregate keys glm/codex/anthropic intact, granularity rides through
[TEST] PASS: report mode renders glm model attribution + codex tier lines
SUITE OK: quota model/tier granularity

```

### Красный прогон (тот же файл под мутантом names[:1], rc=1)

```
[TEST] PASS: glm-status-ok
[TEST] FAIL: glm-models-both-keys-present -- ['glm-5.3']
[TEST] FAIL: T1 glm-models-distinct-attributed-utilization -- glm-5.3=36.0 glm-5.3-flash=None (expected 36.0 / 4.0: shares 90/10 of pooled 40%)
[TEST] FAIL: glm-models-distinct-weekly-too -- weekly attributed 18.0/None
[TEST] PASS: glm-attribution-basis-named
[TEST] PASS: T2 glm-aggregate-key-backcompat
[TEST] PASS: T3 glm-model-keys-carry-real-window-periods
[TEST] PASS: T7 glm-attribution-unavailable-fail-open
[TEST] PASS: T6 codex-access-reuse-login-once
[TEST] PASS: codex-rotation-writeback
[TEST] PASS: T4 codex-tiers-weekly-only-no-invented-five-hour
[TEST] PASS: codex-tier-identity-matches-routing-matrix
[TEST] PASS: T5 codex-aggregate-backcompat
[TEST] PASS: T8 normalize-payload-upgrades-nested-granularity
[TEST] PASS: normalize-payload-upgrades-codex-tiers
[TEST] python part: 3 failure(s)
--- leadv2-quota-live.sh json (fake reader) ---
[TEST] PASS: T9 quota-live-json-arbiter-contract -- aggregate keys glm/codex/anthropic intact, granularity rides through
[TEST] PASS: report mode renders glm model attribution + codex tier lines
SUITE FAIL: python part

```

### Артефакт leadv2-mutation-control.sh

```
suite=plugins/leadv2/scripts/tests/test-quota-model-tier-granularity.sh
file=plugins/leadv2/scripts/leadv2-quota-read.py
anchor=s/    for m in names:/    for m in names[:1]:/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: glm-models-both-keys-present -- ['glm-5.3']
diff_hash=e8cec3b5eb5832c05ae88394a7085b687f139af6af8c1338fb0f2a1f79f41855
lane_diff_hash=fc1539d9ffc3b8d5e1893d2a55486919f53eda8ea325252286e480d3bd5a1de2

```

## Фальсификационный набор (финальный, после последнего фикса)

- `bash -n`: quota-live.sh, обе сюиты — OK.
- `python3 -m py_compile`: quota-read.py, quota-daemon.py — OK.
- `tests/run-all.sh --scope changed`: **8 passed, 0 failed** (сюиты гранулярности и демона выбраны
  своими run-all-triggers и вошли в прогон).
- Живой демон: start → query (возраст ≤9.5с) → quota-live consult (fetched_at демона) → stop — чисто.

## Изменённые файлы

- `plugins/leadv2/scripts/leadv2-quota-read.py` — гранулярность (models/tiers), codex login-once, консульт демона.
- `plugins/leadv2/scripts/leadv2-quota-live.sh` — report-строки гранулярности, док-заголовок.
- `plugins/leadv2/scripts/leadv2-quota-daemon.py` — НОВЫЙ демон.
- `plugins/leadv2/scripts/tests/test-quota-model-tier-granularity.sh` — НОВАЯ сюита (T1-T9).
- `plugins/leadv2/scripts/tests/test-quota-daemon.sh` — НОВАЯ сюита (T1-T7).

Off-limits не тронуты: profile-pick.py, profile-select.sh, route-arbiter.sh, router.sh, dispatch-code.sh.
