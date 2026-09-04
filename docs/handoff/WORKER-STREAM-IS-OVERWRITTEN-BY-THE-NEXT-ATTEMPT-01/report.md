# WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01 — report

Attempt-scope the worker stream path (and the sibling cost-pending marker) so a
re-dispatch of the same lane can no longer truncate the previous attempt's
transcript, with zero edits to the locked `leadv2-dispatch-code.sh`.

## What changed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/claude-subsession.sh` | `_lv2_attempt_id()` (`<epoch>-<pid>`, same shape as dispatch-code's `_dl_attempt_token` minus the redundant sig8); `_lv2_repoint_newest_pointer()` (atomic repoint: unique tmp symlink + same-dir `mv -f`, non-fatal on failure); `STREAM_OUT` routed to `$HANDOFF_DIR/attempts/$ATTEMPT_ID/${ROLE}.stream.jsonl`; unconditional activation (mkdir + repoint, every attempt, first included) placed after the DRY_RUN chokepoint so a dry run still touches nothing and both launch paths (--wait and detached) share one call site; `MARKER_FILE` attempt-scoped. Backfill comment added at the code site. |
| `plugins/leadv2/scripts/leadv2-budget-check.sh` | Fallback token sum widened to the "all attempts" reader: walks top-level `*.stream.jsonl` (regular files only) plus `attempts/*/*.stream.jsonl`; top-level symlinks are excluded so the newest-pointer is never double-counted against its own target. Old-shape dirs (flat regular file, no `attempts/`) behave exactly as before. |
| `tests/run-all.sh` | Suite registered: one `add_suite` line + two `EXTRA_SUITE_MAP` rows (`claude-subsession.sh:…` and `leadv2-dispatch-code.sh:…` — the second so a future change to the locked file re-runs this suite under `--scope changed`). |
| `plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh` | New suite, 22 cases (A1/A2/A3/B1), described below. |

Design and naming follow the brief's §3 option (c): per-attempt subdirectory +
top-level symlink newest-pointer. All audited readers stay symlink-transparent
(`os.stat`/`open`/existence checks) and the three non-recursive top-level globs
see exactly one `*.stream.jsonl` match — identical cardinality to today.

## Deliberate deviation from the brief: marker filename shape

The brief's §3 names the marker `<role>.cost-pending.<epoch>-<pid>.yaml`, but
its own §3 also requires "`leadv2-cost-flush.sh` needs no code change". Those
two are incompatible: cost-flush *discovers* markers by glob, and the glob is
suffix-anchored.

Probe artifact (live tree):

```
$ grep -n 'cost-pending' plugins/leadv2/scripts/leadv2-cost-flush.sh
187:  for m in "$TARGET_DIR"/*.cost-pending.yaml; do
194:    for m in "$HANDOFF_ROOT"/*/*.cost-pending.yaml; do
```

An id placed AFTER the literal `.cost-pending.yaml` suffix would orphan every
marker from discovery; markers would accumulate forever and costs would never
flush. Implemented as `<role>.<attempt-id>.cost-pending.yaml` — distinct per
attempt AND still matched by both globs. `flush_marker()` reads role/stream
path from marker *content*, not filename (verified at :55-62), so no change is
needed there. Mutation control #3 proves the naming contract end to end.

## Test suite (`test-stream-attempt-isolation.sh`, 22 cases, green)

- **A1** (control #5 fixture shape): two `--wait` dispatches, identical
  `--task-id`, fake `claude` binary on PATH, real launcher logic. Asserts
  launcher rc=0 on both calls (checked synchronously before any filesystem
  assertion), two distinct attempt dirs, both real stream files exist, contents
  differ, flat name is a symlink resolving to attempt #2. Setup self-check:
  fake-claude marker string grepped out of both streams.
- **A2**: pointer exists and resolves after the FIRST attempt (repoint is
  unconditional, never lags).
- **A3**: detached arm — two pending-cost markers coexist with distinct
  attempt-scoped names, each recording its own `attempts/<id>/…` stream path
  (the exact path cost-flush flushes from marker content).
- **B1**: budget fallback sums all attempts exactly (fixture: flat regular 10 +
  pointer target 50 + second attempt 100 = `spent: 160`) and does not
  double-count the pointer (no `spent: 210`).

Containment: the suite copies the whole scripts tree to a tmp plugin dir and
runs THE COPY only; md5 tripwire on both real production files
(TEST-DESTROYS-PRODUCTION-SCRIPT-01 pattern). Bash 3.2-safe (no mapfile etc.).

Test-only note: A3 no-ops the two `rm -f MARKER_FILE` cleanup sites **in its
own copy** — both cleanup waiters cannot `wait` across the setsid/subshell
boundary, so in production the marker window is milliseconds and a
coexistence assertion would be racy. This makes the marker observable without
changing the naming contract under test. (The early-rm itself is a pre-existing
weakness of the W6 marker mechanism — markers are auto-deleted near-instantly
on the detached path — out of this lane's scope, flagged here for the owner.)

## Negative controls — 5/5 red-capable

All via `leadv2-mutation-control.sh` (baseline green, mutant red, artifacts in
`mutation-control/` next to this report):

| # | Mutation | Suite line that went red |
|---|---|---|
| 1 | `_lv2_attempt_id()` returns constant `0-0` | `FAIL: A1: setup self-check — fake claude ran twice (2 attempt dirs, got 1)` |
| 2 | repoint call disabled (`if false; then`) | `FAIL: A2: flat newest-pointer is a symlink` |
| 3 | marker reverted to flat `${ROLE}.cost-pending.yaml` | `FAIL: A3: TWO pending-cost markers coexist (attempt#1 not overwritten)` |
| 4 | budget `attempts/` walk disabled | `FAIL: B1: fallback sums ALL attempts exactly (spent: 160)` |
| 5 | STREAM_OUT reverted to flat path + repoint disabled (the whole defect) | `FAIL: A2: exactly one attempt dir exists (got 0)` |

Artifacts: `docs/handoff/WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01/mutation-control/*.txt`.

## Self-check (honest)

- `bash -n` on all three changed shell files: exit 0.
- `python3 -m py_compile`: n/a (no Python files changed; the embedded python in
  budget-check is exercised by B1, which passes).
- Suite: `22 passed, 0 failed`, rc=0 (raw output in final report to lead).
- Registration proof: `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh
  --scope changed` → `[SELECT] …/test-stream-attempt-isolation.sh` among 8
  selected, `run-all: 8 selected, scope=changed, select_only=1`.
- Coupled existing suites re-run: turncap 2/0, absolute-handoff 3/0,
  context-diet 13/0, soft-finish 3/0, worker-outlives 11/0,
  carrier-map 5/0 — all green.
- **Pre-existing red, bisected and NOT caused by this lane**:
  `test-claude-subsession-sentinel.sh` fails 5 cases (false-dead/finalized
  E2/E3 block). Re-run against the pre-change `claude-subsession.sh`
  (`git show HEAD:…` copied over a tmp tree, same suite): identical 5
  failures → environment/timing red in this worktree, present before the
  change. Untouched by this lane.

## Retention & backfill (specified, not built — per brief §5/§6)

No pruner shipped. The contract a future pruner must satisfy: keep every
attempt dir of any dispatch whose ledger state ∉ {landed, dead, refused};
prune beyond N=3 attempts only after terminal + 14-day grace; never key on
mtime alone (the 2026-09-03 failure shape wearing a retention hat); cross-check
`active.yaml` `log_path` resolution before deleting anything a live lane
resolves through. Backfill: none — old-shape dispatch dirs stay as-is; the
code comment at the attempt-scoping block states that a missing `attempts/`
dir predates attempt-scoping and the flat file there is definitionally the
last recoverable attempt.

## Scope discipline

`git status` at finish: exactly `claude-subsession.sh`,
`leadv2-budget-check.sh`, `tests/run-all.sh` (modified) +
`test-stream-attempt-isolation.sh` (new) + this handoff dir. The locked
`leadv2-dispatch-code.sh` is untouched (`git diff --name-only` verified).
