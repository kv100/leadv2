# GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01 — довести перепись до решения

Ты доводишь до конца работу, которая оборвалась на середине. Не переписывай её заново.

## Что уже лежит на диске

В этой же папке два файла — `brief-census-criterion.md` и `brief-census-pass2.md`. Прочти
**оба первым делом**. Это две переписи, сделанные предыдущим прогоном. Итогового отчёта нет —
прогон умер до него.

## Тема

**Гварды, которые молча самоотключаются на пустом наборе записи.**

Болезнь общая для всего плагина и подтверждена независимо тремя линиями: у каждой пробы и
каждого гейта три исхода — `да`, `нет`, `не знаю`. Код знает два. Поэтому «не знаю» молча
превращается в значение, и почти всегда в разрешающее. Здесь конкретно: когда набор записи
линии не объявлен (`writes` пуст), гвард не отказывает и не предупреждает, а считает, что
писать нечего, и пропускает.

**Ключевая развилка, не ошибись в ней:** пустой набор записи — это не «файлов нет», это
НЕИЗВЕСТНОЕ множество. Превратить неизвестное в «ничего не пишем» значит поменять громкий
отказ на тихую двойную запись — строго хуже. Разводи три состояния: объявлен и пуст /
объявлен и непуст / не объявлен вообще.

Контекст, проверенный 2026-09-04: `LEADV2_DISPATCH_LANE_WRITES` в
`leadv2-dispatch-code.sh:5369` только ЭКСПОРТИРУЕТСЯ, но никогда не читается как вход —
объявление через эту переменную молча даёт `writes: null`. Флаг `--writes` при этом работает.
**Проверь это сам, не верь на слово.**

## Что нужно

1. **Сведи обе переписи в одну таблицу:** гвард → файл:строка → поведение при непустом наборе →
   при пустом → при НЕобъявленном → живые последствия (если есть доказательство).

2. **Проверь каждую строку по живому коду**, а не по тексту переписи. Помечай явно:
   `подтверждено чтением кода` / `не подтвердилось, перепись ошибалась` /
   `не проверял, потому что <причина>`.

3. **Отдели доказанное от предполагаемого.** Чтение кода даёт гипотезу, не факт — так и пиши.
   Живое доказательство — строка лога, замер, номер диспатча.

4. **Приоритизированный список правок** — по числу неверных ЖИВЫХ решений, а не по вкусу.
   Для каждой: где править, какое поведение должно быть вместо нынешнего, и какая мутация
   доказала бы, что правка настоящая. Мутацию якорить **регуляркой ВНУТРЬ тела функции**, не
   по номеру строки: вставка по номеру строки садится на верхний уровень, краснит всё по
   неверной причине и читается как проход.

5. **Явно скажи, чего НЕ смог установить** и что для этого нужно.

## Запреты

Это разведка, не правка — **ничего не менять в коде**. Никаких `git add`, `git commit`,
`git reset`, `git clean`, `git stash`, `git checkout`: дерево общее, рядом работают две живые
линии. Читать можно всё, писать — только в эту папку. Не пушить в origin.

## Как не умереть

Раз в 10 минут — строка в stdout о том, что делаешь сейчас: убийца простоя стреляет на 1800
секундах молчания. Никогда не уводи свою проверку в фон — фон будит лида, а не тебя, и для
тебя это конец хода.

## Результат

`docs/handoff/GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01/report.md`.

В ответ верни сжатую выжимку: сколько гвардов в таблице, сколько подтверждены живым
доказательством, первые три правки по приоритету, одна строка про оставшееся неизвестным.
Отчёт целиком не пересказывай — он на диске.

## Набор записи

```
docs/handoff/GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01/
```

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b5abfcfd" "<question>" \
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