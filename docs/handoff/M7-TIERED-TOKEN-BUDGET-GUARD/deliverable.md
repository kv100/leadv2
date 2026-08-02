# M-7 — Tiered token-budget guard: deliverable

Repo: canonical `~/Projects/leadv2/plugins/leadv2/`. Tiered, edge-triggered
context-budget guard replacing the old single "warn at 80" threshold.

## Files changed

| Path | Change |
|---|---|
| `plugins/leadv2/hooks/leadv2-compact-warn.sh` | rewritten: 3 tiers, edge-trigger, tier-fired state file, env contract, header doc |
| `plugins/leadv2/scripts/leadv2-turn-cost-measure.py` | **new** — re-runnable measurement → `b`, `m`, `C`, three `T(x)` |
| `plugins/leadv2/tests/test-compact-warn-tiers.sh` | **new** — 15-assertion suite |
| `plugins/leadv2/docs/context-tier-guard.md` | **new** — measurement, arithmetic, fraction rule, tier table |
| symlinks for `leadv2-turn-cost-measure.py` | created in `~/.claude/leadv2-shared/scripts/`, `persona-engine/.claude/scripts/`, `respiro-ios/.claude/scripts/` |

`hooks/hooks.json` — **unchanged** (same file, event, timeout). `m3-market` is
not present on this machine, so its symlink could not be created (noted, not
fabricated).

## 1. The measurement (every threshold traceable to it)

Source: `~/.claude/projects/**/*.jsonl`. Founder turn = `type=="user"` whose
`message.content` is **not** a tool_result list. Turn-N context = the first
assistant request after founder turn N (input + cache_read + cache_creation).

Filter: interactive sessions (`max_turn >= 10`). Headless 1-turn subagent runs
dominate by count (median max-turn = 1) and would yield `n≈2`/bucket.

**Slope is fit per-session, not on aggregate medians.** An aggregate fit over
the full turn range is dominated by already-compacted sessions (old 80-turn
guard fired → context reset) whose per-turn context is low and non-monotonic;
the full-range fit goes **negative** (`m = -120` over turns 1..127). The
defensible unit is the **per-session slope over its early pre-compact linear
region (turns 1..12)**; the median across sessions is robust to the few giant
multi-compact outliers.

`scripts/leadv2-turn-cost-measure.py` output:

```
interactive sessions kept   : 204  (max_turn >= 10)
sessions reaching turn 30   : 52
b = median context at turn 1 : 100,995
m = median per-session slope : 9,881 tok/turn  (n=196 sessions, turns 1..12; p25=8,112, p75=12,866)
C = p95 of per-session peak  : 527,155  (p99=715,869, max=933,514)
```

## 2. The arithmetic

```
T(x) = ceil( (x*C - b) / m )        fraction rule (authored, not picked):
                                     0.45 = >half window free, trimming cheap
mild       0.45*527155 = 237,219     0.65 = <third free, cheap trim won't close
  ceil((237,219 - 100,995)/9,881)   0.80 = one large tool result from the wall
  = ceil(13.77) = 14
aggressive 0.65*527155 = 342,650
  ceil((342,650 - 100,995)/9,881) = ceil(24.46) = 25
emergency  0.80*527155 = 421,724
  ceil((421,724 - 100,995)/9,881) = ceil(33.27) = 33
```

**Defaults baked into the hook: MILD=14, AGGRESSIVE=25, EMERGENCY=33.** The old
single threshold of 80 sat **~47 turns past the 0.80·C crossing (turn 33)**.

## 3. Each tier demonstrably fires (actual stdout, driven directly)

Seeded count file + synthetic `{"session_id":...}` on stdin:

```
turn 14: [CONTEXT_TIER:MILD] Context is filling. Trim verbose surfaces …
turn 25: [CONTEXT_TIER:AGGRESSIVE] Context is over half full …
turn 33: [CONTEXT_TIER:EMERGENCY] Context is at ~80% of the working ceiling … /compact …
```

## 4. Tiers are distinguishable

Three disjoint instruction bodies, three distinct markers. **MILD and
AGGRESSIVE never mention `/compact`** (asserted in suite test 1-4). Only
EMERGENCY mentions `/compact`.

## 5. Existing behaviour preserved / superseded

- `LEADV2_COMPACT_WARN=0` still exits 0 before any state write, nothing fires
  (suite test 5). Verified: past-emergency count + WARN=0 ⇒ empty stdout.
- The 80/+40 behaviour is **subsumed**: emergency tier = "at measured 0.80·C
  crossing, ask for compact, re-warn every 40". Same action, same re-warn
  cadence, threshold now measured. Reason: *80 was ~47 turns past the point
  where context was already at 80% of ceiling.* An operator who wants the exact
  old number sets `LEADV2_COMPACT_THRESHOLD=80` (legacy pin, overrides
  EMERGENCY only; lower tiers stay measured).

## 6. Suites (exact counts, bash 3.2)

- `bash tests/test-compact-warn-tiers.sh` → **15 passed, 0 failed**.
- `bash tests/test-compact-hooks.sh` → **6 passed, 3 failed** — **unchanged**
  before and after M-7. The 3 failures are pre-existing in the **post-compact
  checkpoint** hook tests, unrelated to compact-warn, **not caused by M-7**.
  Flagged for lead decision; not silently fixed (another lane's scope).

## 7. Cross-provider review gate (Codex)

`codex exec --model gpt-5.4` (xhigh) reviewed the hook logic. It raised two
concrete correctness bugs, **both fixed**:

1. ~~`FIRED` persisted before the emit, so a python3 failure would permanently
   skip that tier.~~ → Fixed: `FIRED` is written **only after a successful
   emit**.
2. ~~`FIRED` not clamped to 0..3; a corrupt value of 4+ bricked the guard
   (`TIER>FIRED` never true; rewarn requires `FIRED==3`).~~ → Fixed: clamp
   `FIRED` to 3 on read (suite test 13 covers it).

## 8. Risks accepted

- Mild (turn 14) may fire in long headless subagent runs — harmless; fix later
  with a session-kind filter if noise appears, not by raising the threshold.
- No `/tmp` state GC (out of scope).
- Hook stays non-blocking (`exit 0` always); never auto-invokes `/compact`.

DELIVERABLE_COMPLETE
