# REVIEW-SENTINELS-LANGUAGE-01 — reviewer output contract must be language-proof and fail loud

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/lib/leadv2-review-parse.sh,plugins/leadv2/skills/leadv2-review/ref/reviewer-setup-steps.md,plugins/leadv2/prompts/**,plugins/leadv2/scripts/tests/test-review-sentinels-language.sh,tests/run-all.sh,docs/handoff/REVIEW-SENTINELS-LANGUAGE-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST. Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`. Commit by LANE_WRITES pathspecs; an uncommitted
exit is a failed round. Write the review-facing text in ENGLISH.

## Measured (lead, 2026-09-02, three occurrences in one night)
- FABLE-THINK-TIER-01 R2: `review-glm.md` 16,987 bytes, verdict written as `ОБЗОР_ВЕРДИКТ: FAIL` and
  `НАХОДКА: severity=High …` → `leadv2-review-run.sh` recorded `reason=empty_response` (twice).
- CACHE-TRUTH-01 R1 and MERGE-QUEUE-DEAD-HEAD-01 R2: same shape, same `empty_response`.
- BRAIN-CLASS-LIVE-01 R1: `НАРУШЕНИЕ: severity=High …` + no `REVIEW_VERDICT:` line at all →
  `review_gate status=blocked`. The lead adjudicated all of them by hand from the Russian text.
Cause: the repo's chat-language rule (Russian) reaches the reviewer's context; the parser at
`leadv2-review-run.sh:308/323/644` accepts only the literal English sentinels
(`REVIEW_VERDICT:`, `FINDING: severity=…`). A 17 KB review with real findings is reported as
"empty" — a false-negative gate: a FAIL review can be mis-read as nothing to act on.

## Do
1. Pin the contract in the reviewer prompt (every arm: glm/codex/kimi/sonnet/opus, whichever files build
   the mission — find them, do not guess): "Write the review in English. The first line MUST be
   `REVIEW_VERDICT: PASS|PASS_WITH_NITS|FAIL`. Each finding MUST be one line starting with
   `FINDING: severity=<Critical|High|Medium|Low> file=<path> line=<n> dimension=<…> desc=<…>`. Any other
   language or sentinel is a contract violation and the review will be rejected." Put it at the END of
   the mission (last-instruction position) as well as the top.
2. Parser: distinguish three states — `parsed` (sentinel found), `unparsed_review` (file has ≥ 200
   bytes but no `REVIEW_VERDICT:` line), `empty_response` (file < 200 bytes or absent). `unparsed_review`
   must be LOUD: `review_gate status=blocked reason=unparsed_review bytes=<n> first_line=<…>` and a
   one-shot re-ask on the same arm with the contract text prepended ("Your previous output violated the
   output contract; reformat it as …"), before falling to the next arm. Never map a 17 KB file to
   `empty_response`.
3. Tolerance, not translation: accept the known Russian sentinel variants seen above as a last resort
   (`ОБЗОР_ВЕРДИКТ`, `ВЕРДИКТ`, `НАХОДКА`, `НАРУШЕНИЕ`) by normalising them to the English ones BEFORE
   parsing, journaling `sentinel_normalised lang=ru`. The re-ask in (2) still happens so the fixture
   count of normalised reviews trends to zero.
4. Suite `test-review-sentinels-language.sh` with fixtures taken from the four real files above
   (copy them into `tests/fixtures/review-sentinels/`): (a) English → parsed; (b) Russian sentinels →
   normalised + parsed with the right verdict and High count; (c) 17 KB with no sentinel →
   `unparsed_review` with the byte count, never `empty_response`; (d) < 200 bytes → `empty_response`.
   Mutation negative controls, RUN and paste red: remove the normaliser → (b) red; remove the size
   branch → (c) red. Revert. Register in `tests/run-all.sh` EXTRA_SUITE_MAP for the `leadv2-review-run`
   stem; `tests/run-all.sh --scope changed` → paste the selected-suite line;
   `leadv2-suite-falsifiable.sh` → paste FALSIFIABLE.
5. `report.md`: which mission files carry the contract now (file:line), the parser state table, suite
   output, controls.

## Do NOT
- Do not change what counts as PASS/FAIL, the round cap, or the arm pool.
- Do not translate findings — normalise sentinels only; the body stays as written.
