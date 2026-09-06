# В7, четыре «не начатых» ряда — все четыре уже на main

Проверка посылки по каждому, прежде чем что-либо делать. Итог: **работы к написанию ноль**,
пометка «не начато» неверна для всех четырёх. Ниже — доказательство на ряд: предковость и
именованный символ, а не текст отчёта.

## 1. `dispatch-1c3ad9d0` — RECOVER-WAVE1-TEN-01, раунд 2

Миссия: перенести в main четыре оставшиеся ветки волны В1. Все четыре — **предки** leadv2/main,
слияния состоялись на следующее утро после брифа:

| ветка | коммит слияния | когда |
|---|---|---|
| `worktree-83c44855` | `ad4be1e3` | 2026-09-05T07:50Z+03 |
| `worktree-5e57c5ff` | `0a499cb3` | 08:21 |
| `worktree-PREPASS-PROVIDER-FALLBACK-01-R5` | `cdf3ffdf` | 08:35 |
| `worktree-PREPASS-PROVIDER-FALLBACK-01-R6` | `30615f10` | 08:36 |

Проверено `git merge-base --is-ancestor worktree-<b> HEAD` для каждой — четыре из четырёх.
Ряд не обновили после слияний; отсюда и «не начато».

## 2. `dispatch-b5abfcfd` — GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01

Закрыт мной сегодня. Предковость: `eca66591` — предок main. Именованный символ на живом дереве:
`foreign-check UNAVAILABLE` в `plugins/leadv2/scripts/leadv2-reply-router.sh` (2 вхождения — обе
слепые ветки `_foreign_check` теперь говорят, что не смогли проверить).

## 3. `dispatch-bc8652c8` — SELFCHECK-FORGED-MARKER-REGRESSION-01

Починено `d539d364` (предок main) — cherry-pick из осиротевшей линии `SELFCHECK-FORGED-MARKER-
REGRESSION-01B` (`950b4aed`), чей воркер умер, не успев приземлить работу. Его собственное
сообщение называет механизм: правка пути фальсификации `4a4ad8ad` заставила падающий тест
советоваться с `_selfcheck_baseline_verdict`, а у файла, созданного самой линией, базы нет по
построению → `SKIP_UNRESOLVED` → fail-open, и подделанный «RED-then-GREEN; exit 1» проходил гейт
зелёным.

**Не поверила коммиту — прогнала сюиту сегодня:**

```
[TEST] RED-then-GREEN: falsification-forged-marker-failing-rc-blocks (codex r1 HIGH #1) (pre_rc=1 -> post_rc=0)
Results: 38 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
```

Это ровно форма «здорового» прогона из улики брифа (38/0 против сломанных 37/1), и именно тот
случай, который регрессировал.

## 4. `dispatch-d3884817` — WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01

Починено `1bbcfbc8` (2026-09-04, предок main). На живом дереве отказ называет виновника:

```
dispatch_refused reason=writeset_pending task=<sig8> blocked_by=<other> age_s=… window_s=…
dispatch_refused reason=writeset_overlap task=<sig8> blocked_by=<other> paths=<paths> writes=…
dispatch_refused reason=writeset_conflict task=<sig8> writes=<lane_writes>      # последний случай
```

Голый `writeset_conflict` остался только там, где ни одна из двух причин не разрешилась — то есть
как обозначенный последний случай, а не как единственное слово на все отказы. Линия самого ряда
умерла с `no_work`: работать было уже не над чем.

## Что из этого следует для доски

Четыре ряда закрываются без единой правки. Общая причина у всех четырёх одна: **строка описывает
намерение, а состояние живёт в git**, и никто не сверил одно с другим. Единственная проверка,
которая их различает, — предковость плюс именованный символ; текст отчёта в трёх случаях из
четырёх ничего бы не сказал (в двух его просто нет).
