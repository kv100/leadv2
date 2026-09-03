# Architect prepass — GATE-FALSE-SILENT-01 fix round 2

Lane worktree: `.claude/worktrees/2d8a2849`, HEAD `fb97555`, working tree clean w.r.t.
`plugins/` (`git diff --stat HEAD -- plugins/leadv2/scripts/` → empty). Tree at selfcheck
time == tree now.

---

## 0. The mission's framing is wrong, and the code says so

The mission asserts two independent defects. Neither reproduces from the tree. Both reds
have **one shared root cause**, and it is not in the product change at all.

### 0.1 Both suites are GREEN in a clean shell

```
$ pwd
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849
$ timeout 300 bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
...
[TEST] 9 passed, 0 failed
$ timeout 300 bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
...
[TEST] 12 passed, 0 failed
```

### 0.2 Both reds reproduce on demand, from ambient environment alone

Red 1 — leak one env var, nothing else:

```
$ export LEADV2_LANE_START_SHA=$(git rev-parse HEAD)   # fb97555… — a sha of THIS repo
$ bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
[TEST] FAIL: Case A: a lane with a commit ahead of base was classified arm_produced_nothing
[TEST] FAIL: Case A: arm_advance decision emitted for a lane that produced a commit
[TEST] 7 passed, 2 failed
```

Red 2 — leak a different one:

```
$ export LEADV2_DISPATCH_LANE_WRITES="plugins/leadv2/scripts/leadv2-dispatch-product-close.sh"
$ bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
[TEST] FAIL: Case 2: expected landed, got -- {"…","terminal":"refused","cause":"unscoped_lane_work",
  "evidence":"lane_root=lane dirty=1 offending=newfile.txt",…}
[TEST] 11 passed, 1 failed
```

That evidence string is **byte-identical** to the one in
`docs/handoff/dispatch-2d8a2849/selfcheck.md` (`lane_root=lane dirty=1 offending=newfile.txt`).
Same for Red 1's journal lines. This is the mechanism, not a lookalike.

### 0.3 Why it fired under selfcheck and not under the core runner

`tests/run-core-offline.sh:101-114` builds an `env -u` denylist that scrubs **every**
`LEADV2_*`, `CLAUDE_*`, `GIT_CONFIG*` name out of the environment before running a suite.
The builder-selfcheck "falsification" step runs each suite **directly**, inside the
dispatch worker's own process environment — which has `LEADV2_LANE_START_SHA` and
`LEADV2_DISPATCH_LANE_WRITES` exported for the real lane. Neither suite scrubs for itself.

So: **both suites are non-hermetic; they pass only under a runner that happens to scrub for
them.** A suite whose greenness depends on which harness invoked it is the defect. It will
re-red the next time anything runs it directly.

### 0.4 Consequence for the mission's instructions

- Mission Red 1's hypothesis ("base resolution fails in the fixture — no `LEADV2_LANE_START_SHA`,
  no cache file, no `origin/main`") is **inverted**. The cache file *is* written
  (`test-silent-arm-commits-ahead.sh:64`) and resolves fine. The failure is that
  `LEADV2_LANE_START_SHA` **is present** and takes precedence (`…product-close.sh:1187`),
  carrying a sha that does not exist as an object in the fixture's throwaway repo →
  `cat-file -e` fails → no `origin` remote → fallback fails → `printf '0'`.
- Mission Red 2's framing ("the fixture writes `newfile.txt` without declaring it, so the
  scope gate refuses — correctly") is **conditionally** true. With no declared write-set
  (`WRITES_CSV` empty, `…product-close.sh:31`) the scope gate does not fire at all and
  Case 2 lands, as designed. It refuses only because a *foreign* write-set leaked in.
  Declaring `newfile.txt` would paper over the leak and leave the suite still non-hermetic.
- The mission's standing instruction to keep the inline duplication of `_pc_diff_base` is
  fine to honour, but **its stated reason is false** and must not be left in the tree as a
  load-bearing comment — see §5.

---

## 1. CALLERS / CALLEES

All paths in `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` unless noted.

### `_pc_lane_commits_ahead` (defined :1182)

| Direction | Symbol | Site | Notes |
|---|---|---|---|
| caller | `pc_silent_arm_probe` step 6 | :1355 | **the only caller in the repo** (`grep -rn _pc_lane_commits_ahead plugins/` → definition + this line) |
| callee | `git rev-parse --is-inside-work-tree` | :1185 | guard |
| callee | `cat "${CACHE_BASE}/dispatch-${TASK}.start-sha"` | :1188 | `CACHE_BASE` set :131 from `LEADV2_DISPATCH_CACHE_DIR` |
| callee | `git cat-file -e`, `git merge-base` | :1189-1193 | base resolution |
| callee | `git rev-list --count` | :1196 | the count |

### `pc_silent_arm_probe` (defined :1307)

| Direction | Symbol | Site | Notes |
|---|---|---|---|
| caller | top-level `if pc_silent_arm_probe; then` | :2111 | single call site; `_lane_root` recomputed immediately above at :2106-2109 |
| callee | `_pc_arm_registered` | :1310 | gate 0 |
| callee | `_pc_stat_mtime` | :1339 | growth guard |
| callee | `_pc_worker_process_alive` | :1348 | liveness |
| callee | `_pc_lane_dirty` | :1351 | dirty check |
| callee | `_pc_lane_commits_ahead` | :1355 | **the mechanism under repair** |

### Sibling that is NOT this path — name it explicitly

`_pc_diff_base` (:1735) is an **independent copy** of the same base-resolution algorithm,
reached only from `_pc_repo_diff` (:1765) → `pc_scope_diff` (:1663). It runs **after** the
probe (:2111 < :2117 `pc_scope_diff`). It is **top level, column 0** — the round-1 comment
at :1163-1179 claiming it is "defined INSIDE `pc_scope_diff()`'s body" is factually false
(`grep -n '^_pc_diff_base' …` → `1735:_pc_diff_base() {`; `grep -n 'pc_scope_diff() *{'` →
`1663`). The two copies are now free to drift: fixing base resolution in one does not fix
the other. That is a real cost of the duplication, and the mission's off-limits on
`pc_scope_diff` means we accept it this round — but the comment must stop asserting a
false reason for it.

Other callers of `_pc_arm_advance`: :772 (the codex-quota-lockout path) as well as :2116.
Both are downstream of a verdict this design does not change.

---

## 2. STATES AND RETURN CODES

### 2a. `_pc_lane_commits_ahead` — today

| # | State | stdout | rc | What :1355-1357 does | User-visible consequence |
|---|---|---|---|---|---|
| 1 | root empty / not a dir / not a worktree | `0` | 0 | `commits_ahead=0`, falls through | lane is called silent |
| 2 | `LEADV2_LANE_START_SHA` set, object exists here, merge-base found | `N` | 0 | `N>=1` → rc1 NOT silent | correct |
| 3 | **`LEADV2_LANE_START_SHA` set, object NOT in this repo, no `origin/main`** | `0` | 0 | falls through | **the bug — a lane that committed is declared to have produced nothing** |
| 4 | env unset, cache file present & valid | `N` | 0 | as (2) | correct |
| 5 | env unset, cache file absent, `origin/main` present | `N` | 0 | as (2) | correct |
| 6 | env unset, cache file absent, no `origin/main` | `0` | 0 | falls through | same defect as (3), different trigger |
| 7 | base resolves, genuinely 0 commits | `0` | 0 | falls through | correct — genuinely silent |

States 1, 3, and 6 are **"cannot tell"** and are today indistinguishable from state 7
**"proven zero"**. That is the whole defect. The count is a lossy channel.

### 2b. `_pc_lane_commits_ahead` — designed

Widen the channel: `unknown` on stdout for states 1/3/6, an integer only when a base was
actually resolved. rc stays 0 always (the probe must never abort the gate).

| State | stdout | :1355 handling | User-visible consequence |
|---|---|---|---|
| base resolved, N>=1 | `N` | NOT silent (rc1) | lane proceeds to scope-diff/review |
| base resolved, N==0 | `0` | continue to silent verdict | genuinely silent arm still parks and advances the chain exactly once |
| **base unresolvable** | `unknown` | **NOT silent (rc1)**, plus one journal line | lane proceeds to scope-diff, which owns the empty/unscoped verdicts; the operator sees a named line saying the commit probe could not resolve a base, rather than a silent misclassification |

### 2c. Terminal outcomes of the caller chain (traced to the end)

| Probe result | :2111 branch | Terminal | Plain-words outcome |
|---|---|---|---|
| rc0 (silent) | writes `review-gate.md` `reason: arm_produced_nothing`, ledger `no_work/arm_produced_nothing`, `_pc_arm_advance`, `exit 5` | `no_work` | this arm is parked; the next arm in the candidate chain is dispatched once (marker `.arm-advanced-<arm>` makes it once-only, :1368) |
| rc1 (not silent) | falls to `pc_scope_diff` :2117 | `landed` / `refused` / `empty_diff` per existing gates | unchanged behaviour |

Fail-open direction change: the probe currently fails **closed to 0** (== "silent"). The
mission mandates the opposite: *"a probe that cannot tell must NOT conclude silence."* The
design adopts fail-open. §4 states what that costs.

### 2d. `_pc_arm_advance` rcs (unchanged, listed because Case A asserts on its output)

Always rc0. Emits exactly one of: `arm_advance_skipped … reason=already_advanced` /
`…=kill_switch` (:1374, when `LEADV2_ARM_ADVANCE=0`) / `…=chain_exhausted` /
`…=no_mission_file`, **or** `arm_advance task=… from=… to=…` (:1399).

**Assertion defect:** `test-silent-arm-commits-ahead.sh:86` greps for the bare substring
`arm_advance`, which also matches `arm_advance_skipped`. Under the fix Case A will emit
neither, so the test passes — but the assertion is wrong on its own terms and would accept
a `_skipped` line as proof of an advance. Tighten to `arm_advance task=`. Case D's
`grep -c 'arm_advance'` (:186) has the same flaw in reverse: it counts a `_skipped` line as
an advance. Tighten both.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads.

### `LEADV2_LANE_START_SHA` (env, read :1187)

| Input | Today | Designed |
|---|---|---|
| absent | falls to cache file | unchanged |
| empty string | `[[ -z ]]` → falls to cache file | unchanged |
| valid sha, object present in this repo | merge-base → count | unchanged |
| **valid sha, object absent from this repo** (multi-repo lane, or a leaked ambient value) | `cat-file -e` fails silently → `origin/main` fallback → often `0` → **false silence** | falls through to cache file, then `origin/main`; if none resolve → `unknown` → NOT silent |
| malformed / non-sha garbage | `cat-file -e` fails → same as above | same as above — never aborts |
| over-long (>4096 chars) | passed to `git cat-file` as one argv; git rejects; no ARG_MAX risk at this size | unchanged; bounded by a single argv, cannot take down the gate |

Note the precedence trap: env **beats** the on-disk cache file. A stale exported value from
an unrelated lane therefore *suppresses* a correct cache file. Designed behaviour keeps the
precedence (changing it is out of scope and `_pc_diff_base` would drift further) but no
longer lets the failure read as `0`.

### `${CACHE_BASE}/dispatch-${TASK}.start-sha` (file, read :1188)

| Input | Behaviour (today and designed) |
|---|---|
| absent | `cat` fails, `|| true`, `sha` empty → `origin/main` fallback |
| empty file | `sha` empty → same |
| valid sha | resolved |
| multi-line / trailing whitespace | passed verbatim to `cat-file -e`; a trailing `\n` is stripped by `$( )`; extra lines make it fail → fallback. **Never aborts.** |
| huge file (MBs) | read into a variable; a pathological file costs memory in this one process only and still fails `cat-file`. Bounded to the one operation. |

`CACHE_BASE` itself (`LEADV2_DISPATCH_CACHE_DIR`, :131): absent → `${HOME}/.claude/cache`;
empty → `${HOME}/.claude/cache` (`:-` treats empty as unset); non-existent dir → `cat`
fails → fallback. No boundary aborts the gate.

### `LEADV2_DISPATCH_LANE_WRITES` (env → `WRITES_CSV`, :31) — Red 2's input

| Input | Behaviour | Designed |
|---|---|---|
| absent / empty | scope gate does not partition; a dirty lane lands | unchanged (this is what Case 2 intends to exercise) |
| set to paths of a **different** lane | every dirty path is undeclared → `refused / unscoped_lane_work` | unchanged in product code — **correct behaviour, do not weaken.** Fixed at the test boundary by making the suite hermetic and by setting the var explicitly-empty for Case 2 |

This is the "over-cap input that takes down more than the one operation it belongs to"
case: one exported var from the enclosing lane silently converts an unrelated sandboxed
fixture's verdict. In production it is correct; in a test process it is contamination. The
fix belongs in the suite, not the gate.

### `LEADV2_PC_SILENT_GROWTH_S` (:1330) — already correct

absent → 60; malformed → 60; `<1` → clamped to 1 with a journal line; `>3600` → clamped to
3600 with a journal line. Listed for completeness; no change.

### `LEADV2_ARM_ADVANCE` (:1374)

absent → `1` (advance); `0` → skip with a journal line; any other value → advance. No
change.

---

## 4. COUNTEREXAMPLE

*After every finding here is fixed, what can still violate the invariant "a lane that
produced work is never declared to have produced nothing"?*

Two things, and one is created by this fix.

**(a) The fix trades a false negative for a stall.** Moving `unknown` to fail-open means a
lane with a genuinely silent arm **and** an unresolvable base is no longer parked — it falls
through to `pc_scope_diff`, produces an empty diff, and terminates `no_work/empty_diff`
*without* advancing the arm chain (the advance lives only on the `arm_produced_nothing`
branch, :2116). Plain words: a dead arm whose base cannot be resolved will not hand off to
the next provider, and the task sits until a human notices. This is strictly better than
today's failure (which discards *committed work*), but it is a real regression surface and
is why the design emits a named journal line rather than degrading quietly — same posture
as commit `1586ba1`, "name the fan-out degradation instead of hiding it behind a strong
label". The line is the mitigation; there is no way to have both without a base.

**(b) The duplication remains, and it is now asymmetric.** `_pc_diff_base` (:1735) keeps the
old fail-to-empty semantics for the diff path while `_pc_lane_commits_ahead` (:1182) gains
`unknown` semantics for the probe path. Two copies of one algorithm with divergent failure
behaviour, in a file where the census comment already got their relationship wrong once. A
future edit to base resolution that lands in one copy and not the other reintroduces
exactly this class of bug. `pc_scope_diff` is off-limits this round, so the mitigation is
the corrected comment (§5) pointing at both sites by line number.

**What I checked and found clean:** the probe's other five gates (registration, assistant
events, stream presence, growth, liveness) each fail-open already and were re-read at
:1310-1351; `_pc_arm_advance`'s once-only marker (:1368) is written before any skip branch,
so no boundary double-advances; `_pc_lane_commits_ahead` has exactly one caller repo-wide.

---

## 5. CHANGES — exact, minimal

### C1 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

1. **:1182-1201 `_pc_lane_commits_ahead`** — emit `unknown` instead of `0` on every
   "cannot tell" path (states 1/3/6 in §2a). Integer output only when a base was resolved.
   rc stays 0 unconditionally.
2. **:1354-1358 the call site** — treat `unknown` as NOT silent (`return 1`), and emit one
   journal line naming the degradation before returning, e.g.
   `silent_probe_base_unresolved task=… arm=… lane=…`. Keep the existing
   `(( commits_ahead >= 1 )) && return 1` for the integer case and the
   `_PC_SILENT_COMMITS_AHEAD` assignment for the evidence string on the proven-zero path.
3. **:1163-1179** — replace the false census comment. `_pc_diff_base` is at top level
   (:1735), reached via `_pc_repo_diff` (:1765) inside `pc_scope_diff` (:1663), which runs
   *after* the probe (:2111), so a call would in fact resolve. State the true reason for the
   duplication — `pc_scope_diff` is off-limits and the two copies now have deliberately
   different failure semantics (§4b) — and cross-reference both line numbers.

**Non-goal:** do not refactor the duplication away, do not hoist `_pc_diff_base`, do not
touch `pc_scope_diff`.

### C2 — `plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh`

1. **Hermetic preamble** (after `set -uo pipefail`, :19): scrub the ambient environment the
   way `run-core-offline.sh:101-114` does — `unset` every exported `LEADV2_*` name before
   the first fixture is built. Each case already passes the vars it needs explicitly on the
   command line, so nothing is lost.
2. **:86 and :186** — tighten `arm_advance` greps to `arm_advance task=` so
   `arm_advance_skipped` cannot satisfy or inflate them (§2d).
3. **New Case E** — the state the whole fix exists for: registered arm, stale stream, clean
   worktree, **`LEADV2_LANE_START_SHA` set to a sha that does not exist in the fixture repo**,
   no `origin`. Assert NOT `arm_produced_nothing` and that the degradation line is present.
   This is the regression lock; without it the fix is untested against its own trigger.

### C3 — `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh`

1. Same hermetic preamble.
2. **Case 2 (:108-116)** — add `LEADV2_DISPATCH_LANE_WRITES=""` to the explicit env block, so
   the case declares "no write-set" as intent rather than inheriting it. **Do not** declare
   `newfile.txt`; that would change what the case tests and would not fix the leak.

**Non-goal:** no change to the scope gate, `unscoped_lane_work`, the e2e gate, or any
assertion outside these two suites.

### Verification the implementer must paste

1. `bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` — all cases incl.
   new Case E and the Case D positive control (silent arm still parks, advances exactly once).
2. The same suite re-run **with `LEADV2_LANE_START_SHA` and `LEADV2_DISPATCH_LANE_WRITES`
   deliberately exported to foreign values** — must stay green. This is the hermeticity proof.
3. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — all cases.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Known
   pre-existing, NOT this lane's: `deferred-GLM ladder (V3-GLM-LADDER-01)` and
   `fanout classifier/runner guard`.
5. `git diff --stat`.

All in the foreground, with a timeout.

---

## 6. Out of scope

`pc_scope_diff` and everything it calls; `_pc_diff_base`; the e2e gate; the ledger schema;
`_pc_arm_advance`'s chain logic; the env-var precedence order (env before cache file); any
other suite under `tests/`; main's unrelated uncommitted files (no stash/reset/clean); any
merge.

---

acceptance:
  surface: log_line
  observable: >
    In the close gate's journal for a lane whose worker committed its work and left the
    worktree clean, the operator no longer sees the line saying that arm produced nothing
    and no longer sees the chain hand the task to the next provider; the lane goes on to
    review instead. For a lane where the probe cannot work out what to compare against, the
    journal carries a line that says exactly that, in place of a silent verdict.
  authored_at: 2026-08-23T06:32:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh

DELIVERABLE_COMPLETE
