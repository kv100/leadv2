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

sha: f2f3c001a6ee917f9c903a957fcaf1ffc3ca4aa9
Revert: `git revert <this commit's sha>` — one step, reintroduces the pre-fix `origin/main`
anchors and removes the fourth-tier function; the standing no-push-to-origin freeze is
untouched either way (nothing in this change touches push/fetch).

checked=3 sites, 2 acceptance test cases (5/5), 3 topologies, 1 negative control, all with real
command output above — no candidate accepted on "looks right."
