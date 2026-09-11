verdict: APPROVE
next_action: review_round_2

# Fix: two standing-red plugin test suites (test-only)

Both suites were RED on `main` (`717b16f`) with no lane involved, as reported in the mission.
Both were false-reds caused by the tests themselves, not the code under test. Only the two
test files were touched; `leadv2-route-bandit.sh`, `leadv2-phase8-close.sh`, and every other
production script were left untouched.

## R1 — `plugins/leadv2/scripts/tests/test-leadv2-route-bandit.sh` Test 9

### Root cause
`SCRIPT_DIR` resolves to `plugins/leadv2/scripts/tests`, so
`${SCRIPT_DIR}/../../docs/handoff` resolves to `plugins/leadv2/docs/handoff` — a directory
that is real, git-tracked, and legitimately contains committed mission docs under
`hermes-adopt/`. The old guard asserted this directory's absence, which is unconditionally
false on any checkout. Test 9's actual subject under test (route-decisions.yaml written to
the consuming-repo path via `LEADV2_PROJECT_ROOT`) was already correct — `rd_exists=1` proved
that — only the leak guard was wrong.

### Fix
Changed the guard to assert that THIS test's own artifact (`TEST-SELECT-03/route-decisions.yaml`)
does not exist inside the plugin tree, rather than asserting the whole `docs/handoff` dir is
absent:

```bash
local no_plugin_leak=1
if [[ -f "${SCRIPT_DIR}/../../docs/handoff/TEST-SELECT-03/route-decisions.yaml" ]]; then
  no_plugin_leak=0
fi
```

### Red-before / green-after demonstration

Before the fix, Test 9 failed unconditionally (verified on the unpatched tree at the start of
this task):

```
[TEST] FAIL: Test 9: rd_exists=1 no_plugin_leak=0; expected file at .../docs/handoff/TEST-SELECT-03/route-decisions.yaml
```

After the fix, to prove the new guard can still go RED for the right reason, I manually
recreated the leak artifact it's meant to catch and re-ran the suite:

```
$ mkdir -p plugins/leadv2/docs/handoff/TEST-SELECT-03
$ echo "leak" > plugins/leadv2/docs/handoff/TEST-SELECT-03/route-decisions.yaml
$ bash plugins/leadv2/scripts/tests/test-leadv2-route-bandit.sh
[TEST] FAIL: Test 9: rd_exists=1 no_plugin_leak=0; expected file at /var/folders/.../bandit-test.CJ8pzg/docs/handoff/TEST-SELECT-03/route-decisions.yaml
```

Then removed the manually-created artifact (`rm -rf plugins/leadv2/docs/handoff/TEST-SELECT-03`)
and confirmed `git status --porcelain plugins/leadv2/docs/handoff/` shows only the pre-existing
`hermes-adopt` dir — no stray artifact left behind.

Full suite after fix (clean tree, no manual artifact):

```
[TEST] === Results: PASS=10 FAIL=0 ===
[TEST] All tests passed.
```

## R2 — `plugins/leadv2/scripts/tests/test-leadv2-phase8-learn-counter.sh` Test 7

### Root cause
`lv2_mktemp_dir()` (`plugins/leadv2/scripts/leadv2-temp.sh:20`) builds its template as
`"${TMPDIR:-/tmp}/${label}.XXXXXX"`. On macOS, `TMPDIR` ends in `/` by default, so the
resulting `tmp_unrelated` path carries a literal double slash
(`.../T//mw-fix-unrel.RNGLn8`). `r_unrelated` is computed by `cd "$tmp_unrelated" && bash -c
"$snippet"`, and the snippet's fallback branch (no `docs/leadv2` marker present) resolves via
plain `pwd` — which normalizes the double slash away as a side effect of `cd`. The test then
compared the raw (double-slash) `tmp_unrelated` against the normalized `r_unrelated`, so it
false-failed even though the resolution logic under test was correct. `tmp_main`/`tmp_wt`
didn't show this because both sides of *those* assertions were already run through the same
`pwd -P` normalization.

### Fix
Added `tmp_unrelated_real`, computed the same way `r_unrelated` itself was produced — `cd
"$tmp_unrelated" && pwd` (no `-P`, since the fallback path doesn't resolve symlinks either) —
and compared against that instead of the raw mktemp path. Updated the failure message to
match.

### Red-before / green-after demonstration

Before the fix (verified on the unpatched tree at the start of this task):

```
[TEST] FAIL: Test 7: expected main='.../mw-fix-jsmain.ymuGC7' wt='.../mw-fix-jsmain.ymuGC7' unrelated='/var/folders/.../T//mw-fix-unrel.RNGLn8'; got main='.../mw-fix-jsmain.ymuGC7' wt='.../mw-fix-jsmain.ymuGC7' unrelated='/var/folders/.../T/mw-fix-unrel.RNGLn8'
[TEST] === Results: PASS=6 FAIL=1 ===
```

After the fix:

```
[TEST] PASS: Test 7: main->main ('.../mw-fix-jsmain.uedmIK'), worktree->main ('.../mw-fix-jsmain.uedmIK'), unrelated->fails-safe-to-own-pwd ('.../mw-fix-unrel.iatr8C')
[TEST] === Results: PASS=7 FAIL=0 ===
[TEST] All tests passed.
```

## Diff scope

```
$ git status --porcelain
 M plugins/leadv2/scripts/tests/test-leadv2-phase8-learn-counter.sh
 M plugins/leadv2/scripts/tests/test-leadv2-route-bandit.sh
```

Only the two named test files changed. Neither `leadv2-route-bandit.sh`, `leadv2-phase8-close.sh`,
nor any other production script was touched. Neither suite was added to any known-failures
registry, per the mission constraint.

## Left alone / not in scope

- The broader `.claude/scripts/tests/` drift noted in the standing open-thread
  (`docs/leadv2/open-threads.md`) is unrelated to this task and was not touched.
- No production logic was changed; if either guard's underlying behavior (route-decisions
  path resolution, `_durable_root`/JS one-liner resolution) is ever suspected to be wrong,
  that is a separate, non-test-file task.

DELIVERABLE_COMPLETE
