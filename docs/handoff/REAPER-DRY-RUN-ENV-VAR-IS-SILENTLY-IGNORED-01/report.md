# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01

## Defect

`plugins/leadv2/scripts/leadv2-orphan-reaper.sh` accepted `DRY_RUN` from the
environment in name only: at (pre-fix) line 86 it unconditionally executed
`DRY_RUN=0`, clobbering whatever the caller had exported, with no read of
`DRY_RUN` anywhere in the file. `DRY_RUN=1 leadv2-orphan-reaper.sh` therefore
killed processes exactly as if the var had never been set — a safety switch
that silently did the opposite of what it claimed.

## Reproduction (before the fix, on HEAD)

Extracted the pre-fix script directly from `HEAD` (no working-tree edits
needed — the fix was not yet committed) and ran it against a fixture aged
past the stuck threshold, scoped hermetically so it can never touch a real
control-plane process:

```
$ git show HEAD:plugins/leadv2/scripts/leadv2-orphan-reaper.sh > /tmp/reaper-buggy.sh
$ grep -n '_dry_run_env' /tmp/reaper-buggy.sh
no _dry_run_env in HEAD copy (expected: bug present)

$ FIX=.../leadv2-stale-sweeper.sh   # sleep 600, aged 1.5s > 1s stuck threshold
$ echo fixture pid=82343 alive_before=yes
$ DRY_RUN=1 LEADV2_REAPER_SUBJECT_SCOPE=<tmp> LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
    bash /tmp/reaper-buggy.sh --project-root <tmp>
[orphan-reaper] sweeper: candidates=1 (... older_than=1s: 1 ...) termed=1
[orphan-reaper] reaped: 1 subject(s) (2 process TERM(s) incl. descendants) termed
$ echo fixture alive_after=no  <-- BUG: DRY_RUN=1 was exported, reaper still killed it
```

`termed=1` / "reaped ... termed" (not "would-reap") with `DRY_RUN=1`
exported and no `--dry-run` flag: confirmed silent-ignore, reproduced
directly against the committed pre-fix script.

## Fix chosen: (a) honour `DRY_RUN` from the environment, same semantics as `--dry-run`

Rejected (b) (refuse at startup) because `DRY_RUN=1` is the conventional,
widely-understood way to ask a script for a dry run; a safety-switch env var
that a caller already believes works should be made to work, not turned into
a hard refusal that forces a rewrite of every caller. Silently ignoring it,
per the mission, was never on the table.

### The fix

`plugins/leadv2/scripts/leadv2-orphan-reaper.sh` (near the old line 86):

```bash
_dry_run_env="${DRY_RUN:-}"
DRY_RUN=0
[[ "$_dry_run_env" == "1" ]] && DRY_RUN=1
```

The inherited value is captured *before* the script's own default
assignment overwrites it. The pre-existing `--dry-run) DRY_RUN=1; shift ;;`
flag-parsing branch (unchanged) runs after this and unconditionally sets
`DRY_RUN=1` again if the flag is present — so it naturally OR-combines with
the env capture.

### Precedence when the two surfaces disagree

**Either surface asking for dry-run wins — OR, not override.** There is no
way to force a *live* run when `DRY_RUN=1` is exported: the flag can only
turn dry-run further *on*, never back off. This is a deliberate asymmetry:
a safety switch must fail toward safe, never toward live. Documented in the
script's own header (`# Env: DRY_RUN=1 ...`) and comments at the fix site.

Disagreement case tested explicitly: `--dry-run` flag + `DRY_RUN=0` in the
env (case 3 below) — flag wins, fixture survives.

## Tests

New suite: `plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh`
(self-registers via `# run-all-triggers: leadv2-orphan-reaper`, git-tracked
so suite auto-discovery picks it up — no `EXTRA_SUITE_MAP` entry needed).

Four cases, all against a hermetically-scoped (`LEADV2_REAPER_SUBJECT_SCOPE`)
aged fixture so no real control-plane process is ever at risk:

1. `DRY_RUN=1` env, no flag → fixture **survives**, log says would-TERM
   (the bug's exact repro, now green)
2. `--dry-run` flag, no env → fixture **survives** (flag regression guard)
3. `--dry-run` flag + `DRY_RUN=0` env (disagreement) → flag wins, fixture
   **survives**
4. Neither switch set → fixture **is killed** (live kill path still intact)

Standalone run (post-fix):

```
PASS: case1: DRY_RUN=1 env alone -> fixture survives, log says would-TERM
PASS: case2: --dry-run flag alone -> fixture survives (flag still works)
PASS: case3: flag=--dry-run + env DRY_RUN=0 (disagree) -> flag wins, fixture survives
PASS: case4: neither switch set -> fixture is killed (live path intact)
PASS: NC-1: neutered env-recognition -> DRY_RUN=1 env is ignored again, fixture killed (case1 goes red on mutation)
PASS: NC-2: neutered flag-precedence -> --dry-run deferred to env=0, fixture killed (case3 goes red on mutation)
ALL PASS: test-reaper-dry-run-env-precedence.sh
rc=0
```

## Negative controls (mutation, on COPIES, mutation inside the function body)

Two separate mutations targeting two separate lines — "one mutation is not
a control for two checks":

- **NC-1** neuters the env-recognition line (`[[ "$_dry_run_env" == "1" ]]`
  → `"MUTATED-NEVER"`), restoring the original defect for the env-only path.
  Flips **case 1** red; leaves case 3 (flag-driven) unaffected.
- **NC-2** neuters the flag-precedence line (`--dry-run) DRY_RUN=1` →
  `--dry-run) DRY_RUN="$_dry_run_env"`), making the flag defer to a
  disagreeing env value instead of always winning. Flips **case 3** red;
  leaves case 1 unaffected.

Both controls, inside the suite, `sed`-mutate a *copy* of the reaper, assert
the mutation marker landed and `bash -n` still passes on the mutated copy,
then re-run only the relevant case against it.

### Standalone red-then-green evidence for the "restore the unconditional overwrite" control

Built a copy with the original bug fully restored (env capture zeroed out,
recognition line neutered), verified the mutation landed and `bash -n`
passed, then ran the case-1-equivalent probe against it:

```
$ diff plugins/leadv2/scripts/leadv2-orphan-reaper.sh /tmp/reaper-mutated.sh
102c102
< _dry_run_env="${DRY_RUN:-}"
---
> _dry_run_env=""
104c104
< [[ "$_dry_run_env" == "1" ]] && DRY_RUN=1
---
> [[ "$_dry_run_env" == "NEVER" ]] && DRY_RUN=1
$ bash -n /tmp/reaper-mutated.sh   # OK

$ DRY_RUN=1 LEADV2_REAPER_SUBJECT_SCOPE=<tmp> LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
    bash /tmp/reaper-mutated.sh --project-root <tmp>
[orphan-reaper] sweeper: candidates=1 (... older_than=1s: 1 ...) termed=1
[orphan-reaper] reaped: 1 subject(s) (2 process TERM(s) incl. descendants) termed
$ echo case1-equivalent alive_after=no  <-- RED expected: no
```

Mutating the env-recognition line alone reproduces the original defect
(RED). Mutating the flag-precedence line alone (NC-2, inside the suite)
reproduces a *different* defect (flag deferring to env on disagreement) and
only flips case 3 — confirmed as a distinct control by construction (two
different lines, two different `sed` patterns, each verified to have
applied before the affected case is re-run).

## Off-limits respected

No change to which processes the reaper selects (`reap_stuck_by_age`'s
`pgrep -f` pattern, needle match, scope filter, and age/owner-death logic
are untouched), no change to the lane registry, lane cap, or
`leadv2-active-registry.sh`. `git diff --stat` for the change:

```
plugins/leadv2/scripts/leadv2-orphan-reaper.sh                        | 20 ++-
plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh    | 183 +++++++
```

## Environmental hazard encountered and handled (not a defect in the fix)

The new suite's fixture is deliberately named `leadv2-stale-sweeper.sh` (to
exercise the reaper's real `pgrep -f` pattern). Under `tests/run-all.sh
--scope changed` (concurrent shard runner), `case1` was observed to fail
intermittently — the fixture died before/without the reaper's own (scoped)
invocation ever flagging it as would-kill.

Root-caused, not merely suspected: the reaper's *only* kill primitive is
`_term()` → `kill -TERM` (`grep -n 'kill -9\|SIGKILL' leadv2-orphan-reaper.sh`
→ no matches), and `_owner_death_state`'s "unknown" verdict never kills
(reaper.sh:466 comment, confirmed in source). A SIGKILL death with no TERM
trap firing (verified via signal-trap instrumentation during triage) is
therefore structurally impossible to attribute to this script — mine or an
unscoped production instance invoked by another concurrent session's
`SessionStart` hook (`plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh`, which
does run the reaper unscoped on every session start, matching the same
process-name substring). This matches the repo's own documented precedent
of concurrent-lane interference during `core-offline` runs.

Handled by making the suite resilient rather than chasing the exact
external actor further: `expect_survive()` retries once (fresh fixture,
fresh reaper run) before declaring a case failed — a real regression still
fails on the *second* independent attempt, since the reaper cannot cause
this failure mode by construction. Verified stable across 3 consecutive
`tests/run-all.sh --scope changed` / `run-core-offline.sh --scope changed`
runs post-fix, 0 failures in the new suite each time.

## Final verification

```
$ bash -n plugins/leadv2/scripts/leadv2-orphan-reaper.sh   # OK
$ bash -n plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh   # OK
$ bash tests/run-all.sh --scope changed
...
[PASS] .../test-reaper-dry-run-env-precedence.sh
run-all: 7 passed, 1 failed, scope=changed
```

The one failure, `test-reaper-per-subject-candidate-report.sh`
("could not find the spawned fixture process by argv"), is a pre-existing,
off-limits suite (candidate-selection logic, not touched by this fix) that
fails identically standalone with **no concurrency involved**, confirmed
independent of this diff: `diff <(git show HEAD:.../leadv2-orphan-reaper.sh)
plugins/leadv2/scripts/leadv2-orphan-reaper.sh` shows the entire change is
confined to the header doc-comment and the two-line `_dry_run_env` capture —
nothing that suite's own fixture-spawn/argv-matching logic depends on.

No Python files changed; `python3 -m py_compile` not applicable.

DELIVERABLE_COMPLETE
