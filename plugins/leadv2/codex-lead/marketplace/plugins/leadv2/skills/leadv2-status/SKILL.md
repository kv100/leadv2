---
name: leadv2-status
description: Build the compact founder status from native Codex agent and plan state plus leadv2 registry/quota sources, without inventing counts or quotas. Use when the founder asks for status, a table of lanes, or quota state in a leadv2 Codex-lead session.
---

## Usage

The user's request text that follows the skill invocation is the task brief.

Собери founder-статус одной компактной таблицей на русском. Показывай только
`IN PROGRESS` и `NEXT`; не добавляй объяснения, технические решения, числа или
квоты, которых нет в источниках.

Сначала возьми native-состояние Codex: вызови `list_agents` и прочитай текущий
native plan. Затем сведи его с внешними leadv2 источниками:

1. Квоты и внешний registry: `bash ~/Projects/leadv2/plugins/leadv2/codex-lead/leadv2-codex-status.sh`.
   `?` для провайдера значит «не удалось прочитать» — никогда не показывай как 0%.
2. `docs/leadv2/founder-status.md` — если файл свежий (сравни `at=` метку
   с сегодняшним временем), используй его состояние без переинтерпретации.
3. Внешние активные lanes: `bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-status-surface.sh --oneline`.

Формат таблицы — две колонки: `IN PROGRESS` | `NEXT`. Объедини native agent
state, native plan и внешние источники по lane/task, не дублируя строки и не
изобретая отсутствующее состояние. Пока работа активна, отправляй компактный
chat-пульс при смене состояния и не реже раза в 60 секунд. Lifecycle hooks
дают машинное pulse-evidence; chat показывает только эту таблицу.
