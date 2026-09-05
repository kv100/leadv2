# PROMISE-GUARD-BIND-01 — CONCERN pass (adversarial, pre-design)

**BLOCK the proposed direction as stated.** The corpus says the extractor, not the binding, is the defect. Artifact- binding binds
the verdict to a field that is empty in 1581 of 1581 rows.
## 1. Corpus — all 1581 rows, 239 sessions, 6 repos
`suppressed_action` 1236 (78.2%) · `fired` 344 (21.8%). Nothing else. All rows are 2026-08.

**Critical — brief.md:35 premise is factually wrong.** It claims "the single `verdict=fired` row in the whole 1579-line log". There
are **344 fired rows across 115 sessions**, 151 with non-empty `tools`. A design built on "it fired once" is built on a 343-row
miscount. Re-derive before design.

Real quotes, different sessions:
- `08-01T04:32 f9d3d592` «За ней идут три регрессии (P100/90/40)» — 3pl noise (pre-fix)
- `08-06T10:48 dbba5191` «Жду сводки — потом соберу карту и решение» — legitimately deferred
- `08-29T12:37` «которую видит заказчик» — a relative pronoun
- `08-29T13:00` «Ревью — **fail**» — a noun plus a verdict word
- `08-30T01:07` «`«спрошу основателя»)`» — the lead quoting the rule at itself

**Critical — the extractor is the deeper problem, not close.** Bindable-token census over all 1581 quotes: file path **0 (0.0%)**,
any slash-path 2 (0.1%), TASK-ID 11 (0.7%), lane/worktree word 28 (1.8%), backticked token 91 (5.8%). Quote length median 35 chars,
p10 14; **1504/1580 (95%) end without terminal punctuation** — fragments. There is nothing here to bind to.

Reproduced against the live regexes lifted from `plugins/leadv2/hooks/leadv2-promise-guard.sh`:
- `COMMIT_RU_LEADING` (:189) HITs «какую поверхность выселить», «которую видит заказчик», «Ревью — **fail**». `RU_1SG_NONPAST` =
  `[а-яё]{3,}[юу]\b`; "Ревью" is a noun ending in -ю.
- `COMMIT_RU` (:111) is **unanchored** — it matched verb `дам` *inside* «раундами». The `(?!т(?:ся)?\b)` lookahead only blocks the 3pl
  collision. Add `\b` prefixes.
- Telemetry lies: `pattern` (:462-471) emits `COMMIT_EN` as the *else* branch, so all 422 `COMMIT_EN` rows include pure- Russian
  clauses matched by SHAPE/LEADING. Do not reason from it.
## 2. False-block cost of artifact-binding
- **Fulfilled by delegation** — "перепишу mission X" kept by dispatching a lane that writes X in a worktree. The path never appears in
  the lead's own tool args (`Agent`/`Task` carry a prompt, not a path). **Blocks wrongly.** Prompt- substring binding is both
  trivially faked and trivially missed.
- **No filesystem artifact** — «спрошу основателя», «подумаю». The modal case (≥93% of quotes). Exempt them and the artifact-free
  phrasing becomes permanent immunity (§5); block them and the guard fires on thought.
- **Legitimately later** — «Жду сводки — потом соберу карту» (real row 08-06). A `Stop` hook sees one turn. **Blocks wrongly.**
  CLAUDE.md's deferred-actions rule *requires* such promises; the guard would have to accept `docs/leadv2/scheduled-decisions.md`,
  collapsing the bind to one file.

**High — the proposal is a re-run of a reverted change.** Lines 359-401 document `PROMISE-GUARD-POSITIONAL-REVERT-01` (2026-08-22):
positional binding produced **five false positives against zero true catches in its first full day**, and three reviewers reproduced
the class against the regex patch. The brief describes that reverted rule as live (brief.md:29-33). It is not —
`action_after_promise = has_action` (:400) is turn-wide. Say why the fix is not that again.

**Medium — the 78% suppression has a mundane cause nobody named.** `ACTION_BASH_RE` (:210) ends in `>>?\s*\S`, so any Bash command
containing `2>/dev/null` counts as state-changing. That, not the positional rule, is what makes every working turn immune. One-
character-class fix, independent of the redesign.
## 3. Blocking loops
`SENTINEL="$HOME/.claude/leadv2-promise-retry-${SESSION_ID}.txt"` (:499) is **per-session, not per-turn**, and the second Stop
*deletes* it and passes. So the guard blocks at most every *other* Stop. It survives a stricter verdict without deadlocking — but it
also **defeats enforcement**: a lead that ignores the block is never re-blocked on the same unkept promise, while a firing guard
becomes a block on ~50% of all turns in every repo. `stop_hook_active` (:46) covers only immediate re-entry. Sentinel files are
never swept. Key the sentinel to the *quote*, with decay, before the verdict gets stricter.
## 4. The two suites
**Critical — neither suite is selected by CI.** `plugins/leadv2/scripts/tests/run-core-offline.sh` enumerates suites by explicit
`run_check` calls; `grep -c promise` on it returns **0**. The only workflow is `.github/workflows/validate-skills.yml`. Add both and
prove selection.

- `test-promise-action-binding.sh` asserts hook *decisions* on synthetic shapes: `promise_only → FIRED`, `action_then_promise →
  SILENT`, `promise_then_action → SILENT`, `action_then_report → SILENT`, `action_then_recap → SILENT` (:134-153). **It would not
  catch this defect — it encodes it**; `action_then_promise → SILENT` is the reverted trade, asserted on purpose. A stricter verdict
  flips this suite red by construction. That inversion is the decision, not a failure.
- `test-promise-guard-morphology.sh` asserts HIT/MISS at the *regex* level only — it lifts the patterns and never runs the hook. It
  has no notion of an artifact, so it cannot catch the binding defect either. Its 3pl negative does work: «Они идут параллельно и
  независимо» is now a MISS.
- **RU morphology is load-bearing, and it works against the fix.** `VETO_RE`'s `PAST_RU` = `\w+(?:л|ла|ло|ли)\b` vetoes any clause
  containing such a word. Measured: «диспатчу лейн — детали в hooks/leadv2-promise-guard.sh:12» is **vetoed by «детали»**; «I'll
  dispatch the lane as discussed» by «discussed» (`\w+ed`). Exactly the promises that *do* name an artifact are the ones most likely
  to be vetoed before the verdict runs. Paths are ASCII; the prose around them is not.
## 5. New gameability
1. **Stop stating intent.** The guard punishes announcing a plan, not failing one. Cheapest compliance is silence —
which contradicts the status-pulse rules.
2. **Name a cheap artifact.** "и перевешу `docs/leadv2/active.yaml`" is satisfied by `touch`, already an action verb
(:208). Path-binding makes the no-op *targeted*.
3. **Redirect once.** `echo x >> <promised-path>` satisfies action class and path bind together.
4. **Drop one past-tense word.** «сейчас поднимаю наблюдателя **как и планировал**» → vetoed. Verified.
5. **Split the clause.** Extraction is comma/sentence split; put promise and artifact in different clauses and the
quote keeps neither.
## Contradiction scan
- **High, path.** brief.md:5 names `scripts/tests/test-promise-*.sh`. Git tracks `plugins/leadv2/scripts/tests/…`. A **second real
  copy** sits at `.claude/scripts/tests/…` (identical bytes, mtime Aug 26 vs Aug 22) — a real copy inside a project, the shape
  CLAUDE.md's single-source rule forbids. Name which one is the write set.
- brief.md:16 "1579 rows" vs 1580 lines / 1581 parsed; the fired count derived from it is off by 343.
- `LEADV2_PROMISE_GUARD` kill switch (:21) consistent everywhere checked. No env-name drift.

**BLOCK.** Fix the extractor anchoring and the `>>?\s*\S` action class first, re-measure, then decide whether binding is still the
problem.

DELIVERABLE_COMPLETE
