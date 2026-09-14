# GLM-MAY-REVIEW-AND-ITS-CEILING-IS-95-NOT-80-01 (решение основателя 2026-09-14, дословно

«я говорил что на ревью оставляй 5 процентов недельной квоты, то есть можно давать на glm все задачи до того как квота будет использована на 95 процентов»; «фрипул и глм флеш не могут делать ревью, а вот обычный глм может»). ТРИ ДЕФЕКТА, все подтверждены кодом. (1) ПРАВИЛО ПРО АРМ ПРЕВРАЩЕНО В ЗАПРЕТ НА РОЛЬ. lib/leadv2-glm-policy-resolve.py:77 DEFAULT_REVIEW_EXCLUSIONS=['glm','glm-flash','freepool']. Комментарий рядом называет НАСТОЯЩЕЕ намерение: «never the arm reviewing its own diff» — то есть арм не должен ревьюить СВОЙ дифф. Реализовано как «glm не ревьюит ничего». Это структурно тот же дефект, что FABLE-THINK-TIER-01 (правило про арм стало правилом про роль), закрытый сегодня рядом d9d4dd663c1d. Убрать 'glm' из списка; glm-flash и freepool ОСТАЮТСЯ — решение основателя. Вместо списка реализовать настоящее правило: ревьюер не равен автору диффа (оно уже есть в гейте, ряд 7b7fb938bb30 — проверить, не дублируется ли). (2) ДВА ИСТОЧНИКА ПОТОЛКА, РАЗНЫЕ ЧИСЛА. Тот же файл: DEFAULT_BUILD_THRESHOLD_PCT=95.0 / DEFAULT_REVIEW_THRESHOLD_PCT=98.0 — это УЖЕ намерение основателя. А config/leadv2-routing.yaml: glm { work_pct: 80, review_pct: 90 }, и читает арбитр именно его (lib/leadv2-route-arbiter.sh:1103 выбирает потолок по роли из ceil). Побеждает источник, противоречащий решению. Свести к одному: glm работает до 95, 5 пунктов резерв под ревью. Назвать, какой источник остаётся единственным, и доказать, что второй мёртв. (3) ТЕСТ-СТРАЖ ЗАКРЕПЛЯЕТ ОШИБКУ. scripts/tests/test-glm-flash-arm.sh:364 требует, чтобы 'glm' был в DEFAULT_REVIEW_EXCLUSIONS. Его надо переписать так, чтобы он охранял НОВОЕ правило (glm-flash и freepool исключены, glm — нет), а не старое. Тест, закрепляющий дефект, — отдельная находка: сказать в отчёте, сколько ещё тестов охраняют не то. ЦЕНА: на 2026-09-14 недельная квота glm 85% по сайту Z.AI, а при потолке 80 он был исключён из работы весь день — восемь линий лида получили 'glm:capped' и ушли на sonnet, то есть нагрузка уехала на Anthropic при живой квоте glm. ПРИЁМКА: (а) живой резолв: glm выбирается ревьюером на дифф ЧУЖОГО авторства — строка route_resolved verbatim; (б) негативный контроль: glm НЕ выбирается ревьюером на дифф СВОЕГО авторства, и отказ назван по имени; (в) glm берёт работу при util 80-94 и исключается при 95+; (г) glm-flash и freepool по-прежнему не ревьюят — проверить отдельным случаем, иначе правка расширит дыру; (д) сюита зарегистрирована так, что run-all --scope changed её ВЫБИРАЕТ.

## Method — binding

- Report the resolve line verbatim for every claim; name the surface of every count.
- Run EVERY negative control this row names. A rule you cannot demonstrate refusing
  is not a rule.
- Live quota truth is the Z.AI usage page, NOT a journal line: journal values go stale
  within the hour. Weekly quota read 85% on 2026-09-14 while journals still said 77.
- Any journal number must be scoped to ONE repo directory; `leadv2-state/*/` spans
  repos running under different account slots.
- Do NOT renumber `capability` (founder ruling) and do NOT write into `router_v2.cost`.
- A test that currently asserts the DEFECT (test-glm-flash-arm.sh:364) must be rewritten
  to guard the new rule, not deleted. Say in the report how many other tests guard the
  wrong thing.
