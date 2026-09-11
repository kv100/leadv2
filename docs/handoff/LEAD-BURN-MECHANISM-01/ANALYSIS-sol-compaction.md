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

Claude 2.1.269 exposes `--autocompact <auto|tokens>` (100k-1M); the binary exposes `autoCompactWindow`, and `claude-subsession.sh` already passes a configurable 250k default. Thus the ceiling is ours to move (with auto-compact enabled), per launch or per-repo setting.

**"Compact earlier" is a real lever; the lead's original dismissal was wrong, but one global 250k threshold is unsafe economics for high-floor getmany sessions.**
