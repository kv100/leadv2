# Scheduled decisions

One row per deferred decision: an id, status, the condition that triggers it, and the
exact reversible action to take when it fires. Anything promised for later goes here the
same turn it is promised (task-anchor DIRECTIVE #4).

---

## PROMISE-GUARD-BLOCK-FLIP-01 — flip promise-guard from log-only to blocking

- **status:** FLIPPED
- **due:** 2026-09-01 — flipped per task PROMISE-GUARD-TURN-IT-ON-01

CONTEXT: PROMISE-GUARD-BIND-01 (2026-08-30) fixed the promise extractor and
`ACTION_BASH_RE`/action-kind binding in `plugins/leadv2/hooks/leadv2-promise-guard.sh` so
a promise of a classifiable kind (dispatch / commit / write / test-run) is only "kept" by
an action of that same kind, not by any tool call. As of 2026-09-01, the guard is flipped
to blocking for classified promises (unless `LEADV2_PROMISE_GUARD_BLOCK=0` is set) and
remains log-only for unclassified promises unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`
is set. Evidence: the hook now defaults to `LEADV2_PROMISE_GUARD_BLOCK=1` and
implements classified/kind-based blocking.

- **status:** FLIPPED
- **due:** 2026-09-01 — flipped per task PROMISE-GUARD-TURN-IT-ON-01

CONTEXT: PROMISE-GUARD-BIND-01 (2026-08-30) fixed the promise extractor and
`ACTION_BASH_RE`/action-kind binding in `plugins/leadv2/hooks/leadv2-promise-guard.sh` so
a promise of a classifiable kind (dispatch / commit / write / test-run) is only "kept" by
an action of that same kind, not by any tool call. As of 2026-09-01, the guard is flipped
to blocking for classified promises (unless `LEADV2_PROMISE_GUARD_BLOCK=0` is set) and
remains log-only for unclassified promises unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`
is set. Evidence: the hook now defaults to `LEADV2_PROMISE_GUARD_BLOCK=1` and
implements classified/kind-based blocking.

GO-CONDITION (query over the journal, evaluate before flipping):
```
python3 -c "
import json
rows = [json.loads(l) for l in open('$HOME/.claude/leadv2-promise-guard.jsonl') if l.strip()]
fired = [r for r in rows if r.get('verdict') == 'fired']
# Consecutive tail: no fired row is a false positive (manually reviewed — a promise
# that really was kept by an action of a DIFFERENT kind than what was promised, or a
# promise/action-kind misclassification). Require >=20 consecutive fired rows with
# zero flagged false positives, spanning >=3 distinct session_ids.
print(len(fired), len({r['session_id'] for r in fired}))
"
```
Flip when: the last 20 consecutive `fired` rows have zero known false positives (checked
by hand against the quoted transcript) AND those rows span at least 3 distinct
`session_id`s (not one session's repeated pattern). Re-run the query above after adding
any new `PROMISE_KIND_PATTERNS` / `ACTION_KIND_BASH` entry — widening the kind taxonomy
resets the evidence window for the newly-covered kind.

FLIP (exact): set `LEADV2_PROMISE_GUARD_BLOCK=1` in the environment that runs the Stop
hook (repo-level `.claude/settings.json` `env` block, or the shell profile that starts
`claude`). **As of 2026-09-01, the hook defaults to `LEADV2_PROMISE_GUARD_BLOCK=1`**
(see `plugins/leadv2/hooks/leadv2-promise-guard.sh`). No code change — the hook already
reads this var.

ROLLBACK (one step): unset `LEADV2_PROMISE_GUARD_BLOCK` (or set it back to `"0"`). The
hook falls back to log-only immediately on the next Stop event; no state to clean up,
the journal keeps accumulating either way.

## SD-WORKER-OUTLIVES-VERIFY-01 — ЗАКРЫТО 2026-09-03T12:15Z доказательством (три контроля мутаций, macOS+Linux rc=0, слито как fd6f221a)
- **Due:** условие — освободилась одна из двух живых линий (`E2E-TIMEOUT-REPORTED-AS-REGRESSION-01`
  или `LEAD-IS-OPUS-THINK-IS-FABLE-01` дошла до слияния). WIP=2, третью не открываем.
- **GO:** у одной из двух линий появился `dispatch_terminal task=<sig> terminal=landed`, ИЛИ её
  ветка слита в `main` (`git -C ~/Projects/leadv2 log --oneline main | grep <task-id>`).
- **Action:** `LEADV2_PROJECT_ROOT=~/Projects/leadv2 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh
  --task-id WORKER-OUTLIVES-ITS-TERMINAL-STATE-01 --resume-lane --kind codex_fitting_dev` с миссией:
  «работа уже закоммичена как `adf89c9b`, гейты по ней НЕ прогонялись; выполнить пункты 4–6 брифа —
  негативный контроль на каждое из трёх исправлений, зелёное на macOS и в Linux-контейнере,
  доказать что `--scope changed` выбирает сюиту». Перед этим очистить четыре хранилища
  (session-id, receipt, active.yaml, lock) — память `reference_redispatch_needs_four_stores_cleared`.
- **Rollback:** один шаг — `git revert adf89c9b` внутри линии, если негативный контроль покажет,
  что спасённая работа неверна.
- **Why:** воркер умер, держа 23 файла несохранённой работы; лид спас их дословно коммитом
  `adf89c9b`, но собственные гейты линии по этой работе не проходили ни разу. «Закоммичено» без
  гейта — это лгущая зелёнка. Третий за ночь случай ровно той болезни, которую сама линия и чинит.

## SD-LEAD-ON-WORK-ACCOUNT-TRIAL-01 — испытание лида на рабочем аккаунте до 15 сентября

**Due:** начать не позже 2026-09-06, закончить до 2026-09-14 (отмена Max 20x вступает в силу 15.09; до этой даты решение обратимо).

**GO-условие:** за неделю работы лида на аккаунте work утилизация 5-часового окна в пиковые часы оркестрации остаётся ниже 80%, И измеренное отношение недельных потолков между аккаунтами выходит >=2x. Обе цифры берутся из `leadv2-ratelimit-probe.sh` по каждому аккаунту отдельно — то есть испытание НЕ может начаться раньше, чем закрыта TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 и запись истории окна (иначе измеряем деградированный роутер, как 03.09).

**Action:** запускать лид-сессии под `CLAUDE_CONFIG_DIR=~/.claude-work` неделю. Если GO выполнено — даунгрейд на 2xMax 5x подтверждён, ничего не делать. Если 5-часовое окно насыщается — восстановить Max 20x до 15.09.

**Rollback:** один шаг — вернуть подписку Max 20x до 15.09 в биллинге. После 15.09 откат стоит переоформления.

**Why:** GLM (assessment-glm.md §6) и лид (assessment-claude.md) разошлись в выводе. Лид опирался на одну пробу binding_window=seven_day, снятую на системе, где балансировка умирала каждую ночь, а рабочий слот 79 раз выбрасывался ложной проверкой — то есть на деградированном роутере. GLM проверила страницы вендоров живьём: Anthropic НЕ публикует ни 5-часовых, ни недельных чисел, поэтому reddit-утверждение про 1.7x недельного множителя ничем не подтверждено. Спор решается не третьим мнением, а одним измерением.

## SD-LANE-KEEPER-IS-A-BUCKET-01 — снять временный подъёмник линий
- **Due:** условие — D3 (`терминал только после доказанной смерти`) и D4 (`ни один путь не теряет работу`) сданы и приняты.
- **GO:** обе линии закрыты с приёмкой, и внешний сиротолов `leadv2-orphan-checkpoint.sh` вызывается из хука SessionStart И из `leadv2-phase8-close.sh`.
- **Action:** убить процесс подъёмника (`pkill -f scratchpad/keeper.sh`) и удалить скрипт; линии держит штатный механизм.
- **Rollback:** перезапустить подъёмник тем же скриптом. Один шаг.
- **Why:** 2026-09-03 линии умирали циклически — диспатч возвращал rc=0, воркер исчезал через минуты; из семи линий ведущей сессии жила одна, у fb две из пяти. Подъёмник поднимает мёртвые линии по PID, максимум 5 попыток на линию, окно 3 часа. Это ведро под течью: пока течь не заделана, снимать нельзя, а после — обязательно, иначе он будет вечно передиспатчивать то, что штатный путь уже починил.

## SD-LANE-CAP-BACK-TO-4-01 — ЗАКРЫТО 2026-09-03T22:1xZ, исполнено ДОСРОЧНО по доказательству

Возврат на 4 сделан не по исходному условию («закрыты волны 0-4»), а раньше — потому что
появилось доказательство, что 64 вредит. Замер двух сессий: load average **188-248 при 10
ядрах** (девятнадцати-двадцатипятикратная перегрузка), 270-322 процесса leadv2, 57-75
одновременных прогонов сюит, при этом настоящих воркеров всего 7-13. Память свободна на 64%,
jetsam-убийств нет — то есть это не нехватка памяти, а конкуренция за процессор. Воркеры не
падают, они голодают и упираются в таймаут, а снаружи это неотличимо от смерти. Это и есть
объяснение «линия умирает через минуты после успешного диспатча», которое мы весь вечер
искали в коде.

Честная часть: потолок 4 подняли до 64 сегодня по просьбе сессий, и старая цифра, вероятно,
защищала машину, а мы прочитали её как произвольное ограничение. Причинность правдоподобна,
но экспериментом с понижением не доказана — доказательство соберём по смертности линий после
возврата.

Резервная копия настроек: `~/.claude/settings.json.bak-lanecap-20260903`.
Откат: поставить 64 обратно, один шаг.

## (историческая формулировка) SD-LANE-CAP-BACK-TO-4-01 — вернуть потолок линий на 4
- **Due:** условие — закрыты волны 0-4 плана (`~/Projects/leadv2/docs/leadv2/PLAN.md`).
- **GO:** в `docs/leadv2/PLAN-PROGRESS.md` (репо persona-engine) нет строк со статусом «начато» или «нет линии» по волнам 0 и 1, и сессии fb/36 отчитались о закрытии волн 2-4.
- **Action:** вернуть `"LEADV2_LANE_CAP": "4"` в `~/.claude/settings.json` (сейчас 64). Резервная копия: `~/.claude/settings.json.bak-lanecap-20260903`.
- **Rollback:** поставить 64 обратно. Один шаг.
- **Why:** основатель поднял потолок на время большого списка и сказал дословно «давай потом вернёмся на 4, когда сделаем весь этот огромный список задач». Значение в его настройках — ручное, не наше; вернуть обязаны мы, потому что подняли тоже мы.

## SD-NO-NEW-LANES-UNTIL-SUITES-HAVE-A-QUEUE-01 — не запускать новые линии, пока у прогонов сюит нет очереди
- **Due:** условие — закрыта `SUITE-RUNS-HAVE-NO-QUEUE-01` (приоритет 1, завела сессия волны 3).
- **GO:** одной командой, на этой машине: `uptime` даёт load average ниже числа ядер (их 10) И `ps -axo command= | grep -c "[r]un-core-offline.sh"` не превышает потолка, выведенного из числа ядер. Оба условия одновременно, замер повторить дважды с интервалом 5 минут — плато, а не всплеск.
- **Action:** возобновить диспатч новых линий обычным порядком.
- **Rollback:** снова остановить диспатч новых линий. Один шаг, ничего не ломает.
- **Why:** замерено 2026-09-03 двумя сессиями независимо: load average 188-248 при **10 ядрах** (девятнадцати-двадцатипятикратная перегрузка), 270-322 процесса leadv2, **57-75 одновременных прогонов сюит при 7-13 настоящих воркерах**. Память свободна на 64%, убийств по памяти нет — это конкуренция за процессор, а не нехватка. Воркер, которому не досталось процессора, упирается в таймаут, и снаружи это неотличимо от смерти: именно этим объясняется «линия умирает через минуты после успешного диспатча», которое весь вечер искали в коде. Соотношение 57 к 7 говорит, что сюиты форкаются быстрее, чем завершаются, то есть проблема не в числе линий, а в отсутствии у сюит очереди. Каждая новая линия до починки очереди добавляет голодания, а не пропускной способности.
- **Не входит в область:** уже работающие линии не останавливаются; 200 воркдеревьев не прибираются (прунинг во время работы линий уже убивал живые).
