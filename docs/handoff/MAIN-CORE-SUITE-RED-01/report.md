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

---

# Round 3 — environment-dependence verdict, the two remaining reds, controls

## 1. Verdict: neither suite depends on live/shared state

The round-3 mission hypothesized `case 10` touches "registration in the
live lane registry". Measured: it does not — and the lead's own correction
landed on main (`587625e7`, `docs/handoff/MAIN-CORE-SUITE-RED-01/round-3-correction.md`)
reached the same conclusion via a neighboring session before this round
started. The runs below are this round's independent confirmation.

Discriminating experiment pair (both in this lane worktree, same edits,
identical commands):

| Run | Registry in reach | test-idle-lead-guard | test-phase-precondition |
|-----|-------------------|----------------------|-------------------------|
| A (ambient, live lanes running) | live `~/.claude/leadv2-state` | rc=1, PASS=18 FAIL=1 (case 10) | rc=1, pass=80 fail=2 (F1 ×2) |
| B (`LEADV2_STATE_ROOT=/tmp/r3/state-root-empty.c0JZ`, `LEADV2_PROJECT_ROOT` threaded to a non-repo dir) | empty dir | rc=1, PASS=18 FAIL=1 (case 10) — identical verdict | rc=1, pass=80 fail=2 (F1 ×2) — identical |

Verdicts do not move when the live registry is swapped for an empty dir →
**not dependent on live shared state**. What the verdict DOES track is the
checkout's own bytes:

| Run | Checkout | idle | prec |
|-----|----------|------|------|
| D | pure main clone (`587625e7`) | rc=1 (case 10) | rc=1 (G3, pass=81 fail=1) |
| C | main clone + this lane's 4 files | rc=0, PASS=19 FAIL=0 | rc=0, pass=82 fail=0 |

Code-level corroboration (why no live read is even possible):
- `test-idle-lead-guard.sh` header documents full isolation; all four
  `LEADV2_IDLE_GUARD_*` overrides point at `mktemp -d` fixtures
  (tests/test-idle-lead-guard.sh:4-8, :111). Case 10 is a static read of
  `$PLUGIN_DIR/hooks/hooks.json` — a checked-in file, no registry involved.
- `test-phase-precondition.sh` `e2e_setup()` cds into the throwaway fixture
  repo and exports `LEADV2_STATE_BASE="${E2E_STATE}"` (throwaway) plus
  sandbox overrides for every dispatch dependency
  (tests/test-phase-precondition.sh:377-414) — the
  FOREIGN-PROJECT-ROOT-GUARD-01 fix.

**Isolation proof (mission-required):** live registry
`~/.claude/leadv2-state/leadv2/active.yaml` sha256
`704aa737fd7d38ee3ed27825b41e84c265cc4dcdb1c2db587ee830b74a1c3bb4`
before run A, and identical after A, B, C, D, the paired-negative runs and
the final base-red runs. Not one suite run in this round touched it.

## 2. What the two remaining reds are, and what was done

### 2a. `test-idle-lead-guard` case 10 — in-lane red is a stale-checkout artifact; fix complete; assert unsilenced

Binary question from the lead's correction — should `leadv2-idle-lead-guard.sh`
be registered in hooks.json? **No.** Evidence:

- `git show --stat c49cc9fb -- plugins/leadv2/hooks/hooks.json` → merge
  ONE-LANE-WATCH-01 "one self-arming lane watcher replaces the idle-guard
  pair" rewired hooks.json there (19 insertions, 14 deletions).
- Probe of `git show main:plugins/leadv2/hooks/hooks.json`:
  `main Stop has idle-lead-guard: False`, `main SessionStart arm: True`,
  `main SessionEnd disarm: True`.
- Live plugin cache
  (`~/.claude/plugins/local/leadv2/plugins/leadv2/hooks/hooks.json`):
  `grep -o "leadv2-idle-lead-guard..."` → 0 matches; `grep -c
  lane-watch-v2` → 2. The live install registers the replacement, not the
  retired hook.
- `git grep -l "leadv2-idle-lead-guard" main -- plugins/leadv2` → only
  `commands/leadv2.md` (docs), `scripts/leadv2-lane-watch-v2.sh` (three
  comments where the successor documents its inheritance), a test fixture,
  and this suite. No hook-path caller exists.

So main's pre-round-2 case 10 asserts a contract that does not exist, and
the lane's da8407a8 rewrite (retired hook absent + promise-guard kept +
lane-watch-v2 on both events) asserts the live one — green on the main
clone (run C). No hooks.json edit is needed anywhere; the correction's
"if the answer is 'register it', report and stop" branch does not trigger.

Why the lead's in-worktree run was red: this lane forked at `10fe3d6e`,
`git merge-base --is-ancestor c49cc9fb HEAD` → NOT an ancestor — the lane's
checked-in hooks.json predates the retirement (`git diff main --stat` on
it: 118 lines drift; probe: worktree Stop still has idle-lead-guard=True,
arm/disarm=False). hooks.json is outside LANE_WRITES, so the lane is not
allowed to freshen it; the merge reconciles it. Expected and documented in
round 2; now also self-explaining (below).

**Round-3 code change (lead order: "сними 2>/dev/null с этого ассерта"):**
the assert's stderr is captured instead of discarded; the FAIL line now
carries the single explaining line (the AssertionError, which names the
broken sub-contract and lists the actual hook array). In-lane run after
the change:

```
[TEST] FAIL: case 10: registration assertion failed — AssertionError: retired idle-lead-guard still registered in Stop: ['"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-force-reflect.sh"', ..., '"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-idle-lead-guard.sh"']
[TEST] idle-lead-guard: PASS=18 FAIL=1
```

The instrument no longer hides the answer. On the main clone the same
edited suite is green: rc=0, PASS=19 FAIL=0.

### 2b. `test-phase-precondition` — both fails are one stale-file case; nothing to re-fix

The two FAIL lines are the two assertions of case F1 (unhashable
directory-artifact refusal): "should refuse with rc=5 (got rc=0)" and
"refused record must not be written". Controlled pair, same test code:
in this worktree rc=0 from the product file (→ fail=2); on the
current-main clone F1 passes (pass=82 fail=0, run C). The only variable
is the vintage of `plugins/leadv2/scripts/leadv2-phase-record.sh`, which
is 390 lines drifted behind main in this lane (`git diff main --stat`),
off-limits to this lane (occupied file list). Round-2's actual fix
(glm-stub envelope) is intact and green on current main; **no code change
made or needed this round for this suite.**

## 3. Paired negative control (round-3 change)

On the main clone (lane files applied): re-added
`leadv2-idle-lead-guard.sh` to hooks.json's Stop array via a python
mutation → rc=1, `FAIL: case 10: registration assertion failed —
AssertionError: retired idle-lead-guard still registered in Stop: [... 7
entries ...]` (the new diagnostics name the regression). `git checkout --
hooks.json` → rc=0, PASS=19 FAIL=0.

## 4. Base must stay red — final check

Pure main clone at `587625e7` (lane files removed):
- test-idle-lead-guard: rc=1, PASS=18 FAIL=1 (case 10) — red.
- test-phase-precondition: rc=1, `FAIL: G3: dispatch should exit 0 (got 4)`,
  pass=81 fail=1 — red.

Base is still red at current main tip → the green in run C comes from this
lane's diff, not from drift on main.

## 5. Falsification set

- `bash -n plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` → OK
  (only shell file changed this round).
- Python files changed: none (inline python only; `py_compile` N/A;
  `tests/mutations/catalog.yaml` is YAML data).
- `tests/run-all.sh --scope changed` → result appended in §6 when it
  completes.

## 6. Round-3 commits

- `3b0d30f5` ("fix(MAIN-CORE-SUITE-RED-01): round-3 case-10 diagnostics …")
  intentionally carries, besides the one-file test edit, three files that
  were sitting pre-staged in this worktree's index since round 2:
  `tests/mutations/catalog.yaml` (round 2's mutation-pair catalog — the
  artifacts round 2 failed to commit), and
  `docs/handoff/dispatch-faee3fc5/developer.{full,summary}.md` (this
  dispatch's own handoff artifacts). All three are this lane's own
  material, none touch the forbidden runtime-state paths, and leaving them
  staged was how round 2's work nearly got lost. Salvaging them under a
  lane-tagged subject is the fix, not a mistake.
