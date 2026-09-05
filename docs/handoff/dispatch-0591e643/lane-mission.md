# PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01 — класс по умолчанию проходит мимо фазового гейта

**Сомнение основателя, подтверждённое замером 2026-09-04:** «не уверен что все задачи идут
через фазы и не скипают на просто написание кода без того чтобы продумать, проверить и тд».

## Что уже измерено (перепроверь, но не переоткрывай)

- `leadv2-dispatch-code.sh:3742` — классификатор в ветке по умолчанию печатает буквально
  `product\tconservative_default`.
- `leadv2-dispatch-code.sh:4166-4173` — `_phase_precondition_guard` принуждает только
  `Standard|Heavy|Strategic`; всё остальное уходит в `mode="warn"`.
- Живая линия `dispatch-96d97702` (класс `product`): в `docs/leadv2/tasks/dispatch-96d97702/journal.md`
  **ноль** строк, содержащих `phase_precondition`. Ни отказа, ни предупреждения — тихий пропуск.

То есть «консервативный» дефолт на деле разрешающий, и следа не остаётся.

## Шаг 1 — перепись, до правки

1. **Перечисли ВСЕ классы**, которые умеет выдавать классификатор, и для каждого скажи:
   принуждается ли он гейтом, и журналируется ли его прохождение. Таблица класс → режим →
   пишет ли строку в журнал. Источник — код, файл:строка, не рассуждение.
2. **Почему `product` вообще существует** как класс и кто его читает дальше по цепочке.
   Возможно, он нужен для другого решения (ладдер, `when:`-гейт арма) — тогда чинить надо
   гейт, а не класс. Если окажется, что `product` нигде больше не читается, это отдельная
   находка, назови её.
3. **Ветка `warn`: пишет ли она хоть что-нибудь.** Сюита `G1` уже красная на
   `journal should contain phase_precondition_warn` — найди её, прочти, и скажи, красная она
   потому что запись отсутствует, или потому что сюита ищет не там. Это два разных бага.
4. **Сколько живых линий за последние сутки прошли мимо гейта.** Считай по журналам
   `docs/leadv2/tasks/*/journal.md`: линии с `dispatch_classified` и без единой строки
   `phase_precondition`. Число — в отчёт. Если оно нулевое, значит мой замер неверен, так и
   напиши и остановись.

Перепись → `docs/handoff/PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01/census.md`.

## Шаг 2 — правка (две, они независимы)

**(A) Дефолт перестаёт быть разрешающим.** Либо `product` входит в принуждаемый набор, либо
классификатор по умолчанию отдаёт класс, который уже принуждается. Выбор обоснуй переписью
шага 1.2 — если `product` читается ладдером, менять класс нельзя, меняй набор гейта.

**(B) `warn` обязан оставлять след.** Ветка `warn` пишет `phase_precondition_warn` в журнал
с классом и списком недостающих фаз. Молчаливый пропуск — это то, из-за чего дыра прожила
незамеченной: её нельзя было увидеть, не читая код.

Не расширяй правку на сам классификатор сверх (A). Не трогай ладдер.

## Шаг 3 — доказательство

Сюита `plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh`, заголовок
`# run-all-triggers: leadv2-dispatch-code.sh`.

1. **Настоящая функция.** Гоняем настоящий `_phase_precondition_guard` и настоящий
   классификатор; подделываем уровень ниже (наличие `context.yaml` / gate1-артефакта).
   Сюита, которая мокает то, что проверяет, не доказывает ничего.
2. **Негативные контроли, минимум три, и ты их ЗАПУСКАЕШЬ**, вносишь ВНУТРЬ тела функции
   якорем по regexp, НЕ по номеру строки (вставка по номеру попадает на верхний уровень,
   красит всё подряд и читается как успех — так уже было 2026-08-25):
   (а) `product` убран из принуждаемого набора → сюита обязана покраснеть;
   (б) `warn` перестаёт писать в журнал → обязана покраснеть;
   (в) гейт принуждает ВСЁ подряд, включая trivial → обязана покраснеть (иначе сюита
   доказывает только «гейт строгий», а не «гейт правильный»).
   Артефакт каждого контроля клади в `mutation-control/` в формате, который уже использовала
   линия BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01: `anchor=`, `baseline_rc=`, `mutated_rc=`,
   `red_line=`, `lane_diff_hash=`.
   Если правило окажется реализовано в двух местах — единичная мутация одного оставит
   утверждение выполнимым и контроль перестанет кусаться. Проверь, что копия одна.
3. **CI её выбирает.** `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`.
   Доказательство снимай изменением ПРОДУКТОВОГО файла, а не сюиты: правка сюиты делает её
   грязной и она выберется по имени файла — ложный зелёный.
   **Никогда не гоняй полный `tests/run-all.sh` в живом чекауте** — он перенаправляет пять
   симлинков control-plane во временный каталог и удаляет их цели.
4. Строка в `tests/mutations/catalog.yaml`. Kill rate не имеет права упасть.

## Границы

- Правки в `~/Projects/leadv2`, сюита в `plugins/leadv2/scripts/tests/`. Один инод — никогда
  не делай реальную копию plugin-owned файла внутри проекта.
- Не трогай `tests/known-red-suites.txt` / `known-failures.txt` иначе как на уменьшение.
- Не пушь в origin.

## Готово =

`census.md` с таблицей классов и числом проскочивших линий + обе правки + сюита + три
артефакта негативных контролей + строка каталога + вывод `[SELECT]`. «Должно работать» без
вывода — не готово.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-0591e643" "<question>" \
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