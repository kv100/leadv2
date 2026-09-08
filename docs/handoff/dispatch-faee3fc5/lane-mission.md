# MAIN-CORE-SUITE-RED-01 — раунд 2: ловушка названа, выход один

## Что произошло в раунде 1

Линия сделала коммит `d2971b7e` («wip: suite fixes from prior run») и была отвергнута гейтом
`selfcheck_failed` на четырёх сюитах:

```
plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
plugins/leadv2/scripts/tests/test-injector-dedup.sh
plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
plugins/leadv2/scripts/tests/test-phase-precondition.sh
```

Я померил их **из чистой базы** — `git archive main | tar -x` во временный каталог,
никакого твоего диффа там нет:

```
test-idle-lead-guard        base_rc=1
test-injector-dedup         base_rc=1
test-lane-diff-single-repo  base_rc=1
test-phase-precondition     base_rc=1
```

Все четыре красны на `main`. То есть линия заблокирована ровно тем, что ей поручено починить.
Гейт этого различить не умеет — это отдельная работа (`REVIEW-GATE-IS-MUTE-01`), и ждать её
не нужно.

## Выход, и он ровно один

**Довести эти четыре до зелёного.** Не оправдать, не занести в список, не откатить — они и есть
предмет задачи. Гейт откроется сам, когда сюита станет зелёной: он не спрашивает «чья краснота»,
он спрашивает «красна ли».

Порядок на каждую из четырёх:

1. **Сначала прогон из базы** — `git archive main | tar -x -C <tmp>`, запустить там, записать
   `rc` и первые строки провала. Это фиксирует, что чинишь настоящую болезнь, а не свою правку.
2. **Прочитать провал, а не догадаться о нём.** Имя коммита раунда 1 перечисляет пять гипотез
   (`idle-lead-guard registration`, `injector-dedup anchor guard`, `lane-diff pycache`,
   `phase-precondition bare handle`, `t14 effort baseline`) — ни одна не сделала сюиту зелёной.
   Значит либо гипотеза неверна, либо правка не дошла до места, которое сюита щупает.
   Различает это прогон, а не рассуждение.
3. **Починка в ПРОДУКТЕ, если врёт продукт; в сюите — только если доказано, что сюита проверяет
   поведение, которого больше нет.** Второе объявляй явно и с указанием коммита, который это
   поведение убрал.
4. **Парный негатив на каждую починенную:** внеси в продукт ту самую поломку, которую сюита
   обязана ловить, — сюита обязана покраснеть; откати — обязана позеленеть. Без этой пары
   зелёная сюита не отличается от сюиты, которая ничего не проверяет.
5. **Прогон из базы ПОВТОРНО в конце** — он обязан остаться красным. Если база вдруг позеленела,
   значит зелень пришла не от тебя, и вывод о починке неверен.

## Приёмка

`docs/handoff/MAIN-CORE-SUITE-RED-01/report.md`: по каждой из четырёх — `rc` из базы до, `rc`
в линии после, что именно было сломано, вывод парного негатива. Плюс строка в
`tests/mutations/catalog.yaml` на каждую.

Если какая-то из четырёх не поддаётся — назови её честно в четвёртой куче «не смог определить»
с тем, что уже известно, и не выдавай откат за починку. Три починенные и одна честно открытая
лучше четырёх зелёных без пары.

## Запреты (без изменений)

Дерево общее: не `git add -A`, не жёсткий сброс, не очистка, не прятание изменений.
В origin не пушить. `tests/known-red-suites.txt` и `known-failures.txt` могут только СОКРАЩАТЬСЯ —
дописывать в них запрещено, это и был бы выдаваемый за починку откат.
Не трогать `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`, `leadv2-dispatch-code.sh`
и `leadv2-phase-record.sh` — они заняты соседними сессиями прямо сейчас.

LANE_WRITES: plugins/leadv2/scripts/, plugins/leadv2/scripts/tests/, tests/, docs/handoff/MAIN-CORE-SUITE-RED-01/

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-faee3fc5" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.