# RECOVER-5FA969AC-01 — recovery of dead branch `worktree-5fa969ac`

Status: **MERGED**. The last of the three branches lost in the 2026-09-04 session
crashes is recovered. Merge commit on lane branch `worktree-RECOVER-5FA969AC-01`
(the lane is `main` + 1 anchor + this merge):

## 1. Merge proof

```
46355906d3e6d2533fc39a8ccc22339123c82666  (Merge: 1d3224d6 e26edc67)
recover 5fa969ac (спасено после падения сессии; контрольная плоскость — ours)
```

`git show --stat` (non-empty), raw output:

```
 plugins/leadv2/config/freepool-arm.yaml            |  7 +-
 plugins/leadv2/scripts/leadv2-dispatch-code.sh     | 13 ++--
 .../scripts/leadv2-dispatch-product-close.sh       | 86 +++++-----------------
 plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh |  6 ++
 .../tests/test-freepool-capability-floor.sh        | 11 +++
 plugins/leadv2/scripts/tests/test-no-work-terminal.sh | 86 ++++++++++++++++++++++
 6 files changed, 137 insertions(+), 72 deletions(-)
```

Control plane resolved per the recover-merge.sh recipe: `docs/LEAD_V2_STATE.md`
ours, `docs/leadv2/{active.yaml,open-threads.md}` symlinks kept (git add),
parked `~worktree-5fa969ac` copies deleted and dropped from the index. No
control-plane path is in the committed diff.

## 2. Eight tracked symlinks intact

```
OK -L .bus-offsets      OK -L .bus.lock         OK -L .merge.lock
OK -L active.yaml.lock  OK -L bus.jsonl         OK -L merge-queue.jsonl
OK -L open-threads.md   OK -L questions         (+ active.yaml)
```

## 3. Foreground suite run: `test-freepool-capability-floor.sh`

Merged tree, run twice (stable):

```
=== 28 passed, 5 failed ===   (both runs)
FAIL: (b) standard build: codex/sonnet do not both rank ahead (codex,freepool)
FAIL: (a) bulk build did not resolve to freepool: dispatch_refused reason=writeset_overlap blocked_by=dispatch-2afd4d44 paths=src/x.py
FAIL: (a) freepool run never completed
FAIL: (a) no diff artifact on disk
FAIL: (e4b) default-mode journal line missing (none)
```

Main baseline (isolated detached worktree at `main`, run twice, stable):

```
=== 26 passed, 5 failed ===   (both runs)
FAIL set identical to the merged run: (b) codex/sonnet, (a)x3 writeset_overlap
(live dispatch-2afd4d44 holds src/x.py in the global registry — a concurrent
live lane, not this merge), (e4b).
```

Same failure set, so the merge introduces **no new red** and **+2 green**
(the two adapted `(b2)` assertions). The suite was red on main before this lane.

## 4. Targeted changed-scope subset (A/B against both parents)

`tests/run-all.sh --scope changed` selects 139 suites for these high-fanout
files — beyond this lane's runtime budget; the four suites that directly cover
the resolved files were run in the foreground, A/B against BOTH parents:

| suite | main | branch e26edc67 | this merge |
|---|---|---|---|
| test-route-arbiter.sh | 10/1 | 10/0 | 10/1 (same fail as main: foreign-project-root WARN — worktree-cwd artifact, absent on the branch's original lane cwd) |
| test-no-work-terminal.sh | 48/0 (old 543-line copy) | 54/4 | 54/4 (identical fail set to branch tip) |
| test-arm-capability-honoured.sh | 1/3 | (suite absent) | 1/3 (identical fail set to main) |
| test-arm-admission.sh | 17/1 | (suite absent) | 17/1 (identical fail set to main) |

**The 4 `no-work-terminal` reds are the dead session's own unfinished work, red
on its own tip (e26edc67), not introduced here.** The branch evolved the suite
(543 -> 626 lines, +10 assertions) to pin the live FP-08 defect: a freepool
diff-writing worker was still classified `no_work` ("the live FP-08 defect").
The session died before production satisfied the pinned contract. Both intents
are preserved verbatim — the evolved suite AND the branch's product-close
dedup — so the pinned contract stays red-and-visible for the follow-up lane
instead of being silently dropped or silently greened.

## 5. Per-file resolution (both intents, how preserved)

- **config/freepool-arm.yaml** — both sides appended the same key
  `capability_floor: bulk_only` with different comment blocks. One key kept;
  main's FP-06 body (env override + journaling + fail-safe) + the branch's
  unique FP-08 clauses (demotes-never-excludes / freepool-only window still
  dispatches; `full` is the flip FP-04's quality gate will make; unreadable
  config degrades to bulk_only).
- **scripts/leadv2-dispatch-code.sh** — branch's FP-08 floor-attribution (parse
  `floor_applied=` from THIS invocation's arbiter output, never the shared
  state file) already landed on main as fix-round H1/H3 with stricter regexes
  + `_MS_FLOOR` telemetry. Code = HEAD (superset); the branch's cross-lane
  attribution-race rationale folded into the comment.
- **scripts/leadv2-dispatch-product-close.sh** — branch's FP-08 dedup kept:
  the copy-pasted standalone `freepool)` liveness case deleted (the shared
  case's body is a verified superset: same PLUGIN-RELIABILITY guards, same
  cross-platform stat), case pattern widened to `glm|glm-flash|kimi|freepool`
  preserving main's `glm-flash` author.
- **scripts/lib/leadv2-route-arbiter.sh** — 6/6 blocks resolved to HEAD: every
  branch change is the round-1 form of a fix main already landed evolved
  (+100 vs +50 floor penalty, atomic same-dir-tempfile JSON state write vs
  bare `arm\n` write, decision-line union already in its third generation).
  The branch's own 3ffef47 had the JSON state write; the checkpoint's bare
  write was WIP regression. Nothing unique lost — verified by reading both
  sides of all six blocks.
- **scripts/tests/test-freepool-capability-floor.sh** — HEAD's 460-line suite
  (cases a-d + FP-06 e1-e4b, which subsume the branch's (config)/(config2)
  flip cases) + one ported assertion from the branch: `(b2)` floor_reason
  raw-class. Ported adapted, not verbatim: on main's routing freepool has no
  heavy/strategic cells, so it never enters `ok` and H1 semantics emit NO
  floor token — the ported assertion pins exactly that (and the raw-class
  vocabulary itself stays pinned by (b)'s `floor_reason=standard/code`).
  A verbatim port was run once and went 2x RED; corrected to H1 semantics.
- **scripts/tests/test-no-work-terminal.sh** — branch's evolved 626-line
  version taken (auto-merge; main's copy was the older RECOVER-TWELVE one)
  + self-registration header added (`# run-all-triggers:
  leadv2-dispatch-product-close`), otherwise it would never run.

## 6. Falsification set

- `bash -n` on all 5 changed shell files: all SYNTAX-OK (dispatch-code.sh,
  dispatch-product-close.sh, route-arbiter.sh, both suites).
- `py_compile`: no .py files changed; the arbiter's 452-line embedded heredoc
  extracted and compiled — `PY-COMPILE-OK`.
- Suite runs: §3 (foreground, timeout 240, twice) + §4 A/B subset.
- Full 139-suite changed scope: NOT run (runtime); selection map captured via
  `LEADV2_RUN_ALL_LIST_TRIGGERS=1`.

## 7. Follow-up for the next lane

`test-no-work-terminal.sh` carries 4 pinned-red assertions (freepool
diff-writing worker exits non-empty path / review.diff non-empty / never
misclassified no_work / terminal row landed). They were red on the dead
branch's own tip; the FP-08 wait-unification fix that satisfies them is the
unfinished work this recovery preserves.
