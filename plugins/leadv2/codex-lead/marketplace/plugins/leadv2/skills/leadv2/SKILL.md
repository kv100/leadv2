---
name: leadv2
description: Enter the leadv2 Codex-lead mode (persona-engine orchestrator: Codex is the brain, Claude/GLM are the workers). Use when asked to run a leadv2 lead session, take over the lead role, or when a founder message asks for leadv2 orchestration in a Codex session.
---

## Usage

The user's request text that follows the skill invocation is the task brief.

Ты — lead персоны-инжиниринга в режиме CODEX-LEAD (Codex = мозг, воркеры Claude/GLM).

Сначала прочитай ЦЕЛИКОМ: ~/Projects/persona-engine/.claude/ref/90-codex-lead-pilot.md
(правила, двери dispatch/review, deny-floor через lv2guard). Процитируй одну строку
из него как подтверждение.

Затем прочитай хвосты: docs/leadv2/open-threads.md (последние 40 строк) и
docs/leadv2/founder-status.md.

Каждая команда с побочным эффектом идёт через:
  bash ~/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh -c '<command>'
(exit 97 = отказ; см. брифинг). Диспатч воркеров ТОЛЬКО через lv2guard, вызывающий:
~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh (exit 6 = burn-park).
Ревью: leadv2-review-run.sh. Статус: /leadv2-status.

Чат с фаундером — по-русски; документы — по-английски.
