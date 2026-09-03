# PROMISE-GUARD-BIND-01 — the guard fires, then silences itself

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin single source).
Write set: `plugins/leadv2/hooks/leadv2-promise-guard.sh` (524 lines) + its suites
(`scripts/tests/test-promise-action-binding.sh`, `scripts/tests/test-promise-guard-morphology.sh`).

`leadv2-promise-guard.sh` is a `Stop` hook, enabled by default (`LEADV2_PROMISE_GUARD:-1`,
line 21), and it can emit `{"decision":"block","reason":…}` (line ~522). It has never once
blocked a real broken promise in a working session.

## The defect

Every firing in a session that did any work resolves to `verdict=suppressed_action`.

Measured 2026-08-30, session `fa00a41c`, from `~/.claude/leadv2-promise-guard.jsonl`
(1579 rows total). All three rows for that session are `suppressed_action`. The clearest:

```
ts=2026-08-30T00:41:40Z  verdict=suppressed_action
quote="какую поверхность выселить"
pattern=COMMIT_EN  n_commitments=1
tools=[Bash:cd, Bash:cd, Write, Bash:cd]
```

Ground truth for that turn: the lead promised to rewrite a mission file and dispatch a lane.
It did neither. It wrote an unrelated `context.yaml`. The guard counted that unrelated `Write`
as satisfying the promise and stayed silent.

## Mechanism

The positional rule — "only actions AFTER the last text block keep a promise" — tests for the
PRESENCE of an action, not for the PROMISED action. Consequence: any lead that touches a single
tool after its final text block is permanently immune, which is every real session.

Contrast the single `verdict=fired` row in the whole 1579-line log, from a different session:

```
quote="and I'll do my best to help you out"   tools=[]
```

It blocks a politeness formula (zero tools) and misses every genuine commitment. So the guard is
simultaneously too loose (any tool call excuses anything) and too tight (it fires on filler).

## What the fix has to do

Bind the verdict to the **promised artifact** — the file path, task id, command, or lane named in
the promise text — not to tool-call presence. "I will rewrite X and dispatch Y" is satisfied by a
write to X and a dispatch of Y, and by nothing else.

Two things to establish before designing, because both change the shape:
- The commitment extractor already classifies `COMMIT_RU` / `COMMIT_RU_NOW` / `COMMIT_EN` and
  stores a `quote`. Does it capture enough of the sentence to name an artifact, or does it only
  keep a trailing fragment? The quotes above are fragments ("какую поверхность выселить"), which
  suggests the artifact is being thrown away before the verdict is computed.
- `tools` is recorded as names plus a first-word (`Bash:cd`, `Write`) with no arguments. If the
  file path and command arguments are not retained, there is nothing to bind against and the
  recorder has to change too.

## Class

Same family as the other defects found this session, and the reason it matters: the check exists
but is bound to the wrong thing. The worktree pin is a string in a mission instead of a check.
Anti-silence is advice to the lead instead of a channel. Lane liveness counts registration
instead of work. This one counts tool calls instead of the promised action.

## Constraint

This is a `Stop` hook on the lead's own turn boundary. A false block is expensive: it costs the
lead an extra turn every time it misfires, on every session in every repo. The negative control
must cover BOTH directions — a real broken promise blocks, and a kept promise does not.
