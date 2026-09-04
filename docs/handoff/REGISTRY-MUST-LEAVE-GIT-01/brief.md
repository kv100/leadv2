# REGISTRY-MUST-LEAVE-GIT-01 — реестр живых линий отслеживается гитом, поэтому копий четырнадцать

## Замер (2026-09-04, сессия fb нашла, ведущая подтвердила и расширила)

`docs/leadv2/active.yaml` **отслеживается гитом** — `git ls-files --error-unmatch` подтверждает.
Значит каждое рабочее дерево линии при создании получает СВОЮ копию, замороженную на коммите
ветки, и процесс внутри дерева читает её, а не общую. Замер — четырнадцать копий, 5-106 строк:

    106  .claude/worktrees/LANE-SALVAGE-TOOL-01/docs/leadv2/active.yaml
    106  .claude/worktrees/LAND-PATH-IS-BROKEN-01/docs/leadv2/active.yaml
    106  .claude/worktrees/LAND-MERGE-GATE/docs/leadv2/active.yaml
    106  .claude/worktrees/HANDOFF-ARTIFACTS-ALLOWLIST-IS-NAME-BASED-01/…
    106  .claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/…
    103  .claude/worktrees/HANDOFF-ARTIFACTS-GITIGNORED-01/…
     74  ~/.claude/leadv2-state/.ephemeral/repo/active.yaml
     19  ~/.claude/leadv2-state/.ephemeral/repo2/active.yaml
      9  docs/leadv2/active.yaml
      7  …/SUITE-THAT-CANNOT-FAIL-01/plugins/leadv2/scripts/tests/docs/leadv2/active.yaml
      5  plugins/leadv2/docs/leadv2/active.yaml
      5  ~/.claude/leadv2-state/leadv2/active.yaml
      5  .claude/worktrees/fe034e50/docs/leadv2/active.yaml
      5  .claude/worktrees/f95b50a3/plugins/leadv2/docs/leadv2/active.yaml

## Что это объясняет — всё, что три сессии за вечер объясняли по отдельности

- чистка реестра 106 → 12 сработала в ГЛАВНОЙ копии; в каждом дереве осталось 106 призраков;
- `leadv2_active_unregister` возвращает **rc=0 и не меняет ничего** для читателя, который
  смотрит другую копию (замер fb: шесть вызовов, было 9 строк, стало 9);
- `writeset_conflict` против строк, которых в главной копии нет — они есть в копии дерева;
- рендер печатает «5 sessions» при 9 строках в файле;
- «два реестра расходятся» — частный случай: их не два.

**Живое состояние не имеет права быть отслеживаемым файлом.** Git раздаёт копии по деревьям по
построению, а рабочее дерево линии — это снимок прошлого. Реестр живых линий в git
гарантированно показывает каждому читателю разное прошлое.

## Задача

1. **Вынести живое состояние из репозитория** — единый путь вне дерева (или `.gitignore` плюс
   абсолютный путь). Разрешение пути обязано быть абсолютным, не относительно дерева.
2. **Разрешение пути не должно зависеть от способа запуска.** Сейчас под `bash -c` ломается:
   `_leadv2_state_path_sh:10: BASH_SOURCE[0]: parameter not set`, и путь уезжает.
3. **Убрать существующие копии** из деревьев так, чтобы ничья работа не пропала: копии в
   рабочих деревьях — не данные, а мусор от чекаута, но убедись в этом ДО удаления.

## Приёмка

1. **Живая проба:** `find` по всем рабочим деревьям находит РОВНО ОДИН `active.yaml`, и он
   вне индекса git. Приложи вывод.
2. **Вторая живая проба:** `leadv2_active_unregister <task>` из ЛЮБОГО рабочего дерева и под
   `bash -c` меняет один и тот же файл. Прогони из трёх разных мест.
3. **Негативный контроль на каждое изменённое требование**, мутация ВНУТРИ тела функции,
   доказательство — пара `baseline_rc`/`mutated_rc` и красная строка, НЕ `diff_hash`.
   Обязателен контроль: верни файл в индекс — сюита обязана покраснеть.
4. **Десять прогонов подряд**, все коды возврата.

## Границы

Правь разрешение пути к состоянию (`lib/leadv2-lane-state.sh`, `leadv2-active-registry.sh`),
`.gitignore`, свою сюиту в `plugins/leadv2/scripts/tests/`, свой каталог handoff.
Строку `EXTRA_SUITE_MAP` в `tests/run-all.sh` НЕ добавляй — положи готовой в отчёт и прямо
напиши, что CI сюиту пока не отбирает.

Не трогать: `main`, `docs/leadv2/` кроме `active.yaml` как предмета задачи,
`tests/known-red-suites.txt`, ослабление ассертов. Отчёт — `report.md`.
