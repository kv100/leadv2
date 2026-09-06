# ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01

Found during the D2-SINGLE-LIVENESS-VERDICT producer census
(`docs/handoff/D2-SINGLE-LIVENESS-VERDICT/producer-census.md`). Filed as
its own row (priority 90, `docs/tasks.yaml` in persona-engine) rather than
fixed inline, since the survey was read-only. Leadmain assigned it back to
me to fix, with four explicit requirements: one shared primitive (not five
patched copies) unless genuinely infeasible; verify the edit actually
executes (bash's silent-second-definition trap); a mutation per
independent verdict path, not one blanket mutation; and a pair control
both directions (EPERM-alive now selectable, ESRCH-dead still excluded).

## The bug

`leadv2-active-registry.sh` had five independent embedded-Python
`_pid_alive`/`pid_alive`/`_prlr_alive` definitions, one per separate
`python3 - ... <<'PYEOF'` heredoc process (they cannot share Python
in-process state — each is its own OS process). All five caught
`PermissionError` (EPERM — the pid **exists**, owned by another user,
alive) as death:

```python
except (TypeError, ValueError, ProcessLookupError, PermissionError):
    return False
```

Two of the five (the list header and `check_limits`'s own filter) were
added THIS MORNING by `4aa51b34`, fixing a genuine overcounting bug
(dead-pid tombstones inflating the session count) by copying the same
still-buggy primitive.

Effects, both directions of the same defect:
- `_lv2_ws_dead` (writeset-conflict admission, site 1): a live
  foreign-owned incumbent misread as dead — a conflicting dispatch could
  be let through into an active write-set.
- `check_limits`'s `_row_dead` filter (site 3): a live foreign-owned pid
  dropped from the live count — the hard cap could admit more lanes than
  configured.
- The list header (site 2): cosmetic — a live foreign-owned worker shown
  `DEAD` in the table.
- `leadv2_fanout_register_session`'s duplicate-registration guard (site
  4): an EPERM-owned existing row misread as dead — a second registration
  for the same `task_id` could silently replace a still-alive session's
  row (two workers believing they own one lane).
- `leadv2_active_release_verified` (site 5): an EPERM-owned foreign row
  misread as stale — the release path could delete a live foreign lane's
  registry row on an unrelated release call.

## Fix — one shared primitive

`lib/leadv2_pid_alive.py` (new), same R4 import contract already
established by `lib/leadv2_pid_birth.py` in this same codebase:

```python
sys.path.insert(0, os.environ.get("LEADV2_AR_LIB_DIR", ""))
from leadv2_pid_alive import pid_alive
```

`LEADV2_AR_LIB_DIR` is computed once, at the top of
`leadv2-active-registry.sh`, via the same `BASH_SOURCE`-safety
`_leadv2_state_path_sh` already uses (empty, not a crash, under
`eval "$(cat ...)"` sourcing), and threaded as an env var into each of
the five `python3 - ... <<'PYEOF'` invocations. Each site falls back to
an inline copy of the identical corrected three-way logic only if the
lib dir is unreachable (a drifted `.claude/scripts/` copy) — the same
degrade-never-crash contract `leadv2_pid_birth.py`'s callers already use.

**Genuinely one primitive, not five patched copies**: all five sites
import the same function object; a single mutation to the shared module
(see below) independently red-lines all five sites' assertions in one
suite run. The five heredoc *processes* remain necessarily separate (no
way to share Python interpreter state across `python3 -` subprocess
boundaries), but the *logic* is unified — exactly the distinction the
task asked me to draw before allowing five separate patches as legitimate.

## Requirement 2 — verify the edit actually executes

`grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' leadv2-active-registry.sh | sort |
uniq -d` → empty, both before and after the fix. The five `_pid_alive`
definitions were never a bash-level duplicate-function hazard (they are
Python `def`s inside separate heredocs, not bash `name() {` declarations
sharing one script-level namespace), but the check was run anyway per
instruction, on the committed file, and is now part of the routine
verification for this repo. Also ran `bash -n` and `python3 -m
py_compile` on every touched file, and extracted+compiled each of the
file's 8 real heredocs individually (one grep false-positive on a comment
line, filtered).

## Requirement 3 — mutation per independent path, not one blanket mutation

Since all five sites route through ONE shared function, the meaningful
version of "count independent paths before trusting a mutation" is:
prove the ONE mutation actually reaches all five *readers*, not assume it
does because they share source. Verified directly (manual mutate +
restore, not just the tool's own summary line) that a single mutation to
`lib/leadv2_pid_alive.py:54` (`except PermissionError: return True` →
`return False`, reverting to the pre-fix collapse) turns red **every one
of the five sites' own assertions, in one suite run**:

```
FAIL: A5 EPERM-owned pid (1) wrongly excluded from the count (rc=0)          # site 3, check_limits
FAIL: B3 header wrong: Active sessions (1 / 5 max):                          # site 2, header
FAIL: B3b EPERM-owned row wrongly marked DEAD in table                      # site 2, header
FAIL: C1 --dead removed wrong count (5 -> 2)                                 # site 1, unregister
FAIL: C1b EPERM-owned pid (1) was wrongly removed by --dead                  # site 1, unregister/admission
FAIL: D1 EPERM-owned foreign row wrongly removed (1 -> 0 rows)               # site 5, release_verified
FAIL: E1 EPERM-owned existing row wrongly treated as dead:                   # site 4, fanout register
```

Two of these five assertion groups (D1, E1) did not exist until this task
— site 5 had ZERO prior coverage anywhere in the repo (see below), and
site 4's only prior coverage exercised the wrong function entirely (see
below). Official tool run: `mutation-control/20260906T164656Z-66360.txt`
(`baseline_rc=0`, `mutated_rc=1`).

### Two coverage gaps found and closed while proving this

1. **Sites 2/3 (header, check_limits) had EPERM-shaped assertions that
   never actually reached the EPERM branch.** A1-A4/B1-B2 all use
   `$DEAD_PID` (a genuinely ESRCH-dead pid) — a mutation that breaks ONLY
   the EPERM branch passes them unchanged. Added A5/B3/B3b using pid=1
   (EPERM on a non-root test run) to close this.
2. **Site 5 (`leadv2_active_release_verified`) had no coverage at all.**
   `test-phase-refusal-lane-release.sh`'s own M3 mutation control targets
   a code pattern (`if _prlr_alive(rpid) and _prlr_kind(rpid) ==
   "worker":`) that no longer exists in `leadv2-dispatch-code.sh` — that
   function was refactored (comment at the call site: "moved into the
   registry as `leadv2_active_release_verified`") to delegate here
   instead. Confirmed this suite's failure count (`PASS=8 FAIL=7`) is
   byte-identical on HEAD before this change and after — pre-existing,
   stale, unrelated to this fix, not something I touched. New D1/D2 added
   directly against `leadv2_active_release_verified`.
3. **Site 4's first draft called the wrong function** (`leadv2_active_register`,
   which delegates to a *different* heredoc/write path entirely, and
   never reaches the `pid_alive` check under test) and passed for the
   wrong reason (never executed the code being tested). Caught this
   myself by asserting on the actual refusal *message*, not just an exit
   code — the message never appeared, which is what led to finding the
   real function, `leadv2_fanout_register_session`.

## Requirement 4 — pair control, both directions, every site

Every one of the five sites now has both halves in
`tests/test-stale-row-starting-grace.sh`:

| site | function | alive-not-dead (fixed) | dead-still-dead (no regression) |
|---|---|---|---|
| 1 | unregister `--dead` / admission | C1b | C1 |
| 2 | list header | B3/B3b | B1/B2 |
| 3 | check_limits | A5 | A1-A4 |
| 4 | `leadv2_fanout_register_session` | E1 | E2 |
| 5 | `leadv2_active_release_verified` | D1 | D2 |

91 → 100 assertions in this suite (9 new), all green:
`test-stale-row-starting-grace.sh: ALL GREEN`.

`test-stale-row-starting-grace.sh`'s own pre-existing C1 fixture had
baked the OLD bug in as its expectation (`add_row ... 1 ... # pid 1:
EPERM -> dead per _pid_alive`) — it silently regressed the moment the
real bug was fixed. Corrected in place (second genuinely-dead pid added
so C1 still tests removing 2 real-dead rows; pid=1 moved to its own
explicit C1b pair-control assertion) rather than loosened.

## Regression check across every suite referencing the file

31 suites in the repo reference `leadv2-active-registry.sh` /
`leadv2_active_*`. Ran all of them with the fix applied; 8 carry
failures. For every one, restored the exact HEAD (pre-fix) copy of
`leadv2-active-registry.sh` and re-ran to confirm the failure is
byte-identical pre-existing and unrelated to this change, then restored
the fix:
`test-beat-loop-orphans.sh`, `test-broad-status-stale-file.sh`,
`test-leadv2-state-path.sh`, `test-liveness-tristate-01.sh`,
`test-phase-refusal-lane-release.sh`, `test-suite-selection-coverage.sh`,
`test-mission-writeset.sh`, `test-writeset-refusal-names-blocker.sh`. All
eight: identical failure signature and count on HEAD before this fix.

## Commits

`394c9076` (fix: shared module + 5-site conversion), `8b1eaa6e` (test:
pair-control coverage for all 5 sites, both new coverage gaps closed).
This report + mutation-control artifact next (artifact not committed —
`docs/handoff/*/*` outside allowlisted `.md` names stays gitignored per
repo convention, same as every other mutation-control run this session).

## Not done here

`lib/leadv2-lane-state.sh` was read (for the original census) but never
written — it was, and remains, under Leadmain's live lane.
