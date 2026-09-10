# REGISTRY-SILENT-RC0-01 — six silent rc=0 sites in one file

Wave B0. File: `plugins/leadv2/scripts/leadv2-active-registry.sh` ONLY.

Six backlog rows share one owner file, so they land as one lane:

| row | site | defect |
|---|---|---|
| 4811e46fdee0 | :532-534 python `unregister` op | rewrites file unchanged, rc=0 when task_id not found; no removed-vs-noop signal |
| 622a2688839a | :952-956 `leadv2_active_set_worktree` | no-ops rc=0 when the target worktree path does not exist; leaves a stale `worktree` field |
| 7780073d7881 | :993-1009 + python `update_phase` :547-573 | missing-file guard AND no-else unmatched task_id both rc=0 without setting phase |
| 80158b9df1d6 | :1012-1021 + python `update_pulse` :575-581 | same shape; pulse timestamp never recorded |
| d7a791c7ce36 | :1106-1114 + python `set_worker_pid` :743-772 | unknown task_id is a documented SILENT no-op rc=0; worker pid never stamped |
| f9c01f58b283 | :969-983 `leadv2_active_unregister` | returns 0 without unregistering when active.yaml is missing |

## The rule this lane establishes
An operation that did not do its work must not return 0. Each site gets a distinct
non-zero code (or one shared "no-op" code documented in the file header) plus a
one-line diagnostic naming the task_id and the reason (not-found / file-missing /
path-absent). Callers that legitimately tolerate a no-op must say so explicitly
with a comment — never by accident.

## Deliver
1. All six sites fixed as above.
2. `grep -rn leadv2_active_` across the plugin repo: every caller audited. Any that
   now breaks on a non-zero is either fixed or given an explicit commented tolerance.
   List the audited call sites in your report.
3. Suite: `plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh`
   with one case per site, driving the REAL functions against a scratch state dir.
   Do not stub the function under claim.

## Negative control (declare it, and RUN it)
Six mutations, one per site: restore `return 0` inside each function body.
The suite must go red on EACH — a single mutation proves nothing against six
independent readers. Paste all six red outputs to
`docs/handoff/REGISTRY-SILENT-RC0-01/round1-red.txt`.

## Off limits
Do not touch `leadv2-journal.sh`, `leadv2-phase-record.sh`, or
`leadv2-state-path.sh` — other lanes own them this round.

## Done
- six sites non-zero + diagnosed, suite green clean and red under each of six mutations
- caller audit listed in the report
