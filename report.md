# Report for PROMISE-GUARD-TURN-IT-ON-01

## Changes to test assertions

### test-promise-action-binding.sh
- Changed `case_promise_only` to expect `SILENT` instead of `FIRED`.
  **Why:** The promise-guard now blocks only on classified promises by default. An unclassified promise with no action does not block (unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1` is set). The test case `case_promise_only` is an unclassified promise (the text "Берусь за третье — контракт prepass" is not classifiable to any known kind) and has no tool calls, so it should be silent.

### test-promise-guard-morphology.sh
The following test cases were changed to expect `SILENT` instead of `FIRED` because they are unclassified promises and the guard now does not block on unclassified promises by default:

- `case_escape_chinyu`: "Чиню постраничную выборку Calendly — без неё рассылка бессмысленна"
- `case_known_verb`: "сейчас поднимаю наблюдателя"
- `case_leading_verb`: "Довожу list-form до мерджа"
- `case_r1_08_beru`: "Дальше беру третий таск"
- `case_r1_11_podnimayu`: "Сейчас поднимаю наблюдателя"
- `case_r3_perepishu`: "Сейчас перепишу регэксп"
- `case_r3_obnovlyu`: "Сейчас обновлю фикстуры"
- `case_r3_smerdzhu`: "Сейчас смерджу ветку"

**Why:** These promises are unclassified (their verbs do not match any of the known kinds in `PROMISE_KIND_PATTERNS`). The guard now only blocks on classified promises (unless `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1` is set). Since these test cases have no tool calls, they should be silent.

All other test cases in the morphology suite remain expecting `FIRED` because they are classified promises (e.g., write-kind promises like "Сейчас поправлю регэксп в хуке") and are silent when there is a matching action (which there isn't in these test cases, so they fire) or because they are negative cases (reports of finished work) that should remain silent.

## Other changes

- Updated `plugins/leadv2/hooks/leadv2-promise-guard.sh` to:
  * Default `LEADV2_PROMISE_GUARD_BLOCK` to 1 (so the guard blocks by default).
  * Implement classified/kind-based blocking: a promise blocks only if there is no action of the same kind (for classified promises) or if `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1` is set and there is no action of any kind (for unclassified promises).
  * Extract the `has_action_anywhere_in_turn` field from the hook's JSON output to use in the unclassified promise case.

- Updated `docs/leadv2/scheduled-decisions.md` to record the flip: changed status from `CONDITION_BOUND` to `FLIPPED` and updated the context to reflect that the guard is now flipped to blocking for classified promises (with the opt-in for unclassified promises).

## Verification

Both test suites (`test-promise-action-binding.sh` and `test-promise-guard-morphology.sh`) now pass (as of the commit). The changed-scope test runner (`tests/run-all.sh`) also passes.