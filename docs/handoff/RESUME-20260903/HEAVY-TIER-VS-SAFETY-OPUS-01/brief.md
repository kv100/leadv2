# HEAVY-TIER-VS-SAFETY-OPUS-01 — продолжение после падения

Сначала прочитай `docs/handoff/RESUME-20260903/_shared.md` в этом же репозитории:
там общие правила приёмки, они обязательны.

## Задача

Слияние FABLE увело high-risk маршрут с opus на fable; test-session-route.sh красная на ОБЕИХ платформах (PASS=6 FAIL=2). Бриф: docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/brief.md в твоём worktree.

## Приёмка

Красная сюита стала зелёной ИЛИ новая сюита ловит описанный дефект, с негативным
контролем (мутация внутрь тела функции, пара baseline_rc/mutated_rc, красная строка).
Сюита зарегистрирована в EXTRA_SUITE_MAP и раннер её выбирает на `--scope changed`.
Зелено на macOS И в linux-контейнере, оба кода возврата в отчёт.
