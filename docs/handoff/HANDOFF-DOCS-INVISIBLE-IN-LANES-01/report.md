# HANDOFF-DOCS-INVISIBLE-IN-LANES-01 — report

Two distinct causes made a lead's handoff doc invisible to the worker it was written for.
Both are fixed in this lane.

## Cause 1 — durable handoff docs sit untracked, `.gitignore`'s negations are correct but nobody `git add`s them

### Census (measured against the main checkout, not this worktree — a worktree only ever
contains tracked content, so the leak itself is invisible from inside a worktree)

```
$ find docs/handoff -type f | wc -l
    7674
$ git ls-files docs/handoff | wc -l
    2134
$ git ls-files --others --exclude-standard -- docs/handoff | wc -l
     275
```

- 7674 files on disk under `docs/handoff/`.
- 2134 already tracked.
- 5265 correctly gitignored generated scratch (dispatch.log, developer.stream.jsonl,
  costs.yaml, session maps, locks, regenerated diffs — verified with `git check-ignore -v`
  against samples of each).
- **275 files are the durable handoff leak**: untracked, but NOT excluded by `.gitignore` (a
  plain `git add` would stage every one of them right now — verified with `git check-ignore -v`,
  exit 1/no match, on every category below). They are simply never `git add`ed.

Breakdown of the 275 leaked files by basename (`sed -E 's#.*/##; s/[0-9]+/N/g' | sort | uniq -c`):

```
  83 architect-prepass.md
  70 fix-round-N.md
  43 context.yaml
  38 .gate1-passed
  26 brief.md
  11 divergence.md
   2 report.md
   2 round3-red/before*-renders.md   (BROAD-STATUS-ROWS-02, depth-5 negative-control evidence)
```

The census separates the 275 durable candidates from the generated bulk rather than treating
every file as authored:

| Census bucket | Name patterns | Files | Treatment |
| --- | --- | ---: | --- |
| Human/worker-authored docs and curated negative-control evidence | `brief*.md`, `fix-round*.md`, `divergence.md`, `report.md`, `round*-red/*` | 111 | Track retroactively |
| Durable gate evidence already explicitly allowlisted by the phase-gate contract | `architect-prepass.md`, `context.yaml`, `.gate1-passed` | 164 | Track; these are not scratch |
| Generated scratch | `*.log`, `*.jsonl`, `costs.yaml`, locks, session maps, regenerated diffs and phase-state subtrees | 5265 | Keep ignored |

The 164-file middle bucket is deliberately called out: it is machine-produced or machine-marked
evidence, but the existing phase-gate contract requires these exact top-level artifacts to remain
committable. It is not the generated bulk swept into the retroactive commit.

Every one of these already matches an existing `.gitignore` negation
(`!docs/handoff/*/architect-prepass.md`, `!docs/handoff/*/fix-round*.md`,
`!docs/handoff/*/context.yaml`, `!docs/handoff/*/.gate1-passed`, `!docs/handoff/*/brief*.md`,
`!docs/handoff/*/divergence.md`, `!docs/handoff/*/report.md`, `!docs/handoff/*/round*-red`) —
i.e. the boundary between authored and generated is already correctly drawn in `.gitignore`.
The gap is behavioural, not a missing pattern: the lead has been relying on remembering
`git add -f` per lane (per brief.md), and 275 files show it isn't remembered reliably.

One genuine pattern gap found by the census: `continue-round-*.md` (the exact filename named
in brief.md's FREEPOOL example) has **no** negation of its own. It happened to survive by luck
— its two on-disk instances were already force-added by the lead — but a *fresh*
`continue-round-N.md` would be blanket-ignored today. Added.

### `.gitignore` change

```
 !docs/handoff/*/fix-round*.md
+!docs/handoff/*/continue-round*.md
 !docs/handoff/*/context.yaml
```

One line. No other pattern was missing — the census showed the existing negations already
cover every authored-doc category on disk.

## Cause 1, item 3 — the regression test

`plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh` (from prior task
HANDOFF-ARTIFACTS-GITIGNORED-01) proves the `.gitignore` patterns make authored docs
*addable*. It does not catch the actual regression: a worker writes brief.md and simply never
runs `git add` — a pattern being correct doesn't self-execute.

New suite: `plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh`. It defines a
detector (`find_leaked_handoff_docs`): scans `git ls-files --others --exclude-standard --
docs/handoff` and flags any hit matching an authored-doc convention. Red → green, on a
fixture, per the DoD:

```
PASS: 1: RED — untracked brief.md, continue-round-2.md, round1-red/ proof all flagged as leaked
PASS: 2: transient dispatch.log (gitignored) is not reported as a leak
PASS: 3: GREEN — after `git add`, the same fixture reports zero leaks
PASS: 4: tracking one doc clears it while the still-untracked one stays flagged
test-handoff-docs-not-leaked: 4 passed, 0 failed
```

Registered in `tests/run-all.sh`'s `EXTRA_SUITE_MAP` under the existing synthetic `gitignore`
stem (the same stem HANDOFF-ARTIFACTS-GITIGNORED-01 wired up for `.gitignore` changes).
Selection proof (`LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`, run with only
this lane's `.gitignore`/`tests/run-all.sh`/script changes staged):

```
[SELECT] .../plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 8 selected, scope=changed, select_only=1
```

## Cause 1, item 4 — retroactive tracking

Committed separately (`1f6dc786`, on this lane branch, before the fix commit): all 275 durable
handoff candidates, copied byte-for-byte from the main checkout into this worktree at identical paths, then
`git add`ed with no `-f` (proving the existing `.gitignore` allowlist already accepts them) and
committed as one commit.

```
git diff --cached --stat | tail -1
 275 files changed, 38437 insertions(+)
```

No generated scratch was swept in — the commit's file list is exactly the 275-line census
output above; `dispatch.log`/`*.jsonl`/`costs.yaml`/session-map/lock files were never staged
because they were never candidates (still correctly gitignored).

## Cause 1, item 5 — repo size impact

```
du -ch <the 275 files> | tail -1
 3.1M    total
```

275 files / 38,437 lines / 3.1M added to the repo. Not hidden: this is the accumulated backlog
of a bug that has been running since HANDOFF-ARTIFACTS-GITIGNORED-01 (2026-08-31) made these
files addable but nothing made them added. It should not recur at this scale — the new suite
(above) is exactly the mechanism that stops it from silently reaccumulating.

## Cause 2 — found mid-task, via `brief-addendum-second-cause.md`: tracking a brief is not
## sufficient if the lane worktree forked before the commit reached it

The addendum (auto-merged into this lane from `origin/main` at 974932a7, timestamped
2026-09-03T04:36Z) measured a second, independent failure: `leadv2-lane-worktree.sh`'s
`pick_base()` always preferred `origin/main` over local `main` whenever `origin/main` existed
at all — even when `origin/main` was **behind** local `main`. The lead commits a brief and
deliberately withholds the push (a push cancels an in-flight CI run through the workflow's
concurrency group). The next lane worktree then forks from a stale `origin/main` with no
`docs/handoff/<id>/` at all. Measured proof from the addendum: two lanes (`LANE-PLACEMENT-PIN-RED-01`,
this one), two arms, `arm_produced_nothing` → `empty_diff`, purely because the brief was one
push away — indistinguishable from "the model produced nothing" without reading the addendum.

### Chosen fix

The addendum offered three options and asked for a justified choice. Rejected:

- **Branch from local `main` unconditionally** — would reintroduce the reason `origin/main`
  was preferred in the first place (the comment it replaces: "origin/main (saw sibling
  landings) > main" — another push landing ahead of a stale local main).
- **Refuse to dispatch when the mission names a missing file** — attractive (fails loudly) but
  requires parsing free-form mission text for file references, is a much larger surface
  (`leadv2-dispatch-code.sh`, 77 commits/90d, flagged "needs care" in this repo's own
  CLAUDE.md), and treats the symptom rather than the cause.

**Implemented**: `pick_base()` in `plugins/leadv2/scripts/leadv2-lane-worktree.sh` now compares
`origin/main` and `main` with `git merge-base --is-ancestor` and forks from whichever is NOT
behind the other — the descendant, not a fixed preference:

- `origin/main` is an ancestor of `main` → `main` is at least as fresh → fork `main` (the
  addendum's scenario, now fixed).
- `main` is an ancestor of `origin/main` → `origin/main` has sibling landings → fork
  `origin/main` (the original protection, preserved).
- Diverged (neither is an ancestor of the other) → fork `main` (what the lead just committed
  and is dispatching against), but `log_error` loudly rather than silently guessing — this is
  a genuinely ambiguous case and the script's own contract is "exit codes: 0 always, never
  silently wrong in the direction that reproduces this bug" is not achievable without breaking
  that contract, so it is surfaced instead of hidden.

Added a `[[ "${BASH_SOURCE[0]}" == "$0" ]]` guard around the CLI dispatch (same idiom already
used by `leadv2-dispatch-ledger.sh` / `leadv2-review-findings.sh` in this repo) so the function
can be sourced and unit-tested without also running `usage; exit 2`.

### Test: `plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh`

```
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: no origin/main ref -> main
PASS: 2: origin/main ahead (sibling landing) -> origin/main preserved
PASS: 3: main ahead of origin/main (unpushed brief) -> main (regression fixed)
PASS: 4: diverged refs -> main, with a loud diverged warning (never silent)
test-lane-worktree-base-pick: 5 passed, 0 failed
```

Registered in `EXTRA_SUITE_MAP` under stem `leadv2-lane-worktree` (self-select-by-convention
would look for `test-leadv2-lane-worktree.sh`, which doesn't exist — the suite is named for the
behaviour, not the carrier). Selection proof: see the 8-suite `[SELECT]` list above, which
includes this suite.

## Regression check (existing suites, not touched by this diff)

```
$ bash plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
test-handoff-artifacts-tracked: 6 passed, 0 failed

$ bash plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh
Results: 22 passed, 1 failed
FAIL: dispatch-reap: no-worker + empty lane worktree NOT reaped (should be gone)

$ bash plugins/leadv2/scripts/tests/test-lane-worktree-resurrect-guard.sh
6 passed, 1 failed
FAIL: T1 registered + live pid: worktree re-created

$ bash plugins/leadv2/scripts/tests/test-lane-worktree-no-nesting.sh
Results: 0 passed(red->green), 0 failed, 3 green-pre-fix
```

Both `lane-worktree-isolation` and `resurrect-guard` failures were verified **pre-existing**:
re-ran both against the unmodified (pre-this-lane) `leadv2-lane-worktree.sh`
(`git show HEAD:plugins/leadv2/scripts/leadv2-lane-worktree.sh`) and got byte-identical
failures (same test name, same rc). Not weakened, not touched — these are environment-sensitive
findings unrelated to this diff, not fixed here.

```
$ bash -n <every changed .sh file>
OK: tests/run-all.sh
OK: plugins/leadv2/scripts/leadv2-lane-worktree.sh
OK: plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh
OK: plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh
```

No Python files were changed.

## Off-limits / DoD compliance

- `main` untouched — all work on `worktree-HANDOFF-DOCS-INVISIBLE-IN-LANES-01`.
- `.gitignore`'s blanket rule was NOT deleted, only extended by one negation line.
- No manual step required going forward: the census showed the *pattern* set was already
  complete except `continue-round-*.md` (now added); the remaining gap was behavioural
  (forgetting `git add`), which the new test suite exists to catch before it recurs.
- Diff does not touch `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*`
  — verified: none of the 275 retroactively-tracked files matched `dispatch-nw*`
  (`grep -c dispatch-nw /tmp/leak_final.txt` → 0), and `docs/LEAD_V2_STATE.md` /
  `docs/leadv2/*` show as unstaged working-tree churn from other concurrent sessions in
  `git status`, never staged or committed by this lane.
- Committed in this lane (two commits: `1f6dc786` retroactive tracking, plus this report +
  gitignore + both test suites + `pick_base` fix).

## Fresh falsification evidence (2026-09-03)

### Red control before the `pick_base()` fix

The old implementation from `origin/main` was run against a fixture where local `main` had
one unpushed commit and `origin/main` pointed at its parent:

```text
pre-fix pick_base choice=origin/main (expected main)
```

### Green after the fix

The focused suites and the strengthened end-to-end base test passed:

```text
PASS: 1: roundN-red/ artifact staged by plain git add (no -f)
PASS: 2: report.md + brief.md staged by plain git add (no -f)
PASS: 3a: transient dispatch.log still matched by check-ignore
PASS: 3b: plain git add is a no-op on ignored dispatch.log
PASS: 4: deleting a tracked proof artifact shows in git status
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
test-handoff-artifacts-tracked: 6 passed, 0 failed
PASS: 1: RED — untracked brief.md, continue-round-2.md, round1-red/ proof all flagged as leaked
PASS: 2: transient dispatch.log (gitignored) is not reported as a leak
PASS: 3: GREEN — after `git add`, the same fixture reports zero leaks
PASS: 4: tracking one doc clears it while the still-untracked one stays flagged
test-handoff-docs-not-leaked: 4 passed, 0 failed
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: no origin/main ref -> main
PASS: 2: origin/main ahead (sibling landing) -> origin/main preserved
PASS: 3: main ahead of origin/main (unpushed brief) -> main (regression fixed)
PASS: 4: diverged refs -> main, with a loud diverged warning (never silent)
PASS: 5: ensure forks from local main and the committed brief reaches the lane
test-lane-worktree-base-pick: 6 passed, 0 failed
test-run-all-carrier-map: 5 passed, 0 failed
```

Changed-scope selection also proves the new suite is selected:

```text
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh
run-all: 5 selected, scope=changed, select_only=1
```

The real changed-scope runner was run in the foreground with `gtimeout --foreground 20` and a
one-suite core override to keep this lane within the explicit bound. Its raw terminal result was:

```text
[CORE-OFFLINE] suites passed=1 failed=0 missing=0 repo=.../HANDOFF-DOCS-INVISIBLE-IN-LANES-01
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
changed_scope_rc=124
```

That timeout is from the unrelated always-on status-surface T3 live-state probe; the changed
lane suite itself completed green immediately before it. No process was left running.

Shell falsification over every changed shell file:

```text
OK: bash -n plugins/leadv2/scripts/leadv2-lane-worktree.sh
OK: bash -n plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh
OK: bash -n plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh
OK: bash -n tests/run-all.sh
No changed Python files; `python3 -m py_compile` set is empty.
```
