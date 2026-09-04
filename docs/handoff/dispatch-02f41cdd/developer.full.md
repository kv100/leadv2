verdict: APPROVE
next_action: continue

# CI-RUNS-THE-SUITES-01 — developer deliverable

## What changed (committed on `worktree-CI-RUNS-THE-SUITES-01`, commit `f3c08921`)

- `.github/workflows/test-suites.yml` — new workflow, two jobs:
  - `changed-scope`: on `push` (main) and `pull_request`, runs
    `tests/run-all.sh --scope changed` via `tests/ci-gate.sh changed`.
    `runs-on: macos-latest`, `timeout-minutes: 35`.
  - `full-scope-nightly`: on a daily `schedule` (06:00 UTC) and
    `workflow_dispatch`, runs `tests/run-all.sh --scope all` via
    `tests/ci-gate.sh all`. `runs-on: macos-latest`, `timeout-minutes: 120`.
  - Both jobs: checkout (`fetch-depth: 0`, needed by the allow-list guard's
    git-history diff), `setup-python` + `pip install pyyaml` (several
    `.py` helpers under `plugins/leadv2/scripts/` do `import yaml`), the
    known-red guard step, then the gated test run.
- `tests/ci-gate.sh` (new) — runs `tests/run-all.sh --scope <changed|all>`,
  parses its output for two failure shapes (`[CORE-OFFLINE] FAILED: <name>`
  for suites nested inside `run-core-offline.sh`, `[FAIL] <path>` for
  top-level `run-all.sh` suites), reconciles each against
  `tests/known-red-suites.txt`. Exits 0 only if every failure is
  allow-listed; otherwise exits 1 and prints the unexpected ones by name.
  Writes a markdown summary to `$GITHUB_STEP_SUMMARY` when present.
- `tests/known-red-suites.txt` (new) — 15 dated entries, one per suite that
  was already red on `main` when this was measured (2026-09-02), each with
  its exact `[CORE-OFFLINE] FAILED:` label, its script path, and why it's
  there. Header states the list may only shrink.
- `tests/known-red-guard.sh` (new) — compares the allow-list's entry count
  against the same file's entry count at a base ref (`origin/<PR base>` for
  PRs, `main` for pushes/schedule); fails if the count grew.

Nothing else in the tree was touched. `tests/run-all.sh`,
`run-core-offline.sh`, and the 15 red suites themselves are untouched —
fixing them is explicitly out of scope (`FIFTEEN-RED-SUITES-01`).

## Why macos-latest, not ubuntu-latest

`tests/test-status-surface-bash32.sh` (one of the three suites `run-all.sh`
always runs regardless of scope) calls the real `/bin/bash` by absolute path
specifically to catch bash-4+-only syntax the way SwiftBar's runtime (which
launches with Apple's frozen bash 3.2) would reject it. On `ubuntu-latest`,
`/bin/bash` is bash 5.x and that check would pass regardless of whether the
code is actually bash-3.2-safe — a false green on exactly the class of bug
this repo has been burned by twice (per CLAUDE.md: GATE-WRONG-ROOT-FALSE-DEAD-01
and its six-file audit). `macos-latest` runners are real macOS with Apple's
bash 3.2 at `/bin/bash`, so the check is meaningful. Cost note: GitHub bills
macOS-hosted minutes at ~10x the Linux rate — flagging this tradeoff rather
than silently picking the cheaper runner and losing the check's meaning.

## Measured wall time and the timeout it drove

`tests/run-all.sh --scope changed` **always** runs the full curated
83-suite `plugins/leadv2/scripts/tests/run-core-offline.sh` set regardless
of what changed (it's unconditionally added in `run-all.sh`), plus the 3
always-on `tests/test-status-surface-*.sh` suites, plus whatever the diff
selects on top. Three back-to-back timed runs on this dev box (a *shared*
machine — several other lanes' agents were running concurrently the whole
time, see the burn-digest note in this session's system reminders):

```
$ time bash tests/run-all.sh --scope changed   (clean tree)
... 16:59.40 total
$ time bash tests/ci-gate.sh changed            (clean tree, gate wrapper)
... 18:37.75 total
$ time bash tests/ci-gate.sh changed            (deliberately broken suite)
... 18:03.66 total
$ time bash tests/ci-gate.sh changed            (fixed again)
... 13:10.79 total
```

Range: ~13-19 minutes wall, all under machine contention from concurrent
lanes — likely an *overestimate* of a dedicated CI runner's time, but I only
have this box to measure on, so I did not round down. Set
`timeout-minutes: 35` for the push/PR job (roughly 2x the slowest observed
run, leaving headroom for CI-runner variance I can't measure directly).

`--scope all` was **not** measured live: it additionally sweeps every
`test-*.sh` under `plugins/leadv2/scripts/tests/`, `.claude/scripts/tests/`,
`plugins/leadv2/tests/`, and `tests/` — 345 files total (`find ... -name
'test-*.sh' | wc -l` = 345, vs. 83 curated inside `run-core-offline.sh`),
many with their own SERIAL locks and multi-second fixtures. Running that
live to get a real number would very plausibly run over an hour on this
same contended box, which I judged not worth spending given it only gates
the once-daily schedule, not every push. `timeout-minutes: 120` is an
extrapolation (not a guess from nothing: ~230 additional suites beyond the
83 already-measured, at a per-suite average pulled from the 17-minute
83-suite run), stated here as extrapolated so nobody mistakes it for a
measurement.

## Red blocks merge — and the part I cannot do from here

The workflow makes a red `changed-scope` job possible, but GitHub does not
block merges on a failing check by default — that requires a **branch
protection rule** on `main`: **Settings → Branches → Branch protection
rules → (rule for `main`) → "Require status checks to pass before
merging" → add the `run-all --scope changed` check** (the job's `name:` in
`test-suites.yml`). This needs repo-admin access to the GitHub UI or API,
which I do not have from this worktree. I am not claiming this is done —
naming the exact setting so whoever has admin access can flip it in under a
minute.

## Prove it

### 1. Clean-branch baseline: gate is green with only known-reds failing

```
$ bash tests/ci-gate.sh changed
...
run-all: 3 passed, 1 failed, scope=changed

ci-gate: scope=changed run_all_rc=1 known_red=15 unexpected=0
ci-gate: PASS — only known-red (allow-listed) suites failed:
  - core:landed-at-spawn (no terminal=landed at spawn; target repo keying)
  - core:dispatch arm vocabulary (kimi retirement)
  - core:phase precondition guard matrix
  - core:claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)
  - core:product-close scopes a single-repo lane worktree
  - core:codex-dead review reroute (QUOTA-GATE-PARITY-01)
  - core:idle-lead guard hook
  - core:review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)
  - core:deferred-GLM ladder (V3-GLM-LADDER-01)
  - core:review round cap (REVIEW-ROUNDCAP-01)
  - core:core-offline cross-run exclusive lock (SUITE-SPEED-01)
  - core:dispatch refusal fallback chain
  - core:Codex full-cycle runner
  - core:lane truth batch (log_path + quarantine convergence)
  - core:report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)
$ echo $?
0
```
(`run_all_rc=1` because the underlying `run-all.sh` still exits non-zero on
its own terms — the gate's allow-list reconciliation is what turns that
into a passing CI job, not a change to `run-all.sh` itself.)

One of the 15, `core-offline cross-run exclusive lock (SUITE-SPEED-01)` /
`test-core-offline-lock-01.sh`, passed 3/3 when run standalone three times
in a row (`[LOCK-01] pass=3 fail=0` every time) — it only fails inside the
full 83-suite run, which points at lock/timing contention under load, not a
logic bug. It stays on the allow-list because it IS one of the 15 that were
red at baseline inside the real `run-core-offline.sh` invocation
(`suites passed=68 failed=16 ... ` — 16 is a double-count: one of the 15,
`dispatch refusal fallback chain`, also dirtied `docs/leadv2` and got
counted twice by `run-core-offline.sh`'s own hermeticity gate, confirmed by
grepping `HERMETIC-VIOLATION (FAIL, lane-owned)` in the raw log — still 15
distinct suite names, matching the task brief's count exactly).

### 2. Break one suite deliberately → gate goes red and names it

Edited `tests/test-worktree-gc-plus-prefix.sh` (fast, 0.6s standalone, not
on the allow-list) to add one line before its summary block:
`fail "DELIBERATE-BREAK: proving tests/ci-gate.sh catches and names a real failure"`.

```
$ bash tests/ci-gate.sh changed
...
[TEST] FAIL: DELIBERATE-BREAK: proving tests/ci-gate.sh catches and names a real failure
FAIL: DELIBERATE-BREAK: proving tests/ci-gate.sh catches and names a real failure
[FAIL] /.../tests/test-worktree-gc-plus-prefix.sh
  Failures (blocking):
    - tests/test-worktree-gc-plus-prefix.sh
run-all: ... 1 failed ...

ci-gate: scope=changed run_all_rc=1 known_red=15 unexpected=1
ci-gate: FAIL — the following suites failed and are NOT on the known-red allow-list:
  - path:tests/test-worktree-gc-plus-prefix.sh
$ echo $?
1
```
Named explicitly (`path:tests/test-worktree-gc-plus-prefix.sh`), not just a
count. Wall time for this run: 18:03.66 (the diff-based selector picks up
any changed `tests/test-*.sh` file and runs it on top of the always-on set).

### 3. Fix it → green again

Reverted the one-line edit (`git diff` on the file after revert is empty —
byte-identical to the tracked version).

```
$ bash tests/ci-gate.sh changed
...
ci-gate: scope=changed run_all_rc=1 known_red=15 unexpected=0
ci-gate: PASS — only known-red (allow-listed) suites failed: [... same 15 ...]
$ echo $?
0
```

### 4. Negative control: remove the run-all step → detection stops

Made a `mktemp` copy of `test-suites.yml`, removed the
`run-all --scope changed` step (verified via diff: exactly those two lines
gone; remaining `changed-scope` steps confirmed via
`yaml.safe_load` + walk: `Checkout`, `Set up Python`, `Install PyYAML`,
`known-red allow-list guard (may only shrink)` — no step left that runs any
suite). Re-injected the same deliberate break, then ran only the steps that
survive in the negative-control copy (checkout/setup-python/install-pyyaml
are no-ops locally; ran the guard for real):

```
[step] Checkout — no-op, already checked out
[step] Set up Python — no-op, already available
[step] Install PyYAML — no-op, already available
[step] known-red allow-list guard (may only shrink)
known-red-guard: no tests/known-red-suites.txt found at base-ref=main — ...
guard_rc=0
[no further steps in this job — run-all/ci-gate.sh step was removed]
NEGATIVE CONTROL RESULT: job would report SUCCESS (exit 0) despite the
deliberately broken suite tests/test-worktree-gc-plus-prefix.sh sitting
uncaught in the tree — because no step ever runs it.

=== confirm the broken suite really is still broken ===
suite_exit=1
Results: 7 passed, 1 failed
FAIL: DELIBERATE-BREAK: proving tests/ci-gate.sh catches and names a real failure
```
Detection depends entirely on the removed step being present — confirmed.
Reverted the break again afterward (`git diff` on the suite file: empty).

### 5. Allow-list guard: add a fake entry → guard fails

```
$ git rev-parse HEAD          # baseline commit, 15 real entries
5c305d76...
$ echo 'core:fake-entry-for-guard-test  # ...' >> tests/known-red-suites.txt
$ bash tests/known-red-guard.sh 5c305d76...
known-red-guard: base=5c305d76... base_count=15 current_count=16
known-red-guard: FAIL — tests/known-red-suites.txt grew from 15 to 16 entries.
known-red-guard: the allow-list may only shrink. ...
$ echo $?
1
```
Fake entry removed afterward; the allow-list committed to the branch holds
exactly the 15 real entries (`grep -vcE '^[[:space:]]*(#|$)' tests/known-red-suites.txt` = 15).

## Self-check (falsification set required by the mission)

```
$ bash -n tests/ci-gate.sh && echo OK
OK
$ bash -n tests/known-red-guard.sh && echo OK
OK
$ /bin/bash -n tests/ci-gate.sh && echo OK          # bash 3.2 parser, this repo's own hard rule
OK
$ /bin/bash -n tests/known-red-guard.sh && echo OK
OK
$ python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test-suites.yml')); print('YAML OK')"
YAML OK
```
No `.py` files were added or changed by this task. The repo's own
changed-scope test runner (`tests/run-all.sh --scope changed` via
`tests/ci-gate.sh changed`) is the tool under test here — its red/green
transitions are the proof in sections 1-3 above, not a separate self-check
run (running it a fourth time to re-prove "still green" would just repeat
section 3's result at another 13-19 minutes of cost for no new information).

## Left alone, deliberately

- The 15 known-red suites themselves — not fixed, per the brief
  (`FIFTEEN-RED-SUITES-01`).
- `tests/run-all.sh` and `run-core-offline.sh` — untouched; `ci-gate.sh`
  wraps them rather than modifying their selection/locking logic.
- `tests/test-lane-worktree-isolation.sh` — **found failing standalone on
  this branch** (`7 failed, 8 passed`, e.g. "lane-A merge-back failed
  (rc=2)", "reap left a worktree behind") when I probed candidate suites
  for the deliberate-break demo. It is NOT one of the mission's 15 (those
  are all inside `run-core-offline.sh`; this one lives at the `tests/` top
  level and is not selected by a clean `--scope changed` run, so it did not
  show up in any of the gate runs above). Its own name and fixture (nested
  `git worktree add` calls keyed off `$ROOT`) make it plausible this is
  specific to running from inside a lane worktree-of-a-worktree, which I
  could not rule out without running it from the main checkout — off-limits
  to me (never touch another lane's tree, never cd out of this worktree).
  Not added to the allow-list (out of the dated scope this list documents,
  and I have no evidence it's red in a plain GitHub Actions checkout).
  Flagging for whoever owns `FIFTEEN-RED-SUITES-01` or a follow-up to
  verify on a non-worktree checkout.
- Branch-protection "require status checks" setting — named above, not
  applied (no admin access from here).

DELIVERABLE_COMPLETE
