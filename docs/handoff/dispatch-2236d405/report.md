# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01 — мёртвый арм неотличим от занятого

## Defect

2026-09-04: фрипул не брал линий сутки. `leadv2-freepool-gate.sh check` отказывал
`arm_down`, но арбитр (`leadv2-route-arbiter.sh`) вызывал шлюз как
`bash "$free_gate" check >/dev/null 2>&1` — единственное, что доходило до решения,
был голый rc. `free_ok=false` рендерился как `util_freepool=100` — то же число,
что и у арма, исчерпавшего квоту. Прокси лежал, а журнал говорил «занят».

## Changes

| File | Change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh` | (1) `check_liveness` оставляет HTTP-код в `FREEPOOL_LAST_HEALTH_CODE` и нормализует двойное `000` от connection-refused (curl пишет `000` через `-w` И срабатывает fallback — сюита поймала `health=000000` на первом прогоне); (2) `check` при arm_down печатает громкую строку с кодом и словами «NOT quota exhaustion»; (3) новая подкоманда `liveness`: /health 2xx + /v1/models непустой, каждый отказ — именованная причина. |
| `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` | (1) stderr шлюза захватывается, из него парсится маркер `LEADV2_DISPATCH_REFUSED: <reason>`; (2) при `arm_down` арбитр сам печатает `[route-arbiter] FREEPOOL ARM DOWN: ...` в свой stderr (это и есть журнал диспетчера); (3) рендер: мёртвый фрипул = `util_freepool=down` (слово), любой отказ шлюза = `freepool_gate=<reason>` в строке решения. Семантика сортировки/отбора не тронута: pct для down остаётся 100, мёртвый арм по-прежнему исключается из цепочки. |
| `plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh` | Новая сюита (stem-конвенция: изменение `lib/leadv2-freepool-gate.sh` выбирает её само). 9 кейсов, реальный loopback HTTP-стаб + гарантированно мёртвый порт. |

## New observables (контракт)

| Состояние | Строка решения арбитра | stderr |
|---|---|---|
| прокси жив | `util_freepool=0` | — |
| прокси мёртв (000/no listener) | `util_freepool=down ... freepool_gate=arm_down` | `[route-arbiter] FREEPOOL ARM DOWN: gate refused arm_down (proxy unreachable) — NOT quota exhaustion; ... Restart with: plugins/leadv2/scripts/freepool-proxy.sh start` |
| шлюз отказал иначе (gate_broken/pin_drift) | `util_freepool=100 ... freepool_gate=<reason>` | — |

`gate liveness` (для человека/пульса):
```
[freepool-liveness] ok health=200 models=1041 url=http://127.0.0.1:8317/health
[freepool-liveness] arm_down health=000 reason=unreachable url=...
[freepool-liveness] arm_down health=503 reason=health_non_2xx url=...
[freepool-liveness] gate_broken health=200 reason=models_empty models_url=...
```
Токен `freepool_gate=arm_down` едет в журнал диспетчера автоматически: `_arb_util`
в `leadv2-dispatch-code.sh:7628` захватывает хвост строки от `util_glm=` и
вклеивает его в `route_resolved ...` verbatim — без изменений диспетчера.

## Evidence: live probes (2026-09-04, proxy up after lead's restart)

```
$ bash plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh liveness
[freepool-liveness] ok health=200 models=1041 url=http://127.0.0.1:8317/health
rc=0
$ bash plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh check
rc=0
$ curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8317/health
200
$ curl -s http://127.0.0.1:8317/v1/models | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]))'
1041
```

Arbiter, живой прокси (реальный шлюз, стаб quota-live, остальные армы дёшевы):
```
arm=freepool model=freepool-default tier=standard effort=medium reason=cheapest_capable chain=freepool,glm util_glm=40 util_codex=20 util_claude=20 util_freepool=0 ... 
rc=0, stderr пуст
```
Arbiter, мёртвый порт (`FREEPOOL_PROXY_URL=http://127.0.0.1:9`):
```
arm=glm model=glm-5.3 tier=standard effort=medium reason=cheapest_capable chain=glm util_glm=40 util_codex=20 util_claude=20 util_freepool=down ... freepool_gate=arm_down
rc=0
stderr:
[route-arbiter] FREEPOOL ARM DOWN: gate refused arm_down (proxy unreachable) — NOT quota exhaustion; util_freepool=down on this line. Restart with: plugins/leadv2/scripts/freepool-proxy.sh start
```

## Evidence: suite (10 consecutive runs, all rc)

```
run1 rc=0
run2 rc=0
run3 rc=0
run4 rc=0
run5 rc=0
run6 rc=0
run7 rc=0
run8 rc=0
run9 rc=0
run10 rc=0
```

Green output (каждый прогон):
```
PASS: liveness green: healthy proxy reports ok with models count ([freepool-liveness] ok health=200 models=3 url=http://127.0.0.1:63941/health)
PASS: liveness red: proxy answering 000 is named arm_down/unreachable (not a number)
PASS: liveness red: port listening but unhealthy (503) is named arm_down/health_non_2xx
PASS: liveness red: healthy port with empty /v1/models is named gate_broken/models_empty
PASS: gate check red: arm_down stderr names http_code=000 and says NOT quota exhaustion
PASS: arbiter names DEAD as a word: util_freepool=down + freepool_gate=arm_down + loud stderr
PASS: arbiter healthy: util_freepool=0, no gate token, no ARM DOWN noise
PASS: arbiter contrast: gate_broken stays util_freepool=100 + freepool_gate=gate_broken (busy is a number, dead is the word)
PASS: hermetic: routing.yaml and freepool-arm.yaml unmodified
freepool-liveness: 9 passed, 0 failed
```

Red-before-fix (мой же первый прогон поймал баг двойного 000 в НОВОМ коде — фикс в `check_liveness`):
```
FAIL: liveness red: proxy answering 000 is named arm_down/unreachable (not a number) -- rc=1 out=[freepool-liveness] arm_down health=000000 reason=health_non_2xx url=http://127.0.0.1:63809/health err=LEADV2_DISPATCH_REFUSED: arm_down
```

## Evidence: runner selection (`LEADV2_RUN_ALL_SELECT_ONLY=1`)

```
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-arm-admission.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-effort-routing.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-complexity-routing.sh
run-all: 13 selected, scope=changed, select_only=1
```
(полный список включает always-on core-offline + 3 status-surface; сокращено до
стем-выбранных. Сюита выбрана ДО коммита — по stem-конвенции от изменённого
`lib/leadv2-freepool-gate.sh`; после коммита выбирается и своим собственным
изменением.)

## Evidence: mutation controls (по одному на каждое изменённое требование)

Артефакты: `docs/handoff/dispatch-2236d405/mutation-control/*.txt` (force-add под
blanket gitignore). Мутация внутри тела функции, доказательство — пара
`baseline_rc`/`mutated_rc` + red-строка, не diff_hash.

**MC-1 — «прокси отвечает 000 → сюита живости краснеет и называет причину».**
Мутант: в `check_liveness` проверка 2xx заменена на `[[ "${code}" != "000" ]]`
(health-проба нейтрализована — мёртвый порт проходит как здоровый).
```
suite=plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh
file=plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh
baseline_rc=0
mutated_rc=1
red_line=FAIL: liveness red: port listening but unhealthy (503) is named arm_down/health_non_2xx -- rc=0 out=[freepool-liveness] ok health=503 models=1 url=http://127.0.0.1:64316/health
```

**MC-2 — «мёртвый арм называется мёртвым в строке решения, не числом 100».**
Мутант: из `ufmt()` арбитра удалён down-рендер (`'down' if ... else` вырезан sed) —
мёртвый фрипул снова печатается как 100.
```
suite=plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh
file=plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
baseline_rc=0
mutated_rc=1
red_line=FAIL: arbiter names DEAD as a word: util_freepool=down + freepool_gate=arm_down + loud stderr -- ... util_freepool=100 ... freepool_gate=arm_down ...
```

**MC-3 — «громкая строка в журнал при arm_down».**
Мутант: текст громкой строки арбитра заменён на тихий (`FREEPOOL ARM DOWN: gate
refused arm_down` → `freepool gate refused: arm_down`).
```
suite=plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh
file=plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
baseline_rc=0
mutated_rc=1
red_line=FAIL: arbiter names DEAD as a word: ... -- ... err=[route-arbiter] freepool gate refused: arm_down (proxy unreachable) ...
```

## Evidence: regression sweep (mapping-ряды арбитра + freepool-семейство)

| Suite | My diff | Clean HEAD (тот же прогон) |
|---|---|---|
| test-route-arbiter-symlink-install | rc=0 | — |
| test-quota-reset-arbiter | rc=0 | — |
| test-freepool-capability-floor | rc=0 | — |
| test-freepool-gets-work | rc=0 | — |
| test-arm-admission | rc=0 | — |
| test-arm-capability-honoured | rc=0 | — |
| test-freepool-model-liveness | rc=0 | — |
| test-freepool-model-selector | rc=0 | — |
| test-effort-routing | rc=1 (5 FAIL) | rc=1 (те же 5 FAIL — предсуществующий) |
| test-complexity-routing | rc=1 (обрыв до SUMMARY) | rc=1 (идентично — предсуществующий) |
| test-freepool-pin-drift | rc=1 (1 FAIL: install-кейс трогает реальный ~/.fcc) | rc=1 (тот же FAIL — предсуществующий) |

Проверка честная: оба файла откатывались на HEAD (`git checkout --`), реды
воспроизводятся без моего диффа, FAIL-подписи идентичны по модулю util-токенов.
Ни один ред не связан с изменёнными строками.

## Evidence: self-check

```
bash -n plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh   -> GATE_SYNTAX_OK
bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh   -> ARBITER_SYNTAX_OK
bash -n plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh -> SYNTAX_OK
python-файлов в диффе нет
tests/run-all.sh --scope changed -> см. ниже
```

### tests/run-all.sh --scope changed (полный прогон)

RUNALL_PLACEHOLDER

## Auto-start proposal (отдельное предложение, НЕ реализовано)

Миссия прямо запрещает автоподъём без разрешения. Предложение на будущее: шлюз
при `health=000` может запускать `freepool-proxy.sh start` (best-effort, один
раз в N минут, только при `FREEPOOL_AUTOSTART=1`, выключено по умолчанию) и
повторять пробу один раз — поднявшийся прокси превращает отказ в успех без
участия ведущей. Риск: маскирует реальную смерть прокси под «само поднялось» —
поэтому автоподъём обязан журналировать `autostart_attempted=1` тем же громким
форматом, что и arm_down. До одобрения основателя — не включать.

## Boundaries

Правлено: только три файла выше + этот каталог handoff. Не тронуты: `main`,
`docs/leadv2/`, `tests/known-red-suites.txt`, `tests/run-all.sh`, ассерты не
ослаблены (всюду добавлены только новые проверки; контраст-кейс 7 фиксирует, что
число 100 остаётся у gate_broken).
