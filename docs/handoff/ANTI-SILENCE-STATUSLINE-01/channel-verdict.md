# CHANNEL VERDICT — supersedes BEAT-IS-A-HOOK-NOT-A-LOOP and PROVE-THE-CHANNEL-FIRST

Measured 2026-08-30 with the founder at the screen. This replaces the design, not just a detail.

## (a) PostToolUse plain stdout is NOT the channel — killed

A probe hook printing `BEATPROBE-7X9K` was installed on PostToolUse. Result:
- it produced an `attachment` row in the session transcript (the hook ran),
- it was **absent from the lead's context** — good, that was the expensive half,
- and the founder **confirmed he sees nothing**. Fatal.

A second probe writing to `/dev/tty` and firing an `osascript` desktop notification produced no
reported sighting either. The founder runs Claude Code inside the Antigravity IDE terminal panel,
where the TUI owns the screen; tool calls collapse to `Ran 2 shell commands` and hook output is
not rendered at all.

## (b) The real channel already exists, already works, and is already lane-aware

`.claude/settings.json` → `statusLine` → `leadv2-lane-status-line.sh` (311 lines).

Run by hand against this session it emits, verbatim:

```
Opus 5 in ? | cc 88%·7d/5d20h · cx 95%·wk/6d20h · glm 19%·wk/23h58m sup:OFF(retired) | lanes 3:
persona-engine/ANTI-SILENCE-DELIVERY-01 worker confirmed·done 51m stale(51m silent)? | leadv
```

That is exactly the beat this task set out to build: lane count, lane identity, worker state,
age, and a silence flag. It is rendered by Claude Code itself, so it is lead-independent by
construction; it is on screen permanently; and it costs zero context.

## (c) The defect is ORDERING plus LENGTH, nothing else

- Rendered length: **188 chars**. The lane section starts at **char 89**, after the model name,
  the cc/cx/glm quota telemetry and `sup:OFF(retired)`.
- The script's own output is **already self-truncated**: it ends mid-word, `| leadv`.
- Claude Code prepends more of its own before rendering — `(1M context)`, `[default]`,
  `62% ctx`, `168t 4h49m`.

Net effect on the founder's actual screen: the visible tail is
`▶▶ bypass permissions on · 1 shell, 1 monitor`, and every lane is off the right edge.
**Three lanes were running and he could see none of them.**

## Consequence for the plan

Build NO new beat hook, NO loop, NO notifier, NO send door. The task collapses to:

1. Put **lanes FIRST** in `leadv2-lane-status-line.sh`.
2. Budget the line to the terminal width instead of self-truncating mid-word, and reserve the
   budget for lanes.
3. Drop or abbreviate the quota telemetry whenever lanes are present. The founder needs to know
   a lane went silent every second; he does not need `cc/cx/glm` percentages every second.

Steps 1 (hookSpecificOutput JSON schema) and 5 (session key hard-fail, `read -N` under bash 3.2)
stay — those are separately proven bugs. **Steps 2, 3, 4 and 6 are cancelled.**
