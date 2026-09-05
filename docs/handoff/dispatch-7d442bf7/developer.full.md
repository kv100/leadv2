verdict: APPROVE
next_action: review_round_2

# GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01 — developer full report

Worktree: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01
Commit: 10fcfa8d "fix(gate): timeout on e2e gate must not be indistinguishable from a real regression"

## What changed and why

The defect was already root-caused in the mission: `leadv2-phase8-e2e-gate.sh`
correctly wrote `status: unknown\nreason: e2e_timeout` to `e2e-gate.md` on
rc==124, but then did `exit 1` — the same exit code used by the generic
blocked/regression paths. Its one conflating consumer,
`leadv2-phase8-close.sh`, treated any non-zero exit identically:

```
bash "$E2E_GATE_SCRIPT" "$TASK_ID" || e2e_rc=$?
if [[ $e2e_rc -ne 0 ]]; then
  log_error "E2E gate failed (exit ${e2e_rc}) — see docs/handoff/${TASK_ID}/e2e-gate.log"
  exit 1
fi
```

### 1. plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh

Timeout branch (was `exit 1`) now:
- computes `commit="$(git -C "${_p8_e2e_root}" rev-parse HEAD 2>/dev/null || echo unknown)"`
- writes `e2e-gate.md` with added `commit:` and `gate: phase8_close` fields:
  ```
  status: unknown
  reason: e2e_timeout
  rc: <rc>
  timeout_s: <timeout>
  commit: <sha or unknown>
  gate: phase8_close
  ```
- exits **5** instead of 1 (5 was unused in this script — verified via
  `grep -n 'exit [0-9]' leadv2-phase8-e2e-gate.sh` before picking it; it also
  mirrors the "parked" exit-5 convention already used elsewhere in
  leadv2-dispatch-product-close.sh).

All other exit-1 paths in this script (blocked/no_entrypoint/regression) are
UNCHANGED — only the rc==124 branch's exit code and printf changed.

### 2. plugins/leadv2/scripts/leadv2-phase8-close.sh

Consumer block changed from:
```bash
e2e_rc=0
bash "$E2E_GATE_SCRIPT" "$TASK_ID" || e2e_rc=$?
if [[ $e2e_rc -ne 0 ]]; then
  log_error "E2E gate failed (exit ${e2e_rc}) — see docs/handoff/${TASK_ID}/e2e-gate.log"
  exit 1
fi
```
to:
```bash
e2e_rc=0
bash "$E2E_GATE_SCRIPT" "$TASK_ID" || e2e_rc=$?
if [[ $e2e_rc -eq 5 ]]; then
  log "INFO: gate inconclusive, work committed — E2E gate timed out (exit ${e2e_rc}); see docs/handoff/${TASK_ID}/e2e-gate.md"
  {
    printf 'status: inconclusive\nreason: e2e_timeout\ngate: phase8_close\ntask: %s\nnote: gate inconclusive, work committed\n' \
      "${TASK_ID}"
  } >> "${LEADV2_HANDOFF_DIR}/${TASK_ID}/close-state.md" 2>/dev/null || true
  exit 5
elif [[ $e2e_rc -ne 0 ]]; then
  log_error "E2E gate failed (exit ${e2e_rc}) — see docs/handoff/${TASK_ID}/e2e-gate.log"
  exit 1
fi
```
`LEADV2_HANDOFF_DIR` is already an established convention in this same file
(used at lines for `_close_flag` and `RED_FIRST_REPORT`, both
`${LEADV2_HANDOFF_DIR}/${TASK_ID}/...`), sourced from `leadv2-helpers.sh`
(`LEADV2_HANDOFF_DIR="$LEADV2_PROJECT_ROOT/docs/handoff"`) — confirmed with
`grep -rn 'LEADV2_HANDOFF_DIR=' leadv2-helpers.sh`. Also added an "Exit codes"
doc-comment line (`5  E2E gate inconclusive ...`) at the top of the file.

The message uses `log` (INFO), never `log_error`, and contains the literal
substring "gate inconclusive, work committed" as required by the mission.

### 3. leadv2-dispatch-product-close.sh — verified already correct, untouched

Grepped `e2e_timeout|_dl_note|_stamp_review_terminal` across the file. Its
own standalone timeout branch (separate code path, its own `e2e-gate.md`
write at line ~2803) already does:
```
printf 'status: unknown\nreason: e2e_timeout\n...' > "${HANDOFF}/e2e-gate.md"
...
_dl_note parked e2e_timeout "rc=${e2e_rc} timeout_s=${_pc_e2e_timeout_s}"
_stamp_review_terminal blocked
```
— `parked`/`blocked` is a distinct terminal from `dead`/`fail` used by the
real regression branch a few lines below (`_dl_note dead e2e_regression`).
This is exactly the correct behaviour the mission described; **left
unmodified**. (Did NOT add `commit:`/`gate:` fields to this script's
`e2e-gate.md` — mission scoped that addition to leadv2-phase8-e2e-gate.sh
only, and this file's write is a separate, already-correct code path with
its own review history; adding fields here was out of scope and risked
touching a script explicitly not enumerated in the "what to build" list.)

### 4. leadv2-status-surface.sh — no lane-alive/dead consumer of e2e-gate.md's status field found

`grep -n "e2e-gate" leadv2-status-surface.sh` → only `close_dir_mtime()`
around line 803, which uses **mtime only** (newest file mtime under
`docs/handoff/dispatch-<sig8>/`) — it never parses the `status:` field out of
`e2e-gate.md`. No fix needed here. Grepped the whole repo for other readers:
```
grep -rln "e2e-gate.md" . | grep -v /tests/
  leadv2-phase8-e2e-gate.sh
  leadv2-dispatch-product-close.sh
```
Those are the only two writers/readers; both handled above.

## Files NOT touched (per mission's do-not-touch list)

leadv2-dispatch-code.sh, leadv2-claude-profile-select.sh,
lib/leadv2-route-arbiter.sh, tests/run-all.sh, tests/known-red-suites.txt,
docs/leadv2/. No retry loop added. No `${BASH_SOURCE[0]}`/`declare -F` zsh
guard used.

## Verification

### bash -n on every changed file

```
$ bash -n plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-phase8-close.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-phase8-e2e-gate-unknown.sh && echo OK
OK
```

### Behavioural proof — real gate script driven end-to-end (T1 in the new suite)

Fixture: fresh scratch git repo, fake e2e entrypoint `sleep 30; exit 0`,
`LEADV2_PHASE8_E2E_TIMEOUT_S=1` (portable-watcher timeout kills it at 1s,
rc=124).

Before (pre-fix, on main): `e2e-gate.md` would read
```
status: unknown
reason: e2e_timeout
rc: 124
timeout_s: 1
```
and the gate process would `exit 1` — the SAME code as `status: blocked` /
a real regression.

After (this fix), running the real `leadv2-phase8-e2e-gate.sh`:
```
T1_RC=5
e2e-gate.md:
  status: unknown
  reason: e2e_timeout
  rc: 124
  timeout_s: 1
  commit: <the fixture repo's HEAD sha>
  gate: phase8_close
```
Then running the real consumer block extracted from `leadv2-phase8-close.sh`
(T2, `_run_consumer 5 t2sig` in the new suite) with a stub gate forced to
exit 5:
```
CONSUMER_RC=5
log output contains:
  INFO: gate inconclusive, work committed — E2E gate timed out (exit 5); see docs/handoff/t2sig/e2e-gate.md
NOT containing:
  ERROR: E2E gate failed
close-state.md:
  status: inconclusive
  reason: e2e_timeout
  gate: phase8_close
  task: t2sig
  note: gate inconclusive, work committed
```
Negative control (T3, `_run_consumer 1 t3sig`, a REAL exit-1 failure, no
timeout involved):
```
CONSUMER_RC=1
log output contains:
  ERROR: E2E gate failed (exit 1) — see docs/handoff/t3sig/e2e-gate.log
NOT containing:
  gate inconclusive
```
This proves the exit-5 branch did not swallow real failures — they still
report as failed with the generic path.

### Mutation test (T4) — negative control per changed function

Mutated ONLY the gate script's timeout branch, flipping `exit 5` back to
`exit 1` (byte-diff verified before/after with `diff`):
```
baseline_rc=5   (before mutation, real timeout drive)
mutated_rc=1    (after mutation, same real timeout drive — single cause:
                 only the exit code changed, same status/reason/commit/gate
                 fields still written)
restored_rc=5   (after restoring the original file, byte-identical via diff,
                 re-run confirms behaviour recovered)
```

### Full raw suite output

`plugins/leadv2/scripts/tests/test-phase8-e2e-gate-unknown.sh` (new suite,
self-registers via `tests/run-all.sh`'s changed-`test-*.sh`-file rule):
```
[TEST] PASS: bash -n clean (leadv2-phase8-e2e-gate.sh)
[TEST] PASS: bash -n clean (leadv2-phase8-close.sh)
[TEST] PASS: T1: real timeout -> exit 5, e2e-gate.md has status/reason/commit/gate fields
[TEST] PASS: extraction: consumer block pulled verbatim from leadv2-phase8-close.sh
[TEST] PASS: T2: consumer branches on exit 5 -> logs 'gate inconclusive, work committed' (not log_error), writes close-state.md, exit 5
[TEST] PASS: T3 (negative control): a real exit-1 gate failure still takes the generic failure path, exit 1
[TEST] PASS: T4: mutation applied (verified byte-diff from original)
[TEST] PASS: T4: mutant kills T1's assertion (mutated_rc=1, baseline was 5) -- single-cause: only exit code changed
[TEST] PASS: T4: restoration verified byte-identical to original
[TEST] PASS: T4: restored_rc=5 matches baseline -- restoration confirmed behaviourally too

[TEST] 10 passed, 0 failed
```

`plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh` (existing
suite, updated R3 assertion since the standalone phase-8 gate's timeout exit
code changed from 1 to 5 — this was a direct consumer of the changed
behaviour, not an unrelated fixture weakened to get green):
```
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: R1: rc=124 classifies as status:unknown reason:e2e_timeout, exit 5 (not 8/e2e_regression)
[TEST] PASS: R1: journal records verdict=timeout rc=124
[TEST] PASS: R1: ledger terminal is parked/e2e_timeout, not dead/e2e_regression
[TEST] PASS: R1: worker's write survives as a checkpoint commit despite the timeout terminal
[TEST] PASS: R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8
[TEST] PASS: R2: ledger terminal is still dead/e2e_regression for a genuine failure
[TEST] PASS: R3: standalone phase-8 gate records timeout as unknown, exit 5, and writes no pass sentinel
[TEST] PASS: R3: standalone phase-8 journal records verdict=timeout rc=124

[TEST] 9 passed, 0 failed, 0 not run
```

### 10x bash + 10x zsh, both suites — 40 exit codes total

`test-phase8-e2e-gate-unknown.sh`:
```
bash run 1..10 rc=0 (x10)
zsh run 1..10 rc=0 (x10)
```
`test-e2e-timeout-classification.sh`:
```
bash 1..10 rc=0 (x10)
zsh 1..10 rc=0 (x10)
```
All 40 runs exit 0. The suite has no bash-4+ features (arrays are `-a`
declared without associative syntax, no `${x^^}`, no `readarray`) so it runs
identically under `zsh scriptfile` invocation (zsh interprets the script body
directly; `#!/usr/bin/env bash` shebang is irrelevant when invoked as
`zsh <file>` explicitly, but the script's own syntax is POSIX/bash-3.2-safe
enough that zsh parses and runs it without incident — confirmed by the
matching 0-exit-code output above, not asserted from memory).

### No deletions, new file tracked

```
$ git diff --diff-filter=D --name-only main...HEAD
(empty)
$ git ls-files | grep test-phase8-e2e-gate-unknown.sh
plugins/leadv2/scripts/tests/test-phase8-e2e-gate-unknown.sh
```

### Diffstat

```
$ git diff --stat main...HEAD
 plugins/leadv2/scripts/leadv2-phase8-close.sh      |  18 +-
 plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh   |  12 +-
 .../tests/test-e2e-timeout-classification.sh       |   9 +-
 .../scripts/tests/test-phase8-e2e-gate-unknown.sh  | 232 +++++++++++++++++++++
 4 files changed, 264 insertions(+), 7 deletions(-)
```

Committed on branch `worktree-GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01`, commit
`10fcfa8d`. Not pushed, not merged.

## Left alone / deliberately not done

- `leadv2-dispatch-product-close.sh` — verified correct, no changes (see §3
  above).
- `leadv2-status-surface.sh` — no `status:` consumer found for e2e-gate.md;
  no changes needed (see §4 above).
- Did not add a retry loop (explicitly forbidden by mission).
- Did not touch any file on the do-not-touch list.

DELIVERABLE_COMPLETE
