# DISPATCH-CLOSE-GATE-01 — round 8: set-equality is still not containment

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-lib-source-guarded.sh,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full review: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r7.md`. HEAD is `1d1daf3`.
**`~/Projects/leadv2` main has moved to `42d3232`.** Rebase onto it before anything else — see
the third item; do not fast-forward blind.

**Round 7's main fix is right and the reviewer proved it — keep it.** `leadv2-broad-status.sh:107-109`
now resolves the local path, falls back to the canonical root, and sources only if found in either;
stripping the fallback names `leadv2-broad-status.sh:112` RED. And the degradation is the SAFE
direction: with the lib absent from both roots, `command -v leadv2_alarm_transition` fails, the `&&`
short-circuits, and the ready-line is emitted anyway — it over-notifies rather than swallowing a
beat. That is the opposite of the sibling PIN-CLUSTER defect (guarded source degrading to a silent
fail-open that records `landed` on a dirty lane), and it is the correct choice here. Suites at HEAD:
5/0, 22/0, 19/0. `--help` from persona-engine: rc=1, 45 lines of usage, zero `command not found`.

## [High] the three controls still flip on any unrelated NEW violation

Round 7 replaced first-violation comparison with `comm -23` against a static `documented` baseline
— better, but the assertion is still exact-set equality:

```bash
[[ "${found}" == "${expect}" ]]
```

The reviewer reproduced it live: he appended one unrelated unguarded `source` to
`leadv2-status-collector.sh`, re-ran, and **all three `mut_site` controls failed**, each reporting
two lines. A stranger's commit anywhere in the tree still flips every control at once — which is
exactly the finding round 7 was supposed to close.

Assert **presence of its own `file:line` in the found set**, not equality with the whole set:

```bash
grep -qF "${expect}" <<< "${found}"
```

Then reproduce the reviewer's exact test: strip each of the three guards in turn and show the suite
RED naming that specific file; separately, introduce one unrelated unguarded `source` in
`leadv2-status-collector.sh`, confirm all three controls still PASS, revert it, and show a clean
`git diff --stat`. Paste all of it.

## [Medium] the `--scope changed` artifact

`report.md:120-131` records exit 124 against a genuinely contended
`/tmp/leadv2-core-offline.lock`, with concurrent PIDs from other live lanes verified. That is an
honest disclosure, not a fabrication, and it is fine to keep disclosing. If the lock clears during
this round, file the completed run with its exit code.

## [High] reconcile `tests/run-all.sh` against main@`42d3232` by hand

The lane's copy has diverged ~100 lines. Main now carries HOOK-OUTPUT-CAP's **state-file-bounded**
last-checked-SHA mechanism (a clean HEAD with one unrelated dirty file must select only that file's
own suite); this lane still carries the older round-3 union of uncommitted dirt with the whole
merge-base range, plus its own `EXTRA_SUITE_MAP` rows for `test-lib-source-guarded.sh`,
`test-mission-writeset.sh` and `test-red-proof-gate.sh`.

Taking either side wholesale is wrong: main's side loses your map rows, your side reinstates the
unbounded union that HOOK-OUTPUT-CAP spent four rounds removing. Keep main's state-file bounding
and re-apply this lane's map rows on top. Then prove both properties in one run: a docs-only HEAD
with unrelated dirt still selects this lane's suites, AND a clean HEAD with one unrelated dirty
file selects only that file's own suite.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

Three controls that survive an unrelated violation elsewhere in the tree, shown with the reviewer's
own repro, and a `tests/run-all.sh` reconciled onto main with both selection properties pasted from
one run.
