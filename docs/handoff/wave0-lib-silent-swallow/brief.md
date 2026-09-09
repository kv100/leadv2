# WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 — девять точек молчаливого проглатывания

Девять рядов волны В0 с одной формой: функция **проглатывает отказ записи**
(`2>/dev/null || true`, `trap 'exit 0' ERR`, guard без `else`) и всё равно
возвращает 0. Артефакт не появился, а вызывающий уверен, что появился.

## Первым делом прочитать все девять улик
```
cd /Users/kostiantyn.vlasenko/Projects/persona-engine
for i in 41d918c32ef0 793fe082b381 7a627a144340 a94029ccff76 ad7eca8c08a4 \
         b4c67761d3c3 d4c572f6b480 d86cdb8d7bad ddaaca991eaa; do
  echo "=== $i"; grep -A6 "id: $i" docs/tasks.yaml; done
```

## Ряды
1. `41d918c32ef0` — `lib/leadv2-receipt-freshness.sh:54,126-133` `leadv2_receipt_is_stale`
   возвращает 0 независимо от того, удалось ли переименование протухшей квитанции.
2. `793fe082b381` — `lib/leadv2-freepool-gate.sh:161-164` `record_result` глотает битый
   `latency_s` через `2>/dev/null || true`, молча теряет результат, файл состояния не меняется.
3. `7a627a144340` — `lib/leadv2-lane-state.sh:150-154` (python heredoc в `lane_deregister`)
   несовпавший `task_id` пропускает тело дедупа, но функция всё равно возвращает 0 после
   безусловной перезаписи yaml.
4. `a94029ccff76` — `leadv2-journal.sh:11` глобальный `trap 'exit 0' ERR` превращает любой
   отказ записи (mkdir/printf) в принудительный rc=0, `journal.md` молча не пишется.
5. `ad7eca8c08a4` — `lib/leadv2-brain-record.sh:111-113` `leadv2_brain_write_yaml` возвращает 0
   вообще без mkdir/записи, когда `task_id` пуст.
6. `b4c67761d3c3` — `leadv2-lanes-snapshot.sh:317-328` запись кэша truth-breaches цепляет
   mkdir/write/mv через `|| true` / `2>/dev/null`, молча теряет файл на незаписываемом каталоге.
7. `d4c572f6b480` — `leadv2-phase-record.sh:174-177` `_emit` глотает запись журнала через guard
   на отсутствующий `JOURNAL_BIN`, и сам вызов идёт через `|| true` — каждое событие
   `phase_recorded` / `phase_mirror_miss` может молча пропасть.
8. `d86cdb8d7bad` — `lib/leadv2-dod-gate.sh:506-566` rc `lv2_dod_gate_run` определяется только
   вердиктами проверок, никогда — тем, записался ли `out_md`; цепочка mkdir/mv/cp может
   отказать молча, и `dod-gate.md` не приземлится.
9. `ddaaca991eaa` — `lib/leadv2-worker-epilogue.sh:85-148` `leadv2_worker_commit_epilogue`
   глотает каждый отказ дописывания `progress.log`/`meta.yaml` через `2>/dev/null || true`
   и возвращает 0 даже когда `run_dir` вообще не существовал.

## Что сделать
Каждая из девяти обязана **отказывать закрыто**: rc отражает, произошла ли запись.
Правило, которое надо соблюсти буквально: «цикл/запись обязаны печатать, сколько
именно сделано» — голое `echo OK` без числа не принимается. Где `|| true` защищает
от реально необязательной записи — оставить, но напечатать причину пропуска.

## Write set — только эти файлы
`leadv2-journal.sh`, `leadv2-phase-record.sh`, `leadv2-lanes-snapshot.sh`,
`lib/leadv2-receipt-freshness.sh`, `lib/leadv2-freepool-gate.sh`, `lib/leadv2-lane-state.sh`,
`lib/leadv2-brain-record.sh`, `lib/leadv2-dod-gate.sh`, `lib/leadv2-worker-epilogue.sh`,
плюс новый `plugins/leadv2/scripts/tests/test-lib-fails-closed.sh`.

## Off-limits — громко
`lib/leadv2-route-arbiter*.sh` и `leadv2-state-path.sh` принадлежат ДРУГОЙ линии
(`518b42814626`) — не трогать. `leadv2-active-registry.sh` принадлежит линии
`wave0-registry-silent-rc`. Также `leadv2-lane-salvage.sh`, `leadv2-deploy-merge.sh`.

## Приёмка — обязательный негативный контроль
По тесту на каждую из девяти: сделать запись невозможной (незаписываемый каталог,
пустой `task_id`, отсутствующий `run_dir`) → функция обязана вернуть ненулевой rc.
Негативный контроль: вернуть `|| true` ВНУТРЬ тела одной функции → сюита краснеет
именно на её тесте. В отчёт — зелёный и красный прогон целиком.
