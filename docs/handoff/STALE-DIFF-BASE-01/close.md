# STALE-DIFF-BASE-01 — close

Founder decision: fix the fallback stage, not the push-to-origin freeze. **Push to origin
remains blocked** — this change only touches which local ref the fallback stage anchors on.

## Sites — three, not two

Leadmain's brief named two (`:1515`, `:2280`); a grep before touching anything found a third:
`:2298-2301` (`_pc_diff_base_main()`), a separate, deliberately-designed unconditional
cross-check, not a duplicate of the other two's fallback chain. All three now fixed. Also fixed,
found by the same grep pass and not in the original brief: three matching
`cat-file -e "origin/main^{commit}"` existence guards at the same three sites — left unfixed,
the guard would check a ref (`origin/main`) different from the one `merge-base` actually uses
(`main`), which is silently wrong whenever `origin/main` doesn't exist at all (no remote
configured) but `main` does.

## Round 1 (straight ref swap) — regressed a real test, did not ship

`merge-base origin/main HEAD` → `merge-base main HEAD` at all three sites, straight swap.
Ran `test-close-gate-nowork-abandoned.sh` (the suite the code's own comment names as the
reproduction case for `_pc_diff_base_main`): **was 5/5 before the edit, 3/5 after — Case A
failing.** Root cause, confirmed by reading the fixture: it commits directly onto the local
branch named `main` (this environment's `git init` default), with `refs/remotes/origin/main`
deliberately frozen at the seed commit as "the true upstream both cases are judged against."
In that topology `merge-base(main, HEAD) = HEAD` (structural zero — `main` IS the branch being
worked on), while `origin/main` — frozen, but a real ancestor in that shape — still correctly
resolved. A straight ref swap doesn't just occasionally get silenced by the `mbase != base`
guard (Leadmain's own first-named risk); it makes the fourth-tier check permanently useless
whenever a lane commits directly onto local `main` with no separate feature branch. Stopped
before committing, reported the regression with the failing/passing rc and root cause, did not
force the test to green.

## Round 2 (accepted rule) — {HEAD, base, main} widest-wins, origin/main as last resort only

Leadmain's rule: keep the existing three-candidate "widest diff wins" picker exactly as it was
(HEAD, `_pc_diff_base`, `_pc_diff_base_main`, all now anchored on local `main`); add a **fourth,
last-resort** candidate — `origin/main` — consulted **only when the winner among the first three
is empty**. New function `_pc_diff_base_origin()` (mirrors `_pc_diff_base_main()`, anchors on
`origin/main`), called from `_pc_repo_diff()` only inside `if [[ -z "${winner}" ]]`.

### Acceptance

**1. Pair control (primary symptom), before/after:**

```
BEFORE (origin/main-anchored fallback, as it was until this fix):
  commits: git rev-list --count origin/main..main  = 676
  files:   git diff --name-only origin/main main    = 2322
AFTER (local-main-anchored fallback, as it is now):
  commits: git rev-list --count main..main           = 0
  files:   git diff --name-only main main             = 0
```

**2. `test-close-gate-nowork-abandoned.sh` — 5/5, both named cases:**

```
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case A: 3 commits ahead of origin/main are NOT stamped no_work/empty_diff
[TEST] PASS: Case A: no empty_diff ledger row for the lane with real work ahead of main
[TEST] PASS: Case B: a lane whose work genuinely landed in main is still stamped empty_diff
[TEST] PASS: Case B: ledger row is no_work/empty_diff for the landed lane
[TEST] 5 passed, 0 failed
```

**3. Degenerate re-dispatch repro — real functions, sourced from the fixed file, called
against an isolated scratch repo (not the live leadv2 tree):** `LEADV2_LANE_START_SHA` set to a
round-1 tip that already contains real committed work; HEAD unchanged (round 2 produced
nothing). `_pc_diff_base()` (base) resolves to that tip → `base_out` = 0 files, the exact
degenerate-empty shape. `_pc_diff_base_main()` (mbase) resolves to the true fork point from
local `main`, different from `base` → guard does not silence it → `main_out` = 2 files, the
branch's real accumulated work. Safety net intact.

**4. Three topologies, called via the real fixed functions (`_pc_diff_base`,
`_pc_diff_base_main`), sourced from the file, not reimplemented:**

- Live lane, round 1, on a feature branch: `base == mbase`, both non-empty (2 files) — local
  `main` wins on its own merits, `origin/main` never consulted.
- Live lane, round 2, degenerate re-dispatch (item 3 above): `base` empty-by-construction,
  `mbase` = 2 files — the `main` candidate wins, `origin/main` never consulted.
- Fixture shape (commits land directly on local `main`, no separate branch): proven by item 2
  above (the actual suite, run end-to-end through the real script, not a scratch stand-in) —
  `main`-based candidates come back empty (structural zero), the fourth-tier `origin/main`
  candidate is consulted and wins with the real 3-file diff. Suite goes green on its actual
  cause, not a patched assertion.

**5. Negative control — mandatory, not a formality.** Temporarily short-circuited the
last-resort tier (`if false && [[ -z "${winner}" ]]` in place of the real condition, restored
immediately after) and re-ran `test-close-gate-nowork-abandoned.sh`: **3/5, Case A red again**,
same failure text as round 1 (`3 commits ahead of origin/main were stamped no_work/empty_diff`).
Restored the real file (`cp` from a saved copy, verified via `git diff --stat` that only the
intended 65-line/54-insertion/11-deletion diff remained) and re-ran: 5/5 clean again. The stage
is reachable and load-bearing, not decorative.

## Reachability of the backup stage (Leadmain's second acceptance item)

Sampled the 30 most-recently-modified `dispatch-*.start-sha` cache files
(`~/.claude/cache/`) and checked resolvability against each of the two repos sharing this
cache directory (leadv2, persona-engine) separately: 11/30 resolved in leadv2, 19/30 resolved
in persona-engine, 30/30 accounted for with zero unresolvable — i.e., when checked against the
CORRECT owning repo, the primary (cached start-sha) tier resolves essentially always in this
sample. That means the raw "cache miss forces the origin-main-style fallback" path is likely
**rare** in the general case — a result, not a non-finding, and worth saying plainly rather than
assuming the fallback fires often. It does NOT mean the fix is low-impact: `_pc_diff_base_main`
(now `_pc_diff_base_origin` for the last-resort tier) is consulted differently — the three-way
picker runs on **every** close regardless of cache-hit status, so the degenerate-re-dispatch
class of bug (item 3 above) is reachable independent of raw cache-miss frequency.

## Commit

sha: (recorded at commit time below)
Revert: `git revert <this commit's sha>` — one step, reintroduces the pre-fix `origin/main`
anchors and removes the fourth-tier function; the standing no-push-to-origin freeze is
untouched either way (nothing in this change touches push/fetch).

checked=3 sites, 2 acceptance test cases (5/5), 3 topologies, 1 negative control, all with real
command output above — no candidate accepted on "looks right."

## Round 3 (2026-09-07, later) — `_pc_lane_commits_ahead` had the same defect, live in the tree

Round 2's picker fix shipped in f2f3c001a without running `test-silent-arm-commits-ahead.sh` --
correction on record: that suite was 15/15 on the commit before mine, dropped to 11/15 (Cases B,
E, G) because round 1's straight `origin/main`->`main` swap at site :1515
(`_pc_lane_commits_ahead`) hit the exact same degenerate-topology bug as the picker, independently
confirmed by building the fixture-shape case (commits directly on local `main`, no start-sha, no
cache) and calling the real function: it printed `0` for a lane with 3 real commits.

**Fix:** the trigger condition here can't be "is the value empty" (unlike the picker) --
`merge-base(main, HEAD)` in the degenerate topology resolves to a real, non-empty value (HEAD
itself), indistinguishable BY COUNT ALONE from a lane genuinely forked from main's current tip
with zero real commits done. Disambiguated by branch identity instead: only distrust the
`main`-based base when `git symbolic-ref --short HEAD` on the lane root is literally `main` (i.e.
the checkout IS local main, no separate feature branch) -- a real feature-branch lane keeps its
(possibly genuinely-zero) `main`-based count untouched, avoiding a false-positive-inflation risk
a plain "always prefer origin/main on a tie" rule would have introduced.

**Verification, both directions, real function, isolated scratch repos:**
- Fixture-shape (commits on local `main`, no separate branch): now returns `3`, not `0`.
- Distinct feature branch, genuinely 0 commits ahead of the CURRENT main tip: still returns `0`
  -- confirms the branch-identity disambiguator does not falsely inflate a real zero.

**Regression suite, `test-silent-arm-commits-ahead.sh`:** 11/15 -> 14/15 after the disambiguator
(Cases B, E now pass; Case G still failing on its literal old assertion).

**Case G -- widened, not weakened, per explicit review.** Case G is a linked worktree, distinct
branch, one real commit, no origin/main in this fixture at all. Its lock (asserted first, never
touched): a lane that committed must NOT be classified `arm_produced_nothing`. Its SECOND
assertion (`silent_probe_base_unresolved` specifically) was the round-2-era MECHANISM for holding
that lock when no candidate could resolve a base -- round 3 adds a legitimate candidate (`main`,
same object in a linked worktree's shared ref-store as its parent, always resolvable via the git
object model) that now resolves this fixture to a real, non-zero count (`1`) instead of "unknown".
Read `docs/handoff/GATE-FALSE-SILENT-01/fix-round-3.md` before touching this: its "Off-limits"
section forbids weakening Case E (untouched, still passes) and forbids gaming
`test-lane-diff-single-repo.sh`'s C5 (untouched); nothing in it argues against trusting a linked
worktree's shared ref-store, so the widening below doesn't cross either boundary.

Widened Case G's second assertion to accept EITHER `silent_probe_base_unresolved` OR a resolved
non-zero count -- added a matching `silent_probe_base_resolved task=... commits_ahead=N` decision
line (previously the resolved-and-nonzero path returned silently with no log line at all, so the
test would have had to infer "resolved" from the ABSENCE of the unresolved line -- too weak a
signal to assert on). First assertion (must not be `arm_produced_nothing`) is untouched.

**Negative control, the meaningful one:** artificially disabled the `main`-based tier in
`_pc_lane_commits_ahead` (the tier Case G actually depends on here -- this fixture never sets up
`origin/main` at all, so that candidate was never reachable for Case G either way, confirmed by
grep across the test file). Result: Case G's log line reverted to exactly `silent_probe_base_unresolved`
(grepped and confirmed the literal string, not just "the widened assertion still passed") --
proving the widened assertion's first branch is genuinely load-bearing, not vestigial. Case F
(the provably-zero linked worktree) stayed `0` and its "no unresolved line" assertion stayed green
throughout every variant tried. Restored the real file after each mutation; `diff` against the
saved good copy confirmed byte-identical restoration before the final commit.

Full suite after restoration: `test-silent-arm-commits-ahead.sh` 15/15,
`test-close-gate-nowork-abandoned.sh` 5/5 (both re-run clean, not assumed from round 2).
