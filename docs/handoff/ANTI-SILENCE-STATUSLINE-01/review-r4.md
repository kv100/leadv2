status: fail
reviewer_says: do_not_merge

# ANTI-SILENCE-STATUSLINE-01 — adversarial review r4

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01` @ `235cf05` (8 commits).
Round 4 is one commit (`235cf05`, 5 files, +110/-11) on top of the r3 head `e49441c`.

Method: `git archive 235cf05` extracted to a scratch tree; every mutation applied **inside the
production function body** of the scratch copy, suite re-run, result recorded. The lane's own
`plugins/` and `tests/` were never written. Every suite run below is `/bin/bash` 3.2.57.

## Verdict in one line

**MUT-R still survives a full revert, and the five new "controls" are not merely decorative —
they PASS when the production fix they name is removed.** Per the round-4 brief ("if MUT-R
survives, the verdict is fail regardless of everything else"), this is `fail`.

## Baselines (mine, not taken on trust)

```
scratch @235cf05  test-statusline-readable.sh   pass=41 fail=0 skip=1   [14.8s]
lane    @235cf05  test-statusline-readable.sh   pass=43 fail=0 skip=0
scratch @235cf05  test-status-surface.sh        69 passed, 22 failed    [exit 1]
```

(The scratch/lane delta is the R1/R2 git-archive block plus one `.10s.sh` wrapper symlink that
`git archive` does not materialise. The material fact is unchanged: **`test-status-surface.sh` is
RED at baseline**, so nothing living in it can gate a merge.)

---

# Per-item verdict

## 1. MUT-R (revert the rank fix) — **NOT FIXED — Critical**

No MUT-R control exists anywhere in the diff:

```
$ grep -n "MUT-R\|MUT_R\|rank=" plugins/leadv2/scripts/tests/*.sh
(no output)
```

Mutation applied to the production file `plugins/leadv2/scripts/leadv2-status-surface.sh:1681,1686`
(`rank=(cls=="dead")?0:(cls=="live")?2:(cls=="done")?3:1` → `rank=(cls=="live")?1:0`) and
`:1683,1688` (`sort … -k1,1n -k2,2` → `sort … -k1,1n`) — a full revert of the round's Critical fix:

```
$ bash plugins/leadv2/scripts/tests/test-status-surface.sh   # MUT-R applied
[TEST] === 69 passed, 22 failed ===          <-- byte-identical to baseline
[TEST] PASS: F4: width-26 oneline shows dead lane before done lane (lanes 2: oc3de…·dead·5m +1)
$ diff <(grep -o 'FAIL: .*' base-surface.log|sort) <(grep -o 'FAIL: .*' mutR-surface.log|sort)
(no output)
```

**SURVIVED.** The F4 control at `plugins/leadv2/scripts/tests/test-status-surface.sh:1687-1694`
is byte-identical to round 3 and still passes for the reason r3 named: its fixture (`oc3deadeeee`
vs `oc3doneeeeeee`) is name-lucky, so `sort`'s last-resort whole-line comparison puts `dead` first
even with the rank collapsed.

`test-statusline-readable.sh` did go `pass=40 fail=1` under MUT-R — but the failing assertion is
`MUT-V`, not anything about rank:

```
[FAIL] MUT-V -- off-by-one tail count still reconciled unexpectedly: lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo
```

That is collateral flake from an unrelated self-mutating control (see C2/H2), not protection. It
does not survive a rename of a fixture lane, and it names the wrong defect to whoever reads the CI
log.

The worker's own artifact concedes this. `round4-red/mutation-controls.log`:

```
MUT-R RED: independently reproduced in the status-surface scratch renderer:
  green: lanes 2: oc3de…·dead·5m +1
  red:   lanes 2: oc3do…·done·5m +1
```

That is a hand-run render comparison, not a suite going RED. The brief asked for the suite.

## 2. MUT-B / MUT-Z / MUT-V / MUT-U / MUT-W — **NOT FIXED — Critical**

Each applied to the **production** file, then `test-statusline-readable.sh` run:

| Mutation | Production line mutated | Suite result | Its own control said |
|---|---|---|---|
| MUT-B | `leadv2-status-surface.sh:1711` `marker_len=${#marker}`→`0` | readable `pass=41 fail=0` **SURVIVED**; surface `68/23` RED **only via a source grep** | — |
| MUT-Z | `leadv2-lane-status-line-tail.sh:1128` delete the `+N` reservation | `pass=41 fail=0 skip=1` **SURVIVED** | `[PASS] MUT-Z RED: …` |
| MUT-V | `…-tail.sh:1132` `_lane_dropped = total - shown - 1` | `pass=40 fail=1` (red via **MUT-Z's** control) | `[PASS] MUT-V RED: …` |
| MUT-U | `…-tail.sh:1141` delete the ANSI strip before the base clip | `pass=41 fail=0 skip=1` **SURVIVED** | `[PASS] MUT-U RED: …` |
| MUT-W | `…-tail.sh:919` `full_label_cap = max(...)` → `LABEL_CAP` | `pass=41 fail=0 skip=1` **SURVIVED** | `[PASS] MUT-W RED: …` |

Four of five survive green. The fifth (MUT-V) dies to the wrong assertion.

**The structural defect is worse than round 3's.** The new controls at
`plugins/leadv2/scripts/tests/test-statusline-readable.sh:551-599` do not assert on the
production renderer at all. Each copies the scripts to a scratch dir, `sed`s its own mutation in,
and asserts the mutated copy differs / renders badly. When the production fix is **absent**, the
`sed`/`python` patch no longer matches, the "mutated" copy is just the already-broken production,
its output is already bad — and the control reports PASS. Measured, with production carrying the
real mutation:

```
# production has MUT-W (fixed label cap)
[PASS] MUT-W RED: fixed label cap truncates wide rendered identity

# production has MUT-V (off-by-one)
[PASS] MUT-V RED: tail dropped count no longer reconciles (lanes 4/5 +3 | …)
```

These controls are self-satisfying: green when the fix is present *and* green when it is gone.
That is strictly worse than the r3 `grep`, because it reads as behavioural.

MUT-U adds a swallowed tripwire on top. `test-statusline-readable.sh:581-591` embeds
`assert old in s, 'MUT-U target missing'`. With the strip line deleted from production the assert
fires — and the suite ignores it (`set -uo pipefail`, no `-e`) and passes anyway:

```
Traceback (most recent call last):
AssertionError: MUT-U target missing
[PASS] MUT-U RED: raw ANSI survives a clipped base
```

MUT-U is a *behaviourally real* mutation, which makes the survival worse. With a colour-bearing
base, deleting the strip under-fills the line by 5-9 columns and the suite does not notice:

```
base   W=20  vis=20  | lanes 4/5 +4 | Sonne
MUT-U  W=20  vis=15  | lanes 4/5 +4 |
base   W=34  vis=34  | lanes 4/5 +4 | Sonnet 5 in /tmp/co
MUT-U  W=34  vis=25  | lanes 4/5 +4 | Sonnet 5 i
```

## 3. The three round-4 behaviour bugs — **FIXED (behaviour); controls UNPROVEN**

Composer probed directly (`leadv2-lane-status-line.sh`, memo `lanes 5: mylane·dead·9m …`):

```
=== user statusLine command configured ===
W=20  vis=20  | lanes 5: …·dead·9m O
W=21  vis=21  | lanes 5: …·dead·9m +4
W=26  vis=26  | lanes 5: mylane·dead·9m +4
=== no user command (builtin base) ===
W=200 vis=101 ansi=yes | lanes 5: mylane·dead·9m aaa·live·1m … Sonnet 5 in /tmp/composer-cwd
W=120 vis=101 ansi=yes | …
W=80  vis=80  ansi=no  | …
W=20  vis=20  ansi=no  | lanes 5: …·dead·9m S
```

- **dead lane at COLUMNS=20** — FIXED. `…·dead·9m` is present at W=20 on both branches
  (`marker_fits=0` retry, `leadv2-status-surface.sh:1729-1741`).
- **`·dead·9` unit truncation** — FIXED. `9m` survives at every width; the shrink loop only ever
  shortens the label (`leadv2-lane-status-line.sh:240-247`).
- **ANSI stripped at every width** — FIXED. Re-probed with a colour-emitting `statusLine.command`:
  `W=200 ansi=yes`, `W=120 ansi=yes`, `W=80 ansi=no` (only when the clip path is entered).

No dedicated behavioural control was found for any of the three. The nearest assertion is the
`F2/F5 tail/composer width 20..200` sweep, which is one-sided (`<= W`) — see M1.

## 4. F9 performance — **NOT FIXED**

10 warm renders each, same fixture as r3, `/bin/bash` 3.2.57:

```
tail      99.6 ms/render
composer  89.6 ms/render
bare `bash -c exit` floor on this machine: 5.1 ms
```

Target was "back under ~60 ms". Missed by ~60%. It is an improvement on r3's 139/122 and the
per-character fork **is** gone — both `visible_len()` (`…-tail.sh:172-180`) and
`_surf_visible_len()` (`leadv2-lane-status-line.sh:212-218`) are now pure-bash `[[ =~ ]]` +
`${var/…/}` with no `sed`/`awk`. But each call site still wraps them in `$( … )`, which forks a
subshell per token; that is where the residual cost is.

## 5. F5 / F7 / F8

- **F5 — NOT FIXED.** `plugins/leadv2/scripts/leadv2-lane-status-line.sh:289` is still a raw
  slice with no marker: `_base_out="${_base_out_plain:0:$_base_visible_budget}"`. Measured cuts:
  `O` (W=20), `Opu` (W=30), `Opus 5 ` (W=34, trailing space), `O` (W=40). The ANSI half of F5 was
  fixed (strip-before-slice); the mid-word-with-no-ellipsis half is byte-identical to round 2.
  The lane's own `render-proof.md` ships `lanes 5: …·dead·9m O` as its proof of success — that
  orphan `O` **is** the F5 defect.
- **F7 — FIXED.** `test-statusline-readable.sh:480` is now
  `if (( $(visible_len "$NARROW_LINE") <= 40 ))`. The `40 + ${#DEAD_ONLY_LINE}` slack and the
  ANSI-byte measure are gone.
- **F8 — PARTIAL.** `skip=0` in the lane (origin/main resolves), but the skip branch at
  `test-statusline-readable.sh:198` still fires wherever git history is unavailable — my scratch
  extraction: `[SKIP] R1/R2 pre-fix baseline -- git archive of prior revision unavailable`,
  `pass=41 fail=0 skip=1`. Separately: R1/R2 assert that an *ancient revision* was broken. They
  can never fail because of a regression in the current code, so they are inert as controls
  regardless of whether they skip. Not disputed with evidence in the deliverable.

## 6. `--scope changed` from a dirty tree — **PARTIAL / NOT FIXED as specified**

Lane is 22 files dirty. The runner's own selection block, with only `ROOT` pinned to the lane and
the execution loop replaced by a print (`tests/run-all.sh:17` and `:167`):

```
SELECTED: …/plugins/leadv2/scripts/tests/run-core-offline.sh
SELECTED: …/tests/test-status-surface-bash32.sh
SELECTED: …/tests/test-status-surface-single-lead.sh
SELECTED: …/tests/test-status-surface-fast-names.sh
SELECTED: …/plugins/leadv2/scripts/tests/test-statusline-readable.sh
```

**One of the two statusline suites.** `test-status-surface.sh` — which is where the F4/MUT-R and
MUT-B controls live — is **not selected**, because `leadv2-status-surface.sh` was last committed
at `981ca1b` (HEAD~2) and is not dirty, and the new fallback still only looks at `HEAD~1..HEAD`
(`tests/run-all.sh:133-144`). The dirty-tree half of the fix does work; the committed-range half
is one commit deep.

A real `tests/run-all.sh --scope changed` was also started in the lane. It never reached the
statusline suites within a 900 s budget — the always-on `run-core-offline.sh` runs first and
serialises on `/tmp/leadv2-core-offline.lock`; the run was killed by the timeout with only:

```
[RUN] …/plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held by a concurrent run)
```

The `SELECTED:` list above is therefore the evidence: it is produced by the runner's own
selection code with nothing changed but `ROOT` and the exec loop, so it is exactly the list that
run would have printed.

## 7. Artifacts — **PARTIAL**

- `round4-red/` exists in the lane, but holds a single hand-written 11-line summary
  (`mutation-controls.log`), not the RED suite logs the brief required. No GREEN/RED suite output
  is pasted for any mutation, and the MUT-R row documents a render diff in place of the suite
  result it was asked for.
- `render-proof.md` regenerated (`pass=43 fail=0 skip=0`) and copied to the main checkout — but
  the two copies already differ (main is missing the "Focused renderer suite" and changed-scope
  paragraphs), and `round4-red/` was **not** copied to main at all
  (`ls: …/docs/handoff/ANTI-SILENCE-STATUSLINE-01/round4-red: No such file or directory`).

## 8. `/tmp/leadv2-core-offline` blocker — **environment artifact, not a gap**

Confirmed live contention, not a stale file:

```
$ ps -o pid,etime,command -p 1057
 1057   13:34 bash …/plugins/leadv2/scripts/tests/run-core-offline.sh
$ lsof /private/tmp/leadv2-core-offline.lock | awk 'NR>1{print $1,$2}' | sort -u
bash 1057 / bash 14906 / bash 78138 / bash 99818 / flock 1071 / sleep …
```

The always-on core suite serialises on that lock and concurrent reviewers queue behind it. The
worker's report is accurate and this costs it nothing. Lock left in place.

## macOS bash 3.2 — clean

```
/bin/bash -n  leadv2-lane-status-line.sh        OK
/bin/bash -n  leadv2-lane-status-line-tail.sh   OK
/bin/bash -n  leadv2-status-surface.sh          OK
/bin/bash -n  test-statusline-readable.sh       OK
/bin/bash -n  test-status-surface.sh            OK
/bin/bash -n  tests/run-all.sh                  OK
```

Scan of every added line across `91c9919..235cf05` for `mapfile|readarray|declare -A|local -A|
${v,,}|${v^^}|read -N|[[ -v |&>>|wait -n` → no hits. No unbound-array-under-`set -u` usage added
(`"${SUITES[@]:-}"` at `tests/run-all.sh:69` already carries the `:-` guard). Nothing to flag.

---

# New findings

## Critical

### C1 — `plugins/leadv2/scripts/tests/` (absent) — no MUT-R control exists; the founding fix is unguarded
Category: test coverage. The round's Critical fix (dead-lane rank, `leadv2-status-surface.sh:1681-1688`)
can be fully reverted with **zero** delta in `test-status-surface.sh` (69/22 → 69/22, F4 still PASS
with byte-identical output). Third round in a row.
**Required fix:** a behavioural assertion driven by a **name-adversarial** fixture — the dead lane
must sort last alphabetically (e.g. `AAAdone·done`, `ZZZdead·dead`, `mmlive·live`) so `sort`'s
last-resort whole-line comparison cannot rescue a collapsed rank — asserting the dead lane is the
first token at W=20,22,26,34,60, and asserting order-invariance across at least two input orders.
Then apply the revert and paste the RED.

### C2 — `test-statusline-readable.sh:551-599` — the five new controls PASS when their own fix is reverted
Category: test correctness. Each control `sed`s a mutation into a scratch copy and asserts the
copy renders badly. With the fix already gone from production the `sed` no longer matches, the
"mutated" copy is the broken production, its render is already bad, and the control reports PASS.
Proven: production carrying MUT-W → `[PASS] MUT-W RED: …`; production carrying MUT-V →
`[PASS] MUT-V RED: …`.
**Required fix:** delete the self-mutation harness. Assert on the **production** renderer's output
directly — e.g. for MUT-V, that `visible-rows + N == declared total` across the width sweep; for
MUT-Z, that the rendered line never exceeds `W` **and** never under-fills by more than one column
while rows remain; for MUT-W, that the widest render contains the complete lane label. If a
control must patch a copy, it must first `assert` the target text exists and **fail the suite**
when it does not.

### C3 — `test-statusline-readable.sh:581-591` — MUT-U's own tripwire is swallowed
Category: error handling. `assert old in s, 'MUT-U target missing'` raises, the traceback is
printed into the log, and the suite continues and passes because the file runs under
`set -uo pipefail` with no `-e` and the heredoc's exit status is discarded.
**Required fix:** `python3 … || bad "MUT-U" "mutation target missing in production file"` — a
missing target is the loudest possible signal that the guarded code changed, never a no-op.

## High

### H1 — `test-status-surface.sh:1972-1978` — MUT-B is still a source grep, verbatim
Category: test correctness. `if grep -q 'marker_len=${#marker}' "$RENDER"` decides the verdict.
The runtime sweep at `:1966-1971` computes `MUT_B_RED` and **never references it again**. The
added comment ("deliberately source-level as well as runtime") defends the exact pattern the
round-4 brief banned; the "as well as" is false — there is no runtime half.
**Required fix:** `if [[ -n "$MUT_B_RED" ]]; then pass …; else fail …; fi`, and delete the grep.

### H2 — `test-statusline-readable.sh:556-571` — the MUT-Z control mutates a different line than its name
Category: test correctness. It `sed`s `_lane_dropped=$(( _lane_total - _lane_shown ))`
(`…-tail.sh:1132`, the dropped **count**) — the same line MUT-V targets — while the real MUT-Z is
the `+N` **reservation** at `…-tail.sh:1128`
(`_lane_marker=""; (( _lane_remaining > 0 )) && _lane_marker=" +${_lane_remaining}"`). Deleting
the reservation in production leaves the suite `pass=41 fail=0`.
**Required fix:** target `:1128` and assert on rendered width, not on "the output differs".

### H3 — `leadv2-lane-status-line.sh:289` — F5 unfixed: the base is still raw-sliced mid-word
Category: correctness / UX. `_base_out="${_base_out_plain:0:$_base_visible_budget}"` produces
`O`, `Opu`, `Opus 5 `. A one-character orphan is noise on the founder's only unrelayed status
channel, and `render-proof.md` presents it as the proof of success.
**Required fix:** cut on a word boundary (`${s% *}`) and append `…` when anything was removed;
emit nothing rather than a 1-2 char fragment. Assert it: at W=20/30/34/40 the base segment is
either empty or ends in `…`, and never ends mid-token.

### H4 — `tests/run-all.sh:133-144` — `test-status-surface.sh` is unreachable on the changed path *and* red at baseline
Category: CI. From the dirty lane the selector picks only `test-statusline-readable.sh`. Even if
it were selected, `test-status-surface.sh` is `69 passed, 22 failed` before any mutation, so no
control living there (F4, MUT-B) can ever gate a merge. Both halves must be fixed or every
surface-side control is decorative by construction.
**Required fix:** select `leadv2-status-surface.sh` off the full lane range
(`merge-base(origin/main, HEAD)..HEAD`, not `HEAD~1..HEAD`) **and** land the 22 baseline failures,
or move the statusline controls into the suite CI actually selects.

### H5 — F9 target missed: 99.6 ms tail / 89.6 ms composer against a ~60 ms bar
Category: performance. Better than r3's 139/122 and no per-character fork remains, but every
`$(visible_len …)` / `$(_surf_visible_len …)` call site is still a subshell fork per token, on a
path that runs on every repaint.
**Required fix:** make the helpers assign to a caller-visible variable instead of printing
(`_vl() { …; VL=${#plain}; }`), removing the command substitution at all call sites
(`…-tail.sh:1114,1129,1140`; `leadv2-lane-status-line.sh:236,245,251,255,281,297,310,318`).

## Medium

### M1 — `test-statusline-readable.sh` F2/F5 width sweeps are one-sided
The 9-width sweeps assert `visible <= W` only, so a render that under-fills by 9 columns is
"exact/smaller" and passes. That is why MUT-U survives with `vis=15` at `W=20`.
**Fix:** add a lower bound — when rows or base text remain unrendered, `visible >= W - 1`.

### M2 — `round4-red/mutation-controls.log` is a hand-written summary, not RED logs
The brief required the RED logs under `round4-red/`. What shipped is 11 lines of prose with one
render pair. No suite output, no GREEN/RED pairs, and the MUT-R row documents a render diff in
place of the suite result it was asked for.

### M3 — `round4-red/` was not copied to the main checkout, and `render-proof.md` has already drifted
`docs/handoff/` is gitignored. `render-proof.md` was copied but the main copy is missing two
paragraphs the lane copy has; `round4-red/` is absent from main entirely.

### M4 — R1/R2 are inert as controls even when they do not skip
`test-statusline-readable.sh:163-197` asserts that a **pre-fix revision** was broken. No change to
the current renderer can make them fail. Resolving the skip made them run; it did not make them
protect anything.

### M5 — `tests/run-all.sh:135-137` — the committed-range fallback is one commit deep
`HEAD~1..HEAD` means one more commit in a lane silently drops a suite from the changed scope
again — the same class of failure this round was dispatched to fix, deferred by one commit.
**Fix:** `git merge-base origin/main HEAD`..`HEAD`.

---

# Contradiction scan

- `LEADV2_STATUSLINE_WIDTH` vs `COLUMNS`: consistent. `_surf_budget` is the full width
  (`leadv2-lane-status-line.sh:211`), so exporting it as `LEADV2_STATUSLINE_WIDTH` to the detached
  refresher is not a double subtraction.
- `EXTRA_SUITE_MAP` keys vs real filenames: `leadv2-lane-status-line.sh`,
  `leadv2-lane-status-line-tail.sh`, `leadv2-status-surface.sh` all exist under
  `plugins/leadv2/scripts/`; all three mapped suites exist. No dead rows.
- Paths asserted in the deliverable: `round4-red/` exists in the lane, absent from main (M3);
  `render-proof.md` exists in both and differs (M3).
- `marker_fits` semantics: set to `0` only on the degenerate-width retry and read once at
  `leadv2-status-surface.sh:1747` — no conflicting use.
- No other contradictions found.

---

# What would make round 5 pass

1. A name-adversarial MUT-R control in the suite `--scope changed` actually selects, with the
   revert applied and the RED pasted.
2. The five controls rewritten to assert on the **production** renderer's output; each proven by
   mutating production (not a scratch copy) and pasting the RED.
3. `leadv2-lane-status-line.sh:289` word-boundary + `…`, with a control.
4. `visible_len` without command substitution; re-measured under 60 ms.
5. `merge-base..HEAD` selection, both suites selected from the dirty lane, runner output pasted.
6. `test-status-surface.sh` green, or its controls relocated.
7. `round4-red/` holding the actual RED logs, mirrored to the main checkout.

**BLOCK** — 3 Critical, 5 High.
