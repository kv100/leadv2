# RECOVER-TWELVE-CONFLICTED-BRANCHES-01 — двенадцать веток с настоящей работой, которые не сливаются

Три сессии упали 2026-09-04. Их линии остались ветками в `~/Projects/leadv2`. Шесть я слил
сам; **двенадцать упираются в настоящий конфликт кода** и без разбора руками пропадут.

Работа НЕ гипотетическая: в каждой ветке есть коммиты с диффом относительно `merge-base`.
Твоя задача — довести их в `main` репо плагина, ничего не потеряв и ничего не выдумав.

## Ветки и их конфликтные файлы (замерено, а не предположено)

| Ветка | Конфликт | Размер |
|---|---|---|
| `worktree-SMART-ARBITER-01` | `tests/mutations/catalog.yaml` | 1 хунк |
| `worktree-6409fada` | `plugins/leadv2/scripts/tests/test-phase-precondition.sh` | 1 |
| `worktree-ARBITER-ESTIMATES-BLIND-01` | `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` | 1 |
| `worktree-66d6209a` | `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` | 3 |
| `worktree-7c9da953` | `test-phase-precondition.sh` | 8 |
| `worktree-DISPATCH-PHASE-DEADLOCK-01` | `leadv2-phase-record.sh`, `test-phase-precondition-bootstrap.sh`, `tests/run-all.sh` | — |
| `worktree-PHASE-BOOTSTRAP-ADMIT-02` | `leadv2-dispatch-code.sh`, `leadv2-phase-record.sh` | — |
| `worktree-CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01` | `leadv2-claude-profile-select.sh`, его сюита, `tests/run-all.sh` | — |
| `worktree-DARK-SUITES-UNREACHABLE-BY-RUNNER-01` | `tests/run-all.sh` | — |
| `worktree-CI-SUITES-ARE-MACOS-ONLY-01` | `leadv2-proof-lib.sh`, `leadv2-skill-proof.sh`, `leadv2-status-surface.5s.sh`, `tests/run-all.sh` | — |
| `worktree-5fa969ac` | `freepool-arm.yaml`, `leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`, `leadv2-route-arbiter.sh`, `test-freepool-capability-floor.sh` | — |
| `worktree-PLUGIN-PAPERCUTS-01` | конфликта нет — слияние отказывается из-за неотслеживаемых файлов в рабочем дереве | — |
| `worktree-agent-a4be34650195f2188` | `plugins/leadv2/scripts/tests/test-brain-class-live.sh` | — |

## Порядок

Иди снизу вверх по размеру конфликта: сначала однохунковые, потом `tests/run-all.sh`
(он конфликтует у четырёх веток — реши его один раз осмысленно, дальше пойдёт легче),
`5fa969ac` последней.

Перед каждым слиянием: `git checkout -- docs/LEAD_V2_STATE.md`. Он вечно грязный, и git
отказывается сливать ВООБЩЕ, ещё до конфликтов, с сообщением про перезапись локальных
изменений. Это не конфликт — это отказ до конфликта, и он выглядит как «ветка не сливается».

## Как разрешать

**Конфликты контрольной плоскости уже решены** — есть готовая петля, повторять её не надо:
`/private/tmp/claude-503/-Users-kostiantyn-vlasenko-Projects-persona-engine/fe5013c6-05e5-4e63-84da-be3e9039517a/scratchpad/recover-merge.sh`.
Она берёт `ours` для всех путей контрольной плоскости и паркованных `~worktree-*` копий,
а на любом ином конфликте откатывается. Запусти её первой; она либо сольёт, либо оставит
тебе ровно конфликты кода.

**Конфликты кода разрешай по смыслу, а не «взять их/взять наши».** Обе стороны — чья-то
настоящая работа. Для каждого файла: прочти обе стороны, пойми, что каждая делала, и собери
версию, которая сохраняет ОБА намерения. Если два намерения несовместимы — не выбирай молча:
опиши обе в отчёте и оставь ветку неслитой.

`tests/run-all.sh` почти наверняка конфликтует по строкам `EXTRA_SUITE_MAP` / списку сюит.
Там правильный ответ — объединение обеих сторон, а не выбор. Проверь это чтением, не верь мне.

## Доказательство, без которого работа не принята

По каждой слитой ветке:
1. `sha` коммита слияния;
2. непустой `git show --stat <sha>` — слияние, которое ничего не принесло, это не слияние;
3. **восемь отслеживаемых симлинков целы** после КАЖДОГО слияния:
   `.bus-offsets .bus.lock .merge.lock active.yaml.lock bus.jsonl merge-queue.jsonl open-threads.md questions`
   в `docs/leadv2/` — каждый обязан быть `-L`. Проверь после каждого, а не в конце: если
   сломается, надо знать на какой ветке;
4. для веток, тронувших сюиту, — прогон этой сюиты **в переднем плане**:
   `timeout 240 bash <сюита>`, и её вывод в отчёт. Красная сюита не блокирует слияние, если
   она была красной ДО тебя — но это надо показать, а не заявить.

По каждой неслитой — причина в одну строку: какие два намерения не сошлись.

## Запреты

Никогда `git add -A`, `git reset --hard`, `git clean`, `git stash` — дерево общее, рядом
работают живые линии. Коммить только поимённо. Не пушить в origin.
Не коммить: `docs/leadv2/{active.yaml,bus.jsonl,merge-queue.jsonl,open-threads.md,questions,.bus-offsets,.bus.lock,.merge.lock,active.yaml.lock}`,
`docs/LEAD_V2_STATE.md`, `docs/leadv2/.compact-freeze.md`, чужие `docs/handoff/*/phases.d/`.
Не сливать `98cec2c0`, `abd48ba4`, `a7f7131c`.

## Как не умереть

Раз в 10 минут — строка в stdout о том, что делаешь сейчас. Убийца простоя стреляет на 1800
секундах молчания. Никогда не уводи свою проверку в фон: фон будит лида, а не тебя, и для
тебя это конец хода. Коммить после КАЖДОЙ ветки, не копи до двенадцатой.

## Набор записи

```
plugins/leadv2/scripts/
plugins/leadv2/config/
tests/run-all.sh
tests/mutations/catalog.yaml
docs/handoff/RECOVER-TWELVE-CONFLICTED-BRANCHES-01/
```

Слияние веток — операция git, набором записи не ограничивается. Файл вне списка не правь;
если он реально нужен — напиши в отчёте и остановись на границе.
