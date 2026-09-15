# GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01

One red suite — `test-journal-honours-the-pinned-root.sh` — whose cause was already located, with a
control, by the Wave-0 diagnosis lane. Subject: `plugins/leadv2/scripts/leadv2-journal.sh`.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**
**Read `docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` — Face 2 — before you
touch anything.** It is on main, and it applied no production change, so nothing in it is done.

Its verdict: **four independent defects, not one.** Yours is Face 2 alone. Do not touch
`leadv2-dispatch-code.sh` or `leadv2-dispatch-product-close.sh`; other lanes own those and your
write set does not include them.

## What was measured
```
== the journal writes where the caller pinned it
  FAIL — (b) pin ignored, resolved to '.../leadv2-state/leadv2/tasks/fixture-task/journal.md'
  FAIL — (a)  NEG-CTL: the new rung overrode an explicit CLAUDE_* pin
  FAIL — (a2) NEG-CTL: rung overrode CLAUDE_PROJECT_DIR
passed=2 failed=4   SUITE_RC=1
```

Decision site: **`leadv2-journal.sh:48`**. Its precedence is
`CLAUDE_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` → `LEADV2_PROJECT_ROOT` → cwd, and lines **81-90** pass
the same precedence down to state-path. At runtime:
```
CLAUDE_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2
LEADV2_PROJECT_ROOT=/private/tmp/.../pinned
winner=CLAUDE_PROJECT_ROOT
```
Control from the delivered probe — removing `CLAUDE_PROJECT_ROOT` and `CLAUDE_PROJECT_DIR` moves
**only** this face:
```
FACE-2 RED             CLAUDE=.../claude  LEADV2=.../pinned  resolved=.../.ephemeral/claude-...
FACE-2 CONTROL GREEN   unset_CLAUDE                          resolved=.../.ephemeral/pinned-...
```

## The judgment this lane exists to make
The suite is **internally inconsistent about its own environment**, and you must resolve that
before writing code:

- Case `(b)` asserts a `LEADV2_PROJECT_ROOT` pin is honoured — but it never clears the inherited
  `CLAUDE_*` variables, so in any real session that pin is outranked and `(b)` is asserting
  something false about its own environment.
- Cases `(a)` and `(a2)` are negative controls asserting the opposite direction: that the newer rung
  must **not** override an explicit `CLAUDE_*` pin.

So the suite already says `CLAUDE_*` should win when explicitly set. The defect is then that `(b)`
runs in a dirty environment, and the fix is to clear the inherited variables for that case — a test
fix, licensed by `lane-rules.md`, and you must quote this reasoning in the report.

**But do not take that as settled before you check one thing**: `persona-engine/.claude/settings.json`
exports `LEADV2_PROJECT_ROOT` in its `env` block, so every session started there carries that root
into a lane dispatched anywhere else. If the intended contract is "an explicit `LEADV2_PROJECT_ROOT`
beats an ambient `CLAUDE_*`", then the precedence at `:48` is the wrong party and `(a)`/`(a2)` are
the stale assertions. Decide which, state the contract you are enforcing in one sentence at the top
of your report, and make the suite assert exactly that contract — including which variable wins when
both are set deliberately.

Whatever you decide, the four-root map is prior art you should read and not re-derive: phase store
reads `LEADV2_PROJECT_ROOT`; journal reads `CLAUDE_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`; the event log
reads `LEADV2_EVENT_LOG_DIR` defaulting to the live path; the lane worktree pin obeys none of them.

## The second, smaller failure
The report also notes the **ephemeral key format** is why the suite's old bare-key expectation
fails (`resolved=.../.ephemeral/claude-…` rather than a bare key). That is a separate claim from the
precedence one and therefore needs its **own** negative control.

## Deliverables
- The fix, with one negative control per independent claim (precedence, ephemeral key format).
- `docs/handoff/GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01/report.md` per `lane-rules.md`, opening
  with the one-sentence contract you chose to enforce.

## Acceptance
```
cd ~/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh >/dev/null 2>&1
```
Red today.
