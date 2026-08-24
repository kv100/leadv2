---
name: leadv2-review
description: Run the leadv2 review gate for a finished lane through lv2guard and leadv2-review-run.sh, and interpret its return codes. Use when a completed lane's diff needs the review verdict before it may move on.
---

## Usage

The user's request text that follows the skill invocation is the task brief.

Запусти ревью для завершённого lane через lv2guard:

```
bash ~/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh -c \
  "bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-review-run.sh \
   --task <task-id> --root <lane-worktree> --handoff <handoff-dir> \
   --diff <diff-file> --author <author> [--fanout <n>]"
```

Раунд-кап теперь на стороне движка (rc=8) — не веди свой счётчик раундов.

| rc | Значение | Действие |
| --- | --- | --- |
| 0 | pass | Только теперь diff может двигаться дальше. |
| 2 | плохие/пропущенные флаги | Исправить вызов; НЕ мержить. |
| 6 | blocked: пустое/потерянное тело ревью | Один повтор другой аркой; второй блок — park. |
| 7 | fail | Один ограниченный fix-раунд по названным находкам, затем ре-ревью. |
| 8 | round/spawn cap | Эскалация или park; НИКОГДА не зацикливаться. |
| 9 | unreviewed: нет доступной арки | Это НЕ pass; park или эскалация. |

`review-gate.md` — не вердикт сам по себе: читай `status:`; двигаться дальше
можно только при rc=0 **и** `status: pass`. `do_not_merge=1` — абсолютен.
