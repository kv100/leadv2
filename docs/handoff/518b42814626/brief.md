# WAVE0-ROOT-RESOLUTION-AND-ARBITER-MUST-NOT-GUESS-01
ряды `518b42814626` (state-path под zsh) и `5d2f022674a6` (арбитр молча умирает на Linux)

## Первым делом прочитать обе улики целиком
```
cd /Users/kostiantyn.vlasenko/Projects/persona-engine
grep -A14 "id: 518b42814626" docs/tasks.yaml
grep -A18 "id: 5d2f022674a6" docs/tasks.yaml
```

## Ряд 1 — `STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01`
`plugins/leadv2/scripts/leadv2-state-path.sh:10` разыменовывает `BASH_SOURCE[0]`,
которая **не установлена**, когда реестр подключают из zsh. Резолвер не отказывает
закрыто — он молча падает на путь репо.

Замер 2026-09-04: при корректно выставленном `LEADV2_PROJECT_ROOT` `_leadv2_yaml_file`
вернул `~/Projects/leadv2/docs/leadv2/active.yaml` вместо живого
`~/.claude/leadv2-state/leadv2/active.yaml`; затем `leadv2_active_unregister`
отрисовал посторонний `LEAD_V2_STATE.md`, ничего не удалил и вернул rc=0.
Те же вызовы под `bash -c` разрешили корень верно и удалили ряды (живых 7 → 3).

**Что сделать:** разрешение корня обязано **отказывать закрыто, а не угадывать**.
Определить оболочку и источник пути явно; отсутствие `BASH_SOURCE` — это отказ
с внятной строкой, а не тихий откат на путь репо.

## Ряд 2 — `ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01`
`route_arbiter` на Linux возвращает код 2 с **нулём байт и на stdout, и на stderr**;
идентичный вызов на macOS возвращает 0 с полной строкой маршрута. Замер 2026-09-03 в
контейнере debian bookworm (jq, python3, sqlite3, bc, uuid-runtime, coreutils на месте),
на той же фикстуре квот. Подтверждено, что это **предсуществующий** дефект: main и линия
`CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01` падают одинаково — ни одна линия не виновата.

Два следствия: каждая арбитро-зависимая сюита в CI (Linux) бессмысленна; и отказ
**молчаливый** — ненулевой код без диагностики неотличим от краха, отсутствия
зависимости и отказа, так что отладка начинается с нулём информации.

**Что сделать, в этом порядке:** (1) найти, откуда берётся `exit 2`, и заставить его
печатать диагностику ПЕРЕД возвратом — это ценно само по себе; (2) затем починить
платформенную разницу.

**Как замерять:** код возврата снимать отдельной строкой, никогда после пайпа; байты
stdout и stderr считать раздельно. Иначе пустой вывод и замаскированный код спутают
снова — так уже случилось дважды при измерении.

## Write set — только эти файлы
- `plugins/leadv2/scripts/leadv2-state-path.sh`
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter*.sh`
- новые сюиты под `plugins/leadv2/scripts/tests/`

## Off-limits
`leadv2-active-registry.sh` и девять файлов линии `wave0-lib-silent-swallow`
(`lib/leadv2-receipt-freshness.sh`, `lib/leadv2-freepool-gate.sh`, `lib/leadv2-lane-state.sh`,
`lib/leadv2-brain-record.sh`, `lib/leadv2-dod-gate.sh`, `lib/leadv2-worker-epilogue.sh`,
`leadv2-journal.sh`, `leadv2-phase-record.sh`, `leadv2-lanes-snapshot.sh`),
`leadv2-lane-salvage.sh`, `leadv2-deploy-merge.sh`.

## Приёмка — обязательный негативный контроль
Проба резолвера под `zsh -c` обязана ОТКАЗАТЬ, а не вернуть путь репо; под `bash -c`
вернуть живой путь состояния. Проба арбитра обязана печатать диагностику на stderr
при любом ненулевом коде — тест считает байты stderr и требует > 0.
Негативный контроль: вернуть тихий откат / убрать диагностику ВНУТРИ тела функции →
сюиты краснеют. В отчёт — зелёный и красный прогон целиком.
