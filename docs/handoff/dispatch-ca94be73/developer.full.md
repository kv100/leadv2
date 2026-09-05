# developer.full.md — LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01`
Commit: `5a459e3f fix(active-registry): stop misreporting a real refresh as a registration miss`

## Premise correction

The mission pointed at `plugins/leadv2/scripts/lib/leadv2-active-registry.sh`. There is no `lib/`
copy — the real file is `plugins/leadv2/scripts/leadv2-active-registry.sh`. Confirmed with `find`;
edited the real path.

## Root cause found

`active_register_miss task=07401216 rc=0` is emitted by `leadv2-dispatch-code.sh:~7079` when
`DISPATCH_SLOT_SESSION` is empty after extracting `leadv2_active_register`'s stdout with the
strict pattern `^s-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$` (`leadv2-dispatch-code.sh:7058`).

`leadv2_active_register`'s REFRESH branch (an existing, PID-alive row for the same task_id) used to
do:
```python
print(existing.get("session_id") or session_id)
```
— re-printing the row's OLD session_id. `leadv2-fanout.sh`'s own pre-registration
(`_fanout_register_session`, `leadv2-fanout.sh:910`) stamps session_id as `"f-<ts>-<pid>-<pid>"`
(prefix `f-`, not `s-`). When dispatch-code.sh's Gate-1 registration call refreshes a
fanout-pre-registered row (the documented normal flow — see the registry's own comment at
`leadv2-active-registry.sh:424-428`), it prints the OLD `"f-..."` id. That id never matches the
caller's `^s-...$` pattern, so `DISPATCH_SLOT_SESSION` stays empty **even though**:
- `rc=0` (the python op genuinely succeeded)
- the row genuinely exists in the correct store (worktree/branch/pulse_log/last_pulse_at/updated_at
  all correctly refreshed)

This is precisely the observed shape: a write that succeeded, logged as a miss. It is also a
second-order defect: because `DISPATCH_SLOT_SESSION`/`DISPATCH_SLOT_REG_ID` never get set
(`leadv2-dispatch-code.sh:7074-7080`), `_release_registered_lane` (`leadv2-dispatch-code.sh:4518`)
silently no-ops on cleanup too (its early-return guard is `[[ -n "${DISPATCH_SLOT_REG_ID}" ]]`), so
the row is never owner-verified-released at exit either — one root cause, two downstream symptoms.

## Fix (landed, in this lane's scope)

`plugins/leadv2/scripts/leadv2-active-registry.sh`:

1. Refresh branch now **restamps** `session_id` with the freshly-generated canonical id before
   printing (was: re-print the possibly-foreign old id). A caller that just refreshed a row is also
   the rightful current owner of its identity from that point — consistent with the existing
   "refresh ownership metadata" comment already at that call site.
2. Defense in depth in the bash wrapper `leadv2_active_register()`: captures the python op's stdout,
   validates it against `^s-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$` itself, and returns a **distinct
   nonzero rc (7)** with a stderr diagnostic (`register_output_malformed: ...`) instead of silently
   returning 0 on any future mismatch — so the contract is enforced once, at the one place that owns
   it, not re-derived (and possibly re-broken) by every caller.

## Fix NOT landed (dispatch-code.sh is off-limits, owned by another session)

Two spots in `leadv2-dispatch-code.sh` are now redundant-but-harmless with the fix above, but still
worth landing for defense in depth / better logging:

**A. `~:7058-7080`** — now redundant (my fix means `_register_out` always matches `^s-...$` on a
genuine success), but if `leadv2_active_register` ever returns a NEW distinct code (7, from my
guard) instead of 0/5/6, the `case` at 7064 falls through to `esac` silently and the code proceeds
to treat it as a "miss" via the existing `else` branch at 7078 — which is now at least accurate
(rc will be 7, not 0, since my guard returns a real nonzero). No change strictly required, but for
clarity the `case` could add:
```bash
7) emit decision "dispatch_refused reason=register_output_malformed task=${sig8}"
   _dl_note "${sig8}" refused register_output_malformed "" "${founder_task_id}"
   printf 'LEADV2_DISPATCH_REFUSED: register_output_malformed\n'
   exit 2 ;;
```
placed alongside the existing `5)`/`6)` cases at `leadv2-dispatch-code.sh:7064-7073`.

**B. `~:7238-7256`** — the SECOND register call (persisting `lane_writes` onto the already-registered
row) swallows any non-5/6 registry error silently:
```bash
    case "${_ws_rc}" in
      0) : ;;
      5) ... exit 2 ;;
      6) ... exit 2 ;;
      *) : ;;  # non-fatal registry error (e.g. missing PyYAML) -- never block dispatch on it
    esac
```
A genuine registry write failure here (including my new rc=7) is intentionally non-blocking
(comment: "never block dispatch on it") but currently produces **zero journal line** — the exact
silent-miss shape this task is about. Suggested replacement for the `*)` arm:
```bash
      *) emit decision "active_register_writes_stamp_failed task=${sig8} rc=${_ws_rc}" ;;
```
This makes the swallow audible (a journal line a reader can find) without changing the
non-blocking behavior the comment explicitly wants.

Both are one-line-per-case additions; I did not apply them since `leadv2-dispatch-code.sh` is
listed off-limits for this lane and owned by another session.

## Reproduction (before/after), pasted from the mutation-control run

Sandbox: isolated `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`, `LEADV2_STATE_PATH_BIN` pinned to the
real resolver (a copy sourced from a scratch dir otherwise silently resolves to a DIFFERENT,
uninitialized `active.yaml` via `leadv2-active-registry.sh`'s own `BASH_SOURCE[0]`-relative
fallback — the exact "wrote into the wrong repository, rc=0, no output" shape from this task's own
brief, here triggered by test-harness relocation rather than the bug under test; documented in the
test file).

```
Test 2: negative control -- mutate leadv2_active_register's refresh branch back to the original bug
  baseline_rc=0 printed=s-20260904T052705Z-91205-34377
  mutated_rc=7 printed= state_session_id=f-20260101T000000Z-32982-32982 diag=[leadv2-active-registry] register_output_malformed: task=AREGMISS-T1 op returned rc=0 but printed f-20260101T000000Z-32982-32982 (expected s-<ts>-<pid>-<pid>) -- registry write is unverifiable, treating as failure
  restored_rc=0 printed=s-20260904T052707Z-91205-36073
PASS: Test 2b: mutant reproduces the exact pre-fix shape (rc=7, printed='' unmatched by caller pattern); baseline and restored both stay green
```

- **Before** (mutant = original code): rc=**0** (the write genuinely succeeded, the row's other
  fields were correctly refreshed — `state_session_id` confirms the row exists and is current), but
  the printed value (`f-20260101T000000Z-32982-32982`) does not match the caller's `^s-...$`
  pattern — this is the exact silent-success-as-miss shape.
- **After** (real, fixed code): a scenario that would have hit this branch now restamps
  `session_id` before printing (Test 1 below), so the false-miss never occurs; and if the output
  ever again fails to match the pattern for any reason, the wrapper now returns **rc=7** with a
  named stderr diagnostic instead of 0 — the caller sees a failure, not a lie.

## Full test output

### New suite, single run
```
[TEST] === leadv2-active-register-miss tests (LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01) ===
[TEST] Script: .../plugins/leadv2/scripts/tests/../leadv2-active-registry.sh

[TEST] Test 3: bash -n syntax check
[TEST] PASS: Test 3a: leadv2-active-registry.sh bash -n OK
[TEST] PASS: Test 3b: this test file bash -n OK
[TEST] Test 1: refresh of a foreign-prefixed alive row against the FIXED registry
[TEST]   printed=s-20260904T052704Z-91205-33117 rc=0 state_session_id=s-20260904T052704Z-91205-33117
[TEST] PASS: Test 1: refresh printed a caller-matchable session_id ('s-20260904T052704Z-91205-33117') that equals the stored row's session_id -- no false miss
[TEST] Test 2: negative control -- mutate leadv2_active_register's refresh branch back to the original bug
[TEST] PASS: Test 2a: mutant differs byte-for-byte from the original
[TEST]   baseline_rc=0 printed=s-20260904T052705Z-91205-34377
[TEST]   mutated_rc=7 printed= state_session_id=f-20260101T000000Z-32982-32982 diag=[leadv2-active-registry] register_output_malformed: task=AREGMISS-T1 op returned rc=0 but printed f-20260101T000000Z-32982-32982 (expected s-<ts>-<pid>-<pid>) -- registry write is unverifiable, treating as failure
[TEST]   restored_rc=0 printed=s-20260904T052707Z-91205-36073
[TEST] PASS: Test 2b: mutant reproduces the exact pre-fix shape (rc=7, printed='' unmatched by caller pattern); baseline and restored both stay green

[TEST] === Results: PASS=5 FAIL=0 ===
[TEST] All tests passed.
EXIT=0
```

### Ten consecutive runs
```
run 1: rc=0
run 2: rc=0
run 3: rc=0
run 4: rc=0
run 5: rc=0
run 6: rc=0
run 7: rc=0
run 8: rc=0
run 9: rc=0
run 10: rc=0
ALL:  0 0 0 0 0 0 0 0 0 0
```

### Pre-existing suites (regression check)
```
$ bash plugins/leadv2/scripts/tests/test-active-registry-failclosed.sh
[TEST] === Results: PASS=3 FAIL=0 ===
[TEST] All tests passed.

$ bash plugins/leadv2/scripts/tests/test-active-registry-update-phase.sh
[TEST] === Results: PASS=7 FAIL=0 ===
[TEST] All tests passed.
```

### Syntax / falsification set
```
$ bash -n plugins/leadv2/scripts/leadv2-active-registry.sh && echo REGISTRY_SYNTAX_OK
REGISTRY_SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-active-register-miss.sh && echo TESTFILE_SYNTAX_OK
TESTFILE_SYNTAX_OK
```
No Python files were changed (all Python is inline heredoc inside the `.sh` files; `bash -n`
covers the shell wrapper, and the heredocs themselves are exercised live by every test run above).

## bash/zsh note

`zsh plugins/leadv2/scripts/tests/test-active-register-miss.sh` (forcing the zsh interpreter over
the bash shebang) fails on `BASH_SOURCE[0]: parameter not set` — but this is **identical,
pre-existing behavior** for every sibling suite in this directory (verified against
`test-active-registry-failclosed.sh`, same failure). `tests/run-all.sh` always invokes suites via
literal `bash "${suite}"` (`tests/run-all.sh:590,594`), never `zsh`, so this matches the actual CI
invocation path and existing convention. Not a regression I introduced.

## Mutation-control compliance notes (per mission's Acceptance section)

- Mutation applied INSIDE the changed function body (`leadv2_active_register`'s python `register`
  op, refresh branch) — reverts exactly the two added lines back to the original one-liner.
- Mutant confirmed byte-different from the original before running (Test 2a).
- Exactly one assertion goes red under the mutation (Test 2b's state check); Test 1, Test 2a, and
  Test 3 (syntax) all stay green under the same mutant run because they exercise the fixed file
  directly (Test 1) or check independent properties (2a: diff, 3: syntax) — confirmed by the actual
  run output above (PASS=5 with only the intentional mutant-comparison logic inside Test 2b
  toggling).
- Falsification: the assertion is a STATE check (row's actual stored `session_id` / the printed
  value's pattern match), never a message-text assertion — there is no message string being
  asserted on that could be stripped to leave a fake-passing shell; removing the pattern check
  itself IS removing the state check, so the falsification requirement is met by construction
  (documented inline in the test file's Test 2 comment).

## Scope notes

- Did not touch `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`, or any
  `docs/leadv2/` path.
- `git diff --diff-filter=D --name-only main...HEAD` — empty, no deletions.
- New test file confirmed tracked: `git ls-files plugins/leadv2/scripts/tests/test-active-register-miss.sh`.
- Self-registration: the new suite needs no `EXTRA_SUITE_MAP` entry — `tests/run-all.sh` (lines
  ~455-460) already self-selects any changed `plugins/leadv2/scripts/tests/test-*.sh` file
  regardless of stem match, confirmed by reading that block.
- Did not touch the emit-site's `task=${sig8}` vs `reg_id` naming inconsistency noticed in
  dispatch-code.sh (the emitted decision line uses the short sig8 hash while the row is actually
  keyed by `reg_id`/`founder_task_id` when set) — cosmetic log-label mismatch, not a registration
  defect, and inside the off-limits file; flagging for awareness only.

DELIVERABLE_COMPLETE
