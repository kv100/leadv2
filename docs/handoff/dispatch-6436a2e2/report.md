# DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01 — continuation report

Continuation of commit `1de50b2c` (writer + seam relocation). This round: the census
deliverable, the tracked-copy verification, the behavioural acceptance battery
(write moved / read works / negative control), the active-registry CI-red attribution,
the `--scope changed` timeout measurement, and one missed reader fixed
(`leadv2-state-compact.sh`).

## Task 1 — writers and readers census (verified, extended)

The repo-wide grep for `LEAD_V2_STATE` names 23 script files + 7 test files. Classification:

**Writers (3)**

| file:line | role | status |
|---|---|---|
| `leadv2-active-registry.sh` — `_leadv2_state_md()` (~:131) | path builder of the regenerator `leadv2_active_render_index` (:1171); auto-refresh after register (:982) and unregister (:1032) | **moved to `leadv2-state-path.sh --no-link` by `1de50b2c`** |
| `leadv2-render-close.sh:57` (`STATE_FILE="${LEADV2_LEAD_STATE_PATH}"`, targeted insert :139–175) | closed-task history insert | inherits the seam fix (`LEADV2_LEAD_STATE_PATH` now resolves to the state root) |
| `claude-subsession.sh` `_write_auto_abort_decision` | `state=paused` marker | **fixed by `1de50b2c`** (seam + resolver) |

**Readers consuming the seam after `1de50b2c`**

- `leadv2-helpers.sh` — `LEADV2_STATE` (:45) and `LEADV2_LEAD_STATE_PATH` (:148, :202) via new `_lv2_state_md_default()` — the single derivation seam
- `leadv2-state-compact.sh:21` — **fixed this round**: it checked the var if exported but never called the resolver, so a bare invocation silently read the stale tracked copy in a lane worktree. Now: var → resolver → old literal (same pattern as the other standalone readers)
- `leadv2-status-snapshot.sh:46–60`, `leadv2-priors-compile.sh`, `leadv2-agent-stats.sh:24,99`, `leadv2-rag-intake.sh:21,74`, `leadv2-backfill-history.sh:20,26`, `leadv2-negative-memory-compile.sh`, `leadv2-pattern-cluster.sh`, `leadv2-outcome-watch.sh`, `leadv2-cost-estimate.sh`, `leadv2-signatures-aggregate.sh`, `leadv2-status.sh`, `leadv2-daemon.sh` (LEADV2_STATE_FILE seam) — all **fixed by `1de50b2c`**
- `leadv2-phase8-assert.sh:173` (`STATE_FILE="${LEADV2_LEAD_STATE_PATH}"`, A4 board check) — inherits the seam fix

**Gate/guard-side references — deliberately untouched (defense-in-depth, verified):**

- `lib/leadv2-dod-gate.sh:27` `_DOD_RUNTIME_STATE_REGEX` + `_dod_check_d` (:409) — the gate itself
- `lib/leadv2-lane-guard.sh:5,:73` — porcelain exclusion set
- `leadv2-lane-watch-v2.sh:160` — explicit `-not -name 'LEAD_V2_STATE.md'` exclusion
- `leadv2-worktree-cleanup.sh:48` — noise-path list
- `leadv2-dispatch-product-close.sh:1421,1429` — comments only, no code

## Task 2 — tracked-copy decision (verified on BOTH mains)

```
$ git ls-tree main docs/LEAD_V2_STATE.md
100644 blob eb6442f2fc7e68f997c5a45ad409f0ba243a200b  docs/LEAD_V2_STATE.md
$ git ls-tree origin/main docs/LEAD_V2_STATE.md
100644 blob eb6442f2fc7e68f997c5a45ad409f0ba243a200b  docs/LEAD_V2_STATE.md
```

Identical blob on both mains, mode 100644, not gitignored — the decision recorded in the
`1de50b2c` commit body (leave tracked as-is; the harness no longer writes there so it can
no longer appear dirty) rests on verified ground. Additional check this round: the tracked
copy contains **zero** `## Recent history` rows, so the fresh state-root view lost nothing
in the migration (no history existed to lose).

## Acceptance evidence

### 1. The write moved — hermetic + in-vivo

Hermetic (scratch repo as lane worktree, `LEADV2_STATE_ROOT` sandbox, real writer path):

```
[registry] rendered /tmp/dod-accept-mD2h/state/LEAD_V2_STATE.md (1 sessions, history_preserved=False)
=== asserts ===
OK-1: no docs/LEAD_V2_STATE.md created in lane worktree
LEAD_V2_STATE.md
active.yaml
active.yaml.lock
1            <- grep -c ACCEPT-DEMO-01 in $SB/state/LEAD_V2_STATE.md
```

(The first sandbox attempt aborted by design — the resolver's guard refused to touch a real
checkout when `PROJECT_ROOT` was not threaded; threaded it and the run went green.)

In-vivo: this lane worktree's `docs/LEAD_V2_STATE.md` is **clean in `git status`** after
~40 min of live harness activity, while the shared-root view is fresh (mtime 12:54, this
dispatch's bookkeeping) and contains this lane's row:

```
| DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01 | build | Standard | 2026-09-04T09:44 | no |
```

### 2. The read still works — named surfaces

- **`leadv2-status-snapshot.sh`** ("=== LEAD_V2_STATE tail ===" section) — live run renders
  the tail of the **moved** view (row table from `~/.claude/leadv2-state/leadv2/LEAD_V2_STATE.md`),
  output above in transcript; the section header proves the resolver-wired read.
- **`leadv2-state-compact.sh`** ("=== Recent history (LEAD_V2_STATE) ===") — the reader found
  the moved file (no `(missing ...)` branch) and prints its history section, empty by design:
  the tracked copy never had history rows either (verified above).
- Hermetic loop: sandboxed `state-compact` shows the freshly registered row
  (`ACCEPT-DEMO-01 phase=intake class=Light started=2026-09-04T11:26`).

### 3. Negative control (mandatory)

Restored-write diff fed to the gate's `_dod_check_d`:

```
NEG: dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md rc=1
```

Positive control — the lane's real round diff, built exactly as product-close builds it
(`git diff HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff'`, product-close:1883):

```
POS2(real construction, lane diff): dod_pass check=runtime_state rc=0
```

(A first positive attempt with a bare `git diff 26f803c0` failed on **foreign sessions'
dirt** — `docs/handoff/dispatch-nw*` phases.d files and other lanes' journals. That is the
gate working correctly, not a defect: the real construction excludes those paths, and with
the excludes the lane passes. Note `docs/LEAD_V2_STATE.md` is NOT in the exclude list — the
gate still checks it, by design.)

### 4. Counter (report-only)

The only handoff artifact currently carrying the defect verdict is **this dispatch's own
first attempt** (`docs/handoff/dispatch-6436a2e2/`, gate run at 12:58, one minute after the
fix commit — leftover pre-fix dirt in the lane worktree, since cleaned; worktree verified
clean now). No new lane artifact carries the verdict. Reported, not treated as proof —
item 3 above is the measurement.

## Active-registry suites and the CI red (Addendum 1)

```
test-active-registry-update-phase   rc=0  (PASS=7 FAIL=0, plain env)
test-active-registry-failclosed     rc=0  (PASS=3 FAIL=3→0, plain env)
```

Faithful CI-pool emulation (run-core-offline sharded branch: all `LEADV2_*`/`CLAUDE_*`
scrubbed, empty sandboxed `HOME` with `.claude/cache`, `PYTHONUSERBASE` = real user base):

```
=== Results: PASS=7 FAIL=0 === All tests passed.
```

**Attribution of the CI red** (`bash: line 4: leadv2_active_register: command not found`):

- In `bash -c '` snippets the first line is empty, so line 4 = the `leadv2_active_register`
  call and line 3 = `source .../leadv2-active-registry.sh`. To reach line 4 under
  `set -euo pipefail`, the `source` must have **succeeded without defining anything** —
  i.e. the CI run executed stale/empty on-disk bytes of the registry script, the same
  mechanism this repo recorded before ("rc=2-everywhere was stale on-disk bytes").
- A red I *could* reproduce — `PyYAML not found` → suite red — happens only when the
  runner's `PYTHONUSERBASE` crutch is omitted from the scrubbed env; with it, green. The
  PyYAML dependency predates the fix (present at `1de50b2c^` at :245/:1166/:1265).
- Verdict: the red does not attach to this lane's code; both candidate mechanisms predate
  it. Suite is green locally in both envs on this commit.

## `test-lane-registry-outlives-dispatcher` — red, pre-existing (falsification honesty)

Red here (`dispatch exited 4` before the stub lane-pulse watcher starts; 6 FAILs) — and
**byte-identically red on `1de50b2c^`** (run in a throwaway worktree at the parent commit:
same 6 FAILs, passed=4 failed=6). Pre-existing, not caused by the relocation. Exact exit-4
site among dispatch-code.sh's five `exit 4` paths (:7569/:7696/:7749/:7806/:7824) not
isolated — the suite swallows dispatcher output. Named and left red per the addendum
(no blind fix, no silencing); NOT added to known-red-suites.txt (untouched file).

## `--scope changed` timeout measurement (the owed numbers)

- **files changed: 15** (the parked run's diff)
- **seconds: 900 — the cap** (`e2e_gate verdict=timeout rc=124 timeout_s=900`, from the
  parked verdict; the gate ran the full budget and was killed)
- **suites selected: not recoverable from the parked run** (no log survives locally).
  Recomputed now against the live trigger map with stem-equality:
  **5 stem-matched suites** (test-cache-truth, test-stream-attempt-isolation,
  test-worker-outlives-terminal-state, test-lane-registry-outlives-dispatcher,
  test-worker-dod-gate) **+ 3 always-on status suites + core-offline — which is
  ALWAYS-ON in `tests/run-all.sh:114`.** Core-offline alone exceeds 10 minutes
  (measured previously), so a 900 s gate budget cannot cover a changed-scope run
  **by construction** — the overrun is structural, not caused by the 15-file width.

## Falsification set (raw output)

`bash -n` — 16/16 SYNTAX-OK (all changed .sh files listed in transcript, including the
new `leadv2-state-compact.sh`). No .py changed → no `py_compile` due.

```
test-leadv2-state-path                   rc=0
test-active-registry-update-phase        rc=0
test-active-registry-failclosed          rc=0
test-lane-registry-outlives-dispatcher   rc=1   (pre-existing, attributed above)
test-worker-dod-gate                     rc=0
test-cache-truth                         rc=0
test-stream-attempt-isolation            rc=0
test-worker-outlives-terminal-state      rc=0
```

`tests/run-all.sh --scope changed` was NOT run whole: it unconditionally includes
core-offline (run-all:114), and another lane (LANE-PLACEMENT-PIN-RED-01) is live inside
its e2e gate — running core-offline concurrently is the exact forbidden interference
(concurrent runners flip nested suites red). The stem-matched + registry suites above are
the changed-scope set minus core-offline, run in the foreground.

## Environment warning

Root disk hit **100% full (1.3 GiB free)** during evidence gathering — an `ENOSPC` killed
one probe. Own transient artifacts cleaned (~250 KiB; not the cause). Other concurrent
lanes writing suite fixtures/tmpdirs will hit this; surfaced for the founder.

## Files changed this round

- `plugins/leadv2/scripts/leadv2-state-compact.sh` — reader completion (resolver wiring)
- `docs/handoff/dispatch-6436a2e2/report.md` — this report
