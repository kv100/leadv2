# SMART-ARBITER-01 — перепись логики решений арбитра (census-fable)

Автор: architect (Fable 5.1). Дата: 2026-09-04. Дерево: `~/Projects/leadv2`, HEAD после `217168a7`.
Режим: только чтение + пробы со стабом квоты. Ни один файл кода не тронут.

Окно живых решений: `docs/leadv2/tasks/*/journal.md`, строки `route_resolved by=arbiter`
с `2026-09-03T18:00Z` по момент переписи (~24 ч): **143 решения, 75 задач, все role=worker,
0 role=reviewer**. Команда пересчёта (zsh: не разворачивай `$J` без кавычек — он не режется по строкам):

```
cd ~/Projects/leadv2 && cat $(find docs/leadv2/tasks -name journal.md -newermt '2026-09-03 12:00') \
 | grep -E '^- 2026-09-03T(1[89]|2[0-3])|^- 2026-09-04T' | grep 'route_resolved by=arbiter' \
 | grep -oE 'arm=[^ ]+ (model=[^ ]+ )?(tier=[^ ]+ )?effort=[^ ]+' | sed -E 's/model=[^ ]+ //; s/tier=[^ ]+ //' | sort | uniq -c
```

Стаб-пробы A–R ниже воспроизводятся скриптом из §5 (JSON квоты в файл, подмена `LEADV2_QUOTA_LIVE`).

Сокращения: `arb` = `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`,
`dc` = `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`pc` = `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`,
`yaml` = `plugins/leadv2/config/leadv2-routing.yaml`,
`qr` = `plugins/leadv2/scripts/leadv2-quota-read.py`.

---

## 1. Таблица решений

Каждое решение — что арбитр (или его вызывающий) выбирает; вход; откуда; что происходит при
неизвестном/сломанном входе (шаблон 1); файл:строка. **[ДЫРА]** = неизвестное становится
благоприятным или решение выводится из чужого решения (шаблон 2). **[OK]** = неизвестное →
пессимизм или явный отказ. **[ПЕССИМИЗМ-С-ЦЕНОЙ]** = отказ/ужесточение с измеренным дорогим
последствием.

| # | решение | вход | откуда вход | что при неизвестном входе | файл:строка |
|---|---|---|---|---|---|
| D1 | принять вызов | `role` | аргумент 1 | не worker/reviewer → rc 64 → dc `arbiter_broken fail_open_to_ladder` | arb:20 |
| D2 | найти конфиг | `routing.yaml` | `LEADV2_ROUTE_ARBITER_ROUTING_YAML` или sibling | нечитаем → rc 65 → fail-open в лестницу | arb:22-23 |
| D3 | получить квоту | вывод `leadv2-quota-live.sh json` | один вызов, stderr в `/dev/null` | rc≠0 → rc 67; пустой/битый JSON → `SystemExit(2)` (проба M: rc=2). Оба → dc:8037 `arbiter_broken fail_open_to_ladder`, а у лестницы потолок только для glm (dc:5425, 8277) — **[ДЫРА-3, остаточная форма]**: codex/claude на fail-open пути не метрятся | arb:31, 59-65; dc:8030-8040 |
| D4 | freepool жив? | rc гейта + маркер `LEADV2_DISPATCH_REFUSED:` | `leadv2-freepool-gate.sh check` | файла нет → `free_rc=1` → `util_freepool=100`, `status=unknown` (не `down`) → capped **[OK]**, но отсутствующий гейт неотличим в журнале от «квота сожжена» (в `down` превращается только `arm_down`) | arb:32-52, 186-188 |
| D5 | нормализовать kind | `work_kind` / `kind` | дескриптор dc:7969 / pc:478 | отсутствует или не из `KNOWN_KINDS` → `code` **[ДЫРА]**: `diagnose` (который task-judge реально эмитит, arb:82) → `code` → glm-flash effort=low (проба G) | arb:80-90 |
| D6 | нормализовать size | `size` / `task_class` | dc: `${task_class:-standard}` | отсутствует → `standard`; не из `SIZE_MAP` → `standard` + токен `size_unmapped` **[ДЫРА, мягкая]**: незнакомый heavy-класс становится standard → glm-flash допущен (проба K, спасает только `complexity=complex`) | arb:97-100 |
| D7 | require_trusted | `protected`, `safety`, `publish`, `ui_judgment` | dc:7949-7957 (флаги ∨ regex по тексту миссии) + dc:7712-7719 (`_lane_writes_class`) | флагов нет → False → untrusted-армы допущены (нейтрально). Но `lane_writes` пустой → `write_class=unknown` → `writes_protected=1` → `effective_protected=1` **[ПЕССИМИЗМ-С-ЦЕНОЙ, см. F1]** | arb:108-114; dc:7712-7720 |
| D8 | allowed_arms | список от dc | `candidate_arms` после лестницы | не список → все армы; пустой список → `no_capable_cell` rc 68 → fail-open в лестницу с тем же пустым набором (проба L) | arb:115-116, 312, 336-339 |
| D9 | util(provider): статус | `status` провайдера | quota-live | `!= ok` → `pct=100, unknown=True` → `unknown_capped` **[OK]** (C3). Живое: `util_codex=unknown_capped` в **122/143** строк — codex выпал на сутки, ни одной громкой строки о поломке пробы | arb:189-190 |
| D10 | util(glm): pct | `five_hour.pct`, `weekly.pct` | quota-live | статус ok, оба pct null → `best_pct is None → return empty` → **pct=0, unknown=False** **[ДЫРА-1, остаточная форма]** (проба B: `util_glm=0 remaining=100.0`, победил glm-flash) | arb:191-192, 229-234 |
| D11 | util(codex): pct | `limit_reached`, `windows[].used_percent` | quota-live | `limit_reached` → 100 **[OK]**; статус ok и `windows=[]` → **pct=0** **[ДЫРА-1, остаточная форма]** (проба C: `util_codex=0`, codex выбран) | arb:193-196, 234 |
| D12 | util(claude): выбор аккаунта | `accounts[].active/status/account_label` | quota-live | active со `status!=ok` → другой ok-аккаунт того же label, иначе любой ok, иначе unknown_capped **[OK, починено 217168a7]**. Живой JSON сейчас: active max_20x `status=unknown`, ok-двойник max_20x 7d=74 % — фикс работает | arb:198-222 |
| D13 | util(claude): pct выбранного аккаунта | `five_hour.pct`, `seven_day.pct` | quota-live | ok-аккаунт, оба pct null → та же строка 234 → **pct=0** **[ДЫРА-1, остаточная форма]** (проба D: `util_claude=0 remaining=100.0`, sonnet выбран). Фикс выбрал аккаунт по `status`, но не защитил от «status ok, pct null» | arb:223-234 |
| D14 | binding window | max(pct) по окнам | D10-D13 | окна с pct null пропускаются; если ХОТЬ одно окно известно — берётся оно, даже если null именно у binding (weekly) → оптимистично на одно окно **[ДЫРА-1, вариант]** | arb:229-233 |
| D15 | hours_to_reset / period | `hours_to_reset`, `limit_window_seconds` | quota-live (qr:131 `hours = reset-now`, **без clamp ≥0**) | reset не читается → полный период → «далеко» → switch **[OK]**; имя окна неизвестно → `unknown_window` → switch **[OK]**; **reset в прошлом (протухший кеш) → отрицательные часы → `near_reset_wait=True` → провайдер над потолком остаётся в игре** **[ДЫРА]** (проба H: glm 5h=95 %, `hours_to_reset=-2` → `wait_applied=glm`, glm-flash выбран) | arb:161-170, 239-242, 294-298; qr:131-134 |
| D16 | потолок квоты | `quota_ceilings.<p>.work_pct/review_pct` | yaml:38-41 | провайдера нет в yaml → 100 (никогда не capped) — дефолт благоприятный **[ДЫРА, мягкая]**. Проба A: claude 7d=96 → `all_arms_capped` — **читатель потолка для claude/codex В АРБИТРЕ ЕСТЬ**; комментарий yaml:33-37 («codex and claude have no ceiling reader at all») устарел для этого пути и верен только для fail-open лестницы (D3) | arb:281-286; yaml:23-41 |
| D17 | семантика потолка | «WEEKLY window» (yaml:33) vs `max(5h, weekly)` (arb:229-233) | — | 5h-окно 85 % при weekly 13 % → провайдер снят с работы, если reset > 30 мин. Док и код расходятся; живых случаев за сутки не найдено (glm 5h ≤ 2 %) — **гипотеза** | arb:226-233; yaml:33 |
| D18 | capable-ячейки | `kinds/sizes/protected/allowed` | yaml:59-114 | ни одной → `no_capable_cell` rc 68 → fail-open в лестницу (dc:8037) **[OK по замыслу C1]** | arb:312, 336-339 |
| D19 | все capped? | D16 ∧ ¬D15 | — | все → `all_arms_capped` rc 3 → dc `exit 4` (смерть лейна) **[ПЕССИМИЗМ-С-ЦЕНОЙ]**: 6 отказов за сутки — ВСЕ с `util_glm=util_codex=util_claude=unknown_capped` (пробы всех трёх провайдеров упали одновременно, 09-03T20:07-20:15Z и 09-04T12:29-12:32Z). Это не квота, это отказ инструмента, но журнал говорит «квота» | arb:340-344; dc:8028-8032 |
| D20 | floor_mode | env `FREEPOOL_CAPABILITY_FLOOR` → `freepool-arm.yaml` → default | — | неизвестное значение → `bulk_only` **[OK]** | arb:253-265 |
| D21 | floor_applies | `size_raw`, `mkind`, `test_only` | дескриптор | `test_only` отсутствует → False → пол остаётся **[OK]** | arb:271-272 |
| D22 | complexity_penalty | `complexity`, `duration_class` | dc: `${DC_COMPLEXITY:-unknown}` из task-judge (dc:7305-7306); pc: **не передаёт вовсе** | `unknown` не входит в `complexities:[complex]` → штраф 0 → дешёвая ячейка побеждает **[ДЫРА]** (проба E: `complexity=unknown` → glm-flash effort=low). Живое: у 143 worker-решений complexity всегда известна (91 standard/26 simple/20 complex) — последствие сегодня 0; на пути reviewer complexity=unknown по построению (pc:478) | arb:310-311, 361-381; dc:7969; pc:478 |
| D23 | штраф только за `complex` | `complexity` | task-judge | `standard/long` → штраф 0 → glm-flash (cost 0.33) **[по политике yaml:92, не дыра]**, но см. F2 — усилие при этом low | yaml:148-168 |
| D24 | сортировка | `(ecost, util, arm, tier)` | D22 + yaml `cost` | **util только tie-break**: glm 79 % проигрывает claude 5 % только если стоит дороже — не проигрывает (проба J: glm@79 выбран при claude@5). Квота = обрыв на потолке, не градиент. `headroom_weights` (yaml:13-21) читает `leadv2-router-v2.py:131-156`, **не арбитр** | arb:382-384 |
| D25 | anti-sticky | state-файл `${TMPDIR}/leadv2-route-arbiter-last-arm` | глобальный, общий для всех задач/ролей/репо | битый → `last=''` → без ротации (нейтрально); при равной ecost `alternatives[0]` перебивает util-tie-break | arb:388-403 |
| D26 | effort | `tags` ПОБЕДИВШЕЙ ячейки `w`, `mkind`, `protected` ЗАДАЧИ | yaml:127-136 | **выводится из результата D24, а не из трудности** **[ДЫРА-2, круговая]**. Плюс строка `{protected: true → high}` ключуется на D7, т.е. на `writes=<none>`. Пробы: E/F2/G → low; F (complex, glm) → **medium**; J (protected, glm) → high. Живое: glm effort=high на simple ×6, glm effort=medium на complex ×3 — усилие обратно трудности | arb:409-419; yaml:127-136 |
| D27 | tier codex | дешевейшая capable-ячейка codex | yaml:109-111 | standard-size + `complex` → `volume` (gpt-5.6-luna/low, cost 3): штраф D22 бьёт только по тегам cheap/mechanical, а у codex теги review/adversarial → сложная задача на самом дешёвом codex-тарифе **[ДЫРА, гипотеза]** (живых codex-решений за сутки 0 — codex `unknown_capped`) | arb:312, 383; yaml:109 |
| D28 | разбор вывода в dc | sed `.*reason=\([^ ]*\)` | строка арбитра | greedy `.*` берёт ПОСЛЕДНЕЕ `reason=` — им оказывается `floor_reason=standard/code` → в журнал уходит `reason=standard/code` **[ДЫРА-журнал]**: 23/143 строк | dc:7973 |
| D29 | reviewer: дескриптор | `kind=review,size=standard,protected,safety` | pc:478 | нет `author`, `complexity`, `allowed_arms`, реального размера → арбитр слеп к автору (проба I: автор glm → reviewer=glm) и к сложности; самоисключение делается ПОСЛЕ, петлёй pc:487-491 по пулу | pc:478-491 |
| D30 | reviewer: glm как ревьюер | yaml `review: true` у glm (GLM-DOES-ANY-WORK-01) vs `DEFAULT_REVIEW_EXCLUSIONS=["glm","glm-flash","freepool"]` | yaml:84 vs `lib/leadv2-glm-policy-resolve.py:65`; yaml:186-187 всё ещё пишет «never a reviewer» | арбитр выбирает glm (проба I), пул его никогда не содержит → пропуск на следующий арм цепочки + `arbiter_broken reason=arbiter_arm_not_available`. **Решение основателя «пусть и ревью делает» на review-пути не исполняется** **[ПРОТИВОРЕЧИЕ КОНФИГА]**; живых reviewer-строк за сутки 0 — последствие не измерено | pc:482-495; glm-policy-resolve.py:65 |
| D31 | protected из текста миссии | regex `safety[_-]?gate|\bpublish\b|\bpayments?\b` | dc:7950-7957 | любое слово «publish» в миссии → safety=1 → require_trusted + effort=high. Ложные срабатывания не подсчитаны (миссии не читались) — **UNVERIFIED**; проверка: `grep -lE '\bpublish\b' docs/handoff/dispatch-*/mission.md \| wc -l` против `protection_derived ... manual_protected=0 ... write_class=standard effective_protected=1` | dc:7950-7957 |

---

## 2. Находки, отсортированные по числу неверных живых решений за сутки

Формат: **Fn — файл:строка — последствие (число решений)**. «Гипотеза» = механизм доказан пробой, живых
неверных решений за окно 0.

**F1. `writes=<none>` → «protected» → самый дорогой арм / effort=high.** dc:7712-7720.
82 из 139 `protection_derived` строк: `writes=<none> write_class=unknown writes_protected=1`.
Следствие вечером 09-03 (glm ещё `protected:false`): 59 решений `arm=sonnet effort=high` при
`util_glm` 13-15 % и `util_claude` 41→80 %; 60 sonnet-выборов при glm < 80 %; 86+88
`arm_excluded reason=protected_path` для glm-flash/freepool. После 09-04 (glm `protected:true`)
тот же вход даёт `glm effort=high` на simple/standard: 29 из 31. Неизвестный набор записей должен
снимать НЕДОВЕРЕННЫЕ армы (это trust), а не переключать усилие и не выкидывать glm из
дешёвого ряда. **~60 неверных армов + ~29 неверных усилий.**

**F2. effort выводится из тегов победившего арма и из флага protected, а не из трудности задачи.**
arb:409-419, yaml:127-136. 37 решений `glm-flash effort=low` (из них 32 `complexity=standard`,
5 `standard/long`); 31 `glm effort=high` (29 simple/standard); 3 `glm effort=medium` на
`complex`. **≥70 решений с усилием, не связанным с трудностью** (пересекается с F1 по 29).

**F3. sed-разбор `reason=` ловит `floor_reason=`.** dc:7973. 23 строки журнала
`reason=standard/code` вместо `cheapest_capable`. Последствие: журнал лжёт, телеметрия
`_model_select_telemetry` получает мусорный reason. **23 решения с неверной записью.**

**F4. Остаточная форма дыры-1: `status=ok`, все pct null → pct=0.** arb:229-234 (одна строка на
три провайдера, пробы B/C/D). До фикса `217168a7` (09-04T14:50Z) — 6 строк `util_claude=0`,
из них 2 выбрали sonnet на «claude свободен» (09-03T19:42Z, 09-04T14:49:20Z `remaining=100.0`),
4 выбрали glm/glm-flash (не повлияло). После фикса — 0. **2 неверных решения (устранены по
активному аккаунту; форма для glm/codex/ok-аккаунта-с-null осталась).**

**F5. Отказ инструмента = отказ лейна.** arb:340-344 → dc:8028-8032 `exit 4`. 6 `all_arms_capped`,
все с тремя `unknown_capped` одновременно — это падение quota-live, не квота. **6 убитых
лейнов с неверной причиной в журнале.**

**F6. Fail-open лестница без потолка для codex/claude (дыра-3, остаточная).** dc:8030-8040 +
dc:5425/8277 (только glm-гейт). Срабатывает при rc 2/64-68. За сутки `arbiter_broken` = 0 →
**гипотеза**, но проба M (пустой вывод quota-live → rc 2) показывает, что путь достижим одним
таймаутом.

**F7. Квота — обрыв, не градиент.** arb:384 (`util` только tie-break). Проба J: glm@79 % выбран
против claude@5 %; на 80 % glm исчезает целиком. `headroom_weights` yaml:13-21 арбитр не читает
(читает только `leadv2-router-v2.py`). Прямой запрос основателя «учитывать квоту при выборе» не
выполнен по конструкции. Живых неверных решений 0 (glm не подходил к 80) — **гипотеза с
приказом основателя за спиной.**

**F8. Отрицательный `hours_to_reset` → «reset вот-вот» → провайдер над потолком остаётся.**
qr:131 (нет clamp) + arb:239-242. Проба H: glm 5h=95 %, `hours_to_reset=-2` → `wait_applied=glm`,
glm-flash выбран. Живых `wait_applied` за сутки 0 — **гипотеза**; воспроизводится протухшим
кешем quota-live (TTL 60/120/300 с) на границе окна.

**F9. `complexity=unknown` → штраф 0 → дешевейший арм.** arb:310, 371. Проба E. У worker-пути
за сутки unknown = 0; у reviewer-пути (pc:478) unknown по построению. **Гипотеза.**

**F10. Неизвестный kind → `code`.** arb:87-88. `diagnose` (task-judge, arb:82) → code → glm-flash
low (проба G). Сколько диспатчей пришли с `work_kind=diagnose` — **UNVERIFIED**; команда:
`grep -rhoE 'work_kind=[a-z]+' docs/leadv2/tasks/*/journal.md | sort | uniq -c`.

**F11. Конфликт конфигов на review: glm `review: true` (yaml:84) vs
`DEFAULT_REVIEW_EXCLUSIONS` (glm-policy-resolve.py:65) vs yaml:186-187 «never a reviewer».**
Проба I: арбитр выбирает glm ревьюером, пул его не даст. Живых reviewer-решений 0 → **гипотеза**;
команда: `grep -rh 'arbiter_arm_not_available\|role=reviewer' docs/leadv2/tasks/*/journal.md | tail`.

**F12. Reviewer-дескриптор без автора/сложности/размера.** pc:478. Самоисключение — только
постфактум по пулу. **Гипотеза.**

**F13. codex `volume` на complex standard-size.** yaml:109, arb:383. **Гипотеза** (codex не
выбирался за сутки).

**F14. Потолок сравнивается с max(5h, weekly), док обещает weekly.** yaml:33 vs arb:229-233.
**Гипотеза.**

**F15. Провайдер вне `quota_ceilings` → потолок 100.** arb:285. Сейчас все три есть; **гипотеза.**

**F16. Глобальный state-файл anti-sticky.** arb:56, 388-403. Общий для всех задач/ролей/репо;
**гипотеза, низкий приоритет.**

**F17. Тихая суточная пропажа codex.** `util_codex=unknown_capped` 122/143 — правильно
пессимистично, но нет ни одной строки «проба codex сломана N часов». Это не дыра решения, а дыра
наблюдаемости; **122 решения приняты без codex, неизвестно — верно ли.**

---

## 3. Калибровка

Метод (шаблон 1 «неизвестное → благоприятное» по каждому входу + шаблон 2 «круговая зависимость»)
прогнан ДО сверки со списком в задаче. Результат сверки: **3 из 3 переоткрыты.**

- Дыра 1 (claude по флагу `active`) — найдена как D12/D13/F4: фикс подтверждён живым JSON
  (active `status=unknown`, ok-двойник 74 %), а остаточная форма той же дыры найдена на общей
  строке arb:234 для всех трёх провайдеров (пробы B, C, D). Это шире исходной формулировки.
- Дыра 2 (effort по тегам арма) — найдена как D26/F2, и дополнена: вторая половина усилия
  ключуется на `protected`, который на 82/139 диспатчей означает «writes не передали» (F1).
- Дыра 3 (нет читателя потолка у codex/claude) — найдена как D3/D16/F6 **с поправкой**: в
  арбитре читатель есть и работает (проба A: claude 96 → capped), комментарий yaml:33-37 устарел;
  без читателя остаётся только fail-open лестница. Утверждение задачи в исходной форме сегодня
  неверно, в форме «на fail-open пути» — верно.

Итого сверх калибровочных трёх: 14 находок (F1, F3, F5, F7–F17), из них с доказанным живым
последствием — F1, F3, F5 (и F4 до фикса).

---

## 4. Что чинить первым (максимум три)

1. **F1 — `writes=<none>` не должен означать «protected для всего».** dc:7712-7720. Обоснование
   журналом: 82/139 диспатчей за сутки пришли без `--writes`; это дало 59 sonnet-решений при
   glm 13 % (09-03) и 29 `effort=high` на simple/standard (09-04), плюс 174 исключения
   glm-flash/freepool. Один вход с неизвестным значением определил 41 % всех решений суток.
   Нужное поведение: unknown writes → снять ТОЛЬКО untrusted-армы (текущее `require_trusted`),
   не трогать effort и не считать задачу safety. Ещё лучше — заставить вызывающих передавать
   writes (сейчас это не ошибка, а норма).

2. **F2 — effort из задачи, не из арма.** arb:409-419, yaml:127-136. Обоснование: 37 `effort=low`
   на glm-flash и 3 `effort=medium` на complex-задачах glm против 6 `effort=high` на simple —
   усилие обратно трудности. Матрица должна ключеваться на `complexity`/`duration_class`/`kind`
   задачи (они уже в дескрипторе, arb:310-311), с тегом арма максимум как понижающим
   ограничением («flash не умеет high»), а не как источником.

3. **F4+F5+F8 — одна строка arb:234 и один clamp в qr:131.** Обоснование: до фикса 2 решения
   ушли на sonnet по `util_claude=0`; та же строка сегодня отдаёт `pct=0` для glm/codex/любого
   ok-аккаунта с null (пробы B/C/D); 6 лейнов за сутки убиты `all_arms_capped` при полном
   отказе quota-live (F5) — отказ инструмента должен журналироваться как `probe_outage`, а не
   как квота, и, по решению основателя, либо fail-open с громкой строкой, либо retry, но не
   `exit 4`. Clamp `hours_to_reset` к 0 в qr:131 закрывает F8 тем же коммитом.

F7 (градиент квоты вместо обрыва) — четвёртый пункт, не вошёл в тройку только потому, что за сутки
не дал ни одного доказанного неверного решения; но именно его основатель назвал словами
«арбитр должен учитывать квоту».

---

## 5. Как воспроизвести пробы

```
cd ~/Projects/leadv2; S=$(mktemp -d); printf '#!/usr/bin/env bash\ncat "$STUB_JSON"\n' > $S/stub.sh
run(){ printf '%s\n' "$2" > $S/q.json; STUB_JSON=$S/q.json LEADV2_QUOTA_LIVE=$S/stub.sh \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE=/nonexistent LEADV2_ROUTE_ARBITER_STATE_FILE=$S/st \
  bash -c 'source "$0"; route_arbiter "$1" "$2"; echo rc=$?' plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh "$1" "$3"; }
CL='"anthropic":{"status":"ok","accounts":[{"account_label":"max_20x","active":true,"status":"ok","five_hour":{"pct":5,"hours_to_reset":2.8},"seven_day":{"pct":74,"hours_to_reset":3.8}}]}'
CX='"codex":{"status":"ok","limit_reached":false,"windows":[{"kind":"secondary","used_percent":92,"limit_window_seconds":604800,"hours_to_reset":62}]}'
G='"glm":{"status":"ok","weekly":{"pct":33,"hours_to_reset":99}}'
run worker "{\"glm\":{\"status\":\"ok\",\"five_hour\":{\"pct\":null},\"weekly\":{\"pct\":null}},$CX,$CL}" '{"kind":"code","size":"standard"}'                 # B: util_glm=0
run worker "{$G,\"codex\":{\"status\":\"ok\",\"limit_reached\":false,\"windows\":[]},$CL}" '{"kind":"code","size":"heavy","allowed_arms":["codex","sonnet"]}' # C: util_codex=0
run worker "{\"glm\":{\"status\":\"ok\",\"five_hour\":{\"pct\":95,\"hours_to_reset\":-2},\"weekly\":{\"pct\":33}},$CX,$CL}" '{"kind":"code","size":"standard"}'  # H: wait_applied=glm
run worker "{$G,$CX,$CL}" '{"kind":"build","size":"standard","complexity":"complex"}'                                                                            # F: glm effort=medium
run worker "{$G,$CX,$CL}" '{"kind":"build","size":"standard"}'                                                                                                   # E: glm-flash effort=low, complexity=unknown
run reviewer "{$G,$CX,$CL}" '{"kind":"review","size":"standard","author_arm":"glm"}'                                                                            # I: arm=glm
run worker "{$G,$CX,\"anthropic\":{\"status\":\"ok\",\"accounts\":[{\"account_label\":\"max_20x\",\"active\":true,\"status\":\"ok\",\"seven_day\":{\"pct\":96,\"hours_to_reset\":90}}]}}" '{"kind":"code","size":"standard","allowed_arms":["sonnet"]}'  # A: all_arms_capped
```

## 6. Вне охвата

- Миссии не читались (D31 остаётся UNVERIFIED).
- `leadv2-router-v2.py` (легаси-роутер) не переписан — только факт, что `headroom_weights` живёт там.
- `tests/run-all.sh` не запускался.

DELIVERABLE_COMPLETE
