# RECOVER-WAVE1-TEN-01 — десять веток волны В1, все с настоящим конфликтом кода

Волна В1 в `docs/WAVES.md` — «перенос готовых веток в main». Осталось ровно десять, и **все
десять упираются в конфликт кода**, а не в контрольную плоскость: контрольную плоскость я уже
разрешила петлёй, после неё остаются только настоящие расхождения.

В каждой ветке настоящая работа, замерено против `merge-base`:

| Ветка | Объём | Где конфликт |
|---|---|---|
| `worktree-PREPASS-PROVIDER-FALLBACK-01-R6` | 8 файлов, 27 268 вставок | `leadv2-dispatch-code.sh` |
| `worktree-PREPASS-PROVIDER-FALLBACK-01-R5` | 3 файла, 7 260 | `leadv2-dispatch-code.sh` |
| `worktree-5e57c5ff` | 39 файлов, 2 190 | `leadv2-dispatch-code.sh` + др. |
| `worktree-83c44855` | 12 файлов, 1 971 | `config/leadv2-routing.yaml`, `leadv2-dispatch-code.sh` |
| `worktree-f7f1c2c8` | 10 файлов, 1 299 | `docs/handoff/REPORT-ONLY-GATE-01/report.md` и др. |
| `worktree-100a892d` | 17 файлов, 761 | `.claude/ref/leadv2-routing.yaml`, `leadv2-dispatch-code.sh` |
| `worktree-049e0e9e` | 4 файла, 712 | `leadv2-dispatch-product-close.sh` |
| `worktree-PLUGIN-RELIABILITY-01` | 9 файлов, 687 | `leadv2-dispatch-code.sh` |
| `worktree-BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01` | 8 файлов, 620 | `hooks/leadv2-single-lead-beat.sh` |
| `worktree-d784b987` | 8 файлов, 592 | `leadv2-dispatch-code.sh`, `leadv2-hel*` |

## Порядок

Снизу вверх по объёму: `d784b987` → … → `PREPASS-R6` последней. Мелкие дадут понимание файла,
к большим подойдёшь подготовленной.

**Шаг 0 перед каждым слиянием:** `git checkout -- docs/LEAD_V2_STATE.md`. Он вечно грязный, и
git отказывается сливать ВООБЩЕ, ещё до конфликтов. Это отказ ДО конфликта, а выглядит как
«ветка не сливается».

**Шаг 1:** запусти готовую петлю — она разрешит контрольную плоскость в пользу main и откатится,
оставив ровно конфликты кода:
`/private/tmp/claude-503/-Users-kostiantyn-vlasenko-Projects-persona-engine/fe5013c6-05e5-4e63-84da-be3e9039517a/scratchpad/recover-merge.sh worktree-<имя>`

**Шаг 2:** разрешай по смыслу. Обе стороны — чья-то настоящая работа. Читай обе, пойми, что
делала каждая, собери версию, сохраняющую ОБА намерения. Несовместимы — опиши обе в отчёте и
оставь ветку неслитой; молчаливый выбор стороны недопустим.

## Что знать заранее про `leadv2-dispatch-code.sh`

Семь из десяти конфликтуют именно в нём, и он менялся сегодня дважды: фазовый гейт теперь
печатает `required=` и `unmet=` рядом с `missing=` (коммит `c668e5ab`), и там же сужен отказ
`phase-record` до целостности артефакта. Если сторона ветки трогает те же места — скорее всего
это ДРУГАЯ правка того же файла, а не откат. Проверь, не выкидываешь ли уже слитую починку.

То же про `leadv2-routing.yaml`: сегодня в него легли `effort_matrix` и память провалов армов.
Две ветки несут свою версию — сохрани обе идеи, не выбирай.

## Доказательство

По каждой слитой: `sha`, непустой `git show --stat <sha>`, и **восемь отслеживаемых симлинков
целы** (`.bus-offsets .bus.lock .merge.lock active.yaml.lock bus.jsonl merge-queue.jsonl
open-threads.md questions` в `docs/leadv2/` — каждый `-L`), проверка после КАЖДОГО слияния.
По каждой неслитой — одна строка: какие два намерения не сошлись.

Тронул сюиту — прогони её **в переднем плане**: `timeout 240 bash <сюита>`, вывод в отчёт.
Читай код возврата САМОЙ сюиты, не конвейера: `bash suite | tail` вернёт код `tail`, а не сюиты
(на этом сегодня уже ошиблись — правильно `bash suite > /tmp/o 2>&1; echo $?`).

## Запреты

Никогда `git add -A`, `git reset --hard`, `git clean`, `git stash` — дерево общее.
Коммить поимённо и после КАЖДОЙ ветки. Не пушить в origin.
Не коммить: `docs/leadv2/{active.yaml,bus.jsonl,merge-queue.jsonl,open-threads.md,questions,.bus-offsets,.bus.lock,.merge.lock,active.yaml.lock}`,
`docs/LEAD_V2_STATE.md`, `docs/leadv2/.compact-freeze.md`, чужие `docs/handoff/*/phases.d/`.
Не сливать `98cec2c0`, `abd48ba4`, `a7f7131c`.

## Как не умереть

Строка в stdout раз в 10 минут — убийца простоя стреляет на 1800 секундах молчания. Никогда не
уводи проверку в фон: фон будит лида, а не тебя. Коммить после каждой ветки, не копи до десятой.

## Результат

`docs/handoff/RECOVER-WAVE1-TEN-01/report.md` — таблица на 10 строк.

## Набор записи

```
plugins/leadv2/
.claude/ref/
docs/handoff/RECOVER-WAVE1-TEN-01/
```

Слияние веток — операция git, набором записи не ограничивается.
