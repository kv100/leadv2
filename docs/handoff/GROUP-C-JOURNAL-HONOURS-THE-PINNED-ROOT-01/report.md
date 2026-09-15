# GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01

**Contract: `CLAUDE_PROJECT_ROOT`, then `CLAUDE_PROJECT_DIR`, wins over `LEADV2_PROJECT_ROOT` when both are deliberately set; `LEADV2_PROJECT_ROOT` wins only when neither explicit `CLAUDE_*` pin is supplied.**

## Reproduction and cause

From this pinned lane on macOS Darwin 25.6.0, with the session carrying
`CLAUDE_PROJECT_DIR=/Users/kostiantyn.vlasenko/Projects/leadv2` and
`LEADV2_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2`:

```
$ bash plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh
== the journal writes where the caller pinned it
  FAIL — (b) pin ignored, resolved to '/Users/.../.claude/leadv2-state/leadv2/tasks/fixture-task/journal.md'
  FAIL — (a) NEG-CTL: the new rung overrode an explicit CLAUDE_* pin -> '/private/tmp/.../claude-root/docs/leadv2/tasks/fixture-task/journal.md'
  FAIL — (a2) NEG-CTL: rung overrode CLAUDE_PROJECT_DIR -> '/private/tmp/.../claude-root/docs/leadv2/tasks/fixture-task/journal.md'
  ok   — (c) nothing pinned -> prior resolution unchanged
== a real write, and the repo it must not touch
  ok   — (d) nothing written into the cwd repo
  FAIL — (e) the append wrote nowhere readable ('/Users/.../.claude/leadv2-state/leadv2/tasks/fixture-task/journal.md') — a silent write is not a fix

passed=2 failed=4
SUITE_RC=1
```

Cause class: `environment_dependent`. The subject's ordering at
`plugins/leadv2/scripts/leadv2-journal.sh:48` and its matching state-path
branches at `:81-90` already enforce the stated contract. The prior recorded
decision is commit `efb8d0be` (2026-09-06), whose code comment at
`leadv2-journal.sh:37-48` says the `LEADV2_PROJECT_ROOT` rung is after both
`CLAUDE_*` rungs so a deliberate foreign-root dispatch keeps its journal.

The old case (b) claimed an `LEADV2_PROJECT_ROOT`-alone input while `jpath`
inherited the runner's `CLAUDE_*` variables. Cases (a)/(a2) assert the opposite
ordering with deliberately supplied values. This is a fixture-environment
contradiction, not a product precedence defect, so the test now clears inherited
root and state overrides before passing each case's deliberate inputs.

The second independent fixture error was the old bare-key matcher. The canonical
resolver's `EPHEMERAL-BASENAME-COLLISION-01` code at
`plugins/leadv2/scripts/leadv2-state-path.sh:258-279` keys scratch repositories
as `<basename>-<8-hex-digest>` below `.ephemeral`; it no longer uses the bare
basename. The suite now supplies a throwaway `LEADV2_STATE_BASE` and asserts the
complete hashed shape, rather than depending on the caller's real state root.

## Fix and green result

Only `test-journal-honours-the-pinned-root.sh` changed. It remains registered in
`plugins/leadv2/scripts/tests/run-core-offline.sh:534`; no new suite was added.

```
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

## Negative controls

Two independent controls use `plugins/leadv2/scripts/leadv2-mutation-control.sh`
against the changed fixture functions; their committed artifacts are under
`docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/mutation-control/`.

1. Precedence isolation: remove `jpath`'s `-u CLAUDE_PROJECT_DIR` scrub. The
   inherited session pin returns, so (b) must fail rather than falsely treating
   that ambient input as `LEADV2_PROJECT_ROOT` alone.
2. Ephemeral key format: mutate `keyed` from the eight-hex keyed shape to the
   retired bare-key shape. The right root then fails its format assertion.

## Falsification set

```
$ bash -n plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh
rc=0

$ bash plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh
SUITE_RC=0
```

No Python files changed, so `python3 -m py_compile` is not applicable. The
changed-scope runner is the registered journal suite above. Nothing is left red
by this lane.
