# PROMISE-GUARD-BIND-01 — round 2 (review said fail)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/tests/test-promise-guard.sh,tests/run-all.sh,docs/leadv2/scheduled-decisions.md,docs/handoff/PROMISE-GUARD-BIND-01/

Full report: `docs/handoff/PROMISE-GUARD-BIND-01/review-r1.md`. HEAD is `fc080bf`; resume from it.

**Kept and proven — do not redo.** The production binding is real: three in-body mutations
(`classify_promise_kind` → `return None`; the `classify_action_kind` loop → `return "dispatch"`;
the fix line → `has_action`) all go red in both suites. Log-only rollout, `--scope changed`
selection and bash-3.2 compatibility all verified working.

## [Critical] the suite writes into the real journal — and has already satisfied the flip condition

`_verdict` never sandboxes `HOME`, so every test run appends to the real
`~/.claude/leadv2-promise-guard.jsonl`. That is **the same file the flip GO-condition reads**.
There are already 84 synthetic `fired` rows across 84 distinct session ids, purely from test runs —
so "≥20 fired rows across ≥3 sessions" is already satisfied by noise, and the decision to start
blocking would be made on fabricated evidence.

Sandbox `HOME` (or the journal path) for the whole suite, and add a control that fails if a test
run writes outside the sandbox. Then say in `report.md` what should happen to the 84 rows already
there — they must not be counted; propose the cleanup, do not silently delete the file.

## [High] the control self-destructs at commit

`test-promise-action-binding.sh:42` pins `PRE_HOOK` to `git show HEAD:`. After the worker commits,
HEAD **is** the fix, so the "pre-fix" arm diffs the fix against itself and reports
`0 passed(red->green), 8 green-pre-fix`. Your `RED-then-GREEN.log` was honest when taken — before
the commit, HEAD was the anchor — but the control can never be re-run and tells a later reader
nothing.

Worse in the other direction: when `PRE_HOOK` is unresolvable, `pre_rc=2` falls through to the PASS
branch. The reviewer measured the same files in a non-git directory printing
`8 passed(red->green)`. The number is noise both ways and the suite `exit 0`s regardless.

Pin the pre-image to a fixed ref or a checked-in fixture, and make an unresolvable pre-image a hard
failure rather than a pass.

## [High] the extractor was never touched — 5 of 12 real promises produce no journal row

The brief said to fix the extractor first, precisely because a binder on a broken extractor binds
the wrong thing convincingly. These realistic promises produce **nothing**:

- «Сейчас поправлю…»
- «Сейчас прогоню тесты»
- «Сейчас закоммичу фикс»

The lead writes in Russian; a guard that only recognises English promise forms will never fire on a
real turn. Extend the extractor to the forms actually used, and use those twelve as fixtures.

## [High] `ACTION_BASH_RE` matches `2>/dev/null`

The `write` kind's `>>?\s*\S` matches shell redirection, so an unrelated command containing
`2>/dev/null` counts as fulfilling a promise to write a file. Removing the catch-all was not the
big win; this is. Tighten it and add a fixture with `2>/dev/null` that must NOT satisfy a write
promise.

## [High] the scheduled-decision row is unparseable by this repo's own grammar

`leadv2-task-anchor.sh` reads the row as NO-MATCH with zero fields, so the ledger layer that is
supposed to surface it will never see it. Rewrite it in the grammar that script actually parses,
and prove it by running the parser over the row.

## [High] the fix is not on the running path

The live plugin-cache copy of the hook has `classify_promise_kind` count 0. Merging alone does not
put this on the path that actually runs. Say in `report.md` exactly what has to happen for the fix
to be live, and verify it.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in
  `docs/handoff/PROMISE-GUARD-BIND-01/round2-red/`.
- No `grep` against script source as an assertion; no negated command as an assertion; no control
  whose pre-image is `HEAD`.
- Keep the rollout log-only under `LEADV2_PROMISE_GUARD_BLOCK=0`. Do not start blocking.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

The suite writes only inside a sandbox with a control proving it; the pre-image pinned and an
unresolvable pre-image failing hard; the extractor recognising the Russian promise forms above,
with all twelve as fixtures; `2>/dev/null` no longer satisfying a write promise; the
scheduled-decision row parseable by `leadv2-task-anchor.sh` (parser output pasted); and `report.md`
stating what must happen for the guard to be live and what to do about the 84 synthetic rows.
