# REPORTS-CLAIM-CODE-THAT-MAY-NOT-EXIST-01 — сверка пяти отчётов с кодом

Вердикт по каждой строке опирается на грep ИМЕНОВАННОГО символа, который правка обязана была
создать. Совпадение по id задачи не считается доказательством: id живёт в сообщениях коммитов,
брифах и журналах работы, которая не легла. Правок не делала.

| # | строка | вердикт |
|---|---|---|
| 1 | `CLASS-IS-COMPUTED-NOT-DECLARED-01` | **раздваивается**: классификатор ЛЁГ (по другой строке), пол класса — **заявлен и не существовал никогда** |

---

## 1. `CLASS-IS-COMPUTED-NOT-DECLARED-01`

Отчёт `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/report.md` (2026-09-01, 11.8 КБ)
озаглавлен «— implemented» и **сам себе противоречит**: сразу под заголовком стоит баннер
`STOP — PREPASS-MECHANISM-CLOSURE-01 census falsified`, запрещающий линии идти в реализацию,
ревью, E2E и закрытие. То есть даже по собственным словам отчёт не является отчётом о
сделанном. Это первое, что видно, и этого достаточно, чтобы не верить заголовку.

Именованные символы, которые отчёт называет, разделились надвое:

```
for sym in _admission_classify _lv2_class_rank _lv2_class_canonical _pump_classify \
           leadv2_admission_class _class_floor_check LEADV2_REQUIRE_CLASS_FLOOR _class_floor_alerts; do
  printf '%-28s files_in_main=%s commits_anywhere=%s\n' "$sym" \
    "$(git grep -c "$sym" main -- plugins/ | wc -l)" \
    "$(git log --all --oneline -S"$sym" -- plugins/ | wc -l)"
done
```

```
_admission_classify        files_in_main=7   commits_anywhere=9     ЕСТЬ
_lv2_class_rank            files_in_main=6   commits_anywhere=8     ЕСТЬ
_lv2_class_canonical       files_in_main=5   commits_anywhere=5     ЕСТЬ
_pump_classify             files_in_main=2   commits_anywhere=2     ЕСТЬ
leadv2_admission_class     files_in_main=5   commits_anywhere=6     ЕСТЬ
_class_floor_check         files_in_main=0   commits_anywhere=0     НЕТ НИКОГДА
LEADV2_REQUIRE_CLASS_FLOOR files_in_main=0   commits_anywhere=0     НЕТ НИКОГДА
_class_floor_alerts        files_in_main=0   commits_anywhere=0     НЕТ НИКОГДА
```

`commits_anywhere=0` от `git log -S` означает, что символ не появлялся ни в одном коммите за всю
историю — не «не в main», а не существовал вовсе.

**Ноль выведен вторым способом**, как требует бриф: грep по ВСЕМ ссылкам, а не по main, с
отбрасыванием `docs/handoff` (иначе отчёт сам себя подтвердит):

```
git grep -l "<sym>" $(git for-each-ref --format='%(refname)' refs/heads refs/remotes) \
  | grep -v docs/handoff | wc -l        # для всех трёх: 0
```

**Вердикт: раздваивается, и обе половины важны.**

- Классификатор (`lib/leadv2-admission-class.sh` + `tests/test-admission-class.sh` +
  `_admission_classify`) **лёг** — но лёг он по СОСЕДНЕЙ строке
  `ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01`, чей каталог лежит рядом. Именно поэтому строка
  читалась выполненной: часть заявленного действительно есть, и поверхностная проверка это
  подтверждает.
- **Пол класса — та половина, ради которой строка заводилась** (`_class_floor_check`,
  `LEADV2_REQUIRE_CLASS_FLOOR`, `_class_floor_alerts`) — **не существовал никогда**. Это ровно
  форма 2026-09-04: отчёт пережил, код не родился.

### Оговорка о конфликте интересов

Сегодня, 2026-09-06, я сама трогала этот id: коммит `8c0f75f4`
(`LEADV2_NON_PRODUCT_KINDS`, явная петля разбора вместо арма `case`). Это ТРЕТЬЯ, ещё одна
половина — именованная «люк» для непродуктовых видов работ, — и она к полу класса отношения не
имеет. Отмечаю прямо, потому что судить строку, которую сам чинил, — конфликт; смягчение в том,
что вердикт держится на грепе, который любой может перезапустить, а не на моём слове.

### Что осталось сделать (для последующей линии)

Нужен сам пол: проверка, которая при вычисленном классе `Standard`/`Heavy` требует минимального
набора записи и отказывает, если его нет, плюс её флаг и оповещение. И — по собственному
STOP-баннеру отчёта — она обязана стоять НЕ только в `leadv2-dispatch-code.sh`: путь помпы
(`leadv2-backlog-pump.sh`) сам зовёт `leadv2_admission_class` и для `Standard`/`Heavy` запускает
полноцикловый раннер напрямую, минуя диспетчер. Правка только в диспетчере оставит пол
необеспеченным ровно на том пути, ради которого он нужен.

---

## 2. `D2-SINGLE-LIVENESS-VERDICT` — **лёг**

Отчёт (`docs/handoff/D2-SINGLE-LIVENESS-VERDICT/report.md`) относится к
`D2-UNBLIND-AND-THIRD-STATE-M0M1-01`, строки M0+M1. Три именованные переменные, которые он
называет, все в main:

```
LEADV2_LANE_FINISHED_WINDOW_S   main_files=5  commits=7
LEADV2_SUITE_SHARDS_DUMP        main_files=3  commits=3
LEADV2_SUITE_DEFS_OVERRIDE      main_files=3  commits=3
```

**Второе выведение**, не по переменным окружения, а по самому предмету строки — третьему
состоянию. Оно называется `finished_unlanded`, и оно в main в пяти файлах, включая
`leadv2-lane-liveness.sh` и `leadv2-lanes-snapshot.sh`:

```
git grep -c finished_unlanded main -- plugins/
git ls-tree -r main --name-only | grep three-state
#   plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh
git grep -c three-state main -- plugins/leadv2/scripts/tests/run-core-offline.sh   # 1
```

Сюита трёх состояний не просто существует — она **зарегистрирована в раннере**
(`run-core-offline.sh`), то есть CI её выбирает. Это тот пункт, на котором обычно ломается
«зелёное, которое никто не гоняет». Плюс merge-коммит `f847f92c merge(...): wave В1`.
