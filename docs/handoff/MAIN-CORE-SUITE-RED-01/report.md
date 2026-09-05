# MAIN-CORE-SUITE-RED-01 — round 2 report

All four suites named in the round-2 mission were reproduced red against a
**clean current-`main` base** (a real `git clone --local -b main`, not a
`git archive` — archives drop `.git`, which spuriously breaks any test that
does `git show <rev>:<path>`), diagnosed, fixed, and re-verified red→green
with a paired negative control. All four are genuinely fixed; none required
weakening a fixture or reverting product behavior.

Base clone tip used for the final round of verification: `a1cca7e6` (main
advanced one more commit, `ca4d52d1`, before this report was written; that
commit does not touch any of the four files below, so no re-verification was
needed — confirmed via `git show --stat ca4d52d1`).

`tests/known-red-suites.txt` and `tests/known-failures.txt` do not exist
anywhere in this checkout (`find . -iname "known*"` returns nothing), so
there was nothing to shrink or grow for any of the four suites.

---

## 1. `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh`

- **rc before (clean main):** 1 — `PASS=18 FAIL=1`, sole failure `case 10:
  registration assertion failed`.
- **rc after (clean main + fix):** 0 — `PASS=19 FAIL=0`.
- **Root cause:** case 10 asserted a stale `hooks.json` registration
  contract — that `leadv2-idle-lead-guard.sh` is registered on `Stop`,
  ordered after `promise-guard`, and last in the array. **ONE-LANE-WATCH-01**
  (`9f00e7ed`, merged `c49cc9fb`) retired that standalone Stop hook in favor
  of the self-arming `leadv2-lane-watch-v2.sh` (armed via `SessionStart
  --arm-from-hook`, disarmed via `SessionEnd --disarm-from-hook`). The test's
  assertion rotted the day that landed; the hook itself was never broken.
- **Fix:** rewrote case 10 to assert the *current* contract: retired hook
  absent from `Stop`, `promise-guard` still present, `lane-watch-v2`
  registered on both `SessionStart` (`--arm-from-hook`) and `SessionEnd`
  (`--disarm-from-hook`).
- **Negative control:** re-added `leadv2-idle-lead-guard.sh` to a copy of
  `hooks.json`'s `Stop` array → case 10 FAILS (`PASS=18 FAIL=1`, exact
  original symptom). Reverted → green again (`PASS=19 FAIL=0`).
- **Note:** this suite genuinely fails when run inside this lane's own
  worktree, because this worktree's own `hooks.json` is stale relative to
  `main` (outside `LANE_WRITES`, not touched). The authoritative measurement
  is the clean-main-base one above.

## 2. `plugins/leadv2/scripts/tests/test-injector-dedup.sh`

- **rc before (clean main):** 1 — `PASS=9 FAIL=1`, sole failure
  `multisession negative control stayed green`.
- **rc after (clean main + fix):** 0 — `PASS=10 FAIL=0`.
- **Root cause:** the multisession negative control mutates a copy of
  `leadv2-user-prompt-context.sh` with a `perl -0pi` regex anchored on a
  single-line literal comprehension (`others = [sess for sess in s...]`).
  **TERMINAL-LANES-STILL-READ-AS-LIVE-01** (`b8db6058`) rewrote that
  comprehension to span multiple lines; the anchor silently stopped
  matching, so the mutation became a no-op and the "negative control"
  degenerated into a pass that proved nothing (the suite was checking the
  cap regression path against unmutated code and calling it a control).
- **Fix:** updated the anchor to match across the line break, and added an
  explicit `grep -q '\[:3\]'` guard right after the `perl` call so a future
  anchor rot fails loudly (`negative-control anchor rotted`) instead of
  silently passing.
- **Negative control:** the fixed mutation now correctly reintroduces the
  4-session cap bug and the suite's own control assertion (`multisession
  negative-control red`) fires as designed — this control IS the suite's
  built-in red/green pair, now restored to actually exercising the mutated
  code path.
- **Out-of-scope finding (reported, not fixed):** `leadv2-user-prompt-context.sh`
  (line ~167, under `plugins/leadv2/hooks/`, outside `LANE_WRITES`) has a
  backtick pair inside a comment embedded in a bash double-quoted
  `python3 -c "..."` string, which bash attempts to execute as a nested
  command substitution — printing `line 167: phase: command not found` to
  stderr on every invocation with the default `LEADV2_ANCHOR_OWNS_CONTEXT=1`.
  Harmless (stderr noise only, does not affect behavior or exit code) but
  should be fixed in that file directly since it's off-limits to this lane.

## 3. `plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh`

- **rc before (clean main):** 1 — `4 passed, 1 failed` (`FAIL:
  C5-registered-arm-silent`).
- **rc after (clean main + fix):** 0 — `5 passed, 0 failed`.
- **Root cause:** `_pc_lane_commits_ahead()` in
  `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` could not prove
  "zero commits of my own" for the common real-world case of a lane
  worktree whose `LEADV2_LANE_START_SHA`/cache file/`origin/main` are all
  unresolvable. Every lane worktree is born with exactly one
  `--allow-empty "lane <id> anchor"` commit (`leadv2-lane-worktree.sh`,
  tagged `T11-F2`), so `HEAD` is always one commit ahead of the parent
  repo and the existing "HEAD == parent HEAD" prove-zero check never
  fires — such a lane fell through to `unknown`, and case
  `C5-registered-arm-silent` (which needs a silent arm to be provably
  silent, i.e. "0") failed.
- **Fix:** added a second prove-zero branch that recognizes the birth
  anchor specifically: `HEAD^` equals the parent repo's `HEAD`, the commit
  subject matches `"lane "*" anchor"`, and its diffstat is empty. Only then
  is it discounted as "0" — any lane with real work on top of the anchor
  still correctly reports `unknown`/its true count.
- **Negative control:** this suite runs its own internal red-first pass
  (`git archive HEAD` of its own current, unpatched committed state) as
  pass 2 of 2; that pass reported `FAIL C5-registered-arm-silent` against
  the unpatched product file and passed against my working-tree patch,
  which is the suite's own built-in mutation-pair proof — no separate
  manual mutation needed.

## 4. `plugins/leadv2/scripts/tests/test-phase-precondition.sh`

- **rc before (clean main):** 1 — `pass=81 fail=1`, sole failure `G3:
  dispatch should exit 0 (got 4)`.
- **rc after (clean main + fix):** 0 — `pass=82 fail=0`.
- **Root cause:** NOT in `_phase_precondition_guard()` — its
  `REQUIRE_PHASES=0` kill switch is byte-identical to pre-C4 behavior and
  was confirmed (by reading it directly) to `return 0` unconditionally
  before any subprocess/journal/refusal logic runs, ruling out the phase
  guard itself. Root-caused instead to the test's own `glm-stub.sh` fixture:
  its `bg` subcommand emitted a doubled `"$RUNS/$handle$handle"` envelope
  under the claim that "dispatch-code's GLM adapter extracts a handle from
  the legacy envelope." That claim is stale: **GLM-ARM-THROUGHPUT-01** (a
  comment directly above the current glm spawn case in
  `leadv2-dispatch-code.sh`) documents that the real `glm-coder.sh` `bg`
  echoes the bare run_id **once**, with no doubling and no leading
  `$RUNS/` path, and that the old halving/extraction logic was deliberately
  removed because it truncated every handle to a garbage half-string that
  never matched a real run dir. The doubled stub envelope made `status
  <handle>` always report `not_live`; dispatch declared glm dead, fell back
  to the real (unstubbed) sonnet launcher, which failed for its own
  unrelated reason (`role file not found in agents/ or roles/: developer`)
  — the visible G3 failure (`exit 4`) was several arms removed from the
  actual cause. Confirmed by instrumenting a copy of the test to capture
  the real dispatch stderr instead of discarding it to `/dev/null`.
- **Fix:** changed the stub's `bg` case to emit the bare handle exactly
  once (matching the current, documented dispatch-code contract), and
  documented why (so a future edit doesn't reintroduce "the doubled form
  because it mirrors some historical adapter behavior" — that history is
  exactly what was removed and is no longer the contract).
- **Fix location note:** this fix lives entirely in the test file
  (`plugins/leadv2/scripts/tests/`), inside `LANE_WRITES`. Neither
  off-limits file (`leadv2-dispatch-code.sh`, `leadv2-phase-record.sh`) was
  touched.
- **Negative control:** re-mutated a clean-main copy's stub back to the
  doubled envelope (`sed` on the fixed file) → G3 fails again with the
  exact original symptom (`pass=81 fail=1`, `FAIL: G3: dispatch should
  exit 0 (got 4)`). Restored the fix → green again (`pass=82 fail=0`).
- **Lane-staleness caveat:** running this suite inside this lane's own
  worktree (not the clean-main clone) surfaces an unrelated `F1` failure
  (`recording an unhashable (directory) artifact should refuse with rc=5`)
  caused by this lane's own copy of `leadv2-phase-record.sh` being ~284
  lines behind current `main` (off-limits, not touched by this lane). The
  authoritative measurement — clean main clone plus this lane's diff — is
  green at `pass=82 fail=0` with no F1 failure; that measurement is what
  the mission's acceptance gate reproduces.

---

## Lane-staleness discovery (process note, not a 5th finding)

Partway through diagnosing suite 4, discovered this lane's own copies of
several files are substantially stale relative to current `main` — this
lane's fork point (`10fe3d6e`) is old enough that unrelated concurrent
lanes have since landed hundreds of lines of independent changes to files
this task touches. Two different flavors of this showed up:

- `hooks.json` and `leadv2-phase-record.sh` are genuinely outside
  `LANE_WRITES` (this lane may not touch them) and stale — this only
  matters as an explainable source of spurious in-lane-only failures
  (idle-lead-guard case 10 failing when run in this lane; test-phase-
  precondition's F1 failing when run in this lane), never as something to
  fix here.
- `test-phase-precondition.sh` (a file this lane *is* allowed to touch) was
  itself ~218 lines behind current `main`. Editing it in place would have
  produced a lane diff that reverted those 218 lines the moment it merged
  with `main`. Fixed by re-syncing the file's content from current `main`
  first, then applying the one-hunk stub fix on top, so the diff against
  `main` stays a clean ~16-line change instead of an accidental revert.
- `leadv2-dispatch-product-close.sh` (also in `LANE_WRITES`, 36 commits/90d
  — one of the hottest files in the repo per this lane's own knowledge
  base) shows the same ~440-line drift against current `main`. This file
  was **not** re-synced: unlike the test file, the specific function this
  task fixes (`_pc_lane_commits_ahead()`) was independently verified
  correct by applying the exact same hunk directly to a fresh `main` clone
  (not this lane's stale copy) and confirming it produces `5 passed, 0
  failed` there too — so the fix itself is proven sound regardless of what
  else has changed elsewhere in the file. Re-syncing an entire 3700+ line,
  actively-churning product file mid-task risked colliding with other
  lanes' concurrent in-flight edits to unrelated functions in the same
  file; reconciling that drift is squarely the job of this repo's existing
  merge tooling at integration time, not something to attempt here.

Because of this, every fix in this report was **built and verified against
a fresh `git clone --local -b main`**, not this lane's own working tree.
All four fixes were re-confirmed green by copying this lane's final
committed files onto that fresh main clone and re-running each suite
there.
