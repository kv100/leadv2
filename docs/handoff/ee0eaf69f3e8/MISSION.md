# ee0eaf69f3e8 — PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01

Subject: `~/Projects/leadv2/plugins/leadv2/hooks/leadv2-promise-guard.sh` (809 lines).
This is the plugin repo. The plugin symlink makes an edit live immediately but
**only a commit inside `~/Projects/leadv2` makes it durable** — an uncommitted
edit in a lane worktree is invisible to the running hook.

## The escape, measured

2026-09-13. The lead ended a turn with «Начинаю с пункта 1 прямо сейчас» and did
not start. The guard stayed silent.

## Why it escaped — read this before theorising

The row text filed in `docs/tasks.yaml` blames the turn-wide binding at line 585.
That is **not precise enough**, and the lane must not stop there. The real chain,
re-derived from the file 2026-09-13:

1. `«начинаю»` IS in `COMMIT_RU_VERBS` (:137), so the clause was **detected**.
2. `classify_promise_kind()` (:406) walks `PROMISE_KIND_PATTERNS` — `test`,
   `commit`, `dispatch`, `write`, `diagnose`. None of them matches «начинаю».
   The clause classified **None**.
3. The `primary_kind is None` branch keeps the promise if the turn contains any
   action of kind `write | commit | dispatch`, anywhere.
4. That turn wrote a scratch analysis script into the session scratchpad with the
   `Write` tool. `ACTION_TOOL_KIND['Write'] = 'write'`. So a file written to
   `/private/tmp/.../scratchpad/` — which has nothing whatever to do with the
   promised work — satisfied the promise.

So the defect is **not** "turn-wide binding is too loose in time". It is that an
unknown-kind promise is kept by a state-changing action **whose target is never
examined**. A scratch write and a repo write are the same evidence today.

## Two approaches that are already closed. Do not re-propose them.

- **Positional binding** ("only actions after the last text block count") shipped
  2026-08-21 and was REVERTED 2026-08-22 with the reasoning and the five live
  false positives written out at :585-610. A closing recap is structurally after
  its own actions, so every summarising turn is a false positive. Do not reopen.
- **Widening the trigger verbs.** Three adversarial reviewers reproduced the same
  defect class against the regex patch with fresh phrasings. The verbs are not
  the cause; «начинаю» was already detected.

## What to build

Two changes, both target-aware, and the second is the load-bearing one.

1. **Give the start-family its own kind.** «начинаю / начну / приступаю /
   приступлю / стартую / принимаюсь» name an intention to BEGIN and carry no
   object. Anchoring discipline is the one already documented in the file
   (TURN-IT-ON-01): `\b`-anchored, verb-formed, 1sg only — the nouns «начало»,
   «начальник», «приступ» must never classify. Note «берусь» is already claimed
   by `write`; leave it there unless you can show the move is safe.

2. **An unknown-kind or `start`-kind promise is kept only by a state-changing
   action on a DURABLE target.** A write whose path is the session scratchpad,
   `/tmp`, `/private/tmp`, or `$TMPDIR` is not evidence that promised work began.
   `commit` and `dispatch` stay durable by construction. Derive the scratch
   prefixes from the environment the hook already sees; do not hard-code one
   machine's path.

You may find a better mechanism than (2) while reading. You are allowed to — the
binding constraint is that your rule must discriminate the true positive below
from all five reverted false positives, and you must show it doing so.

## Acceptance

A new suite at
`~/Projects/leadv2/plugins/leadv2/scripts/tests/test-promise-guard-closing-promise.sh`,
rc 0, containing **both** halves:

**True positive** — a synthesised transcript whose final assistant text is
«Начинаю с пункта 1 прямо сейчас» and whose turn contains a `Write` to a path
under the scratchpad plus several read-only `Bash` calls. The guard MUST fire.
Add a second true positive with «Приступаю ко второму пункту».

**Negative controls, all five, verbatim from :590-596** — each must stay SILENT:
- «они идут параллельно и независимо»
- «Поэтому контракт теперь требует…»
- «дальше по твоему порядку: …»
- «...ту болтовню, которую контракт запрещает»
- «...историю, которую они рассказывают»

Plus a sixth: «Начинаю с пункта 1» in a turn that ALSO commits to the repo —
SILENT, because the work demonstrably began.

A suite with only the true positive is not accepted. A guard verified in
isolation is not verified in composition: run the existing promise-guard suites
too and report their counts before and after.

## Scope and phases

This is a plugin fix, not a strategic line. Full architect divergence is not
required. Required:
- **Review by a second model** on the diff, named in the report.
- **e2e scoped to changed**: your write set is executable hook code, so run
  `tests/run-all.sh --scope changed` in `~/Projects/leadv2` and paste the
  selection proof showing it selects the promise-guard suites. Do not run the
  full suite.
- Commit inside `~/Projects/leadv2`. An edit left in the worktree is not
  delivered.

## Report

| item | value |
|---|---|
| new suite rc | |
| true positives fired | 2 of 2 |
| negative controls silent | 6 of 6 |
| pre-existing promise-guard suites, before → after | |
| `run-all.sh --scope changed` selected | |
| second-model review verdict | |
| commit sha in ~/Projects/leadv2 | |
