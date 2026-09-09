# W1-ARBITER-BYPASSED-ON-DISPATCH-01 — арбитр обойдён на боевом пути (пункт 1.7 §1)

Полная постановка:
`/Users/kostiantyn.vlasenko/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PRE-WAVES-PLAN.md` §1.7.
Ряды: `dfc9444bd227` (ARBITER-REFUSES-INSIDE-DISPATCH-BUT-WORKS-ALONE-01),
`6bff55f1e36e` (LADDER-FALLBACK-TELEMETRY-DIES-UNDER-SET-U-01).

Почему одна линия на два ряда: второй баг глушит ровно ту строку, которая объясняет первый.
Чинить их порознь — значит расследовать отказ вслепую.

## Часть A — арбитр отказал внутри диспатча и решала легаси-лестница

Замерено на живом диспатче 2026-09-10 (линия `b0ec3b03`, задача `84d8f25ae5eb`):

```
arbiter_broken task=b0ec3b03 rc=68 reason=fail_open_to_ladder arb_reason=pool_empty_all_excluded arb_kind=code
candidate_chain task=b0ec3b03 arms=glm,codex,sonnet
route_resolved by=router router=v1 model=glm task=b0ec3b03 rule=none reason=glm_default after=fail_open arb_rc=68
```

Арм выбрала **лестница**, не арбитр. При этом та же форма запроса вручную отдаёт `rc=0`:

```
bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '{"kind":"code","protected":true,"task_class":"standard"}'
-> arm=glm reason=cheapest_capable chain=glm,codex,sonnet
   arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio
```

Значит **арбитр исправен, а вход в него — нет**. Разница в том, что передаёт
`leadv2-dispatch-code.sh` на protected-пути; роутер отдельно исключил `glm-flash` и `freepool`
по `protected_path` ДО вызова арбитра, и это первый подозреваемый — но **механизм не найден, и
назначать его запрещено**. Порядок работы обязателен:

1. Залогировать ТОЧНЫЙ JSON, который диспатчер передаёт арбитру (и переменные окружения, если
   они влияют на пул), в строке диспатча.
2. Воспроизвести `rc=68 pool_empty_all_excluded` этим JSON вручную. Пока воспроизведения нет —
   причина не найдена, и чинить нечего.
3. Только потом править. В отчёте назвать причину одной фразой и показать обе строки: до и после.

**Значимость, записать в отчёт:** вся работа §1 (1.1 балансировка, 1.4 прогноз, 1.6
гранулярность) живёт ВНУТРИ арбитра. Пока боевой путь fail-open в лестницу, ни одна из этих
правок на выбор арма не влияет — они зелёные в сюитах и мертвы в проде.

**Fail-open сам по себе не убирать.** Отказ арбитра не должен останавливать работу; чинится
причина отказа, а не глушится запасной путь. Но fail-open обязан быть **громким и считаемым**:
строка с причиной + счётчик, по которому видно, как часто боевой путь идёт мимо арбитра.

## Часть B — телеметрия падения умирает под set -u

`plugins/leadv2/scripts/leadv2-dispatch-code.sh:2026` в живом прогоне:
`leadv2-dispatch-code.sh: line 2026: attempted: unbound variable`.

Строка внутри `_route_arm_source_suffix()`:

```bash
if declare -p attempted >/dev/null 2>&1; then
  n=${#attempted[@]}          # <- 2026
```

`declare -p` проходит для **объявленного** массива, а bash 3.2 (штатный на macOS) под `set -u`
падает на `${#arr[@]}` объявленного пустого массива. Функция умирает ровно тогда, когда должна
напечатать `arbiter_pick=<...> arm_source=ladder_fallback depth=<...> after=<...>` — единственную
строку, объясняющую уход на лестницу. Самоослепление.

Починка: страж обязан проверять непустоту способом, безопасным на bash 3.2 (не `declare -p`).
Проверить, нет ли того же шаблона в других местах файла, и назвать их число в отчёте.

## Правило
**Переиспользовать существующее.** Ни второго резолвера, ни второй лестницы. Правится вход в
арбитра и страж телеметрии. В отчёте назвать словами, что именно изменено.

## Write set — только эти файлы
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- новые сюиты в `plugins/leadv2/scripts/tests/`

## Off-limits — чужая линия идёт параллельно
`lib/leadv2-route-arbiter.sh` и `config/leadv2-routing.yaml` (линия
w1-granularity-continuous-headroom — арбитра **вызывать** можно, **править** нельзя),
`leadv2-router.sh`, `leadv2-claude-profile-select.sh`, `lib/leadv2-claude-profile-pick.py`,
`leadv2-quota-live.sh`, `leadv2-quota-read.py`.

## Приёмка — обязательный негативный контроль, проверяется лидом
1. Сюита: на форме `kind=code, protected=true, task_class=standard` диспатч выбирает арм
   **через арбитра** — в журнале есть строка решения арбитра и НЕТ `fail_open_to_ladder`.
2. Сюита: воспроизведение отказа. На входе, который раньше давал `pool_empty_all_excluded`,
   теперь пул непуст; сам факт отказа при действительно пустом пуле сохраняется и остаётся
   громким (ненулевой код, строка с причиной).
3. Сюита на bash 3.2 с `set -u`: `_route_arm_source_suffix()` печатает свою строку и не падает —
   и для пустого, и для непустого `attempted`.
4. Негативный контроль, два, оба ВНУТРЬ тела функции: (а) вернуть `declare -p attempted` —
   сюита из п.3 краснеет; (б) вернуть прежний вход в арбитра — сюита из п.1 краснеет.
5. Зелёный и красный прогон целиком в отчёт, плюс артефакт в
   `docs/handoff/w1-arbiter-bypassed-on-dispatch/mutation-control/`. Лид прогонит мутацию
   независимо на настоящем файле; мутация своей копии доказательством не считается.
