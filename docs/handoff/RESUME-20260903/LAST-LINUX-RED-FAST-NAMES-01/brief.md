# LAST-LINUX-RED-FAST-NAMES-01 — продолжение после падения

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` в этом же репозитории:
там общие правила приёмки, они обязательны.

## Задача

tests/test-status-surface-fast-names.sh зелёная на macOS (12/0) и красная на Linux (9/3). ci-gate на ca99326b даёт known_red=14 unexpected=1 — это единственный unexpected и последний блокер гейта CI. Бриф: docs/handoff/LAST-LINUX-RED-FAST-NAMES-01/brief.md в твоём worktree.

## Приёмка

Красная сюита стала зелёной ИЛИ новая сюита ловит описанный дефект, с негативным
контролем (мутация внутрь тела функции, пара baseline_rc/mutated_rc, красная строка).
Сюита зарегистрирована в EXTRA_SUITE_MAP и раннер её выбирает на `--scope changed`.
Зелено на macOS И в linux-контейнере, оба кода возврата в отчёт.
