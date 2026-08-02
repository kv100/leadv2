# Context-tier guard (M-7)

`hooks/leadv2-compact-warn.sh` is a **tiered, edge-triggered** context-budget
guard. It replaces the old single "warn at 80 turns" threshold with three
proportional tiers, each fired once per session, never blocking.

This document records the **measurement** the thresholds are derived from, the
**arithmetic**, and the **fraction rule**. A reader can recompute every
threshold from what is on this page.

> Re-derive any time: `scripts/leadv2-turn-cost-measure.py` re-runs the
> measurement over the current transcript tree and prints `b`, `m`, `C`, and
> the three `T(x)` computations. Paste its output here when you do.

---

## 1. The defect this fixes

The old hook had one threshold (80 turns) and therefore one action: shout
"run /compact". One threshold cannot trim cheaply early, and cannot force the
expensive action late. Worse — measurement shows the session is already at or
past the context ceiling by turn 80, so the warning arrived **after** the
window in which trimming was cheap.

---

## 2. Measurement

Source: `~/.claude/projects/**/*.jsonl` — every `type=="assistant"` record
carries `message.usage`; context size at that point =
`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`. A
**founder turn** = a `type=="user"` record whose `message.content` is **not** a
`tool_result` list (genuine input, not a tool return). Turn N's context = the
**first** assistant request after founder turn N (the request whose context
reflects having loaded turn N's state).

**Filter:** interactive sessions only (`max_turn >= 10`). Headless 1-turn
subagent runs dominate the tree by count (median max-turn = 1) and would
otherwise yield `n≈2` per bucket and a garbage median. With the filter there
are enough long sessions (max observed 1084 founder turns) to fit growth.

**The slope is fit per-session, not on aggregate medians.** An aggregate fit
over the full turn range is dominated at its tail by sessions that have
**already compacted** (the old 80-turn guard fired, `/compact` ran, context
reset to ~baseline). Their per-turn context is low and non-monotonic, so a
full-range aggregate fit yields a **negative** slope (verified: `m = -120` over
turns 1..127) — it describes post-compact sessions, not growth. The defensible
unit of growth is the **per-session slope over its own early pre-compact linear
region** (turns 1..12, where cache + added context climb near-linearly and no
compaction has yet occurred). Taking the median across sessions is robust to
the few giant multi-compact outliers.

### Latest run (`scripts/leadv2-turn-cost-measure.py`)

```
transcripts scanned         : whole ~/.claude/projects tree (8143 .jsonl)
interactive sessions kept   : 204  (max_turn >= 10)
sessions reaching turn 30   : 52

b = median context at turn 1 : 100,995
m = median per-session slope : 9,881 tok/turn  (n=196 sessions, turns 1..12;
                                               p25=8,112, p75=12,866)
C = p95 of per-session peak  : 527,155  (p99=715,869, max=933,514)
```

Per-turn medians (interactive sample), confirming the shape — steep early
(~11K/turn for turns 1..12), plateauing near ~297K by turn 30 where active
self-trimming flattens it:

```
turn   n   median      p75
   1 184   101,199   104,586
  10 151   203,440   242,198
  20  63   268,155   310,746
  30  40   297,447   341,938
  40  31   297,354   368,832
```

---

## 3. The fraction rule (authored, not picked)

The one authored choice is the fraction of `C` at which each tier fires. The
fractions are a **rule**, not numbers (`feedback-derive-alert-thresholds-from-config`):

| fraction | meaning |
|---|---|
| **0.45** | still over half the window free — trimming is cheap and non-disruptive |
| **0.65** | under a third free — cheap trimming no longer closes the gap |
| **0.80** | one large tool result from the wall |

`C` is the **empirical** working ceiling — p95 of per-session peak context —
not the hard model limit. 5% of interactive sessions exceed it; the tiers warn
before a typical session gets there.

---

## 4. The arithmetic

```
T(x) = ceil( (x*C - b) / m )

mild      x=0.45  target = 0.45 * 527,155 = 237,219
                 T = ceil( (237,219 - 100,995) / 9,881 ) = ceil(13.77) = 14

aggressive x=0.65 target = 0.65 * 527,155 = 342,650
                 T = ceil( (342,650 - 100,995) / 9,881 ) = ceil(24.46) = 25

emergency  x=0.80 target = 0.80 * 527,155 = 421,724
                 T = ceil( (421,724 - 100,995) / 9,881 ) = ceil(33.27) = 33
```

**Derived thresholds → `LEADV2_COMPACT_TIER_MILD=14`, `_AGGRESSIVE=25`,
`_EMERGENCY=33`.** These are the defaults baked into the hook. The old single
threshold of **80 sat ~47 turns past the emergency crossing (turn 33)** — the
guard arrived long after the useful trimming window.

---

## 5. Tier semantics

Each tier fires exactly once per session (edge-triggered on
`tier(count) > highest-fired`); tiers never regress. A session that jumps past
a boundary still fires the highest tier once.

| Tier | Marker | Instruction | Compacts? |
|---|---|---|---|
| mild | `[CONTEXT_TIER:MILD]` | Trim verbose surfaces: bound every `Read` with `limit=`, stop re-reading files already in context, pipe `head`/`tail`/`grep` at the source, no raw log paste. | no |
| aggressive | `[CONTEXT_TIER:AGGRESSIVE]` | Summarize and close finished threads: append journal lines for closed lanes, prune resolved rows from `docs/leadv2/open-threads.md`, collapse completed lane detail to one line each. | no |
| emergency | `[CONTEXT_TIER:EMERGENCY]` | Run `/compact` now (the pre-compact checkpoint hook freezes state first). Re-warns every `LEADV2_COMPACT_REWARN` turns until it happens. | yes |

The three bodies are disjoint with distinct markers; **mild and aggressive never
mention `/compact`** — acceptance #3 is satisfied structurally.

---

## 6. Env contract (backward compatible)

| Var | Default | Behaviour |
|---|---|---|
| `LEADV2_COMPACT_WARN` | `1` | `0` ⇒ hook exits 0 immediately, nothing fires. Unchanged. |
| `LEADV2_COMPACT_TIER_MILD` | `14` (derived) | override mild threshold |
| `LEADV2_COMPACT_TIER_AGGRESSIVE` | `25` (derived) | override aggressive |
| `LEADV2_COMPACT_TIER_EMERGENCY` | `33` (derived) | override emergency |
| `LEADV2_COMPACT_THRESHOLD` | unset | **legacy pin**: if set & positive, overrides `_EMERGENCY` (an operator who pinned 80 keeps a compact demand at 80). Lower tiers stay measured. |
| `LEADV2_COMPACT_REWARN` | `40` | emergency re-warn interval. Unchanged semantics. |

Overrides are validated as positive integers and must satisfy
`mild < aggressive < emergency`; a nonsensical set degrades to the derived
defaults rather than firing silently wrong.

### Supersession of the 80/+40 behaviour

The old single warning ("at 80 turns, ask for a compact, re-warn every +40") is
**subsumed**: the emergency tier is "at the measured 0.80·C crossing, ask for a
compact, re-warn every 40". Same action, same re-warn cadence, threshold now
**measured** instead of picked. Reason, in one line: *80 was ~47 turns past the
point where the context was already at 80% of ceiling; the guard arrived after
the useful window.* An operator who wants the exact old number back sets
`LEADV2_COMPACT_THRESHOLD=80`.

### State files (format unchanged for back-compat)

```
/tmp/leadv2-turn-count-${SESSION_ID}     bare int: current turn count
/tmp/leadv2-tier-fired-${SESSION_ID}     highest tier already fired: 0|1|2|3 (new)
```

The count file is byte-identical in format to the old hook, so an older copy of
this hook running concurrently in another repo still reads it. The tier-fired
file is new and ignored by old copies.

---

## 7. Risks accepted

- **Sampling trap** — handled by the `max_turn >= 10` filter and per-session
  slope median (§2).
- **Mild fires in headless subagent sessions** (turn 14 is reachable by a long
  agent run) — acceptable; the mild instruction is harmless there. If noise
  shows up the fix is a session-kind filter, not a higher threshold.
- **bash 3.2** (macOS) — integer `if/elif` only; no associative arrays, no
  `${x,,}`. No lock needed (one `UserPromptSubmit` per session at a time;
  distinct `SESSION_ID` ⇒ distinct files).

---

## 8. Proof (re-runnable)

1. **Measurement** — §2 and §4 show `b`, `m`, `C`, sample sizes, and the three
   `T(x)` computations with arithmetic visible.
2. **Each tier fires** — driven directly with a seeded count file and synthetic
   `{"session_id": ...}` on stdin, the hook emits:

   ```
   [CONTEXT_TIER:MILD] Context is filling. Trim verbose surfaces …  (turn 14)
   [CONTEXT_TIER:AGGRESSIVE] Context is over half full …            (turn 25)
   [CONTEXT_TIER:EMERGENCY] Context is at ~80% of the working …     (turn 33)
   ```

   (Run `bash tests/test-compact-warn-tiers.sh` for the automated proof —
   14 assertions including distinguishability, disable, jump-past, re-warn,
   legacy pin, degrade, and the bare-integer count-file format.)
3. **`LEADV2_COMPACT_WARN=0`** + a turn count past emergency ⇒ empty stdout, exit 0.
4. **No regression** — `bash tests/test-compact-hooks.sh` is 6 passed / 3 failed
   both **before and after** this change. The 3 failures are pre-existing in
   the **post-compact** checkpoint hook tests (unrelated to compact-warn); they
   were not caused by M-7 and are out of scope (flagged for lead decision — do
   not silently fix; that is another lane's work).
