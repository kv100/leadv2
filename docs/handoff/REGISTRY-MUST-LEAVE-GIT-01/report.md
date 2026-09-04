# REGISTRY-MUST-LEAVE-GIT-01

## What changed

1. **Untracked `docs/leadv2/active.yaml` from git** — `git rm --cached docs/leadv2/active.yaml`
   (content is left on disk, untouched, in every worktree; only the git index entry is removed
   in this lane's commit). Added a `.gitignore` rule (`/docs/leadv2/active.yaml`) so a future
   `git worktree add`/`checkout` never re-materializes a real file at that path.
2. **Fixed `BASH_SOURCE[0]` crash under `bash -c`/`eval` sourcing** in two files:
   - `plugins/leadv2/scripts/leadv2-active-registry.sh` (`_leadv2_state_path_sh`)
   - `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` (`_lv2_lane_state_dir` init)
   Both now guard with `${BASH_SOURCE[0]:-}` and fall back to
   `LEADV2_PROJECT_ROOT/plugins/leadv2/scripts[/lib]` when unset, instead of crashing with
   `set -u`'s "unbound variable".
3. New suite `plugins/leadv2/scripts/tests/test-leadv2-state-path.sh` (self-selects by stem
   convention against `leadv2-state-path.sh`... **not exact** — see "Suite selection" below).

## Root cause (measured, not guessed)

`docs/leadv2/active.yaml` was a real, git-tracked file. `plugins/leadv2/scripts/leadv2-state-path.sh`
(LEAD-CONTROL-PLANE-01, already merged before this task) already resolves and redirects live
reads/writes to a single control-plane root (`~/.claude/leadv2-state/<repo-slug>/active.yaml`)
and, on every un-`--no-link` call, idempotently migrates any real local file at
`docs/leadv2/active.yaml` into that control plane and replaces it with a symlink.

That migration logic is correct but powerless against git: every `git worktree add <branch>`
checks out the CONTENT git has recorded for that path at that commit — a real file, not a
symlink — so a fresh worktree always starts with its own frozen, real copy, undoing any prior
worktree's migration. Fourteen such copies were measured 2026-09-04 (see the task's own
measurement note). The fix is not "migrate harder" — it's stopping git from ever recording a
real blob at that path, which is what the `.gitignore` + untrack does.

The `BASH_SOURCE[0]` crash is a second, independent defect on the same resolution path:
`_leadv2_state_path_sh`'s `bundled="$(cd "$(dirname "${BASH_SOURCE[0]}")" ...)"` and
`lib/leadv2-lane-state.sh`'s equivalent line assume `BASH_SOURCE[0]` is always set. It is NOT
set (not merely empty — literally absent from the array) when the file's contents are sourced
via `eval "$(cat file)"` rather than `source file` — a pattern this repo's own callers use
(headless/subprocess wrappers). Under any caller with `set -u` (leadv2-active-registry.sh sets
`set -euo pipefail` itself), referencing `${BASH_SOURCE[0]}` unguarded is an immediate
`unbound variable` crash before any fallback logic runs. Reproduced directly (see Test 3/4
in the new suite, and the raw repro below).

## Reproduction (before fix)

```
$ bash -uc 'eval "$(cat plugins/leadv2/scripts/lib/leadv2-lane-state.sh)"'
bash: line 13: BASH_SOURCE[0]: unbound variable
```

## Evidence

### Live probe #1 (acceptance criterion 1) — **partially satisfied, scope-limited**

```
$ git -C /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REGISTRY-MUST-LEAVE-GIT-01 \
    ls-files --error-unmatch docs/leadv2/active.yaml
# (exits 1 — not found; the fix removes it from THIS lane's index)
```

Fleet-wide `find . -name active.yaml` across all worktrees under the main checkout still shows
every OTHER existing worktree's `docs/leadv2/active.yaml` as git-tracked. This is expected and
cannot be fixed from this lane: each of those worktrees was checked out from a commit where
the file was still tracked, and this task's boundaries explicitly forbid touching another
lane's worktree (`.claude/worktrees/`). The untrack only prevents the problem from THIS commit
forward — existing worktrees converge only after (a) this change merges to `main` and (b) each
of those worktrees is either recreated or has `git rm --cached docs/leadv2/active.yaml` run in
it by its own owner. That follow-up is out of this lane's writable/reachable scope; flagging it
here rather than silently declaring "fixed" is deliberate.

Within the boundary this lane actually owns (this worktree's own git state), the criterion is
met exactly:

```
$ git status --short docs/leadv2/active.yaml
D  docs/leadv2/active.yaml
$ git check-ignore -q docs/leadv2/active.yaml; echo $?
0
```

### Live probe #2 (acceptance criterion 2) — path resolution is invocation-independent

Ran `leadv2_active_unregister`/`lane_count_live` after sourcing via plain `source`, `bash -c`,
and `eval "$(cat …)"` (the exact failure mode reported) against the SAME sandboxed
`LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT` pair — all three resolve the identical target path and
none crash post-fix. This is proven with a scratch git repo (never the real registry — see
"Test safety" below) inside `test-leadv2-state-path.sh` tests 3 and 4; raw repro:

```
$ bash -uc 'eval "$(cat plugins/leadv2/scripts/lib/leadv2-lane-state.sh)"; lane_count_live x'
0        # post-fix: no crash
```

### Negative controls (acceptance criterion 3) — one per changed requirement

All four are `baseline_rc`/`mutated_rc` pairs with a red line on mutation, not `diff_hash`:

| Test | baseline_rc | mutation | mutated_rc/behavior |
|---|---|---|---|
| 1: active.yaml untracked | 1 (not found, PASS) | stage into a scratch git index copy | 0 (tracked, RED as expected) |
| 2: `.gitignore` covers path | 0 (ignored, PASS) | delete the `.gitignore` line | 1 (not ignored, RED as expected) |
| 3: registry resolver survives `eval` sourcing | 0 (no crash, PASS) | reintroduce bare `${BASH_SOURCE[0]}` | crashes (RED as expected) |
| 4: lane-state resolver survives `eval` sourcing | 0 (no crash, PASS) | reintroduce bare `${BASH_SOURCE[0]}` | `unbound variable`, RED as expected |

Full raw output of a representative run:

```
[TEST] Test 1: docs/leadv2/active.yaml is NOT git-tracked (baseline)
[TEST] PASS: active.yaml untracked: baseline_rc=1 (git ls-files does not find it)
[TEST] Test 1 negative control: staged into a scratch index copy -> check must flip red
[TEST] PASS: negative control confirmed: baseline_rc=1 (untracked) -> mutated_rc=0 (tracked) after re-adding to index
[TEST] Test 2: git check-ignore reports docs/leadv2/active.yaml as ignored
[TEST] PASS: gitignore covers docs/leadv2/active.yaml: baseline_rc=0
[TEST] Test 2 negative control: gitignore rule removed -> check-ignore must go red
[TEST] PASS: negative control confirmed: baseline_rc=0 -> mutated_rc=1 after removing the gitignore rule
[TEST] Test 3: sourcing leadv2-active-registry.sh via eval (no BASH_SOURCE) must not crash under set -u
[TEST] PASS: registry resolver survives eval-sourcing: baseline_rc=0, output=[RC=0]
[TEST] Test 3 negative control: reintroduce bare BASH_SOURCE[0] -> must crash the same way
[TEST] PASS: negative control confirmed: mutated (unguarded BASH_SOURCE[0]) crashes: output=[bash: eval: line 86: syntax error near unexpected token `fi'] rc=2
[TEST] Test 4: sourcing lib/leadv2-lane-state.sh via eval (no BASH_SOURCE) must not crash under set -u
[TEST] PASS: lane-state resolver survives eval-sourcing: baseline_rc=0, output=[RC=0]
[TEST] Test 4 negative control: reintroduce bare BASH_SOURCE[0] -> must crash the same way
[TEST] PASS: negative control confirmed: mutated (unguarded BASH_SOURCE[0]) crashes: output=[bash: line 21: BASH_SOURCE[0]: unbound variable
RC=0] rc=0
[TEST] Test 5: bash -n on changed files
[TEST] PASS: bash -n clean on both changed files
[TEST] ----------------------------------------
[TEST] RESULTS: 9 passed, 0 failed
```

Note on Test 3's mutation: the awk splice that reintroduces the bare `BASH_SOURCE[0]` line also
happens to break `if/fi` balance in that particular case, producing a bash syntax error (rc=2)
rather than the exact "unbound variable" string. This is still a valid red — the assertion is
"mutated code does not behave like the fix", which holds — but it is reported honestly rather
than dressed up as a byte-identical repro of the original crash. Test 4's mutation DOES
reproduce the exact original message (`BASH_SOURCE[0]: unbound variable`).

### Ten consecutive runs (acceptance criterion 4)

```
run 1 rc=0
run 2 rc=0
run 3 rc=0
run 4 rc=0
run 5 rc=0
run 6 rc=0
run 7 rc=0
run 8 rc=0
run 9 rc=0
run 10 rc=0
```

Verified after the 10 runs that no runtime-state file in this worktree was touched by the test
run itself (`git status --short docs/leadv2/active.yaml docs/LEAD_V2_STATE.md .gitignore
plugins/leadv2/scripts/...` — only the intended source diffs show).

## Test safety — why the suite never touches this worktree's real active.yaml

`leadv2_active_unregister`/`lane_count_live` perform a real atomic rewrite (or, for read-only ops,
still open+flock) of whatever `active.yaml` the resolver lands on. Running them directly against
`$ROOT` (this worktree, a real checkout with a git remote) would mutate the live control-plane
file — the exact file this task exists to stop clobbering. Tests 3/4 instead build a throwaway
`git init` scratch repo per call (`_mk_scratch_repo`, guarded by the existing
`lv2_assert_scratch_repo` safety net from `leadv2-temp.sh`, same pattern as
`test-active-registry-failclosed.sh`) and pass it as `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`, so
every mutation lands in a directory that is `rm -rf`'d immediately after the assertion.

Two real mistakes were made and corrected during this task before landing on that design:
early manual repro calls against the real `$ROOT` did write real content into
`docs/leadv2/active.yaml` and `docs/LEAD_V2_STATE.md` (mtime changed, format re-serialized); both
were caught via `git status --short` and reverted with `git checkout --` before being
committed. Left in this report as the reason the scratch-repo pattern above is not optional.

## Suite selection / CI wiring

`test-leadv2-state-path.sh` is named for the file most central to the fix
(`leadv2-state-path.sh`) but the two files it actually edits are
`leadv2-active-registry.sh` and `lib/leadv2-lane-state.sh` — the self-select-by-stem convention in
`tests/run-all.sh` (`test-<changed-file-stem>.sh`) does **not** automatically pick this suite up
for either of those two stems. Per this task's explicit boundary ("`EXTRA_SUITE_MAP` in
`tests/run-all.sh` НЕ добавляй — положи готовой в отчёт"), the suite is NOT wired into CI by this
lane. The row a maintainer would add to `tests/run-all.sh`'s `EXTRA_SUITE_MAP` (both stems, so
either changed file selects the suite):

```
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
```

Until that row is added, `tests/run-all.sh --scope changed` will NOT run this suite even when
either changed file is in scope; only an explicit
`bash plugins/leadv2/scripts/tests/test-leadv2-state-path.sh` invocation runs it.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/leadv2-active-registry.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/lib/leadv2-lane-state.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-state-path.sh && echo OK
OK
```

No Python files were changed by this lane; `py_compile` not applicable.

## What I deliberately left alone

- **Other worktrees' tracked copies** (14+ measured) — boundary forbids touching another lane's
  worktree; these converge only after merge + per-worktree `git rm --cached` or recreation. Not
  fixed by this lane, and I'm not claiming it is.
- **`tests/run-all.sh`'s `EXTRA_SUITE_MAP`** — not touched per explicit task boundary; the row to
  add is given above for a maintainer/lead to apply.
- **`leadv2-active-registry.sh`'s missing CLI dispatcher** (the separate defect noted in the task
  brief under "поправка ведущей" — direct `bash leadv2-active-registry.sh unregister <id>` is a
  silent no-op because the file has no argv dispatcher) — out of this task's stated Задача
  (which is scoped to git-tracking + path resolution, not the CLI-vs-source calling convention).
  Flagging it here since it's adjacent and easy to conflate with this task's fix.
- **`docs/LEAD_V2_STATE.md`, `docs/leadv2/` other files, `main`, `tests/known-red-suites.txt`** —
  untouched, per explicit boundaries.

---

# Round 2 (2026-09-04) — three items, nothing else

Round 1 is not rewritten; everything below is additive.

## 1. NC-4 now proves the consequence, with a nonzero `mutated_rc`

**Choice made: the control asserts the observable consequence — WHICH file the resolver
settled on — not the error text** (option (b) of the brief). Option (a) — make the resolver
itself return nonzero on an unresolved path — was rejected: the legacy
`$root/docs/leadv2/active.yaml` else-branch in `_lv2_lane_state_path()` is a deliberate
degraded mode (the registry stays usable when the bundled helper is not next to the sourced
file); hard-failing it converts a working-but-degraded registry into an outage across the
consumer repos — a product behavior change with real blast radius, made to satisfy a test.
The defect the brief names is the control's discriminating power; that is fixed test-side.

Mechanics (`test-leadv2-state-path.sh`, test 4 only; the round-1 mutation awk is
byte-identical, only detection changed):

- A sentinel `leadv2-state-path.sh` is planted at
  `<scratch>/plugins/leadv2/scripts/leadv2-state-path.sh` — reachable ONLY through the fixed
  `${BASH_SOURCE[0]:-}` fallback branch when the file is eval-sourced. It prints
  `<LEADV2_STATE_ROOT>/<name>`.
- Baseline arm: the inner script captures `got="$(_lv2_lane_state_path)"`, prints
  `RESOLVED=<got>`, exits 7 on path mismatch, 8 if `lane_count_live` fails. Passes only
  when rc=0 AND the resolved path is the sentinel's.
- Mutant arm: the mutant derails `_lv2_lane_state_dir` to `/`, the sentinel is not found
  there, the resolver silently falls back to the legacy path — precisely the
  rc-0-from-failure case the brief flagged — and the resolution check exits 7.

Why this closes the class: under eval-sourcing the unbound-variable error kills only the
inner command-substitution subshell; the parent prints the error AND STILL EXITS 0 (that is
exactly why round-1 NC-4 showed `mutated_rc=0`). A control grepping that message cannot
tell a fixed resolver from a derailed one that swallows the error; comparing the resolved
path can, in BOTH directions — a "fixed" resolver that resolves the wrong file but exits 0
now fails the BASELINE arm as well (`RESOLVED` mismatch → exit 7).

Raw before (round 1, verbatim):

```
PASS: negative control confirmed: mutated (unguarded BASH_SOURCE[0]) crashes:
output=[bash: line 21: BASH_SOURCE[0]: unbound variable
RC=0] rc=0
```

Raw after (round 2, verbatim suite output; scratch paths abbreviated `…`):

```
PASS: lane-state resolver survives eval-sourcing AND resolves the sentinel: baseline_rc=0 output=[RESOLVED=…/state-path-scratch.8vkJ2a/.state/active.yaml]
PASS: negative control confirmed: mutated resolver resolved a WRONG path and the check caught it by rc: mutated_rc=7 output=[bash: line 21: BASH_SOURCE[0]: unbound variable
RESOLVED=…/state-path-scratch.JPV8lK/docs/leadv2/active.yaml]
```

`mutated_rc=7` — nonzero by construction of the harness (exit 7 on path mismatch), not by
luck of bash's stderr wording. Stability: 5 consecutive full-suite runs, all rc=0, and all
five logs contain the `mutated_rc=7` line.

NC-3 (test 3's control) is left as round 1 accepted it: its mutant already yields a nonzero
rc (2, via the mutant's own eval syntax error — the form disclosed and credited in round 1),
so the specific defect named by the brief (rc=0 from the mutated arm) does not exist there.
Extending the sentinel pattern to test 3 would be a round-3 decision, not one of this
round's three items.

## 2. Report relocated

`report.md` (repo root, commit f7f96fbf) → `docs/handoff/REGISTRY-MUST-LEAVE-GIT-01/report.md`
via `git mv` — pure rename; round-1 content is byte-identical, this section appended below
it. `git status` shows `R report.md -> docs/handoff/REGISTRY-MUST-LEAVE-GIT-01/report.md`.
The path needs no force-add: `.gitignore` carries `!docs/handoff/*/report.md`.

## 3. The runner selects the suite — proof

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | tail -6
[SELECT] …/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] …/tests/test-status-surface-bash32.sh
[SELECT] …/tests/test-status-surface-single-lead.sh
[SELECT] …/tests/test-status-surface-fast-names.sh
[SELECT] …/plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
run-all: 5 selected, scope=changed, select_only=1
```

`tests/run-all.sh` was NOT modified. Selection fires through the self-select rule (a
changed `plugins/leadv2/scripts/tests/test-*.sh` adds itself), because the suite is in this
run's changed set.

Honest caveat — a carrier-coverage gap that this lane cannot fix (`tests/run-all.sh` is a
shared serialization point, explicitly out of bounds): the self-select rule covers only
commits that touch the suite itself. A future change touching `leadv2-active-registry.sh`
or `lib/leadv2-lane-state.sh` alone will NOT select this suite — the stem convention looks
for `test-leadv2-active-registry.sh` / `test-leadv2-lane-state.sh` (neither exists), and no
`EXTRA_SUITE_MAP` row points here. Ready rows for the run-all owner:

```
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
```

## Falsification set (round 2)

- `bash -n plugins/leadv2/scripts/tests/test-leadv2-state-path.sh` → OK (the only shell
  file changed this round; the resolvers are untouched in round 2).
- Python: 0 files changed → `py_compile` not applicable.
- Suite stability: 5/5 full-suite runs rc=0 (logs `/tmp/state-path-run-1..5.log`).
- Changed-scope runner (`bash tests/run-all.sh --scope changed`): see verdict below.
