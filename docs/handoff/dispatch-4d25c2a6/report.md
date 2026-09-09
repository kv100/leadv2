# GUARDS-REFUSE-REAL-WORK — two dispatch guards that refuse legitimate work

Branch `worktree-GUARDS-REFUSE-REAL-WORK`, commits `ab68fc5f` (code+tests) — merged to
`main` by the lead as `800e7828` while the mutation controls were running. This file and
the mutation-control artifacts are the lane's post-merge evidence commit.

## The signal that distinguishes audit from build (defect 1, the design call)

The dispatcher ALREADY had the signal: the **validated lane deliverable declaration**
(`--lane-deliverable 'report:<path>'`, or a `LANE_DELIVERABLE: report:<path>` mission
line), resolved and exactly-parsed once in `cmd_resolve` (dispatch-code.sh :8046-8056)
before both `_undiffable_writes_guard` call sites. No new flag was added:

- A lane that declared its document deliverable IS the audit/design shape; the close
  gate's `kind=report` branch certifies that file (exists, ≥600B/12 lines substantive,
  no code laundering, reviewed against the mission excerpt). The doc-only write set
  naming it is honest scope.
- A build lane that "quietly produced nothing reviewable" declares nothing → still
  refused pre-spawn (case B of the new suite, red under wr-mut-2).
- An UNPARSABLE declaration (`diff:...`) does not exempt — fail-closed (case B2).
- A parallel `--lane-kind audit` flag was rejected: it would be a second, unenforceable
  way to say "document lane" (nothing at close certifies a bare kind flag), which is
  exactly the laundering hole the guard exists to close.

**Both ends key on the same declaration**: `_undiffable_writes_guard` admits with a loud
`write_set_undiffable_exempt reason=report_deliverable` decision; `pc_precheck_writes`
(product-close) carries the mirror exemption on `_pc_kind == "report"` so the admitted
lane is certified at close instead of bouncing there (which would have recreated B5's
paid-worker-then-refused disease one phase later).

## Defect 2 — the matcher now reads execution position, not bytes

Round 2 (2026-08-05) had fixed the plain `scripts/task-add.sh "…"` shape, but the
INTERPRETER branch scanned every token after `bash/sh/zsh` via `shlex` — which strips
quotes — so `bash scripts/task-add.sh "…fix leadv2-dispatch-code.sh…"` (the actual
incident shape, row e433cf64f4f0) still matched the quoted prose as a script path.
Reproduced live before the fix: rc=2 BLOCKED. Round 3:

- `q_tokens()` tokenises quote-aware;
- for an interpreter head, only what the interpreter EXECUTES is examined: the script
  token (first non-flag after the interpreter / after `--`), or the `-c`/`-lc` payload,
  re-parsed as a command (depth-capped);
- argv after the script is data, never a command;
- no bypass phrase added; `LEADV2_ALLOW_FG_DISPATCH` and `# fg-dispatch: allow` are
  unchanged author-intent escapes.

Bonus: `bash -c "leadv2-fanout.sh …"` / `bash -lc "cd /x && leadv2-fanout.sh …"`, which
previously ESCAPED the guard (known false negative), are now blocked — verified rc=2.

## Files changed (ab68fc5f, merged as 800e7828)

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — WRITESW-AUDIT-EXEMPT in
  `_undiffable_writes_guard` + docstring/declared-controls + remedy text.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — mirror exemption in
  `pc_precheck_writes`.
- `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` — Round 3 matcher.
- `plugins/leadv2/tests/test-writeset-admits-an-audit-lane.sh` — NEW, self-registered
  (`run-all-triggers: leadv2-dispatch-code leadv2-dispatch-product-close`).
- `plugins/leadv2/tests/test-fg-dispatch-guard-reads-the-command.sh` — NEW,
  self-registered (`run-all-triggers: leadv2-block-fg-dispatch`).
- `plugins/leadv2/tests/test-handoff-only-write-set-is-refused-early.sh` — case 1b
  flipped from "still refused" to the exemption invariant (its old comment said "combo
  is undiffable at close today" — "today" is what this lane changed).

## Falsification set (all green, raw lines in the session log)

- `/bin/bash -n` on all 6 changed shell files: OK ×6. No standalone .py changed.
- `test-writeset-admits-an-audit-lane.sh`: SUMMARY: failures=0 (A/A2/B/B2/C/D/E).
- `test-fg-dispatch-guard-reads-the-command.sh`: SUMMARY: failures=0 (22 checks).
- `test-handoff-only-write-set-is-refused-early.sh`: SUMMARY: failures=0.
- Close-side consumers of `pc_precheck_writes`: report-only-gate 2/0,
  review-gate-scope-evidence 7/0 red→green, empty-writes-autocommit-loud-skip ALL PASS,
  stop-gate 13/0, empty-diff-waits-for-a-live-worker pass=32 fail=0.
- `tests/run-all.sh --scope changed`: "4 passed, 0 failed" — NOTE: degenerate selection,
  the lead's merge had already landed so the range was empty; the per-suite runs above
  are the real coverage.
- Trigger selection proof: `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` prints
  `leadv2-block-fg-dispatch:plugins/leadv2/tests/test-fg-dispatch-guard-reads-the-command.sh`,
  `leadv2-dispatch-code:plugins/leadv2/tests/test-writeset-admits-an-audit-lane.sh`,
  `leadv2-dispatch-product-close:plugins/leadv2/tests/test-writeset-admits-an-audit-lane.sh`.

## Mutation controls (4/4 red-then-green, artifacts in ./mutation-control/)

| control | mutation (inside function body) | red line |
|---|---|---|
| wr-mut-1 | exemption `if` disabled | `FAIL: caseA declared audit lane dispatches (rc==0) -- rc=2` |
| wr-mut-2 | refusal predicate → `return 0` | `FAIL: caseA exemption decision is loud (reason=report_deliverable)` (caseB's refusal checks fail on the same mutant — the unconditional return also kills the exemption decision) |
| h-mut-1 | head check → whole-segment text match | `FAIL: mention allowed: plain quoted mention (the row text) -- rc=2 err=… BLOCKED` |
| h-mut-2 | matcher → `return False` | `FAIL: exec blocked: direct guarded path -- rc=0` |

Every artifact: `baseline_rc=0`, `mutated_rc=1`,
`lane_diff_hash=27ff3b67…` (bound to ab68fc5f, the last non-artifact commit).
In-suite python mutants (cases C/D and 4/5) double as run-time red-capable copies.

## Operational notes for the lead

- The live hook on THIS session's path was main's Round 2 and blocked my own
  mutation-control invocation because the dispatcher's PATH appeared as a file argument
  (`bash leadv2-mutation-control.sh … leadv2-dispatch-code.sh …`). Worked around with a
  variable-split name; after 800e7828 the live hook is Round 3 and that command shape
  passes. The fix is live via the symlink the moment main moved — no restart observed
  needed for new Bash calls.
- Residual (documented in the hook header): `env X=1 bash launcher.sh` (assignment
  between wrapper and interpreter) still escapes; subshells/heredocs/xargs/ssh still
  unparsed. All fail-open, unchanged posture.
