Собери статус founder'а одной компактной таблицей на русском (формат как в
single-lead-pulse.md), из трёх источников — не сочиняй числа:

1. Квоты: `bash ~/Projects/leadv2/plugins/leadv2/codex-lead/leadv2-codex-status.sh`
   (одна строка: cc/cx/glm % + окно сброса, lanes, active task). `?` для
   провайдера значит "не удалось прочитать" — никогда не показывай как 0%.
2. `docs/leadv2/founder-status.md` — если файл свежий (сравни `at=` метку
   с сегодняшним временем), процитируй его как есть.
3. Активные lanes: `bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-status-surface.sh --oneline`.

Формат таблицы — три колонки: Lane | Состояние | Следующий шаг. Никаких
дополнительных чисел, которые не пришли из перечисленных выше команд.

Дальше: $ARGUMENTS
