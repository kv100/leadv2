# Adversarial review — V3-DISPATCHER-ACCEPTANCE-01 (lane b4042501)

Reviewer: critic (adversarial). Repo: `~/Projects/leadv2`, worktree
`~/Projects/leadv2/.claude/worktrees/b4042501`, branch `worktree-b4042501`.

## 0. Diff state — there is no commit

```
$ git rev-parse HEAD          -> 53d4465f00c5e37cff74aa04dd8840a5ec72a0e1
$ git rev-parse 53d4465       -> 53d4465f00c5e37cff74aa04dd8840a5ec72a0e1
$ git log --oneline 53d4465..HEAD   -> (empty)
$ git diff 53d4465...HEAD | shasum -a 256
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855   # sha256 of the EMPTY string
```

`HEAD == 53d4465`. The lane has **zero commits**. The requested review diff is empty; the
entire change set is uncommitted working-tree state. The mission's Acceptance clause says
"COMMIT on lane branch" — unmet.

Hashes of what actually exists (uncommitted):

| what | sha256 |
|---|---|
| `git diff -- plugins/leadv2/scripts/` (the real fix) | `4de5c51ed83c9a0cf638070d76e6e172104664278742a8a663c764bfd3268026` |
| `git diff` (all tracked modifications, incl. pollution) | `e6bb99ebc1a79bff98d916085b0faab226fcf1710dfad10a173e9a40377a8407` |

Any commit will change both hashes.

## 1. Uncommitted-change classification: MIXED

**FIX (keep):**
- `plugins/leadv2/scripts/claude-subsession.sh` (+45/-8) — Fault 1.
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (+105/-2) — Faults 2 and 3.
- 4 untracked test files under `plugins/leadv2/scripts/tests/`:
  `test-subsession-absolute-handoff-path.sh`, `test-subsession-soft-finish-dead-return.sh`,
  `test-foreign-project-root-guard.sh`, `test-dispatch-retry-dead.sh`.

**JUNK (must be reverted / cleaned before any commit):**
- `docs/leadv2/{active.yaml,bus.jsonl,open-threads.md,questions,merge-queue.jsonl,.bus.lock,.bus-offsets,.merge.lock,active.yaml.lock}` —
  these are **symlinks into shared leadv2 state**, and a test run repointed all nine into a
  now-deleted temp dir:
  ```
  docs/leadv2/active.yaml -> /var/folders/.../T//core-offline-run.7nERFQ/suite.vDIccp/
                             leadv2-rog1-home.juQJBa/.claude/leadv2-state/leadv2/active.yaml
                             exists=NO   (dangling)
  ```
  Verified dangling for `active.yaml`, `bus.jsonl`, `open-threads.md`. Committing these
  detonates the lane's whole state layer. Fix: `git checkout -- docs/leadv2/`.
- `docs/handoff/dispatch-{nw5sig005,nw9sig009,nwcm0012}/phases.d/{e2e,review}.yaml` —
  `started_at` bumped from `2026-08-09T14:39:19Z` to `2026-08-20T09:50:44Z` by a test run
  writing into **tracked live phase state**. These files declare
  `owner: leadv2-dispatch-product-close.sh:e2e_gate` — i.e. the test suite mutated state
  belonging to the file this lane was told not to touch. The script is untouched (off_limits
  honored in the letter), but its data was not.
- 14 untracked `docs/handoff/dispatch-*/` dirs (`ca00sig1`, `tasig001`, `50e51359`, …), each
  containing only `phases.d/` — test-fixture debris.
- Untracked `docs/leadv2/founder-status.md`, `docs/leadv2/status-snapshot.json`.

The temp-dir name `core-offline-run.7nERFQ` is direct evidence `run-core-offline.sh` was
started; the leftover dangling symlinks and stray handoff rows are what an **interrupted or
non-cleaning** run leaves behind. There is no artifact anywhere in the lane showing
run-core-offline finishing green. The Acceptance requirement "run-core-offline FOREGROUND
solo green in the lane" is unevidenced.

## 2. Fault 1 (PREPASS-RC1-RACE-01) — root cause plausible, fix partial

### What changed
`claude-subsession.sh:274-281` — `PER_TASK_BOILERPLATE` now advertises the **absolute**
`${HANDOFF_DIR}` instead of the relative `docs/handoff/${TASK_ID}/`.
`claude-subsession.sh:995-1012` — the SOFT_FINISH fallback's bare `return 0` is replaced by
a real `exit 0` (plus legacy-symlink creation and the `LABEL=…` line).

### Ordering is sound
`HANDOFF_DIR` is assigned at line 188, `PER_TASK_BOILERPLATE` at 274. No use-before-def.

### The SOFT_FINISH sub-fix is genuinely correct and genuinely load-bearing
Verified the block is top-level: the nearest preceding function definition is
`_detect_truncation()` at 914, closed at 943; line 995 sits inside a bare
`if [[ "$WAIT" == "1" ]]` at top level. A `return` there is a bash usage error, so execution
fell through to the exit-1 refusal path **after** printing "auto-promoting" and appending the
marker. That is an independent, real, previously-unreported bug — the strongest single item
in this diff.

### Root-cause evidence is a stub, not the incident
The comment claims the mechanism was "reproduced live by a fixture claude stub". A stub that
is *written to obey the prompt's own `Deliverable full:` line* will, by construction, write
relative-under-cwd before the fix and absolute-under-PROJECT_ROOT after it. That demonstrates
the boilerplate change works; it does **not** prove this was the mechanism behind the 09:26 /
09:46 live failures. Note also that `architect_prepass` exports `PROJECT_ROOT` into the
`subprocess.Popen` env (`leadv2-dispatch-code.sh:2652`), so `HANDOFF_DIR` and `adir`
(line 2707) are computed from the *same* root — which actively falsifies the mission's own
"different HANDOFF_DIR" hypothesis without a replacement live probe being offered. Verdict:
a defensible hardening, root cause **unproven against the live incident**.

### Residual inconsistency the fix leaves behind
`claude-subsession.sh:281` still hands the agent a **relative** path:
```
- Question proxy: .claude/scripts/ask-lead.sh ${TASK_ID} "<question>"
```
If the diagnosis is right (exec'd `claude` inherits an arbitrary cwd), the question proxy is
broken under exactly the conditions the deliverable path was just fixed for. Either both are
absolute or neither diagnosis holds.

### Fault 1 secondary — NOT DONE
The mission required: "verify a park can be cleared by a successful prepass (or add a
`--clear-park` path), test it." There is no `--clear-park`, no park-clearing change
(`grep -n 'clear-park\|clear_park'` → no hits), and no test. Silently dropped.

## 3. Fault 2 (mis-rooted lane worktree) — NOT FIXED on the live path

### The guard is opt-in and defaults to the buggy behavior
`leadv2-dispatch-code.sh:288-305`. The env-first precedence is preserved verbatim; the
cwd-wins override only runs `if [[ "${LEADV2_FOREIGN_ROOT_GUARD:-0}" == "1" ]]`. The flag is
set **nowhere** in the repo outside the new test:
```
$ grep -rn LEADV2_FOREIGN_ROOT_GUARD . --exclude-dir=.git
leadv2-dispatch-code.sh:282   (comment)
leadv2-dispatch-code.sh:291   (the gate)
tests/test-foreign-project-root-guard.sh:14,52,101
```
So on every real dispatch, the guard is inert and the 09:58 ENV-GUARDS incident recurs
byte-for-byte. The mission's requirement was unconditional: "explicit cwd-derived root must
win for repo selection, **or** refuse on mismatch with a loud journal line." Neither branch is
live. The code comment argues the decision "is a separate, reviewed decision this lane does
not make unilaterally" — but the lane's whole mandate was to make it.

### The test locks the bug in
`test-foreign-project-root-guard.sh` Case 2 asserts that with the flag off, the foreign-root
override **must not** fire ("legacy env-wins precedence preserved"). Confirmed: Case 2 and
Case 3 **pass on pristine pre-fix code** (`pass=2 fail=2` in the red run). Half this "red-first"
suite is a regression lock on the defect. Only Case 1 is genuinely red-first.

### The stated justification is weakened by the author's own Case 3
The rationale is that "50+ suites `git init` a throwaway repo and set CLAUDE_PROJECT_ROOT".
Case 3 documents that the shape most fixtures actually use is a **bare tmpdir with no `.git`**,
which the guard already ignores. The cited counter-example is a single suite
(`test-dispatch-architect-prepass-late-artifact.sh`). One conflicting fixture does not justify
shipping the production fault disabled; narrowing the predicate (e.g. only override when the
cwd root is not an ancestor/descendant of the env root, or gate on the fixture convention
rather than on production) was not attempted.

### NEW REGRESSION introduced on the healthy default path — proven
`_LV2_CWD_GIT_ROOT` is assigned **only** at line 292, inside the `if [[ -n "${_LV2_ENV_ROOT}" ]]`
branch *and* inside the `LEADV2_FOREIGN_ROOT_GUARD=1` sub-branch. The `else` branch at line 304
therefore always dereferences an unset variable:
```bash
else
  PROJECT_ROOT="${_LV2_CWD_GIT_ROOT:-$(pwd)}"   # _LV2_CWD_GIT_ROOT is ALWAYS empty here
fi
```
Pre-fix, that path was `$(git rev-parse --show-toplevel 2>/dev/null || pwd)`. Proven by
extracting both PROJECT_ROOT blocks and running them from a subdirectory of a git repo with
all four env roots unset:
```
--- OLD --- PROJECT_ROOT=/private/var/folders/.../tmp.5vJsLsCffY/myrepo
--- NEW --- PROJECT_ROOT=/private/var/folders/.../tmp.5vJsLsCffY/myrepo/sub/deeper
```
Any invocation with no `CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` / `PROJECT_ROOT` /
`LEADV2_PROJECT_ROOT` in env, launched from a subdirectory, now roots the entire control plane
(journal, `docs/handoff`, `active.yaml`, cache, ledger) at the subdirectory. This is the same
disease class as Fault 2, newly introduced by the Fault 2 fix, on the default path, with no
test covering it. **This alone is a blocker.**

Minimal fix: hoist `_LV2_CWD_GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"`
above the `if`, and add a test asserting subdir + no-env ⇒ git toplevel.

### Live proof the fault is still active
While running the lane's own `test-dispatch-retry-dead.sh` from this worktree, the run emitted:
```
[registry] rendered /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/LEAD_V2_STATE.md
```
— a leadv2 test, executed inside the leadv2 worktree, writing into **persona-engine**, via the
inherited `CLAUDE_PROJECT_DIR`. That is Fault 2, reproducing today, after the fix.

## 4. Fault 3 (duplicate_task_signature after dead worker) — implementation good, test broken

### The implementation is real and correct-by-probe
`cmd_retry_dead` (`leadv2-dispatch-code.sh:5069-5111`) reuses the existing
`_dispatch_worker_liveness` / `_dispatch_evidence_exists` / `_dispatch_abort_locked` helpers,
takes the dispatch lock, and refuses rather than forcing. All helpers verified to exist
(1849 / 1927 / 2187). The `^[a-f0-9]{8}$` arg validation is tight. Because the test is broken
(below), I probed the command directly against a hand-built ledger row:
```
dead PID  -> [leadv2-dispatch-code] dispatch_retry_over_dead_attempt task=deadbeef tokens=tok-deadbeef-1
             ledger row removed (file now empty)
alive PID -> dispatch_retry_dead_refused task=cafebabe reason=not_dead liveness=alive
             ERROR ... refusing   (rc=2, row left in place)
```
Both sanctioned behaviors work. Good design: it composes with the existing reclaim path
instead of duplicating it.

### But the regression test is RED in the lane
```
$ bash ./test-dispatch-retry-dead.sh
[TEST] FAIL: case1 setup: no ledger file written at .../cache-c1/dispatch-ledger/leadv2.jsonl
[TEST] FAIL: case2 setup: could not extract sig8 or ledger file missing
[test-dispatch-retry-dead] pass=0 fail=2     EXIT=1
```
Cause: the test relies on `LEADV2_DISPATCH_SPAWN=0` leaving a `pending` row, but the dispatch
rolls the reservation back — `dispatch_rolled_back reason=no_spawn_dry_run task=1a887c75` — so
no ledger file is ever created. **Both cases die in setup; `retry-dead` is never invoked at
all.** Fault 3 ships with zero passing coverage. Secondary: the test also resolves the wrong
ledger slug (`leadv2.jsonl` vs the fixture repo's own slug), so even a surviving row would not
be found.

## 5. Test-suite audit (red-first legs)

Executed against the lane (green) and against a pristine copy of the two scripts restored from
`HEAD` (red).

| suite | pristine (red) | lane (green) | red-first? |
|---|---|---|---|
| `test-subsession-absolute-handoff-path` | pass=0 fail=3 | pass=3 fail=0 | yes |
| `test-subsession-soft-finish-dead-return` | pass=0 fail=3 | pass=3 fail=0 | yes |
| `test-foreign-project-root-guard` | pass=2 fail=2 | pass=4 fail=0 | partial — Cases 2 & 3 are green pre-fix by design |
| `test-dispatch-retry-dead` | n/a | **pass=0 fail=2** | no — broken in setup |

`bash -n` clean on all six files. `shellcheck -S warning` on the two changed scripts surfaces
8 warnings, **all pre-existing** (SC1090 ×2, SC2046, SC2097/SC2098 ×3, SC1010 ×2) — none in
the new hunks. `claude-subsession.sh` is `set -euo pipefail`; `leadv2-dispatch-code.sh` is not,
so the unset `_LV2_CWD_GIT_ROOT` fails silently rather than erroring.

## 6. Behavior change on healthy dispatch paths

- **Fault 2 else-branch**: yes — see §3, silent PROJECT_ROOT relocation. Blocker.
- **Fault 2 guarded branch**: no, flag defaults off.
- **Fault 1 boilerplate**: prompt text only; when cwd already equals PROJECT_ROOT (the common
  case) the resolved path is identical. Low risk.
- **Fault 1 SOFT_FINISH**: strictly widens success (a run that previously exited 1 despite a
  promoted marker now exits 0). Intended, and it now creates the legacy symlink the primary
  branch creates. Low risk.
- **Fault 3**: new subcommand only; `case` arm added, no existing arm altered. No risk.

## 7. Off_limits

- `leadv2-dispatch-product-close.sh` — **untouched** (not in `git diff --name-only`). Its
  `phases.d` *data* was mutated by a test run (§1); the script itself is clean.
- routing order / ceilings — untouched.
- `supervise*` — untouched.

## 8. Required before this can pass

1. Fix the `_LV2_CWD_GIT_ROOT` else-branch regression + add the subdir/no-env test. (blocker)
2. Make Fault 2's guard live — default-on, or a loud refusal — and drop/invert Case 2, which
   currently certifies the defect. (blocker)
3. Repair `test-dispatch-retry-dead.sh` so it actually reaches `retry-dead`. (blocker)
4. `git checkout -- docs/leadv2/ docs/handoff/dispatch-nw*/` and remove the 14 stray
   `docs/handoff/dispatch-*/` dirs + `founder-status.md` + `status-snapshot.json` before
   staging. (blocker — dangling state symlinks)
5. Commit on `worktree-b4042501` with a run-core-offline green transcript attached.
6. Deliver Fault 1's secondary (park-clearing path + test), or explicitly renegotiate it.
7. Nits: make the `ask-lead.sh` line absolute too; set `JOURNAL_TASK` in `cmd_retry_dead` so
   `dispatch_retry_over_dead_attempt` reaches the task journal instead of stderr only
   (`emit()` at 1107 no-ops the journal write when `JOURNAL_TASK` is unset — the mission asked
   for a journal line).

VERDICT: FAIL
DIFF_HASH: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  (sha256 of `git diff 53d4465...HEAD` — EMPTY, HEAD == 53d4465, zero commits on the lane)
  Uncommitted scripts-only diff: 4de5c51ed83c9a0cf638070d76e6e172104664278742a8a663c764bfd3268026
  Uncommitted full tracked diff: e6bb99ebc1a79bff98d916085b0faab226fcf1710dfad10a173e9a40377a8407
