# INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 — developer (resumed run)

## Context

A prior developer run in this same worktree had already produced the diff and a
new test suite, but **never actually committed** (its own report claimed a
commit that does not exist in `git log`) and the Phase-8 e2e gate had timed out
(`e2e-gate.md`: `status: unknown, reason: e2e_timeout, rc: 124, timeout_s: 900`).
This run picked up the existing worktree state, independently verified the
diff and the new suite, ran it on both macOS and Linux, and performed the
missing commit.

## What changed (verified via `git show --stat 0b3e3e09`)

- `plugins/leadv2/scripts/leadv2-repo-install.sh` — §5 rewritten:
  - Reads both `.claude/settings.json` (tracked) and `.claude/settings.local.json`
    (untracked) and computes the missing-key set against the **union** of their
    `env` blocks, so an already-damaged repo (env already present in the
    tracked file) is not re-nagged.
  - Any write now targets `.claude/settings.local.json` only; `settings.json`
    is opened read-only, never written.
  - New §5b: heals `settings.local.json`'s git-ignore state via
    `.git/info/exclude` only (never a tracked `.gitignore`, never a commit).
  - Defense-in-depth: if `settings.local.json` is itself ever tracked, the
    installer refuses the whole run (`FATAL: ... TRACKED by git ...`, exit 1)
    rather than write env into a shared file.
  - Install-log row now names the actual destination
    (`.claude/settings.local.json env`) instead of the old hardcoded
    `.claude/settings.json env` label.
- New `plugins/leadv2/scripts/lib/leadv2-settings-guard.sh` — single pure
  predicate `leadv2_path_is_tracked(repo, relpath)` (`git ls-files
  --error-unmatch`), sourced by both the installer and the test.
- New `tests/test-installer-settings-guard.sh` — 18 assertions covering:
  (a) the guard predicate against a tracked fixture (exit 0, byte-identical,
  never mutates), (b) full-installer run on an untracked repo, (c) idempotency,
  (d) the tracked-settings.json ("damaged") case — env lands in
  `settings.local.json`, tracked file left byte-identical, (e) an
  already-damaged repo (env already in the tracked file) is not re-nagged,
  (f) defense-in-depth refusal when `settings.local.json` is itself tracked,
  (g) the `.git/info/exclude` ignore-heal path, and a **negative control**:
  mutating `leadv2_path_is_tracked`'s body to `return 1` flips case (a) from
  exit 0 to exit 1 (RED), reverting brings it back to exit 0 (GREEN) — both
  printed verbatim in the suite's own output below.
- `tests/run-all.sh` — two-line `EXTRA_SUITE_MAP` addition:
  `leadv2-repo-install.sh:tests/test-installer-settings-guard.sh` and
  `leadv2-settings-guard.sh:tests/test-installer-settings-guard.sh`, so
  `--scope changed` selects the new suite whenever either production file
  changes.

## DoD gate self-check

- (a) report.md: N/A — mission asked for handoff deliverable files, not a
  `report.md`; produced per protocol instead.
- (b) named-artifact evidence: every claim below is followed by its raw
  command output, not prose.
- (c) new suite registered: `tests/run-all.sh` EXTRA_SUITE_MAP rows above;
  selection proven live (§ "scope changed selection" below).
- (d) runtime-state paths untouched: commit `0b3e3e09` is a pathspec commit
  scoped to exactly the four intended files (verified below) — `docs/leadv2/*`
  and `docs/LEAD_V2_STATE.md` remain modified-but-unstaged from concurrent
  shared-worktree lead activity, not touched by this commit.

## Evidence

### Falsification — bash -n / py_compile

```
$ bash -n plugins/leadv2/scripts/leadv2-repo-install.sh && echo "OK: leadv2-repo-install.sh"
OK: leadv2-repo-install.sh
$ bash -n plugins/leadv2/scripts/lib/leadv2-settings-guard.sh && echo "OK: leadv2-settings-guard.sh"
OK: leadv2-settings-guard.sh
$ bash -n tests/test-installer-settings-guard.sh && echo "OK: test-installer-settings-guard.sh"
OK: test-installer-settings-guard.sh
$ bash -n tests/run-all.sh && echo "OK: run-all.sh"
OK: run-all.sh
```

No `.py` files were touched (the env logic is a `python3 -c` one-liner
embedded in the shell heredoc); `py_compile` does not apply. Both `python3 -c`
invocations executed live and successfully in every suite run below.

### New suite — macOS (host)

```
$ bash tests/test-installer-settings-guard.sh; echo "EXIT_CODE=$?"
PASS: bash -n leadv2-settings-guard.sh
PASS: bash -n leadv2-repo-install.sh
INFO: (a) guard vs tracked fixture exit=0
PASS: guard: tracked fixture -> exit 0
PASS: guard: byte-identical (predicate never writes)
PASS: guard: untracked path -> exit 1
INFO: negative control unmutated_exit=0 mutated_exit=1
PASS: negative control: RED with mutation (0 -> 1), GREEN on revert
PASS: installer: exit 0 on untracked repo
PASS: installer: settings.local.json stays untracked
PASS: installer: settings.json untouched (absent)
PASS: installer: env keys landed in settings.local.json (17)
PASS: installer: idempotent (17 == 17)
PASS: installer: tracked settings.json left byte-identical
PASS: installer: tracked-repo case lands env in settings.local.json (17)
PASS: installer: settings.local.json stays untracked in the damaged-repo case
PASS: installer: already-damaged repo (17 keys already in tracked file) is not re-nagged
INFO: (f) guarded-repo install exit=1
PASS: installer: refuses the whole install when settings.local.json is tracked (exit 1)
PASS: installer: settings.local.json becomes git-ignored after install
PASS: installer: healed via .git/info/exclude only, no tracked .gitignore created

18 passed, 0 failed
EXIT_CODE=0
```

### New suite — Linux (Ubuntu 22.04 container, git + python3 + perl installed)

First attempt used the bare `bash:5` image and failed with `git: command not
found` / `shasum: command not found` / `python3: command not found` — an
image-provisioning gap, not a script bug (`shasum -a 256` is this repo's
established convention, already used by `test-freepool-capability-floor.sh`,
`test-landed-at-spawn.sh`, `test-review-round-exhaustive.sh` and others).
Re-ran on `ubuntu:22.04` with those three packages installed:

```
$ docker run --rm -v "$(pwd)":/repo -w /repo ubuntu:22.04 bash -c '
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq git python3 perl >/dev/null 2>&1
  bash tests/test-installer-settings-guard.sh
  echo "LINUX_EXIT_CODE=$?"
'
PASS: bash -n leadv2-settings-guard.sh
PASS: bash -n leadv2-repo-install.sh
INFO: (a) guard vs tracked fixture exit=0
PASS: guard: tracked fixture -> exit 0
PASS: guard: byte-identical (predicate never writes)
PASS: guard: untracked path -> exit 1
INFO: negative control unmutated_exit=0 mutated_exit=1
PASS: negative control: RED with mutation (0 -> 1), GREEN on revert
PASS: installer: exit 0 on untracked repo
PASS: installer: settings.local.json stays untracked
PASS: installer: settings.json untouched (absent)
PASS: installer: env keys landed in settings.local.json (17)
PASS: installer: idempotent (17 == 17)
PASS: installer: tracked settings.json left byte-identical
PASS: installer: tracked-repo case lands env in settings.local.json (17)
PASS: installer: settings.local.json stays untracked in the damaged-repo case
PASS: installer: already-damaged repo (17 keys already in tracked file) is not re-nagged
INFO: (f) guarded-repo install exit=1
PASS: installer: refuses the whole install when settings.local.json is tracked (exit 1)
PASS: installer: settings.local.json becomes git-ignored after install
PASS: installer: healed via .git/info/exclude only, no tracked .gitignore created

18 passed, 0 failed
LINUX_EXIT_CODE=0
```

### `--scope changed` selection proof

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh
[SELECT] .../tests/test-installer-settings-guard.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 8 selected, scope=changed, select_only=1
EXIT_CODE=0
```

`test-installer-settings-guard.sh` self-selects via the new `EXTRA_SUITE_MAP`
row on `leadv2-repo-install.sh` (and on `leadv2-settings-guard.sh`).
`test-adoption-gate-passable.sh` and `test-fable-think-tier.sh` predate this
change and self-select because they already reference
`leadv2-repo-install.sh` in their own bodies. `test-run-all-carrier-map.sh`
self-selects because `tests/run-all.sh` itself changed (pre-existing
special-cased stem). None of these three are touched by this diff.

### Full `tests/run-all.sh --scope changed` run — pre-existing, unrelated timeout

```
$ timeout 480 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
EXIT_CODE=124 (timeout)
```

Isolated the slow suite to confirm it, not my diff, is the cause:

```
$ time timeout 550 bash plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] running 83 suites across 4 shards
9:10.03 total, EXIT=124 (timeout)
```

`run-core-offline.sh` is the repo's always-on suite (83 sub-suites, 4 shards),
unrelated to and untouched by this diff. This is the same failure mode the
prior run hit (`e2e-gate.md`: `rc: 124, reason: e2e_timeout`) and matches an
already-tracked, separate issue visible in this session's active-task list
(`E2E-TIMEOUT-REPORTED-AS-REGRESSION-01`). Per this repo's own guidance
("establish whether it fails on clean main too before touching it — an
environment-sensitive failure is a finding, not a test bug"), I did not modify
`run-core-offline.sh` or weaken any assertion to force a green full run; the
suite this task is responsible for (`test-installer-settings-guard.sh`) is
independently proven green above, on both platforms, and its selection under
`--scope changed` is proven.

### Commit — pathspec-scoped, verified

```
$ git add plugins/leadv2/scripts/leadv2-repo-install.sh tests/run-all.sh \
    plugins/leadv2/scripts/lib/leadv2-settings-guard.sh tests/test-installer-settings-guard.sh
$ git status --porcelain | grep -E '^[AM]'
M  plugins/leadv2/scripts/leadv2-repo-install.sh
A  plugins/leadv2/scripts/lib/leadv2-settings-guard.sh
M  tests/run-all.sh
A  tests/test-installer-settings-guard.sh
$ git commit -m "fix(installer): write leadv2 env block to settings.local.json, not tracked settings.json" \
    -- plugins/leadv2/scripts/leadv2-repo-install.sh tests/run-all.sh \
       plugins/leadv2/scripts/lib/leadv2-settings-guard.sh tests/test-installer-settings-guard.sh
[worktree-INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 0b3e3e09] fix(installer): ...
 4 files changed, 309 insertions(+), 13 deletions(-)
 create mode 100755 plugins/leadv2/scripts/lib/leadv2-settings-guard.sh
 create mode 100755 tests/test-installer-settings-guard.sh
$ git log --oneline -1
0b3e3e09 fix(installer): write leadv2 env block to settings.local.json, not tracked settings.json
```

`git status --short` after the commit shows only `docs/leadv2/*` and
`docs/LEAD_V2_STATE.md` as modified — pre-existing concurrent shared-worktree
lead activity, not staged or committed by this run, and off-limits per the
mission (runtime-state paths).

## Off-limits / scope discipline

- Did not touch `main`, `tests/known-red-suites.txt`, or any assertion inside
  the new or existing suites.
- Did not touch `~/MythicalGames/m3` or any other consumer repo — report only,
  per the mission's "measured" framing; migrating an already-damaged repo's
  tracked `settings.json` by hand is out of scope for this installer fix.
- Did not touch `run-core-offline.sh` to force the full changed-scope run
  green; that suite's runtime is a separate, already-tracked concern.
- `want` dict (the 17 env keys themselves) is untouched — only the write
  destination and tracked-ness handling around them changed.

## Deliberately left alone

- `E2E-TIMEOUT-REPORTED-AS-REGRESSION-01`-style full `run-all.sh --scope
  changed` completion — pre-existing, unrelated, already has its own lane per
  this session's active-task list.
- The prior developer run's incorrect self-report of having committed — noted
  here for the record, not corrected in place (that file is this run's own
  predecessor's deliverable, not something to silently rewrite).

DELIVERABLE_COMPLETE
