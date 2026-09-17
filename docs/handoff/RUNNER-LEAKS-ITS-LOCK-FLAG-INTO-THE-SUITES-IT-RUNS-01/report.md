# RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01

Platform: macOS Darwin 25.6.0. Commit base: HEAD at dispatch (`2fd2c635`), lane branch `worktree-3f44760b3faa`.

## Suite 1/2: `test-core-offline-lock-01.sh` (the named mechanism)

### Reproduction (from branch, before any fix-shaped code)

```
cd ~/Projects/leadv2 && _LV2_CORE_OFFLINE_LOCK_HELD=1 \
  bash plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh >/dev/null 2>&1
```

Reproduced red (`rc=1`) on this branch before any edit, re-confirmed against the exact committed HEAD
blobs (checked out in place, run, then restored — see Negative control below):

```
=== PRE-FIX BASELINE (real checkout, HEAD blobs): acceptance command (expect red) ===
[LOCK-01] case (a)/(b): held lock -> bounded wait times out
[LOCK-01]   (a)/(b) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=/var/folders/.../lv2-lock-test.A7vIFK>>>
[LOCK-01] case (c): wait long enough to outlast the holder
[LOCK-01]   (c) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=/var/folders/.../lv2-lock-test.A7vIFK>>>
[LOCK-01] case (d): kill-switch bypasses a held lock
[LOCK-01]   (d) kill-switch bypassed the held lock ✓
[LOCK-01] pass=1 fail=2
rc=1
```

Paired control (clean env, no injected flag) on the same pre-fix blobs — green, proving the
difference is the flag, not a general defect in the suite or runner:

```
=== PRE-FIX BASELINE: clean-env paired control (expect green) ===
[LOCK-01] case (a)/(b): held lock -> bounded wait times out
[LOCK-01]   (a)/(b) bounded wait times out with journaled lines ✓
[LOCK-01] case (c): wait long enough to outlast the holder
[LOCK-01]   (c) waited then acquired ✓ (elapsed 2s)
[LOCK-01] case (d): kill-switch bypasses a held lock
[LOCK-01]   (d) kill-switch bypassed the held lock ✓
[LOCK-01] pass=3 fail=0
rc=0
```

### Cause class
`harness_self_interference` — already named as a confirmed instance in `lane-rules.md` (the runner's
own flock re-exec leaks a flag into the suite bodies it runs).

### Mechanism

- `plugins/leadv2/scripts/tests/run-core-offline.sh:179` (pre-fix) re-execs the locked run as
  `env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" ...` to mark "I am the already-locked
  child" and skip re-acquiring the flock.
- The runner's own env-scrub (`_core_offline_build_scrub_args`, CRITICAL-1 round-2) strips
  `LEADV2_*` / `CLAUDE_*` / `GIT_CONFIG*` (plus a short fixed list) before launching each suite body
  via `run_check`. `_LV2_CORE_OFFLINE_LOCK_HELD` uses a **different prefix** (`_LV2_*`, not
  `LEADV2_*`), so it is never matched by that denylist and survives into every suite body.
- `test-core-offline-lock-01.sh` launches `run-core-offline.sh` **as its own subject under test**
  (`bash "$RUNNER"` at lines 62/90/118, pre-fix). When this suite itself runs as a body under a
  locked `run-core-offline.sh` (the real end-to-end shape), or the flag is otherwise present in its
  ambient environment (the mission's own acceptance probe), every nested runner invocation silently
  believes it already holds the lock and skips real acquisition — so cases (a)/(b) and (c), which
  depend on genuinely observing "waiting for lock" / "lock-probe acquired" against an externally
  held flock, fail.
- There are two distinct leak paths, not one, which is why one fix alone was insufficient:
  1. **Forward leak**: a locked runner launching a suite body that inherits the flag (fixed in the
     runner).
  2. **Ambient/direct contamination**: the suite's own top-level process inherits the flag from
     whatever launched *it* (fixed in the suite) — `env VAR=VAL cmd` only adds/overrides named vars
     on the child it launches, it never clears a var the calling shell already has exported, so a
     runner-only fix does not reach a case where the suite process itself is the first thing to see
     the flag.

### Fix
- `run-core-offline.sh` (line ~223, after the lock-holder stamp, before any suite is launched):
  added `unset _LV2_CORE_OFFLINE_LOCK_HELD`, scoped strictly after the flock re-exec's own
  self-recognition check (which is decided earlier, at the top of the same block) and before the
  first `run_check` call — so the re-exec still recognises itself correctly (no infinite
  lock-recursion), but nothing launched after that point can see the flag.
- `test-core-offline-lock-01.sh` (line 35, right after `RUNNER=` is resolved, before any case runs):
  added `unset _LV2_CORE_OFFLINE_LOCK_HELD` — so every `bash "$RUNNER"` call in this suite always
  starts from a genuinely clean top-level invocation, regardless of what this suite's own process
  inherited.

### Negative control (informal, mutate/revert in place)

Mutation: revert both files to the exact committed HEAD blobs (pre-fix), in place, run, then restore
the fix files verbatim (byte-identical, confirmed via `git diff --stat` afterward showing the same
2-file / 18-insertion / 1-deletion diff as before the round-trip):

RED (pre-fix blobs, acceptance command — pasted above) → pass=1 fail=2, rc=1.
GREEN (post-restore, same command):

```
=== RESTORED FIX: re-verify green ===
[LOCK-01] case (a)/(b): held lock -> bounded wait times out
[LOCK-01]   (a)/(b) bounded wait times out with journaled lines ✓
[LOCK-01] case (c): wait long enough to outlast the holder
[LOCK-01]   (c) waited then acquired ✓ (elapsed 2s)
[LOCK-01] case (d): kill-switch bypasses a held lock
[LOCK-01]   (d) kill-switch bypassed the held lock ✓
[LOCK-01] pass=3 fail=0
rc=0
```

Paired control re-run post-fix (clean env) — also green, byte-identical case-by-case shape to the
dirty-env run, confirming the flag no longer changes behaviour either way:

```
[LOCK-01] pass=3 fail=0
rc=0
```

### Negative control (formal, `leadv2-mutation-control.sh`)

Two independent claims (runner-side forward-leak fix, suite-side ambient-contamination fix) get two
separate mutation-control runs, per "one mutation is not a control for N checks."

**Runner-side.** Because a plain existing suite invocation doesn't naturally exercise forward-leak
into a *descendant* process the way the real defect shape does, this control uses a small,
non-registered, purpose-built harness committed at
`docs/handoff/RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01/probe-runner-noleak.sh`. It
lives outside `plugins/leadv2/scripts/tests/`, is not named `test-*.sh`, and is not selected by
`run-core-offline.sh`/`run-all.sh` triggers — it exists solely as a mutation-control target, not a
suite. It pre-sets the flag ambiently (standing in for "inherited from an ancestor
`run-core-offline.sh` that re-exec'd me"), then asks the runner to run ONE fake suite via the
repo-native `LEADV2_SUITE_DEFS_OVERRIDE` test hook; the fake suite reports whether it can still see
the flag.

Mutation applied: `s/^unset _LV2_CORE_OFFLINE_LOCK_HELD$//` on
`plugins/leadv2/scripts/tests/run-core-offline.sh` (deletes the added unset, inside the function
body's execution flow, not a top-level `exit 1`).

Artifact: `mutation-control/20260916T092339Z-88374.txt`

```
suite=docs/handoff/RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01/probe-runner-noleak.sh
file=plugins/leadv2/scripts/tests/run-core-offline.sh
anchor=s/^unset _LV2_CORE_OFFLINE_LOCK_HELD$//
baseline_rc=0
mutated_rc=1
red_line=[CORE-OFFLINE] SHARD_RESULT idx=0 pass=1 fail=0 missing=0
diff_hash=2eef20cfc6a86cc940c0bccc51540c6d11e81d1f706c320c9b87f822d5a07ba7
lane_diff_hash=36ec8d0427fde307f42e10b4f0afbc4696d9a4335deaa07e6bb9a9b960cb8487
```
`leadv2-mutation-control.sh` exit code 0 (`MUTATION-CONTROL ok`): baseline green, mutant red,
mutation confirmed landed.

**Suite-side.** Suite and mutated file are both
`plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh`; the tool's overlay exports
`_LV2_CORE_OFFLINE_LOCK_HELD=1` ambiently (simulating the direct-contamination scenario) and the
mutation removes the suite's own `unset` line.

Artifact: `mutation-control/20260916T092424Z-317.txt`

```
suite=plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh
file=plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh
baseline_rc=0
mutated_rc=1
red_line=[LOCK-01]   (a)/(b) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=...>>>
diff_hash=95d696434b4c4fee5d364cee6a2b7e24d01d3b9e5649e7eaecf3df4b59180293
lane_diff_hash=36ec8d0427fde307f42e10b4f0afbc4696d9a4335deaa07e6bb9a9b960cb8487
```
`leadv2-mutation-control.sh` exit code 0: baseline green, mutant red, mutation confirmed landed.

### Final suite run (boundary)
`test-core-offline-lock-01.sh`: 3 of 3 cases pass, at no ceiling (suite runs in well under a
second per case; it uses `LEADV2_SUITE_LOCK_PROBE=1` acquire-then-exit, not the full 57-suite
batch), on macOS Darwin 25.6.0, lane branch `worktree-3f44760b3faa` off HEAD `2fd2c635`. Confirmed
both standalone and under the mission's exact acceptance command (`_LV2_CORE_OFFLINE_LOCK_HELD=1`
injected) — both green, `rc=0`.

## Audit of the other vars flagged in the same block

| var | leaks past the fixed point? | why |
|---|---|---|
| `LEADV2_SUITE_SHARDS_DUMP` | No | Read at the sharding-default-calc block (`run-core-offline.sh` ~1109-1120); when set, the runner prints the shard plan and does `exit 0` immediately — no suite ever runs in that process, so there is nothing downstream for it to leak into. |
| `LEADV2_CORE_OFFLINE_SCOPE_DUMP` | No | Same shape, earlier: read at the `--scope changed` selection-result print (~line 998), followed by `exit 0` before any suite is launched. |
| `LEADV2_TEST_CONTEXT` | Scrubbed by the general `LEADV2_*` denylist (intentional, not a bug) | This one *is* covered by the CRITICAL-1 round-2 scrub (it matches `LEADV2_*`), so it does not survive into suite bodies. That is safe by design: `lib/leadv2-test-context.sh`'s `lv2_test_context()` has an independent ancestor-process-walk fallback (`ps -o command=`, up to 12 hops, matching `*/tests/test-*.sh|*/tests/run-*.sh`) that re-derives test-context status without needing the env var, so scrubbing it does not blind any suite body to the fact that it is running under test. |

No other leak found among these four.

## Suites 3-4: the two unexplained suites (`test-dod-gate-suite-registration.sh`, `test-shared-sink-test-guard.sh`) — CONFIRMED, fixed

Both are catalogued in `tests/known-red-suites.txt` (dated 2026-09-14, pointing to
`SD-MAIN-CORE-SUITE-RED-01`) as red under the full census/gate run, and both passed every
*isolated* condition tried by the lead and by me:

```
bash plugins/leadv2/scripts/tests/test-shared-sink-test-guard.sh      -> PASS=35 FAIL=0, rc=0
bash plugins/leadv2/scripts/tests/test-dod-gate-suite-registration.sh -> 16 passed, 0 failed, rc=0
```

I ran the full, bare `run-core-offline.sh` end-to-end (no override) once, as the mission also
requires for the runner overall, and **both suites reproduced red there** (`RC=1 WALL_S=1713`,
2026-09-16, this commit):

```
[CORE-OFFLINE] FAILED: shared-sink test guard (TESTS-POLLUTE-REAL-JOURNAL-01)
  FAIL: case6: real journal not found at /var/folders/.../core-offline-run.uEiWFF/suite.DgxSxG/home/.claude/cache/leadv2-events/leadv2.jsonl (cannot byte-guard)
  FAIL: case8: real arm-state file not found at .../suite.DgxSxG/home/.claude/leadv2-state/freepool-arm-state.json
  FAIL: case13: real journal/ledger pair not found for the copy check
  shared-sink test guard: PASS=29 FAIL=3
[CORE-OFFLINE] FAILED: dod gate suite registration (both map forms + run-all selection)
  [TEST] FAIL: (g) live repo not found at .../suite.mLuxGk/home/Projects/persona-engine (set LEADV2_DOD_LIVE_REPO) — this case must not silently skip
  [TEST] 15 passed, 1 failed
```

That single detail line — `.../suite.DgxSxG/home/.claude/cache/...` and `.../suite.mLuxGk/home/Projects/persona-engine` — is the mechanism: these are not the real `$HOME`, they are per-suite sandbox directories. **This is not concurrency.**

### The named mechanism: `harness_self_interference`, same cause class as the lock leak

`run-core-offline.sh:335-345` (pre-fix comment, still accurate for every suite not on the new
exemption list):
```bash
  # Shards execute independent suites concurrently.  TMPDIR alone cannot
  # isolate suites that use the conventional ~/.claude/cache state surface,
  # so give every sharded suite an otherwise-empty HOME rooted in its
  # already-private fixture directory.
  if [[ "${LEADV2_SUITE_SHARDS:-1}" -gt 1 ]]; then
    local suite_tmp
    suite_tmp="$(mktemp -d "$RUN_TMP/suite.XXXXXX")"
    suite_home="$suite_tmp/home"
    mkdir -p "$suite_home/.claude/cache"
  fi
```
Whenever `LEADV2_SUITE_SHARDS` is greater than 1 — the default for any bare, full `run-core-offline.sh`
invocation, confirmed by the `SHARD_RESULT idx=0..3` lines in the full run — **every** suite body
gets `HOME` pointed at a fresh, empty directory, for isolation between suites running concurrently
in different shards. `test-dod-gate-suite-registration.sh` case (g)
(`PE_ROOT="${LEADV2_DOD_LIVE_REPO:-${HOME}/Projects/persona-engine}"`, line 188) and
`test-shared-sink-test-guard.sh` cases 6/8/13 (`REAL_JOURNAL="${HOME}/.claude/cache/..."` /
`REAL_LEDGER="${HOME}/.claude/dispatch-ledger/..."`, lines 42-45) both deliberately resolve paths
against `$HOME` as their acceptance ground truth — the real, shared state, on purpose (that is the
whole point of these two suites: `test-shared-sink-test-guard.sh` verifies write-guards against the
real journal; `test-dod-gate-suite-registration.sh` case (g) verifies the gate parses a real,
external repo's suite map). Under sharding, `$HOME` is the sandbox, not the real one, so both always
fail to find the files they need — deterministically, every time, not intermittently.

Distinct from what the suite's own docstring already discloses: `test-shared-sink-test-guard.sh`'s
header describes the *historical* TESTS-POLLUTE-REAL-JOURNAL-01 bug (fixture rows polluting the real
journal before write-guards existed) — that is not this finding and is not repeated here as one. The
finding here is that the runner's *own* shard-isolation mechanism, added for a different reason
(protecting concurrently-running suites' writes from colliding on the real `~/.claude/cache`
surface), incidentally also blinds these two *read-only* suites to the real state they need to see.

### Confirmed with a targeted reproduction (not just the one full run)

```
$ LEADV2_SUITE_LOCK_DISABLE=1 LEADV2_SUITE_SHARDS=2 \
    LEADV2_SUITE_DEFS_OVERRIDE="dod gate suite registration (both map forms + run-all selection)|||bash .../test-dod-gate-suite-registration.sh
shared-sink test guard (TESTS-POLLUTE-REAL-JOURNAL-01)|||bash .../test-shared-sink-test-guard.sh" \
    bash plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] suites passed=0 failed=2 missing=0   <- SHARDS=2 (matches the failing full-run condition)

$ LEADV2_SUITE_LOCK_DISABLE=1 LEADV2_SUITE_SHARDS=1 \
    LEADV2_SUITE_DEFS_OVERRIDE="<same two suites>" \
    bash plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] suites passed=2 failed=0 missing=0   <- SHARDS=1 (matches every isolated green run)
```
2 suites, 2 shard settings, 100% reproducible each way, same host, same commit — the sharding
setting alone flips the result, with everything else held constant. This is the boundary: it is not
a flake or a race with a hit rate; it is deterministic on whether `LEADV2_SUITE_SHARDS > 1`.

Ruled out for both: `never_reaches_subject` (both suites' real logic executes every time — the
failures are inside the suites' own assertions, not a fixture gap), `rc_127`/`timeout` (both
complete in ~1-2s), and "flaky under load" (0 flakiness observed across repeated runs at each
shard setting — it is 100% deterministic on the shard count, not probabilistic).

### The fix
`run-core-offline.sh`: added `_CORE_OFFLINE_REAL_HOME_SUITES` (a name-matched exemption list,
mirroring the existing `_CORE_OFFLINE_OWNED_SUITES` pattern) naming exactly these two suites, and
gated the `suite_home` sandbox construction on `! _core_offline_suite_needs_real_home "$name"`.
Exempted suites still get their own private `TMPDIR` (unrelated isolation axis, untouched); only the
`HOME` override is skipped for them. Both suites are read-only against the real paths in every case
that reads them (`cp`, `-f` tests, string compares — cases that write, like
`test-shared-sink-test-guard.sh`'s production-emit case, already manage their own internal fake-home
via an explicit env override to the script under test, independent of this outer sandbox), so this
does not reopen the collision risk the sandbox exists to prevent for suites that actually write to
`~/.claude/cache`.

### Negative control (informal, mutate/revert in place)
Mutation: removed the ` && ! _core_offline_suite_needs_real_home "$name"` conjunct (function-body
edit, not a top-level `exit 1`) from the same targeted 2-suite/SHARDS=2 repro above.

RED (mutated): `[CORE-OFFLINE] suites passed=0 failed=2 missing=0` (both suites fail, same
`not found ... /home/...` lines as the original discovery).
GREEN (reverted, byte-identical to the intended fix — confirmed via `git diff --stat`):
`[CORE-OFFLINE] suites passed=2 failed=0 missing=0`.

### Negative control (formal, `leadv2-mutation-control.sh`)
Bare-invocation target: a third purpose-built, non-registered probe,
`docs/handoff/RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01/probe-realhome-suites.sh`
(same rationale as the runner-side lock-leak probe: a plain existing suite doesn't exercise "runs
correctly specifically under `LEADV2_SUITE_SHARDS=2`" the way this fix needs). It runs both suites
through the runner's `LEADV2_SUITE_DEFS_OVERRIDE` hook under `LEADV2_SUITE_SHARDS=2` and asserts
`suites passed=2 failed=0`.

Mutation applied: `s/&& ! _core_offline_suite_needs_real_home "\$name"//` on
`plugins/leadv2/scripts/tests/run-core-offline.sh`.

Artifact: `mutation-control/20260916T094318Z-28527.txt`
```
suite=docs/handoff/RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01/probe-realhome-suites.sh
file=plugins/leadv2/scripts/tests/run-core-offline.sh
anchor=s/&& ! _core_offline_suite_needs_real_home "\$name"//
baseline_rc=0
mutated_rc=1
diff_hash=314fc949869b68d0603ae7edf11710d161a69a25cca10750540cd504d6d44acc
lane_diff_hash=36ec8d0427fde307f42e10b4f0afbc4696d9a4335deaa07e6bb9a9b960cb8487
```
`leadv2-mutation-control.sh` exit code 0 (`MUTATION-CONTROL ok`): baseline green, mutant red,
mutation confirmed landed.

### Final suite run (boundary)
Both suites: green standalone (35/35, 16/16), green under the targeted `SHARDS=1` repro (2/2), green
under the targeted `SHARDS=2` repro post-fix (2/2), on macOS Darwin 25.6.0, this lane's HEAD. A
second full end-to-end `run-core-offline.sh` run with all three fixes in place is the closing
verification — see "Full end-to-end runner run" below for its `SHARD_RESULT` lines and whether these
two suites' names still appear in any `FAILED:` line.

## Re-verification by the resumed lane (2026-09-17)

The worker that produced everything above died before the closing full-battery run. The resumed
lane re-verified each claim independently instead of trusting the dead session's transcript:

- **Lane diff hygiene.** The STOP-GATE auto-checkpoints had swept `docs/leadv2` runtime state
  (lane-liveness share `rc`/`result`/`ts`, the `.compact-freeze.md` marker) and a
  `test-core-offline-lock-01.sh.bak_suite_fix` backup into the branch. All reverted/removed; the
  committed lane diff is now exactly `run-core-offline.sh`, `test-core-offline-lock-01.sh`, and
  this report directory.
- **Paired control, re-run by this lane.** Pre-fix blobs restored in place from dispatch base
  `2fd2c635` (`git restore --source=2fd2c635 …`), acceptance command run, blobs restored to HEAD
  (clean `git status` after):

  ```
  === PRE-FIX blobs, acceptance command (red side) ===
  [LOCK-01]   (a)/(b) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=/var/folders/.../lv2-lock-test.sIhnQo>>>
  [LOCK-01]   (c)     FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=/var/folders/.../lv2-lock-test.sIhnQo>>>
  [LOCK-01] pass=1 fail=2
  rc=1

  === HEAD (fixed), acceptance command, flag injected ===
  [LOCK-01] pass=3 fail=0
  ACCEPTANCE(flag-set) rc=0

  === HEAD (fixed), clean env (paired control) ===
  [LOCK-01] pass=3 fail=0
  CLEAN-CONTROL rc=0
  ```
- **Both probe harnesses re-run, green.** `probe-runner-noleak.sh` → `LEAK_CHECK=UNSET`,
  `suites passed=1 failed=0`, rc=0. `probe-realhome-suites.sh` → `SHARD_RESULT idx=1 pass=1`,
  `suites passed=2 failed=0`, rc=0.
- **Per-variable audit independently re-confirmed** (previously taken from the table above; now
  verified against the code by this lane): both dump variables are read-only in the runner and each
  dump path `exit 0`s before any suite launch (`run-core-offline.sh:1030` scope-dump,
  `:1156` shards-dump); both are also excluded from the lock guard at `:170-171`, so neither even
  produces a re-exec child. `LEADV2_TEST_CONTEXT` is exported at `:131` but stripped per-suite by
  the `LEADV2_*` denylist arm of `_core_offline_build_scrub_args` (`:273`), and
  `lib/leadv2-test-context.sh:51-59` re-derives test context via a 12-hop `ps` ancestor walk when
  the variable is absent. Verdicts unchanged: **no leak** for either dump variable; scrub-by-design
  for `LEADV2_TEST_CONTEXT`.
- **Mechanism spot-check for suites 3-4.** The `$HOME`-rooted real-path reads exist at exactly the
  cited lines: `test-dod-gate-suite-registration.sh:188`
  (`PE_ROOT="${LEADV2_DOD_LIVE_REPO:-${HOME}/Projects/persona-engine}"`) and
  `test-shared-sink-test-guard.sh:42-45` (`REAL_EVENTS_DIR`, `REAL_FP_STATE`, `REAL_LEDGER` all
  `$HOME`-rooted) — which the sharding sandbox at `run-core-offline.sh:388-391` replaces with a
  fresh empty directory for every suite when `LEADV2_SUITE_SHARDS > 1`.
- **Syntax.** `bash -n` clean on all four changed/added shell files (runner, lock suite, both
  probes). No Python files changed.

## Full end-to-end runner run

Command: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` (bare, full battery, no
`LEADV2_SUITE_DEFS_OVERRIDE`, no `--scope changed`).

Command: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` (bare, full battery, no
`LEADV2_SUITE_DEFS_OVERRIDE`, no `--scope changed`), run detached (`nohup`) on this lane's HEAD
`48150574`, macOS Darwin 25.6.0, 2026-09-17.

Result: **69 passed / 24 failed / 0 missing**, `known_red_skipped=0`, wall time **1833 s**
(~30.5 min), 93 suites across 4 parallel shards + 1 serial shard.

```
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=16 fail=5 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=15 fail=6 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=19 fail=4 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=17 fail=3 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=serial pass=2 fail=6 missing=0
[CORE-OFFLINE] suites passed=69 failed=24 missing=0 known_red_skipped=0 repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/3f44760b3faa
```

None of this lane's three suites appears in any `FAILED:` line. Their own in-log summaries are
visible in the battery replay: `[LOCK-01] pass=3 fail=0` (the lock suite green **in situ**, i.e.
under exactly the gate condition that used to make it permanently red) and
`shared-sink test guard: PASS=35 FAIL=0`; the dod-gate suite's replay block ends in an all-PASS
tail (its failure signature from the pre-fix run — `(g) live repo not found at .../home/...` —
appears nowhere in the log).

### Attribution of the 24 failures: exactly the census population minus this lane's three fixes

The census (`docs/handoff/MAIN-RED-SUITES-CENSUS-01/report.md`, "The 27, named") measured 27 red
suites at plan start. This battery's 24 failures are **exactly** that population minus this lane's
three (the only census-red suites now green under the gate: `core-offline cross-run exclusive
lock`, `dod gate suite registration`, `shared-sink test guard`). No suite outside the census
population went red, and no census-red unexpectedly went green.

Two honest bookkeeping notes for the lead, neither a defect of this lane's diff:

- 21 of the 24 are on the `tests/known-red-suites.txt` allow-list; 3 are census-red but **missing
  from the allow-list file** (`burn governor`, `product-close waits for worker exit`,
  `stop-gate autocommit on worker exit`) — an allow-list staleness gap in
  `tests/known-red-suites.txt`, not a new failure (all three names are in the census list at
  `report.md:87/107/111`, which predates this lane).
- The 5 `HERMETIC-VIOLATION (WARN, follow-up)` lines are WARN-class (non-lane-owned suites that
  dirty `docs/leadv2`), a pre-existing property of those suites; none of this lane's three suites
  produced a hermeticity line.

## Changed-scope runner (`tests/run-all.sh --scope changed`)

Run on the same HEAD, same host, 2026-09-17:

```
[CORE-OFFLINE] SCOPE_RESULT selected=9 total=93 base=main@a5af120f42 changed=2 unmapped=0 verdict=selected
[CORE-OFFLINE] suites passed=6 failed=1 missing=0 known_red_skipped=2
[NOT-KNOWN-RED] core:tests/test-run-all-forwards-scope.sh (scope-selected ad-hoc)
```

The scope machinery suites around the changed runner are green
(`scope-changed passed=38 failed=0`, `scope-excludes-nested-housekeeping passed=10 failed=0`,
`known-red-skip` cases pass), and both of this lane's allow-listed suites are correctly skipped in
budget mode (`KNOWN-RED-SKIP` lines above — the full battery just proved them green out of band).

The single `NOT-KNOWN-RED` failure is **inherited, not this lane's diff**:

- Reproduced standalone on this tree: the suite's scratch tree lacks
  `plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh` (`.../run-all-scope-fix.CS7isJ/.../lib/leadv2-suite-discovery.sh:
  No such file or directory` ×5), then `FAIL: scope=all forwards all: fake core-offline stub was
  never invoked`, `1 passed, 1 failed`, rc=1.
- The introducing commit `f206d3ed` ("C5 GATE-DISCOVERS-246-UNTRACKED-SUITES-01: tracked-admission
  lib for suite discovery") is an **ancestor of this lane's merge-base** `a5af120f`
  (`git merge-base --is-ancestor` → true), so the red predates the lane.
- This lane's diff does not touch `tests/run-all.sh` or
  `tests/test-run-all-forwards-scope.sh` (`git diff main...HEAD --stat` over both paths is
  empty). This matches the previously recorded inherited population ("scratch lacks
  lib/leadv2-suite-discovery.sh" reds). Fixing it belongs to whatever lane owns
  `tests/run-all.sh`'s scratch copy-list — outside this lane's write set.

## Left red / anything not fixed
Nothing in this lane's write set is left red. All three mission suites are confirmed green under
the closing full battery (69/24, see above): `test-core-offline-lock-01.sh` (both leak fixes;
standalone, under the mission's exact acceptance command, and in situ under the gate),
`test-dod-gate-suite-registration.sh` and `test-shared-sink-test-guard.sh` (the shard-mode
real-`$HOME` exemption; standalone, under the targeted `SHARDS=2` repro, and in situ). All fixes
live inside the declared write set (`run-core-offline.sh` and `test-core-offline-lock-01.sh`; the
two mystery suites needed no edit to their own files — only their names in the runner's exemption
list).

Still red, by name, with cause — none of it this lane's to fix:

- 24 suites in the full battery, all pre-existing census-red ("The 27" minus this lane's three).
  Owners: the respective lanes of the 93/93 plan. Three of the 24 are additionally missing from
  `tests/known-red-suites.txt` (allow-list staleness, noted above).
- `tests/test-run-all-forwards-scope.sh` under `--scope changed` — inherited scratch copy-list gap
  (missing `lib/leadv2-suite-discovery.sh` in the scratch tree), red since `f206d3ed`, which
  predates this lane's merge-base; owner: the lane holding `tests/run-all.sh`'s scratch logic.
