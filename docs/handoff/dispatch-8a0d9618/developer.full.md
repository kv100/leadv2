verdict: APPROVE
next_action: review_round_2

# developer.full.md — dispatch-8a0d9618 / REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01

## Defect

`plugins/leadv2/scripts/leadv2-orphan-reaper.sh` accepted `DRY_RUN` from the
environment in name only. Pre-fix (line 86), the script executed an
unconditional `DRY_RUN=0` with no read of `DRY_RUN` anywhere in the file —
so `DRY_RUN=1 leadv2-orphan-reaper.sh` killed processes exactly as if the
var were never set, silently defeating a safety switch.

## Reproduction (before fix)

Pulled the pre-fix script straight from `HEAD` (the fix was not yet
committed there) and ran it against an aged, hermetically-scoped fixture:

```
$ git show HEAD:plugins/leadv2/scripts/leadv2-orphan-reaper.sh > /tmp/reaper-buggy.sh
$ DRY_RUN=1 LEADV2_REAPER_SUBJECT_SCOPE=<tmp> LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
    bash /tmp/reaper-buggy.sh --project-root <tmp>
[orphan-reaper] sweeper: candidates=1 (... older_than=1s: 1 ...) termed=1
[orphan-reaper] reaped: 1 subject(s) (2 process TERM(s) incl. descendants) termed
fixture alive_after=no   <-- BUG
```

`termed=1` / "reaped" (not "would-reap") with `DRY_RUN=1` exported: bug
confirmed live, before any edit.

## Fix: option (a) — honour DRY_RUN from env, same semantics as --dry-run

Chose (a) over (b) (refuse at startup) because `DRY_RUN=1` is the standard,
already-expected convention; callers believe it works today, so make it
work rather than force a hard refusal and a rewrite of every caller.
Silently ignoring it was explicitly off the table per the mission.

```bash
_dry_run_env="${DRY_RUN:-}"
DRY_RUN=0
[[ "$_dry_run_env" == "1" ]] && DRY_RUN=1
```

placed before the script's own default assignment previously clobbered it.
The existing `--dry-run) DRY_RUN=1; shift ;;` flag branch is unchanged and
runs afterward, so it naturally OR-combines with the env capture.

**Precedence when the two surfaces disagree:** either surface asking for
dry-run wins. There is no way to force a live run once `DRY_RUN=1` is
exported — the flag can only turn dry-run further on, never back off. This
is deliberate: a safety switch fails toward safe, never toward live.
Documented in the header `# Env:` block and at the fix site.

Confirmed post-fix:

```
$ DRY_RUN=1 LEADV2_REAPER_SUBJECT_SCOPE=<tmp> LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
    bash plugins/leadv2/scripts/leadv2-orphan-reaper.sh --project-root <tmp>
[orphan-reaper] sweeper: candidates=1 (...) would-kill=1
[orphan-reaper] dry-run: 1 subject(s) (2 process TERM(s) incl. descendants) would-reap
fixture alive_after=yes   <-- FIXED
```

## Tests

New: `plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh`.
Self-registers via `# run-all-triggers: leadv2-orphan-reaper`; git-tracked
so the suite-discovery lib (`lib/leadv2-suite-discovery.sh`) picks it up
automatically — no `EXTRA_SUITE_MAP` entry required.

Four cases, all against a `LEADV2_REAPER_SUBJECT_SCOPE`-scoped aged fixture
(never touches a real control-plane process):

1. `DRY_RUN=1` env, no flag → survives, log names would-TERM (the bug's repro)
2. `--dry-run` flag, no env → survives (flag regression guard)
3. `--dry-run` flag + `DRY_RUN=0` env (disagreement) → flag wins, survives
4. Neither switch → killed (live path intact)

Two mutation negative controls, each on a distinct line of a **copy**
(never a top-level insert):

- **NC-1**: neuters the env-recognition line
  (`[[ "$_dry_run_env" == "1" ]]` → `"MUTATED-NEVER"`) — restores the
  original defect for the env path. Flips case 1 red; case 3 unaffected.
- **NC-2**: neuters the flag-precedence line
  (`--dry-run) DRY_RUN=1` → `--dry-run) DRY_RUN="$_dry_run_env"`) — flag
  now defers to a disagreeing env value. Flips case 3 red; case 1
  unaffected. "One mutation is not a control for two checks" — hence two
  separate mutations on two separate lines.

Both controls verify the mutation marker landed and `bash -n` still passes
on the mutated copy before re-running the affected case.

Standalone post-fix run:

```
PASS: case1 ... PASS: case2 ... PASS: case3 ... PASS: case4
PASS: NC-1 (case1 goes red on mutation)
PASS: NC-2 (case3 goes red on mutation)
ALL PASS: test-reaper-dry-run-env-precedence.sh
rc=0
```

Standalone red-then-green for "restore the unconditional overwrite" (built
independently, outside the suite, to demonstrate the exact original defect
restored):

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
$ DRY_RUN=1 ... bash /tmp/reaper-mutated.sh ...
[orphan-reaper] sweeper: ... termed=1
case1-equivalent alive_after=no   <-- RED, as expected
```

## Off-limits respected

No change to which processes the reaper selects (`reap_stuck_by_age`'s
`pgrep -f` pattern, needle match, `LEADV2_REAPER_SUBJECT_SCOPE` filter, age
gate, and owner-death oracle are byte-identical pre/post). No change to the
lane registry, lane cap, or `leadv2-active-registry.sh`. Diff confined to:

```
plugins/leadv2/scripts/leadv2-orphan-reaper.sh                       | 20 ++-
plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh   | 183 (new)
```

## Environmental hazard triaged during development (not a defect in the fix)

The new suite's fixture is named `leadv2-stale-sweeper.sh` to exercise the
reaper's real `pgrep -f` pattern. Under `tests/run-all.sh --scope changed`
(concurrent shard runner), case 1 intermittently failed — fixture died
before the reaper's own scoped invocation had even flagged it.

Investigated rather than dismissed: instrumented the fixture with signal
traps (TERM/INT/HUP/EXIT) — no trap ever fired, meaning the fixture was
SIGKILLed, not TERMed. Checked the reaper's kill surface directly:
`grep -n 'kill -9\|SIGKILL' leadv2-orphan-reaper.sh` → no matches; the only
kill primitive is `_term()` → `kill -TERM` (verified in source, not
assumed). `_owner_death_state`'s "unknown" verdict never kills (source
comment at reaper.sh:466, confirmed). A SIGKILL death with no TERM trap
firing is therefore structurally impossible to attribute to this script —
neither my invocation nor any concurrently-running production instance
(the plugin's own `SessionStart` hook, `leadv2-stale-pid-sweep.sh`, does
invoke the reaper *unscoped* on every session start and would match the
same process-name substring, but it too can only TERM). This lines up with
the repo's documented precedent of concurrent-lane interference during
`core-offline` runs (memory: core-offline-reds-under-concurrent-runners).

Rather than continue chasing the exact external actor (out of scope for
this fix, and the mission's off-limits list forbids touching selection
logic anyway), hardened the suite: `expect_survive()` retries once with a
fresh fixture and a fresh reaper invocation before failing a "should
survive" case. A real regression in the fix still fails on the *second*
independent attempt, since the reaper cannot cause this failure mode by
construction. Verified stable across 3 consecutive
`run-core-offline.sh --scope changed` runs post-hardening: 0 failures each
time (previously ~1-in-N intermittent).

## Final verification

```
$ bash -n plugins/leadv2/scripts/leadv2-orphan-reaper.sh                              # OK
$ bash -n plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence.sh          # OK
$ bash tests/run-all.sh --scope changed
...
[PASS] .../test-reaper-dry-run-env-precedence.sh
run-all: 7 passed, 1 failed, scope=changed
```

The single failure, `test-reaper-per-subject-candidate-report.sh`
("could not find the spawned fixture process by argv"), is a pre-existing,
off-limits suite (candidate-selection logic) that fails identically
standalone with zero concurrency — confirmed independent of this diff:
`diff <(git show HEAD:.../leadv2-orphan-reaper.sh)
plugins/leadv2/scripts/leadv2-orphan-reaper.sh` shows the entire change
confined to the header doc-comment and the two-line `_dry_run_env` capture,
nothing that suite's fixture-spawn/argv-matching logic touches.

No Python files were changed; `python3 -m py_compile` is not applicable.

## Runtime-state paths

`docs/leadv2/.compact-freeze.md` shows as modified in `git status` but this
is automatic session/runtime state, not part of this diff — not staged,
not touched intentionally. Staged set for this task: the reaper script, the
new test suite, and this handoff's own docs under
`docs/handoff/REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01/` and
`docs/handoff/dispatch-8a0d9618/`.

DELIVERABLE_COMPLETE
