REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=1 low=4

FINDING: severity=High file=plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh line=237 dimension=design desc=case9 third arm sets LEADV2_SESSION_PROVIDER=glm which execs leadv2-glm-session-runner.sh at session-runner.sh:111 BEFORE completion_proof_present (:282/:361) — all four changed hunks in leadv2-session-runner.sh have zero test coverage; the "case9: leadv2-session-runner exits rc 2" PASS is produced by the glm runner (duplicate of arm 1)
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh line=128 dimension=design desc=rewritten comment claims "Every runner propagates rc 2" but the codex path (session-runner.sh:103 exec → leadv2-codex-session-runner.sh:112-131 sentinel_present) honours a stale schema-valid phase8_passed receipt with no freshness guard at all — same defect shape, fourth instance unpatched

**Пруфы, на которых держатся findings** (всё проверено живьём в этом worktree):

- Тест-сьют зелёный: `bash scripts/tests/test-stale-receipt-requeue.sh` → `=== 24 passed, 0 failed ===`.
- Кода в самом диффе **корректна**: ручной прогон claude-пути (provider не задан, read-only completions) дал `rc=2` + `ERROR: stale receipt rotation failed for probeTID1 (rc=2); refusing completion`. Но именно этот путь сьют не трогает: `leadv2-session-runner.sh:106-111` — `provider=glm → exec "$GLM_RUNNER"` стоит выше `completion_proof_present` (:361). Регрессия, удаляющая любой из трёх `elif [[ "$?" -eq 2 ]]` или `return "$receipt_freshness_rc"`, пройдёт 24/24. Тест мог безопасно тестировать claude-путь напрямую (выход rc=2 происходит до запуска claude — проверено), но не делает этого.
- Кодекс-инстанс: grep по `leadv2-codex-session-runner.sh` — `sentinel_present()` на :117 валидирует receipt (`phase8_passed`/`7/7`) без `leadv2_receipt_is_stale`; lib в сорсерах не значится. Стейл-реквизит прошедшего close имеет ровно эти поля → кодекс-лейн молча завершится «already complete» для перезаполненной задачи. Дифф при этом переписывает комментарий либы на «Every runner propagates rc 2» — утверждение ложно на уровне флота (4 раннера, охвачено 3).

**Census (lens 4)**: все call-site `leadv2_receipt_is_stale` — ровно 3 раннера, все три пропатчены консистентно; все 3 call-site `completion_proof_present` — все три получили `elif $? -eq 2`; exit-2 в glm/kimi — по два на файл (flock + новый). Утраченных same-shape внутри затронутых файлов нет; единственный непокрытый инстанс формы — кодекс-раннер (High #2).

**Claims-without-evidence (lens 5)**:
1. *MEDIUM*: тест-комментарий «root can rename through directory mode bits» (case 8/9 root-skip) — утверждение о поведении ОС без пробы/артефакта и без тега UNVERIFIED; оно драйвит решение (пропуск кейсов под root). Косвенно подтверждается памятью репо (root маскирует chmod-репродюсы), но артефакта в диффе нет.
2. «no provider credentials or network calls» — внутреннее, подтверждено порядком кода (receipt-гард выше `GLM_CODER_BIN`/`GLM_SECRETS_FILE` проверок, glm:130+) и моим пробом. ОК.
3. «rc 2 means the receipt was proven stale but could not be rotated» — соответствует либе (`return 2` только на `rename_failed`). ОК.

**Low findings**:
- rc=2 перегружен в glm (:70) / kimi (:88): уже означает «another live session runner owns the task» (flock), теперь ещё и «rotation failed». Сегодня rc раннера никто не ветвит (fanout запускает nohup-ом), различие только в логе — но будущий потребитель rc==2 получит коллизию.
- `completion_proof_present` теперь возвращает rc=2 **до** проверки `e2e-gate-passed.flag`: задача с валидным e2e-флагом и невращаемым стейл-реквизитом хард-фейтится. Соответствует заявленному fail-closed, но порядок лимбов поменялся молча.
- Правка ассерта case1 (`renamed=1 dest=` вместо старого сообщения) молча чинит pre-existing red: в базе 6dad23f8 либа уже логировала `renamed=1 dest=...` (:138), а тест ассертил старое сообщение (:89) — сьют был красный до диффа, в диффе это не отмечено.
- (вне диффа, наблюдение с пробы) на claude-пути при заданном `LEADV2_PROJECT_ROOT` sourcing helpers сыплет `leadv2-helpers.sh:64: PROJECT_ROOT: readonly variable` — не фатально (прогон дошёл до rc=2), но честный тест claude-пути упёрся бы в это.

---
FINISH CONTRACT: стэшей не создавал; правок в репо нет (только read-only ревью + пробники в /tmp, удалены). NOT-COMMITTED — ревью-онли deliverable, изменений для коммита нет. Files changed: none. Test results: test-stale-receipt-requeue.sh 24/24 pass (честный прогон в этом worktree).
