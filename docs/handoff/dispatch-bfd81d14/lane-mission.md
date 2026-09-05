# RECOVER-5FA969AC-01 — последняя невосстановленная ветка

Три сессии упали 2026-09-04. Двадцать линий уже спасены: восемь слил лид, двенадцать разобрала
линия `RECOVER-TWELVE-CONFLICTED-BRANCHES-01`. Осталась одна — самая тяжёлая, до неё не дошли.

Ветка: **`worktree-5fa969ac`**. В ней настоящая работа по фрипул-арму, арбитру и закрытию
продуктового диспатча. Без разбора руками она пропадёт.

## Конфликт, замерен а не предположен

| Файл | Хунков |
|---|---|
| `plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh` | 13 |
| `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` | 6 |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | 2 |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | 1 |
| `plugins/leadv2/config/freepool-arm.yaml` | 1 |

Плюс конфликты контрольной плоскости (`docs/LEAD_V2_STATE.md`, `docs/leadv2/active.yaml`,
`docs/leadv2/open-threads.md` и паркованные копии `~worktree-5fa969ac`) — **их решать не надо**,
для них есть готовая петля, см. ниже.

## Порядок

**Шаг 0.** `git checkout -- docs/LEAD_V2_STATE.md`. Он вечно грязный, и git отказывается
сливать ВООБЩЕ, ещё до конфликтов, с сообщением про перезапись локальных изменений. Это отказ
ДО конфликта, и выглядит он как «ветка не сливается».

**Шаг 1.** Запусти готовую петлю — она разрешит контрольную плоскость в пользу main и
откатится, оставив тебе ровно конфликты кода:
`/private/tmp/claude-503/-Users-kostiantyn-vlasenko-Projects-persona-engine/fe5013c6-05e5-4e63-84da-be3e9039517a/scratchpad/recover-merge.sh worktree-5fa969ac`

**Шаг 2.** Разрешай конфликты кода **по смыслу, а не «взять их/взять наши»**. Обе стороны —
чья-то настоящая работа. По каждому файлу: прочти обе стороны, пойми, что делала каждая, собери
версию, сохраняющую ОБА намерения. Если два намерения несовместимы — не выбирай молча: опиши
обе в отчёте и остановись на этом файле.

Иди от лёгкого к тяжёлому: `freepool-arm.yaml` → `leadv2-dispatch-code.sh` →
`leadv2-dispatch-product-close.sh` → `leadv2-route-arbiter.sh` → сюита.

Про арбитр знай заранее: за сутки его чинили несколько линий (квота claude, `best_pct is None`,
эффорт из тегов победившего арма). Если сторона ветки трогает те же места — скорее всего это
ДРУГАЯ правка того же файла, а не откат; проверь, не выкидываешь ли уже слитую починку.

Сюита `test-freepool-capability-floor.sh` на 13 хунков — почти наверняка обе стороны добавляли
разные кейсы. Правильный ответ там обычно объединение, а не выбор. **Проверь это чтением, не
верь мне.**

## Доказательство, без которого работа не принята

1. `sha` коммита слияния и непустой `git show --stat <sha>`;
2. **восемь отслеживаемых симлинков целы**: `.bus-offsets .bus.lock .merge.lock
   active.yaml.lock bus.jsonl merge-queue.jsonl open-threads.md questions` в `docs/leadv2/` —
   каждый обязан быть `-L`;
3. прогон сюиты **в переднем плане**: `timeout 240 bash plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh`,
   вывод в отчёт. Красная сюита не блокирует слияние, если была красной ДО тебя — но это надо
   показать прогоном на main, а не заявить;
4. по каждому файлу — одна строка: какие два намерения ты сохранил и как.

Если ветка непереносима — назови, какие именно два намерения не сошлись. Это допустимый исход,
молчаливый выбор стороны — нет.

## Запреты

Никогда `git add -A`, `git reset --hard`, `git clean`, `git stash` — дерево общее.
Коммить поимённо. Не пушить в origin.
Не коммить: `docs/leadv2/{active.yaml,bus.jsonl,merge-queue.jsonl,open-threads.md,questions,.bus-offsets,.bus.lock,.merge.lock,active.yaml.lock}`,
`docs/LEAD_V2_STATE.md`, `docs/leadv2/.compact-freeze.md`, чужие `docs/handoff/*/phases.d/`.

## Как не умереть

Раз в 10 минут — строка в stdout о том, что делаешь сейчас: убийца простоя стреляет на 1800
секундах молчания. Никогда не уводи проверку в фон — фон будит лида, а не тебя, и для тебя это
конец хода. Коммить сразу после каждого разрешённого файла, не копи до конца.

## Результат

`docs/handoff/RECOVER-5FA969AC-01/report.md`.

## Набор записи

```
plugins/leadv2/scripts/
plugins/leadv2/config/
docs/handoff/RECOVER-5FA969AC-01/
```

Слияние ветки — операция git, набором записи не ограничивается.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-bfd81d14" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.