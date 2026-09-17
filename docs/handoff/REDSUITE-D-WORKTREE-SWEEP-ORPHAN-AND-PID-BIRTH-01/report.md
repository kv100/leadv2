# REDSUITE-D-WORKTREE-SWEEP-ORPHAN-AND-PID-BIRTH-01 — lane report

Row `f43a661f5ece`. Suite: `plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh`.
Platform for every count: macOS Darwin 25.6.0, suite run alone at the mission's 400s ceiling.

## 0. State of the branch at lane start (divergence from the mission's main measurement)

The lane branch carried `df03fb4d` ("wip: work interrupted by the founder stop order
2026-09-15") — an un-reviewed prior session that had already touched this suite. Baseline from
this branch, before any edit of mine:

```
$ bash plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh >/tmp/p6-baseline.log 2>&1; echo rc=$?
rc=1 wall=31s
[TEST] RED-then-GREEN: P6-orphan-swept-and-journaled(hook) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: P6-orphan-swept-and-journaled(dead) (pre_rc=1 -> post_rc=0)
[TEST] FAIL: P14-pid-birth-lib-absent-degrades
Results: ... (P14 the only failure)
```

So on this branch P6 was already fixed by the WIP commit (see §2) and only P14 was red. The
lead's main measurement (P6 hook+dead rc=2, P14 red) could not be reproduced as-is; §2 explains
what the rc=2 actually was, and the negative control in §2 reproduces it byte-for-byte.

## 1. P14-pid-birth-lib-absent-degrades

**Reproduction.** Command above; observed `FAIL: P14-pid-birth-lib-absent-degrades` (rc=1 suite,
wall=31s).

**Cause class** (suite-level): `never_reaches_subject`.

**Mechanism.** The case builds a "drift" copy of the gate (`tests/test-worktree-lane-safety.sh:148-158`):
`lib/leadv2-worktree-protected.sh` + `leadv2-state-path.sh` into a temp dir whose `lib/`
deliberately lacks `leadv2_pid_birth.py` (the R4 import contract — the drifted gate must degrade
to the inline birth rule, `lib/leadv2-worktree-protected.sh:79-83` and `:115-126`, never exit 3).
`leadv2-state-path.sh:119` unconditionally sources its own sibling `leadv2-portable-lock.sh`;
the drift dir did not contain it, so every probe died at
`lv2_wt_protect_prime` → `LV2_WT_PROTECT_ERR=state-path-resolver-failed`
(`lib/leadv2-worktree-protected.sh:198-199`), and the case's first assertion
(`[[ -z "$LV2_WT_PROTECT_ERR" ]]`, `tests/test-worktree-lane-safety.sh:160`) failed. The case
never reached the R4 contract it exists to pin.

Measured directly (bash, isolating the case's own construction):

```
== A: drift WITHOUT portable-lock (committed WIP state) ==
A: prime rc=0 err=[state-path-resolver-failed]
== B: drift WITH portable-lock copied ==
B: prime rc=0 err=[] alive_lane_rc=0   (matching birth -> alive)
B2: err=[] alive_lane_rc=1             (2020 birth -> pid-reuse -> not alive)
```

**Guard vs fixture verdict.** The guard is right: failing closed on a missing lock-lib sibling
is the documented direction (`lib/leadv2-worktree-protected.sh:43-45` — "On a broken control
plane nothing is ever removed"). The fixture was wrong. The degrade assertion is also right —
variant B proves the inline fallback (`lib/leadv2-worktree-protected.sh:119-126`) works both
ways with `lib/leadv2_pid_birth.py` genuinely absent.

**Provenance of the defect.** `df03fb4d` had replaced the fixture's
`cp .../leadv2-portable-lock.sh "$drift/"` with `: # MUTATION-CONTROL-P14 (portable-lock copy
removed)` — i.e. the interrupted session committed the *negative-control mutation* itself and
never recorded the control (commit message admits "no controls recorded"). The comment block
right above that line (suite lines 152-155) already states the fix; only the mutation was
committed.

**Fix** (mine, `0b2cafcd`): restore the `cp` line; `lib/leadv2_pid_birth.py` stays absent.
Subject files needed **no change**: `leadv2-worktree-cleanup.sh` untouched;
`lib/leadv2-worktree-protected.sh` and `lib/leadv2_pid_birth.py` untouched (and outside this
lane's write set — but the write-set escape hatch was never needed, because neither was the
owner of the defect).

**Negative control 1** (mutation inside the fixture code I changed; artifact
`mutation-control/20260917T010136Z-77605.txt` via `leadv2-mutation-control.sh`, worker mode):

```
anchor=   s|cp "${SCRIPT_DIR}/../leadv2-portable-lock.sh" "$drift/"|: # mutation-control: portable-lock copy removed|
baseline_rc=0
mutated_rc=1
```

(the tool's `red_line` field is cosmetic noise — its `grep -iE 'fail|assert|error' | head -1`
matched the word "failed-removal" inside a P9 pass line; the redness proof is
`mutated_rc=1` vs `baseline_rc=0`, and the identical code state's actual failure output is the
P14 FAIL line quoted in §0.)

## 2. P6-orphan-swept-and-journaled (hook + dead) — already green on this branch; the fix is signed off here with the control the interrupted session never ran

**What the WIP fix is.** The case grepped the journal at the hardcoded pre-2026-09-06 path
`$repo/docs/leadv2/tasks/lane/journal.md`. That layout was superseded by
**LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01 (2026-09-06)**, recorded at
`plugins/leadv2/scripts/leadv2-journal.sh:8-20`: journal paths resolve through
`leadv2-state-path.sh`'s canonical control-plane root (`leadv2-journal.sh path <id>` is the one
resolver). The WIP commit added `_journal_path()` (suite lines 192-194, decision quoted in its
comment) and pointed P6's grep at the resolved path. Per lane-rules this is the legitimate
test-change case: the test encoded a superseded requirement, the decision is quoted with
file:line, and the same case still guards the NEW behaviour (the `worktree_swept id=lane
reason=` entry must exist at the resolved path).

**Cause class**: `never_reaches_subject` — the sweep ran and journaled correctly all along;
the fixture's assertion looked at a dead path.

**The lead's rc=2 explained.** The mission guessed "the sweeper refused (rc=2 is a refusal)".
Wrong layer: with the stale path, `grep -q 'worktree_swept …' <nonexistent>` exits **2**
(open error), and that grep is the case's last command — the case returns 2. The refusal was
grep's, not the sweeper's.

**Negative control 2** (mutation inside the function the fix changed — `_journal_path` reverted
to the stale layout; artifact `mutation-control/` via `leadv2-mutation-control.sh` + one manual
mutated-suite run to capture both variants):

```
leadv2-mutation-control: MUTATION-CONTROL ok ... red_line=[TEST] FAIL: P6-orphan-swept-and-journaled(hook) -- post-fix rc=2, expected 0
baseline_rc=0  mutated_rc=1
```

Manual mutant run (same sed, untracked suite copy, deleted afterwards; `git status` verified
clean apart from pulse state):

```
mutant_suite_rc=1
[TEST] FAIL: P6-orphan-swept-and-journaled(hook) -- post-fix rc=2, expected 0
[TEST] FAIL: P6-orphan-swept-and-journaled(dead) -- post-fix rc=2, expected 0
Results: 9 passed(red->green), 2 failed, 13 green-pre-fix
```

**Single shared cause, proven not assumed**: one mutation of the shared `_journal_path` moved
BOTH P6 variants (identical rc=2 signature), matching the lead's main measurement byte-for-byte.
Two independent causes would have needed two mutations; it took one.

## 3. Final suite run (the acceptance command)

```
$ bash plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
rc=0 wall=37s
Results: 11 passed(red->green), 0 failed, 13 green-pre-fix
```

11 of 24 verdict-lines red→green, 0 failed, 13 green-pre-fix, macOS Darwin 25.6.0, at
`0b2cafcd` + report commit, 400s ceiling (used 37s).

P12-min-age-s-precedence remains `GREEN-PRE-FIX` and is NOT claimed as evidence of any fix —
it is a safety invariant that was already green (suite runner labels it explicitly, and the
runner counts it separately).

Changed-scope runner (falsification set): `bash tests/run-all.sh --scope changed` → rc=0,
wall=416s, `selected=2 total=93 … changed=1 unmapped=0` (suite is registered — self-select
header, suite line 2), core-offline verdict `passed=1 failed=0 known_red_skipped=1`.
`bash -n` on the changed file: ok. No Python changed (py_compile n/a).

Concurrency check: five other build-phase sessions were live during these runs; the suite
sandboxes all control-plane state via `LEADV2_STATE_ROOT` + a private `mktemp` `WORK` dir, and
results were stable across six runs (baseline, post-fix, mutant, two controls, run-all) — no
`harness_self_interference` observed.

## 4. Still red

Nothing. The suite is 0-failed at `0b2cafcd`. No assertion was deleted, loosened, or
`|| true`d; the only two suite edits on this lane are (a) the WIP session's journal-path
resolution (superseded-requirement case, decision quoted) and (b) restoring the `cp` line its
interrupted control had removed.

## 5. Write set

Declared: `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh` + the suite. Actual diff: the
suite only. The subject sweeper needed no change; P14's owner turned out to be neither the
pid-birth library (`lib/leadv2_pid_birth.py`, correct and genuinely absent in the drift) nor the
protected lib (degrade path correct), but the fixture's drift-dir inventory — inside the
declared set.

Commits on this lane: `df03fb4d` (prior WIP, P6 fixture fix, signed off in §2 with its
control), `0b2cafcd` (P14 fixture fix + control 1), plus this report/artifacts commit.
