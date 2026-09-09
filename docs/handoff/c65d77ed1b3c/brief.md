# SALVAGE-EXITS-ZERO-ON-CONFLICT-01 (ряд `c65d77ed1b3c`, волна В0)

## Первым делом прочитать улику целиком
```
grep -A8 "id: c65d77ed1b3c" /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/tasks.yaml
```
Поле `intent:` — единственный источник постановки. Не выдумывать проблему.

## Кратко
`plugins/leadv2/scripts/leadv2-lane-salvage.sh` печатает
`SALVAGE_RESULT verdict=conflict ... carried=0/4` и **выходит с кодом 0**.
Замер 2026-09-04: цикл по 17 линиям В1 отрапортовал 17 OK, веток `salvage/*`
не создано ни одной — вердикт был в stdout, вызывающий смотрел на rc.

## Что сделать
1. `verdict=conflict` → **ненулевой rc, отличный от `verdict=fail`**
   (предлагается 0 ok / 3 conflict / 1 fail). Коды описать в usage-тексте скрипта.
2. `grep -rn leadv2-lane-salvage ~/Projects/leadv2` — пройти КАЖДОГО вызывающего
   и убедиться, что новый ненулевой rc не проглатывается там (`|| true`,
   `$(...)` под `set -e`, игнор rc). Где проглатывается — починить минимальным диффом.
3. Сюита `plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh`.

## Write set — только эти файлы
- `plugins/leadv2/scripts/leadv2-lane-salvage.sh`
- `plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh` (новый)
- вызывающие из п.2 — минимальным диффом

## Off-limits (чужие линии, идут параллельно)
`leadv2-deploy-merge.sh`, `leadv2-active-registry.sh`, `lib/*`,
`leadv2-state-path.sh`, `scripts/waves-refresh.sh`.

## Приёмка — обязательный негативный контроль
Сюита зелёная **и** названная мутация краснит её. Мутацию вставить ВНУТРЬ тела
функции (не на верхний уровень файла): вернуть `return 0` на ветке conflict.
В отчёт вставить оба прогона: зелёный и красный, с выводом. Без красного прогона
работа не принимается — «сюита есть» это не доказательство, что она что-то ловит.
