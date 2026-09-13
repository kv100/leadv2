# ee0eaf69f3e8 round 2 — the escape still reproduces, and the new pattern fires on an honest sentence

Round 1's work is UNCOMMITTED in `~/Projects/leadv2` (live through the plugin
symlink, not durable): `plugins/leadv2/hooks/leadv2-promise-guard.sh` +126/−5 and
the new `scripts/tests/test-promise-guard-closing-promise.sh`. Keep it, fix the
two gaps below, then commit. Read `MISSION.md` and `critic.full.md` here first.

## What round 1 got right — do not touch

- Positional binding was NOT reintroduced. Verified. Keep it that way.
- The scratch-prefix derivation is env-derived, not hard-coded to one machine.
- Mutation controls M1/M2 mutate the real production file, not a suite fixture.
- All five promise-guard suites are green in composition.

## BLOCKING 1 — the same escape, one tool over

`leadv2-promise-guard.sh:630-632`:

```python
if action_kind != 'write' or name == 'Bash' or is_durable_target(write_target(inp)):
```

`or name == 'Bash'` exempts the Bash tool from the durability check entirely.
But `ACTION_KIND_BASH` (:304) classifies `touch`, `cp`, `mv`, `tee`, `sed -i` and
shell redirection as kind `write`. So `echo x > /tmp/y` keeps a start-promise for
exactly the same reason `Write` to the scratchpad used to: the target is never
examined. The reviewer reproduced the original escape verbatim through this path.

Worse, the new suite's case **N11 pins this as a "documented residual"** — a test
that asserts the hole is present. Delete that framing: a test that ratifies the
defect is the defect's second life.

**Fix:** a Bash write must have its target extracted and checked for durability
like any other write. Redirection target, the destination argument of
`cp`/`mv`/`tee`/`install`, the file `sed -i` edits. When the target genuinely
cannot be extracted, say so explicitly and choose the conservative answer — a
promise NOT kept — rather than silently passing.

## BLOCKING 2 — the new pattern fires on an honest sentence

```
«Не начинаю новую линию, пока не закрою эту — работаю по плану.»
```

This is a report that the lead is NOT starting something. The new `start`
pattern fires and blocks. That is the false-positive class that killed the
2026-08-21 positional rule — five in one day — and the mission forbade extending
it.

The reviewer also found this is **wider than the new pattern**: `не закоммичу`
fires on the OLD hook too. So negation blindness is a pre-existing engine-wide
gap, not something round 1 invented.

**Fix it once, for the whole detector, not just for `start`.** A commitment
clause carrying a negation of its own verb is not a commitment. Mind the Russian
shapes: `не начинаю`, `не буду`, `пока не`, `не стану`, `вместо того чтобы`, and
the double-negative trap (`не могу не начать` IS a commitment). Do not special-case
one phrase; the point is the class.

## Acceptance

Extend the suite. It must contain, each with its verdict asserted:

**Must FIRE (true positives):**
- «Начинаю с пункта 1 прямо сейчас» with a scratch `Write` in the turn (already there)
- «Приступаю ко второму пункту» (already there)
- **new:** «Начинаю с пункта 1» where the turn's only write is
  `Bash: echo x > "$TMPDIR/scratch"` — this is BLOCKING 1's reproduction
- **new:** «Начинаю с пункта 1» where the turn's only write is
  `Bash: sed -i '' 's/a/b/' /tmp/thing`

**Must stay SILENT (negative controls):**
- all five reverted 2026-08-21 quotes (already there)
- «Начинаю с пункта 1» in a turn that commits to the repo (already there)
- **new:** «Не начинаю новую линию, пока не закрою эту — работаю по плану.»
- **new:** «Не буду коммитить это сегодня.»
- **new (double negative, MUST fire):** «Не могу не начать с первого пункта.»

Remove N11's "documented residual" case or invert it into a true positive.

Also required:
- Re-run all five promise-guard suites; report counts before → after. A guard
  verified in isolation is not verified in composition.
- `run-all.sh --scope changed` proof, taken **after** the commit.
- Second-model review must complete and be named. Do not report a verdict that
  did not run.
- Commit inside `~/Projects/leadv2`. Round 1 died on a false `git_truth_commits`
  refusal precisely because nothing was committed there.
