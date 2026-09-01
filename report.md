# GLM-ARM-THROUGHPUT-01 — report

## Symptom
One per-repo GLM single-flight lock serialised every lane sharing a repo, and
`glm-flash` (and any `glm` spawn that reached the handle-extraction code)
never actually launched a live worker.

## Fix 1 — lock key is now per lane worktree, not per repo

`plugins/leadv2/scripts/glm-coder.sh`: added `glm_lock_key_for()`, called from
`cmd_bg()` in place of the old `shasum` of the raw `--cwd` string. It resolves
git identity via `git rev-parse --git-common-dir` (absolute, symlink-safe) and
`git rev-parse --show-toplevel`:

- if the common dir's parent is the toplevel itself → this is the **main
  checkout** → key = `common_abs` alone (repo-wide, deliberately — real
  collision risk there, per mission spec).
- otherwise → this is a **linked worktree** → key = `common_abs|toplevel`
  (each worktree gets its own key; the shared common-dir component still ties
  them to the same repo for the main-checkout case).
- non-git `--cwd` falls back to hashing the raw path (unchanged behaviour).

The existing "no `started` marker → refuse, never reclaim as age=0" rule and
the rc-75 `LEADV2_DISPATCH_REFUSED: lock_busy` contract are untouched — only
the key computation changed.

## Fix 2 — glm-flash / glm handle extraction

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `_spawn_worker_body`'s
`glm|glm-flash)` case: `glm-coder.sh bg` prints the bare run_id **once**
(e.g. `260902-000858-repo-60fa`) — never a doubled `$handle$handle`, never
with a `$RUNS/` prefix. The prior code assumed a doubled format and took the
"first half" of the last slash-segment, which truncated every real handle to
a garbage string that `status <handle>` never resolved — so every
glm/glm-flash spawn silently died with `spawn_failed ... not_live`. Fixed by
trimming only the trailing newline; the run_id **is** the handle.

The identical halving bug still exists in the sibling `kimi)` case
(`_kimi_half` etc., ~line 5056). `kimi-coder.sh` is not in this lane's write
set — left as a documented, out-of-scope finding for a future lane.

## Tests added

- `plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh` (7 checks): two
  worktrees of one repo both acquire; same-worktree second `bg` refused
  (rc75 + `lock_busy` marker); a subdir of an occupied worktree also refused;
  main checkout keeps its repo-wide lock (root and subdir); an embedded
  scratch-copy mutation control proves the fix is actually exercised.
- `plugins/leadv2/scripts/tests/test-glm-flash-handle.sh` (8 checks):
  launcher-level (`GLM_MODEL=glm-5.3-flash bg` → non-empty handle, `status`
  true, correct `model:` line) and dispatcher-level (a real
  `leadv2-dispatch-code.sh` spawn on the glm arm journals `worker_spawned`
  with a handle that `status` resolves, no `spawn_failed .../not_live`).
- Both registered in `tests/run-all.sh`'s `EXTRA_SUITE_MAP` so `--scope
  changed` picks them up for `glm-coder.sh` / `leadv2-dispatch-code.sh`.
- Both hermetic: stub `claude` binary, temp `GLM_RUNS_DIR` /
  `LEADV2_GLM_LOCK_ROOT`, `GLM_SKIP_QUOTA_GATE=1`, no network. Each runs in a
  few seconds.

## Mutation negative controls — RUN, red captured, then reverted

### (a) Lock key reverted to repo-only

Manually flattened `glm_lock_key_for()`'s if/else to `key="${common_abs}"`
(the exact pre-fix bug) directly on the working-tree `glm-coder.sh`, ran
`test-glm-lock-per-lane.sh`:

```
[TEST] PASS: bash -n glm-coder.sh (incl. 3.2)
[TEST] FAIL: (a) worktree serialization survived: a1=[rc0	260902-002115-wt-a-20e3] a2=[rc75	]
[TEST] PASS: (b) same-worktree second bg: rc 75 + lock_busy marker
[TEST] PASS: (b2) subdir of occupied worktree refused (key resolves the worktree root, not the cwd string)
[TEST] FAIL: (c) main checkout wrongly blocked by a worktree run: [rc75	]
[TEST] PASS: (c) main checkout stays repo-wide: second run at root AND at a subdir refused
[TEST] PASS: mutation_control_repo_only_key_collides_across_worktrees (RED reproduced — confirms case (a) actually exercises the fix)
test-glm-lock-per-lane: 5 passed, 2 failed
EXIT=1
```

Cases (a) and (c) correctly went red — a repo-only key collapses two
worktrees onto one lock, exactly the reported incident. Reverted from
`/tmp/glm-coder.sh.orig-backup`; re-ran clean: **7 passed, 0 failed**.

### (b) Handle-halving bug reintroduced

Reinstated the old halving logic in `leadv2-dispatch-code.sh`'s
`glm|glm-flash)` handle-extraction line, ran `test-glm-flash-handle.sh`:

```
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: launcher: glm-5.3-flash bg prints a non-empty handle (260902-002616-repo-4d5f)
[TEST] PASS: launcher: status <handle> true right after bg
[TEST] PASS: launcher: run record names model glm-5.3-flash
[TEST] FAIL: dispatcher: no worker_spawned handle — journal tail: ... arm_refused by=router model=freepool ... dispatch_rolled_back reason=all_arms_unavailable task=c9585207 attempts=glm-flash_failed_launcher,glm_refused_lock_busy,glm_failed_launcher,... dispatch_terminal task=c9585207 terminal=dead cause=all_arms_unavailable
[TEST] FAIL: dispatcher: spawn_failed not_live/empty_handle present (handle parser broke the run id)
[TEST] PASS: dispatcher: status true on the journaled handle
test-glm-flash-handle: 6 passed, 2 failed
MUTATED_FLASH_EXIT=1
```

The dispatcher case correctly went red (`glm-flash_failed_launcher`,
`all_arms_unavailable`) — reproducing the reported production symptom.
Reverted from `/tmp/leadv2-dispatch-code.sh.orig-backup`; re-ran clean:
**8 passed, 0 failed**.

## Final state (all green)

- `test-glm-lock-per-lane.sh`: 7 passed, 0 failed
- `test-glm-flash-handle.sh`: 8 passed, 0 failed
- `bash -n` and `/bin/bash -n` (macOS 3.2) clean on all 5 changed files:
  `glm-coder.sh`, `leadv2-dispatch-code.sh`, `tests/run-all.sh`, both new
  test files.

## Known out-of-scope finding
`kimi-coder.sh`'s spawn path in `leadv2-dispatch-code.sh` (`_kimi_half` etc.)
has the identical handle-halving bug. Not fixed here — `kimi-coder.sh` is not
in this lane's write set.
