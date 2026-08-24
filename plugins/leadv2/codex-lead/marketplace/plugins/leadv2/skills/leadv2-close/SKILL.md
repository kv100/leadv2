---
name: leadv2-close
description: Close a leadv2 task on evidence only (diff, test output, review rc=0 status:pass, live probe) and record ledger/open-threads entries. Use when a leadv2 lane is finished and the task must be closed.
---

## Usage

The user's request text that follows the skill invocation is the task brief.

Закрой задачу только на основании evidence (диф, тестовый вывод, вердикт
ревью rc=0 status:pass, живой пробник) — не по факту существования файла.

1. Добавь строку в ledger для этой задачи (переход -> closed), append-only.
2. Для всего отложенного/неисправленного — строка в burn-deferred / open-threads,
   не тихое опущение.
3. Worktree lane остаётся на диске — не удалять и не `git worktree prune`,
   пока lane не снят из active.yaml (lv2guard заблокирует prune, пока сессия
   активна).
4. Обнови docs/leadv2/founder-status.md, если ты его владелец в этом раунде.

Не используй здесь `git reset --hard`, `git clean`, `rm -rf` — они либо
запрещены lv2guard'ом безусловно, либо требуют `# deny-floor: allow` только
на выброшенном дереве и никогда не в shared-репозитории.
