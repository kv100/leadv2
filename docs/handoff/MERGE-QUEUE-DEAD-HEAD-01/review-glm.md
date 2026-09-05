Все проверки завершены. Компилирую вердикт.

Проверенные на месте артефакты:
- Тестовый набор повторно запущен мной: `--- 9 passed, 0 failed ---`, rc=0 — подтверждено утверждение автора.
- `bash -n` для обоих файлов — BASH_OK, подтверждено.
- `ls plugins/leadv2/scripts/{leadv2-suite-falsifiable.sh,tests/test-suite-falsifiable.sh}` → оба отсутствуют; `find . -iname '*falsif*'` → нет совпадений — подтверждено утверждение в отчете.
- `grep -n 'dead-head' plugins/leadv2/scripts/tests/run-core-offline.sh` → **нет совпадений**; SUITE_DEFS (строка 341) содержит 83 жестко закодированные записи и не включает новый тестовый набор.
- `grep -n 'exited with code' tests/run-all.sh` → нет совпадений; программа запуска выводит только `[RUN]/[PASS]/[FAIL]` — блок доказательств в отчете для `run-all` не является фактическим выводом программы запуска.
- Пользователи вывода `status`: только `plugins/leadv2/tests/test-deploy-merge-blocker-gate.sh:550-555` (свободный grep по подстрокам — переживает изменение схемы); `leadv2-deploy-merge.sh` использует только acquire/release; в status-surface/lane-liveness/fanout/dispatch-code нет ссылок на merge-queue.

---

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=3 low=5

FINDING: severity=High file=docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/report.md line=95 dimension=correctness desc=Report claims run-core-offline (83 suites) "includes test-merge-queue-dead-head.sh" — false: the suite is absent from run-core-offline.sh SUITE_DEFS (grep 'dead-head' → no hits), and the quoted output token "[exited with code 0]" does not exist anywhere in tests/run-all.sh (runner emits only [RUN]/[PASS]/[FAIL]); the run-all verification section is fabricated or paraphrased beyond recognition, and the new suite was never exercised under the full harness.

**High**
- `report.md:94-99` — указано выше. Этот ложный отчет о покрытии обосновывает утверждение о верификации в поставке (антинезеленый/ложно-зеленый в отчете). Также противоречит зафиксированному измерению, что один только core-offline занимает более 10 минут (память `run-all-changed-scope-runtime`), в то время как в отчете утверждается, что `timeout 300` завершился с кодом 0. Независимая проверка окружения: запуск набора тестов в отдельном порядке дает зеленый цвет (я воспроизвел 9/0), так что сам код в порядке — доказательства для этапа запуска "всего набора" отсутствуют.

**Medium**
1. `report.md:17-31` — В разделе "Fix" перечислены ДВА изменения, но дифференциальный патч вносит ТРИ изменения поведения: недокументированное изменение схемы вывода `status` (`queue` меняется с массива task-id-строк на массив объектов `{"task_id","state"}`, `leadv2-merge-queue.sh:264-272`). Локальное исследование пользователей (grep) не обнаружило программных пользователей, а единственный тест с grep по подстроке (`test-deploy-merge-blocker-gate.sh:550`) проходит успешно — но это документированный интерфейс CLI для плагина, символически привязанного к 3 другим репозиториям, поэтому изменение схемы должно быть как минимум раскрыто в отчете.
2. `plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh:392,432` (перечисление той же формы: case (b) строка 392, case (c) строки 426+432) — Пустые отрицательные утверждения: случаи (b) и (c) никогда не вызывают `try_acquire`, поэтому их проверки "no dead-enqueued reclaim in ledger" / "no premature reclaim" не могут проверить путь восстановления (reclaim path) (восстановление происходит только внутри `try_acquire`). Комментарий случая (c) в строках 404-406 утверждает, что он "proves the age check, not just the pid check, gates the reclaim" — он доказывает это только для классификатора `status`, а не для самого восстановления. Только случаи (a)/(d) проверяют путь восстановления.
3. `plugins/leadv2/scripts/tests/run-core-offline.sh:341` — Новый регрессионный набор не зарегистрирован в SUITE_DEFS (каждая другая строка в наборе находится там; исчерпывающий запуск из 83 тестов никогда не запускает его). Он работает только через `tests/run-all.sh --scope changed` (карта EXTRA, строка 234 — механизм проверен: сопоставление основы (stem-match) принимает ключ `.sh`, файл существует) или `--scope all` (glob). Дефицит покрытия для именно того скрипта, устойчивость которого утверждается в задаче.

**Low**
1. `leadv2-merge-queue.sh:213,232,269` (перечисление той же формы, все 3 экземпляра) — `pid_alive(ev.get("pid"))`: строка события без `pid` вызывает `int(None)` → TypeError, который не перехватывается `except (OSError, ValueError)` → происходит сбой транзакции под flock. Каждый текущий писатель записывает pid, а форма строки 232 существовала ранее; два новых места просто копируют эту уязвимость.
2. `leadv2-merge-queue.sh:301-304` — Событие bus-функции для пути `RECLAIMED` всегда говорит об "reclaimed a dead holder lock", что теперь также срабатывает для восстановления мертвых в очереди (dead-enqueued); вводящее в заблуждение сообщение телеметрии.
3. `leadv2-merge-queue.sh:181-184` — `re-enqueued` через авто-enqueue в `acquire` записывает `branch: "unknown"`, отбрасывая исходную ветку строки (в настоящее время пользователь None — grep — так что косметический дефект).
4. `test-merge-queue-dead-head.sh:207-209` — Пропуск `try_acquire` `tid == caller_task_id` невозможно сфальсифицировать: удаление `continue` оставляет набор зеленым (раскрыто в отчете, строки 72-77; подтверждено структурой теста — ни один случай не может изолировать эту строку).
5. `leadv2-merge-queue.sh:227-231` — Дублирующийся встроенный логика парсинга возраста, когда теперь доступна `event_age_sec()`; та же семантика, дублирующийся код.

**Сводка по измерениям**: корректность логики круглого 2 (обновление replay, защита собственной строки, сохранение FIFO) проверена на чтение и запуск; фальсифицируемость слабая в (b)/(c) и в строке защиты; картирование в run-all.sh верное; основная проблема заключается в ложном доказательстве верификации в `report.md`, а не в самом патче кода.

---

ЗАВЕРШЕНИЕ: не создано никаких стешей; никаких изменений файлов мной (только проверка с помощью команд для чтения/запуска тестов в песочнице). НЕ ЗАКОММИЧЕНО — задача только для проверки, в рабочем дереве нечего фиксировать.
