# dispatch-510c9c4f — GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01

## Finding: the fix was already committed on this lane

Before touching anything I found the mission's target suite already green,
via a commit already on this branch (`worktree-7ece7ffdc771`):

```
1179c2aa test(GROUP-C): isolate journal root fixture
```

That commit rewrote `plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh`
(fixture-only — scrubbed inherited `CLAUDE_*`/`LEADV2_*` vars in `jpath()`, and
updated `keyed()` to match the current `<basename>-<8-hex>` ephemeral key shape
instead of the retired bare-basename layout) and wrote
`docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/report.md`. A prior
subagent instance on this same task/lane evidently did this work; my run
re-verified it and closed one gap it left.

## Contract confirmed

**`CLAUDE_PROJECT_ROOT`, then `CLAUDE_PROJECT_DIR`, wins over `LEADV2_PROJECT_ROOT`
when both are deliberately set; `LEADV2_PROJECT_ROOT` wins only when neither
explicit `CLAUDE_*` pin is supplied.**

This is not a new decision — it is recorded in a code comment at
`plugins/leadv2/scripts/leadv2-journal.sh:37-48` (commit `efb8d0be`,
2026-09-06, `TESTS-POLLUTE-REAL-JOURNAL-01`): *"The rung goes AFTER both
CLAUDE_* ones and BEFORE the cwd fallback, so the production path -- which
sets CLAUDE_PROJECT_ROOT deliberately, to keep a foreign-root dispatch out of
the losing repo's journal -- does not change by a byte."* I verified
`persona-engine/.claude/settings.json:74` ambiently exports
`LEADV2_PROJECT_ROOT` for every session started there — confirming the
scenario the comment describes (an ambient/inherited `LEADV2_PROJECT_ROOT`
must not beat a session's deliberate `CLAUDE_*` pin). I did not touch this
comment or the precedence order in `leadv2-journal.sh` — changing it would
reintroduce the `TESTS-POLLUTE-REAL-JOURNAL-01` incident it documents.

Old case `(b)` asserted a `LEADV2_PROJECT_ROOT`-alone input while its `jpath`
helper let the runner's own inherited `CLAUDE_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`
leak through — a fixture-environment contradiction against cases `(a)`/`(a2)`,
which assert the opposite ordering deliberately. `test_encodes_superseded_requirement`
does NOT apply here — nothing was superseded; the fixture was simply dirty. Cause
class: `never_reaches_subject` (case (b) never tested "LEADV2_PROJECT_ROOT alone"
because inherited CLAUDE_* vars were still present).

## What I found broken and fixed this run

The report at `docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/report.md`
claims the two mutation-control artifacts under `mutation-control/` are
"committed." They were not: `.gitignore:77` has a blanket
`docs/handoff/*/*` rule that silently dropped
`ephemeral-key-format.patch`, `precedence-isolation.patch`, and their two
timestamped `.txt` probe-output files (matches known repo issue
`handoff-artifact-sh-gitignored.md`). I verified the artifacts themselves are
genuine `leadv2-mutation-control.sh` output (matching baseline_rc/mutated_rc/
red_line/diff_hash/lane_diff_hash schema, red_line text matching the suite's
actual `bad()` output) and force-added them:

```
$ git add -f docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/
A  docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/20260915T165540Z-73915.txt
A  docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/20260915T165648Z-36298.txt
A  docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/ephemeral-key-format.patch
A  docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/precedence-isolation.patch
```

No other production or test code was changed this run — `leadv2-journal.sh`
and `test-journal-honours-the-pinned-root.sh` are exactly as committed at
1179c2aa.

## Falsification set (this run, from this worktree, macOS Darwin 25.6.0)

```
$ bash -n plugins/leadv2/scripts/leadv2-journal.sh
rc=0
$ bash -n plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh
rc=0
$ bash plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh
== the journal writes where the caller pinned it
  ok   — (b) LEADV2_PROJECT_ROOT alone -> the pinned root, not cwd
  ok   — (a) NEG-CTL: CLAUDE_PROJECT_ROOT still outranks LEADV2_PROJECT_ROOT
  ok   — (a2) NEG-CTL: CLAUDE_PROJECT_DIR too
  ok   — (c) nothing pinned -> prior resolution unchanged
== a real write, and the repo it must not touch
  ok   — (d) nothing written into the cwd repo
  ok   — (e) the line landed at the pinned root's own address

passed=6 failed=0
SUITE_RC=0
```

No Python files in this diff; `python3 -m py_compile` not applicable.

Registration check:
```
$ grep -n "test-journal-honours-the-pinned-root.sh" plugins/leadv2/scripts/tests/run-core-offline.sh
534:  "journal honours the pinned root|||bash $TEST_DIR/test-journal-honours-the-pinned-root.sh"
```
Suite is registered — no new suite was added this run.

## Off-limits respected

Did not touch `leadv2-dispatch-code.sh` or `leadv2-dispatch-product-close.sh`
(other lanes' write sets per `report.md` Face 2/3/4 split). No runtime-state
paths (`docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`)
were touched.

## Left red

Nothing in this suite's scope is left red. Faces 1/3/4 of
`ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01` are explicitly other lanes'
responsibility and are untouched here.

DELIVERABLE_COMPLETE
