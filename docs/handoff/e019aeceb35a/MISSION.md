# PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01

если в router_v2.cost когда-нибудь появится настоящая цена Anthropic, арбитр её молча не увидит. Блок цен ключует запись как anthropic: (plugins/leadv2/config/leadv2-routing.yaml:179), а строки capability_matrix для haiku/sonnet/opus/fable несут provider: claude (:314-331), и обе реализации _price_key (lib/leadv2-launch-registry.py:277-278, lib/leadv2-route-arbiter.sh:581-582) возвращают c.get(provider) дословно для всех строк кроме glm-flash. То есть поиск пойдёт по ключу claude, не найдёт его и свалится в _COST_MEDIAN — ровно то же поведение, что и сегодня при null. Настоящая цена и её отсутствие стали бы неразличимы по поведению. Найдено линией 99df9e6b189e (2026-09-14) и НЕ починено там сознательно: править _price_key, не имея ни одной цены, против которой это проверить, значит поставить непроверяемое изменение в общую ценовую логику. Сейчас мина инертна ровно потому, что правильный результат подгонки — оставить null (R2 отрицательный в обеих формах). Чинить до того, как любая подгонка выдаст защитимое число: либо переименовать ключ yaml в claude, либо научить _price_key нормализовать claude->anthropic — и в обоих случаях сюита должна содержать негативный контроль, доказывающий, что число ЧИТАЕТСЯ (как уже сделано в test-arbiter-prices-by-provider.sh: подмена цен переворачивает выбор арма).

## Method — binding

- Name the surface of every count; report the command that produced each number.
- Run the negative control this row names. A rule you cannot demonstrate refusing is not a rule.
- Register any new suite so `tests/run-all.sh --scope changed` SELECTS it.
- Do NOT renumber `capability` (founder ruling 2026-09-14) and do NOT write into
  `router_v2.cost` (that thread is closed on measured evidence).
