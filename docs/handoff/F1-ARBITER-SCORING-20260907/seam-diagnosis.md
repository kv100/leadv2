# Seam diagnosis: the 0/39 vs 15/79 "judge usage" disagreement

**Conclusion: no seam bug in the instrumentation. The "15/79" fresh count was contaminated by
synthetic-fixture journals (paths under `.ephemeral/` or `dispatch-deadbeef*`) that a correct
path-based exclusion filters out. Once excluded, `complexity_basis=judge` occurs on 0 real live
lines, same as the original census's `estimate_source=judge` = 0/39. The judge is still fully
dead on the live complexity-estimate path today. This is "no bug, different corpora" (case: a
content-based exclusion, not a path-based one, silently let synthetic rows through) — not a
seam between `estimate_source` and `complexity_basis`.**

## 1. Do `estimate_source` and `complexity_basis` ever disagree on one real line?

`leadv2-task-judge.sh` sets both fields together, in the same branch, every time:

- Judge branch (real model call succeeded): `estimate_source='judge'` (:345) and
  `complexity_basis='judge'` (:352) are set on consecutive lines inside the same code path —
  there is no way to set one without the other here.
- Fallback branch (:229-230): `estimate_source='fallback'` and `complexity_basis=basis` (the
  class-hint/line-count branch that ran) are set in the same dict literal.
- The journal line itself (:386) prints both tokens from the SAME parsed `estimate_json`
  (`src=` at :361, `complexity_basis=` at :379) — one `python3 -c` parse of one JSON blob, so
  a discrepancy on one real line would require the judge to have written self-contradictory
  JSON, which the branches above show it cannot do.
- `complexity_basis` is intentionally left OPTIONAL, not REQUIRED, in `_validate_estimate`
  (:244-250, comment at :246-249): a cached `estimate.json` written *before* Step 2 shipped has
  `estimate_source` (always required) but no `complexity_basis` key, so `complexity_basis=none`
  can appear next to `estimate_source=judge` on an old cache hit. The reverse — `complexity_
  basis=judge` next to `estimate_source=fallback` — has no code path; nothing ever writes
  `complexity_basis` without also writing `estimate_source` in the same dict.

**Answer to mission item 1: no, these two fields cannot disagree on a real line produced by the
current code.** The only asymmetry is one-directional staleness (`complexity_basis` absent on
old cache hits), never a contradiction.

## 2. Is `complexity_source=judge` reachable from a real `estimate_source=judge`?

`leadv2-dispatch-code.sh:7637-7660` (the derivation block) reads `DC_ESTIMATE_SOURCE` and
`DC_COMPLEXITY_BASIS` (both populated at :7614-7616 from `_dispatch_complexity_estimate`'s
tab-separated output) and computes `DC_COMPLEXITY_SOURCE` via a small python block:

```python
elif est_src == 'judge':
    src = 'judge'
```

This branch is checked *after* the `raised and flaglike` branch (declared-class floor takes
priority, exactly as §5 describes: `task_class` is a floor that can only raise the level, never
a difficulty vote of its own) and *before* the fallback/heuristic branches. So: whenever the
judge really ran and `estimate_source=judge` came back, `complexity_source=judge` is reached
unless the declared-class floor also fired and raised the level (in which case `source=flag`
correctly wins, per §5.1's own precedence — that is not a bug, it is the floor doing its job).

**Answer to mission item 2: yes, reachable, and no seam found here either.** The two live
lines produced on this lane after Step 2 landed (see §4) confirm it in practice:
`complexity_source=flag conf=0.7` (declared-class floor fired) and no live line yet shows
`complexity_source=judge` simply because no real judge call has succeeded on this lane's own
traffic (see §3) — not because the derivation can't reach it.

## 3. Where did "15 of 79 `complexity_basis=judge`" actually come from?

Reproduced directly against the live corpus at `~/.claude/leadv2-state`:

```
$ find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
    | xargs grep -h 'route_v2_estimate' > /tmp/live_rv2.txt
$ wc -l /tmp/live_rv2.txt
112 /tmp/live_rv2.txt
$ grep -oE 'complexity_basis=[a-z]+' /tmp/live_rv2.txt | sort | uniq -c
  28 complexity_basis=class
  29 complexity_basis=line
$ grep -c 'complexity_basis=judge' /tmp/live_rv2.txt
0
```

**checked=112: zero real `route_v2_estimate` lines carry `complexity_basis=judge` once file
paths (not line text) are filtered for `ephemeral|deadbeef`.** This matches the original
census's `estimate_source=judge`=0/39 exactly in direction (100% heuristic/flag path, 0% judge).

So where do `complexity_basis=judge` lines exist at all? All of them:

```
$ grep -rl 'complexity_basis=judge' ~/.claude/leadv2-state --include=journal.md
.../persona-engine/tasks/dispatch-deadbeef6/journal.md
.../persona-engine/tasks/dispatch-deadbeefa5/journal.md
.../persona-engine/tasks/dispatch-deadbeefa4/journal.md
.../persona-engine/tasks/dispatch-deadbeef4/journal.md
.../persona-engine/tasks/dispatch-deadbeef5/journal.md
.../.ephemeral/myrepo/tasks/dispatch-b7504d3f/journal.md
.../.ephemeral/repo/tasks/7032d143/journal.md
... (18 files total)
$ grep -rl 'complexity_basis=judge' ~/.claude/leadv2-state --include=journal.md | grep -cE 'ephemeral|deadbeef'
18
$ grep -rl 'complexity_basis=judge' ~/.claude/leadv2-state --include=journal.md | grep -vcE 'ephemeral|deadbeef'
0
```

**checked=18/18: every single file that ever carries `complexity_basis=judge` is a synthetic
fixture** (path under `.ephemeral/` or a `dispatch-deadbeef*` id — exactly the two markers
`docs/handoff/F1-HARD-WORK-20260907/corpus-split.md` case 6 names as the synthetic-fixture
signature). Zero real task directories carry it.

**The mechanism that produced "15 of 79": a `grep -h`/`grep -rhE` pipeline strips filenames
from its output (`-h`) before the `grep -vE 'ephemeral|deadbeef'` exclusion runs.** Since the
markers `ephemeral` and `deadbeef` live in the **directory path**, not in the **line text**,
that second grep has nothing to match against and passes every line through unfiltered —
including the ~15-30 synthetic `complexity_basis=judge` lines the fixture set carries by
design (it exists specifically to give the parser a positive control for the token, per §1's
own methodology note: "unfiltered corpus ... yields 59 `estimate_source=judge` lines with the
same regex → the zero is not a parser artefact" — i.e. the design doc's own M3 row already
warns that the *unfiltered* count is large and judge-heavy, which is exactly the number a
`-h`-stripped exclusion reproduces). I reproduced this failure mode directly:

```
$ grep -rhE 'route_v2_estimate.*complexity_basis=judge' ~/.claude/leadv2-state 2>/dev/null \
    | grep -vE 'ephemeral|deadbeef' | wc -l
      30
```

(30, not exactly 15 — the corpus has grown since the mission's snapshot was taken minutes
earlier in the same session; the mechanism, not the exact count, is what matters and it
reproduces the same failure mode.) Re-running the same exclusion with filenames preserved
(`grep -rE`, no `-h`) drops this to 0 real matches (the only 2 hits that survive are the
mission's own prompt text quoting this regex, filed under
`~/.claude/leadv2-state/leadv2/glm-deferred.d/94b88e76.md` — not a task journal at all).

## 4. Does this affect `source_confidence` grading today?

**No — because there is no live judge signal to mis-grade.** `complexity_source` on this
lane's own two post-Step-2 real `route_resolved` lines reads `flag` (`conf=0.7`), not `judge`
downgraded to something lower:

```
complexity_source=flag conf=0.7 req_eff=4.0 fit_mode=off fit_pick=glm fit_differs=0 ...
complexity_source=flag conf=0.7 req_eff=2.3 fit_mode=off fit_pick=sonnet fit_differs=0 ...
```

Both are declared-class floor cases (`Heavy`/explicit class), not a judge run being silently
relabeled. Since §1/§3 above establish that **zero real lines anywhere in the live corpus
carry a real judge-originated `complexity_basis=judge`**, there is no real judge decision
anywhere in today's traffic that *could* be downgraded to `heuristic`/`unknown` — the risk R4
the design doc already names ("the judge is dead on the live path (0/39) ... expected and
documented") is confirmed unchanged, not worsened, by this diagnosis. The confidence tiers
(judge=0.9, heuristic=0.4) are ungraded on live traffic today simply because the judge branch
practically never executes — that is the same finding as the original census, not a new,
larger risk.

## Summary (checked=N discipline)

| Claim | checked=N | Result |
|---|---|---|
| `estimate_source`/`complexity_basis` can disagree on a real line | code-path review, task-judge.sh:220-352 | No — always set together |
| `complexity_source=judge` reachable from `estimate_source=judge` | code-path review, dispatch-code.sh:7637-7660 | Yes, reachable (subject to the flag-floor precedence, itself correct) |
| Real (path-excluded) `complexity_basis=judge` lines in live corpus | 112 real `route_v2_estimate` lines scanned | 0 |
| Files ever carrying `complexity_basis=judge` that are synthetic fixtures | 18 files found, 18 synthetic | 18/18 (100%) |
| `-h`-stripped exclusion reproduces the false-positive judge count | 1 reproduction run | 30 (contamination confirmed; exact figure differs from "15" only because corpus grew between the mission snapshot and this check) |

**No seam bug. No Step 3 blocker.** The judge remains 0% live on the estimate path exactly as
the original design-doc census found; the "15/79" figure was a measurement artifact of
excluding synthetic fixtures by line content instead of by file path.
