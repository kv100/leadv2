verdict: APPROVE
next_action: deploy

# developer.full.md — LAST-LINUX-RED-FAST-NAMES-01 / dispatch-261d7cf7

## Status

The fix was already implemented and committed in this lane before this session
picked the task back up: commit `a5de5862` ("fix(status-surface.5s): portable
mtime — GNU stat -f dump killed PAYLOAD_AGE"). This session's job was to
independently verify that work rather than trust the prior report, since no
`context.yaml` or developer deliverable existed yet at
`docs/handoff/dispatch-261d7cf7/` (the prior pass wrote its report to
`docs/handoff/LAST-LINUX-RED-FAST-NAMES-01/report.md` instead — a path
mismatch worth flagging, see "Notable" below).

## Root cause (TWELVE-LINUX-ONLY-SUITES-01 group A, 8th instance)

`plugins/leadv2/scripts/leadv2-status-surface.5s.sh` used the BSD-first mtime
idiom at two call sites:

    $(stat -f %m "$PATH" 2>/dev/null || echo 0)

On GNU coreutils, `stat -f` means "report on the filesystem" and *succeeds*,
printing a multi-line dump beginning with `File:` — so the `||` fallback
never fires. The captured value is that dump; the subsequent
`$(( date +%s - <dump> ))` arithmetic then chokes on the token `File:`, the
assignment never completes, and under the widget's `set -uo pipefail` every
later `[ "$PAYLOAD_AGE" ... ]` reference dies with `File: unbound variable`.
T2 (cold cache) passes on Linux only because it early-exits before reaching
the `PAYLOAD_AGE` site; T3/T4/T5 all traverse it — exactly CI's three
failures (`warm cache`, `stale cache`, `rename hygiene`/`bashpath=''`).

Fix (`plugins/leadv2/scripts/leadv2-status-surface.5s.sh`): a new portable
`_stat_mtime()` helper (`uname -s == Darwin ? stat -f %m : stat -c %Y`,
missing file → 0), used at both call sites (`_kick_refresh`'s lock-age check
and the cached-render `PAYLOAD_AGE` computation). Mirrors the already-fixed
`_mtime()` in the sibling `leadv2-status-surface.sh`.

## Independent re-verification (this session)

### macOS (this machine, commit a5de5862)

    test-status-surface-fast-names: 12 passed, 0 failed
    MACOS_RC=0

### Linux (fresh ubuntu:24.04 container, isolated snapshot — NOT a bind mount
of the live shared worktree, to avoid interference from other concurrent
lanes' writes to docs/leadv2/active.yaml etc.)

Snapshot built via `git ls-files -co --exclude-standard` + tar, extracted to
a throwaway directory under the worktree root (deleted after the run — no
trace left in `git status`). Container: `apt-get install -y git python3`
(python3 is required by T4/T5; its absence produces an unrelated
`python3: command not found` failure that is not part of this bug — first
run without it showed a spurious knock-on `active.yaml fallback` failure in
T1 too, resolved once python3 was installed).

    test-status-surface-fast-names: 12 passed, 0 failed
    LINUX_RC=0

### Negative control (mutation → red → revert → green), same Linux snapshot

Reverted `_stat_mtime "$PAYLOAD"` back to the original
`stat -f %m "$PAYLOAD" 2>/dev/null || echo 0` form via `sed`, re-ran in the
same container:

    FAIL - warm cache (title='.../leadv2-status-surface.5s.sh: line 372: File: unbound variable' ...)
    FAIL - stale cache (title='.../leadv2-status-surface.5s.sh: line 372: File: unbound variable')
    FAIL - rename hygiene (bashpath='' out=.../leadv2-status-surface.5s.sh: line 372: File: unbound variable)
    test-status-surface-fast-names: 9 passed, 3 failed
    MUTATED_LINUX_RC=1

Byte-identical failure signature to CI run `33712162153` (same 3 test names,
same `File: unbound variable`, same `bashpath=''`). Reverting the sed edit
and re-running gave `12 passed, 0 failed` again.

`leadv2-mutation-control.sh` was also tried directly (mutating the same call
site), but it runs the suite on the *host* OS — macOS — where the reverted
code (`stat -f %m ...`) is the *correct* BSD form and is not buggy, so the
mutant survives there by construction (`MUTATION-CONTROL mutant_survived`,
rc=1). That tool cannot demonstrate redness for a Linux/GNU-coreutils-only
defect when run on a macOS host; the Linux-container reproduction above is
the operative negative control for this bug and matches CI's own signature
exactly, which the local-only tool structurally cannot do here.

## DoD gate

Ran `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` standalone against this
lane's actual diff:

    git diff 7a97229e HEAD -- . ':(exclude,glob)**/mutation-control/**'
    LEADV2_LANE_START_SHA=7a97229e bash lib/leadv2-dod-gate.sh <root> \
      docs/handoff/LAST-LINUX-RED-FAST-NAMES-01 <diff> <out>
    -> dod_pass check=suite_registration
       dod_pass check=runtime_state
       dod_skip check=paste_not_required reason=no_brief
       GATE_RC=0

(First attempt used `ca99326b` as base and produced a spurious
`dod_fail check=runtime_state_in_diff paths=docs/leadv2/SINCE-0450.md` —
that file was touched by a shared journal commit merged in before this
lane's own anchor commit `7a97229e`, not by this lane's work; using the
correct lane-start SHA as base resolves it. Worth noting in case other
lanes hit the same false-positive from picking the wrong base.)

## Falsification set

    bash -n plugins/leadv2/scripts/leadv2-status-surface.5s.sh   -> OK (no output, rc=0)
    (no Python files changed)

## Notable / left alone

- The prior pass's report lives at
  `docs/handoff/LAST-LINUX-RED-FAST-NAMES-01/report.md` (lane name), not
  `docs/handoff/dispatch-261d7cf7/` (this task's dispatch id) — a path
  mismatch. Left as-is; not this task's mandate to fix the handoff-path
  convention (a sibling task, HANDOFF-DOCS-INVISIBLE-IN-LANES-01, appears to
  be tracking exactly this class of issue).
- Nothing added to `tests/known-red-suites.txt`.
- No assertion weakened.
- `docs/leadv2/known-red-suites.txt`, `main`, and assertion strength were not
  touched, per the task's off-limits.

## Second re-verification (this continuation-after-crash session)

Re-ran everything independently from scratch, since this session had no
memory of the prior pass beyond the deliverable file:

    git log --oneline -2  ->  a5de5862 (fix), 7a97229e (lane anchor) -- HEAD unchanged, fix already committed
    git diff 7a97229e HEAD --stat  ->  report.md + leadv2-status-surface.5s.sh only (2 files, 78 insertions, 2 deletions)

macOS (this machine, 3x in a row after one incidental single-run flake — a
`FAIL - warm render too slow (wall 2s)` timing assertion, unrelated to this
bug, caused by CPU contention from the many other concurrently-running
lane sessions on this box):

    run1: test-status-surface-fast-names: 12 passed, 0 failed
    run2: test-status-surface-fast-names: 12 passed, 0 failed
    run3: test-status-surface-fast-names: 12 passed, 0 failed
    MACOS_RC=0

Linux (fresh ubuntu:24.04 container via `docker run`, isolated snapshot
under the worktree root via `git ls-files -co --exclude-standard -z | tar
--null -T -`, deleted after the run -- confirmed Docker Desktop does not
share `/tmp` into the VM on this machine, so the snapshot had to live
under the worktree, matching the prior session's approach):

    baseline (fix in place): test-status-surface-fast-names: 12 passed, 0 failed
    BASELINE_LINUX_RC=0

Negative control, same container, `_stat_mtime "$PAYLOAD"` at line 372
reverted to `stat -f %m "$PAYLOAD" 2>/dev/null || echo 0`:

    mutated: test-status-surface-fast-names: 8 passed, 4 failed  (rc=1)
      FAIL - warm cache   (...leadv2-status-surface.5s.sh: line 372: File: unbound variable)
      FAIL - stale cache  (...leadv2-status-surface.5s.sh: line 372: File: unbound variable)
      FAIL - rename hygiene (bashpath='' ...line 372: File: unbound variable)
    MUTATED_LINUX_RC=1

(Failure count varied 3 vs 4 across the two independent mutation runs in
this task's history -- one extra assertion trips under container load;
the three failures this task is scoped to (`warm cache`, `stale cache`,
`rename hygiene`) reproduce identically both times, with the identical
`File: unbound variable` signature CI showed on run `33712162153`.)

Registration check: `test-status-surface-fast-names.sh` is wired into
`tests/run-all.sh` as an always-on `add_suite` call (line 127, alongside
`test-status-surface-bash32.sh` and `test-status-surface-single-lead.sh`,
per the `SWIFTBAR-FAST-NAMES-01` comment) -- added unconditionally, before
the `--scope changed` branch, so it runs under every scope including
`changed`. It was already wired this way before this task; nothing to
register. Confirmed also NOT present in `tests/known-red-suites.txt`
(no match).

`bash -n plugins/leadv2/scripts/leadv2-status-surface.5s.sh` -> clean, rc=0.
No Python files in this diff.

Conclusion: unchanged from the first pass. The fix at `a5de5862` is
correct, committed, and independently reproducible on both platforms with
a working negative control. Nothing further to do for this task.

DELIVERABLE_COMPLETE
