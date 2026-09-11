# Compaction arithmetic: earlier is real, but 250k is not universal

## Measurement

I reproduced the brief's 5,304 usage-bearing records for `fe5013c6` and its component totals. Across 23 default-ceiling sessions, 122 auto-compactions had median `preTokens=467,627` (mean 468,178), median `postTokens=17,617`, and median duration 162 s. However, **0/122 `compact_boundary` records and 0/122 linked `isCompactSummary` records contain an API `usage` object**. The compaction's billed usage is therefore not measurable from these transcripts; below I charge the measured `preTokens` as a one-call input-cost proxy. This is the brief's unsupportable premise.

## Re-derivation tax

For 118 compactions with complete windows, I compared 50 unique assistant responses before and after (5,900 each), deduplicating streamed records by message id. A probe repeat means the same tool target/arguments (`Read` path, search query, or exact `Bash` command) appeared in both windows. Post-compact repeats were **14 calls/responses = 0.12 per compaction**; matched pre/pre controls had 32, so the point estimate is no positive re-derivation tax. Probe volume did rise 4,077 -> 4,725, mainly `Bash` (3,900 -> 4,501) and tool rediscovery (`ToolSearch`, 11 -> 68). Treating every 648 excess call as a whole lost response gives an intentionally punitive 5.49-turn bound.

## Break-even curve

From 99 complete cycles: effective post-compact floor `F=146,092`, growth `g=1,343 tokens/response`, median cycle 231 responses. I modelled cost per productive response as

`C(T,D)=(F+T)/2 + g(T + D*R(T))/(T-F)`,

including one `T`-token compaction call; `D=0.12`, and `R(T)` is the mean first-50 sawtooth context. Measured repo floors/growth produce:

| threshold | persona-engine | getmany | m3-market |
|---:|---:|---:|---:|
| 164k | **165k** | invalid (<245k floor) | 127k |
| 200k | 177k | invalid | 145k |
| 250k | 200k | 331k | 169k |
| 275k | 212k | **276k** | 182k |
| 350k | 249k | 303k | 219k |
| 468k | 307k | 360k | 278k |

Optima are ~164k persona-engine, ~274k getmany, and the CLI minimum ~100k m3-market. At 250k, getmany stops beating 468k above only **0.51** lost response/compaction; the other break-evens are 74 and 205.

## Control and verdict

> **CORRECTION, lead, 2026-09-12 — both controls named in this paragraph are fictions.**
> `--autocompact` is **not a CLI option**: the single bundle match for that string is the
> telemetry event name `tengu_post_autocompact_turn`, and `claude` silently accepts unknown
> flags (verified live: `claude --autocompact 250000 -p 'say OK'` -> `OK`, rc=0).
> `autoCompactWindow` has **0 occurrences** in the 2.1.269 bundle, and so does
> `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. So the 250k default that `claude-subsession.sh:652`
> has been passing to every worker for months is inert (row
> `SUBSESSION-AUTOCOMPACT-FLAG-IS-INERT-01`). It is inert but harmless: workers peak at
> 240,727 over 68 sessions and never reach any threshold.
>
> The real control is the env var `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, a **percentage of the
> window**, clamped `0 < G <= 100`, and `Math.min(...)`-capped so it can only LOWER the
> threshold. Measured window `EHA = 479,500`, default threshold **466,500** from 9 live
> compaction boundaries. Applied in persona-engine as `70` on 2026-09-12; the next
> compaction fired at a peak of **334,776**, against a predicted 335,650 — the knob works.
> Full detail: `ANALYSIS-sol-threshold.md`.
>
> The conclusion below still stands on its own arithmetic; only the named controls were wrong.

**"Compact earlier" is a real lever; the lead's original dismissal was wrong, but one global 250k threshold is unsafe economics for high-floor getmany sessions.**
