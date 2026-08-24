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

Дальше: $ARGUMENTS
