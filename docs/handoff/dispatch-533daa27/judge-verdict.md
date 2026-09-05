# Judge verdict — lane dispatch-533daa27 (LANE-WRITESET-REGISTRY-01)

- **verdict:** APPROVE
- **confidence:** 0.92
- **adjudicated_head:** 8537856 (branch `worktree-533daa27`)
- **blocking_issues:** [] (none)

## Round-2 findings re-checked against HEAD (not against the lead's summary)

**H1 — two-phase TOCTOU / `_lv2_ws_pending` absent → REFUTED (stale-diff artifact confirmed).**
`git show HEAD:plugins/leadv2/scripts/leadv2-active-registry.sh` contains `_lv2_ws_pending` at 3
sites: doc note :40, definition :192, call site :270. The call site sits INSIDE the `fcntl.flock`
block, BEFORE the D7 unknown/enforce split, and `sys.exit(5)` fires unconditionally — i.e. it is
not gated on `LEADV2_WRITESET_ENFORCE`, which is what the finding demanded. Suite case
"H1: a lane mid-resolution (writes not yet persisted) refuses an intersecting concurrent register,
even under warn" passes. Not open.

**M1 — `writeset_drift_conflict` losing its cause in the `!= partial_diff` reclassification →
REFUTED (fixed at 963687c, tested at 8537856).**
`leadv2-dispatch-product-close.sh:2306` reads
`if [[ "${blocked_reason}" != "partial_diff" && "${blocked_reason}" != "writeset_drift_conflict" ]]`.
Test at `tests/test-writeset-admission-block.sh:210-238` asserts both arms (drift_conflict keeps
`_pc_cause`, other non-partial reasons still reclassify). Medium anyway — would not have blocked.

## Independent verification run by the judge

Suite executed by me in the lane worktree: `PASS=7 FAIL=0`, including the H1, H4 and M1 cases.
Lane tree is clean under `plugins/` (`git status --porcelain -- plugins/` empty), so HEAD is what
runs — no working-tree-only fix this time. The only dirty paths are lead-owned runtime state
(`docs/leadv2/bus.jsonl`, `active.yaml`, lock files, other lanes' phase yaml), none of which are
in the diff under judgement.

## off_limits compliance (plan context.yaml:202-208)

- `leadv2-writes-overlap.sh` — FROZEN, honoured: `git diff --stat main...HEAD` on that path is empty.
- `tests/test-writes-overlap.sh` — append-only, honoured trivially: untouched (empty diff).
- `LEADV2_WRITESET_ENFORCE` — still defaults to `warn` at BOTH read sites, registry.sh:251 and
  registry.sh:378. Only tests pass `=block` explicitly.
- No consuming-repo paths: `git diff --name-only main...HEAD | grep -E 'persona-engine|m3-market|respiro-ios'`
  → none. All 7 changed files are canonical `plugins/leadv2/**` inside the leadv2 repo.
- `docs/leadv2/active.yaml` not in the diff (its working-tree modification is live registry state
  written through the flocked ops, not a hand-edit).
- `leadv2-fanout.sh` / `leadv2-supervise-loop.sh` — untouched.

## Non-blocking note (Low, do not re-open a round for it)

`LEADV2_WRITESET_PENDING_WINDOW_SEC` (registry.sh:~203, default 900) is a new env knob that exists
only in the two lines that read it — no registry row, no `leadv2.md` mention. Advisory: document it
on the next touch of that file. It does not affect correctness; the default is safe and the guard
fails closed on an unparseable/absent `started_at`.

## Contradiction scan

env-var names vs settings: consistent (`LEADV2_WRITESET_ENFORCE` spelled identically at both read
sites and in all test invocations). Flag semantics: rc=5 = conflict/pending, rc=6 = unknown-under-
block, rc=0 = admit — used identically in code and in the suite's assertions, no arm reused for two
meanings. Path existence: all 7 diff paths resolve in the worktree; `test-writeset-admission-block.sh`
is registered in `tests/run-core-offline.sh` (+1 line), matching the lead's shard=3 idx=19 claim.
Result: **none**.

## Rationale

Both round-2 findings are closed against the adjudicated HEAD, verified by me at file:line rather
than from the lead's prose, and the one that mattered (H1) is the stale-diff artifact the escalation
predicted — the guard is committed, is inside the lock, precedes the enforce split, and is exercised
by a passing test that names the exact race. The plan's off_limits are intact: the frozen detector
and its baseline suite have byte-identical diffs against main, enforcement still defaults to `warn`
so the gate ships in observe mode, and nothing was edited through a symlinked consuming repo. The
suite is real rather than string-matching — the lead's targeted negative controls (`return False` in
`_lv2_ws_overlaps` reddens exactly the three overlap cases; reverting half the M1 condition reddens
exactly M1) show the assertions bind to behaviour, and CI selects the suite. Nothing critical or high
remains OPEN; the single residual is a Low documentation gap on a new env knob, which by the stated
gate does not block a land.

DELIVERABLE_COMPLETE
