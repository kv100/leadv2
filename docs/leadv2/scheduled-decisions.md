# Scheduled decisions

One row per deferred decision: an id, status, the condition that triggers it, and the
exact reversible action to take when it fires. Anything promised for later goes here the
same turn it is promised (task-anchor DIRECTIVE #4).

---

## PROMISE-GUARD-BLOCK-FLIP-01 — flip promise-guard from log-only to blocking

- **status:** FLIPPED
- **due:** 2026-09-01 — flipped per task PROMISE-GUARD-TURN-IT-ON-01

CONTEXT: PROMISE-GUARD-BIND-01 (2026-08-30) fixed the promise extractor and
`ACTION_BASH_RE`/action-kind binding in `plugins/leadv2/hooks/leadv2-promise-guard.sh` so
a promise of a classifiable kind (dispatch / commit / write / test-run) is only "kept" by
an action of that same kind, not by any tool call. As of 2026-09-01, the guard is flipped
to blocking for classified promises (unless `LEADV2_PROMISE_GUARD_BLOCK=0` is set) and
remains log-only for unclassified promises unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`
is set. Evidence: the hook now defaults to `LEADV2_PROMISE_GUARD_BLOCK=1` and
implements classified/kind-based blocking.

- **status:** FLIPPED
- **due:** 2026-09-01 — flipped per task PROMISE-GUARD-TURN-IT-ON-01

CONTEXT: PROMISE-GUARD-BIND-01 (2026-08-30) fixed the promise extractor and
`ACTION_BASH_RE`/action-kind binding in `plugins/leadv2/hooks/leadv2-promise-guard.sh` so
a promise of a classifiable kind (dispatch / commit / write / test-run) is only "kept" by
an action of that same kind, not by any tool call. As of 2026-09-01, the guard is flipped
to blocking for classified promises (unless `LEADV2_PROMISE_GUARD_BLOCK=0` is set) and
remains log-only for unclassified promises unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`
is set. Evidence: the hook now defaults to `LEADV2_PROMISE_GUARD_BLOCK=1` and
implements classified/kind-based blocking.

GO-CONDITION (query over the journal, evaluate before flipping):
```
python3 -c "
import json
rows = [json.loads(l) for l in open('$HOME/.claude/leadv2-promise-guard.jsonl') if l.strip()]
fired = [r for r in rows if r.get('verdict') == 'fired']
# Consecutive tail: no fired row is a false positive (manually reviewed — a promise
# that really was kept by an action of a DIFFERENT kind than what was promised, or a
# promise/action-kind misclassification). Require >=20 consecutive fired rows with
# zero flagged false positives, spanning >=3 distinct session_ids.
print(len(fired), len({r['session_id'] for r in fired}))
"
```
Flip when: the last 20 consecutive `fired` rows have zero known false positives (checked
by hand against the quoted transcript) AND those rows span at least 3 distinct
`session_id`s (not one session's repeated pattern). Re-run the query above after adding
any new `PROMISE_KIND_PATTERNS` / `ACTION_KIND_BASH` entry — widening the kind taxonomy
resets the evidence window for the newly-covered kind.

FLIP (exact): set `LEADV2_PROMISE_GUARD_BLOCK=1` in the environment that runs the Stop
hook (repo-level `.claude/settings.json` `env` block, or the shell profile that starts
`claude`). **As of 2026-09-01, the hook defaults to `LEADV2_PROMISE_GUARD_BLOCK=1`**
(see `plugins/leadv2/hooks/leadv2-promise-guard.sh`). No code change — the hook already
reads this var.

ROLLBACK (one step): unset `LEADV2_PROMISE_GUARD_BLOCK` (or set it back to `"0"`). The
hook falls back to log-only immediately on the next Stop event; no state to clean up,
the journal keeps accumulating either way.

## SD-WORKER-OUTLIVES-VERIFY-01 — прогнать гейты на спасённой работе линии WORKER-OUTLIVES
- **Due:** условие — освободилась одна из двух живых линий (`E2E-TIMEOUT-REPORTED-AS-REGRESSION-01`
  или `LEAD-IS-OPUS-THINK-IS-FABLE-01` дошла до слияния). WIP=2, третью не открываем.
- **GO:** у одной из двух линий появился `dispatch_terminal task=<sig> terminal=landed`, ИЛИ её
  ветка слита в `main` (`git -C ~/Projects/leadv2 log --oneline main | grep <task-id>`).
- **Action:** `LEADV2_PROJECT_ROOT=~/Projects/leadv2 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh
  --task-id WORKER-OUTLIVES-ITS-TERMINAL-STATE-01 --resume-lane --kind codex_fitting_dev` с миссией:
  «работа уже закоммичена как `adf89c9b`, гейты по ней НЕ прогонялись; выполнить пункты 4–6 брифа —
  негативный контроль на каждое из трёх исправлений, зелёное на macOS и в Linux-контейнере,
  доказать что `--scope changed` выбирает сюиту». Перед этим очистить четыре хранилища
  (session-id, receipt, active.yaml, lock) — память `reference_redispatch_needs_four_stores_cleared`.
- **Rollback:** один шаг — `git revert adf89c9b` внутри линии, если негативный контроль покажет,
  что спасённая работа неверна.
- **Why:** воркер умер, держа 23 файла несохранённой работы; лид спас их дословно коммитом
  `adf89c9b`, но собственные гейты линии по этой работе не проходили ни разу. «Закоммичено» без
  гейта — это лгущая зелёнка. Третий за ночь случай ровно той болезни, которую сама линия и чинит.
