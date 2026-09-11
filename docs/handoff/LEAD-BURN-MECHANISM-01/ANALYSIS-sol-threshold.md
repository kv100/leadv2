# 450k is indistinguishable from zero

## Price of the decision

I re-read every unique usage-bearing assistant message in the canonical repo transcripts. Persona-engine now has 119 context drops (median pre/post `466,276/144,639`) and 99 complete cycles (mean growth `1,314` tokens/response), consistent within 2% with my round-2 `F=146,092`, `g=1,343`. Re-running `C(T,D)` with `D=0.12` and first-50 mean `R=F+24.5g` gives:

| T | cost/response | saving vs 467,627 |
|---:|---:|---:|
| 467,627 | 308.9k | — |
| 450k | 300.1k | **2.84%** |
| 400k | 275.3k | 10.89% |
| 350k | 250.5k | 18.91% |
| 300k | 225.9k | **26.89%** |
| 250k | 201.6k | 34.75% |
| 164k | 169.0k | 45.30% |

The 450k saving is below the model's measurement residual: **indistinguishable from zero**. There is no bend at 450k or 400k; 76% of the maximum modelled saving lies below 400k. The defensible conversation starts at 300k.

## Session-start condition

Snapshot `2026-09-11T20:43:31Z`; values are `p25/p50/p75|max`, where context is `input + cache_creation + cache_read` on the first unique real assistant message. Launch modes are not mixed:

| repo / launch | n | start tokens |
|---|---:|---:|
| persona-engine `cli` | 30 | 119.5/155.9/220.5\|277.5k |
| persona-engine `sdk-cli` | 153 | 81.1/82.9/84.1\|218.4k |
| getmany `cli` | 5 | 216.1/218.8/219.4\|260.3k |
| getmany `sdk-cli` | 84 | 43.1/104.8/179.9\|243.9k |
| m3-market `cli` | 8 | 83.2/94.9/97.1\|112.1k |
| leadv2 `sdk-cli` | 1,373 | 96.1/97.4/98.4\|199.8k |

The condition is already met in m3-market, and in worker medians; it is not reliably met in persona-engine interactive sessions. Subtracting the decided 10k schema deferral **and, optimistically, every pre-first-response hook payload** (bytes/4, more than the guard reduction can save) leaves persona `p25/p50/p75 = 102/127/204k`. Median becomes reachable; p75 still needs another **54k** removed.

## Implementable thresholds

| repo/surface | setting now |
|---|---:|
| persona-engine interactive | `autoCompactWindow: 300000` |
| getmany interactive | `autoCompactWindow: 275000` |
| m3-market interactive | `autoCompactWindow: 150000` |
| leadv2 subsessions | keep `LEADV2_SUBSESSION_AUTOCOMPACT=250000` |

One global value is unsafe: 250k loses for getmany, while 450k buys persona-engine nothing. Interactive thresholds **are settable**, per repo, through `.claude/settings.json` (with Auto-compact enabled); `claude-subsession.sh:652` controls only workers.

**Brief error:** m3-market has eight reproducible starts, `59,878..112,087`; no first event is `416,198`. Its claim that the ~59,876 floor does not reproduce is itself false.
