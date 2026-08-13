# W-1a — lane worktree isolation (close-phase diff) — deliverable

**Repo:** canonical `~/Projects/leadv2/plugins/leadv2/`
**Commits:** `589c973` (ensure fires on the dispatch path + sweep-dead) · `fc3ab51`
(reap on the direct-dispatch path + loud "left on disk" line + unit tests)
**Prepass verdict:** the three-point slice was already implemented and committed before
this lane; the work here was (A) land the one uncommitted edit that made isolation fire at
all, (B) close the real residual reap gap on the pump path, (C) add the interim loud line.
No second implementation of `ensure`/`path-of`/`diff_root` was written — that was the single
most likely way to return an empty diff, and it was not taken.

---

## 1. What shipped (two commits, by explicit path)

### 589c973 — make isolation fire + reap dead lane worktrees (W-1a)
The `lane-worktree.sh ensure` call existed, was tested, and was documented — and had never
once fired for a real lane. Only the fanout launcher invoked it; the **direct-dispatch path**
(backlog pump `leadv2-backlog-pump.sh:130`, supervisor pump) ran every real lane in the shared
tree. That is the lying-GREEN pattern in its exact classical form.

- `leadv2-dispatch-code.sh` `cmd_resolve`: call `lane-worktree.sh ensure` **unconditionally**
  on the one call site every lane passes through — fanout's three launch paths, the detached
  per-lane launcher, AND a direct lead dispatch that skips fanout. Keyed on
  `${founder_task_id:-${sig8}}` — the SAME key the close gate's `path-of` fallback
  (`leadv2-dispatch-product-close.sh:386`, `path-of "${FOUNDER_TASK_ID:-${TASK}}"`) uses.
  Keying on this script's own sig8 would make the close gate look in the wrong worktree
  (prepass finding CRITICAL/R1). Fail-open: on any git failure `ensure` returns `PROJECT_ROOT`
  (today's shared-tree behaviour) and the fallback is journaled loudly
  (`lane_worktree_fallback … reason=ensure_fell_back_to_shared_tree`) so a silent fallback is
  never indistinguishable from a working feature.
- `leadv2-dispatch-code.sh` `_lane_writes_guard` `path-of` call: pin
  `LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"` (R2). Unpinned, `resolve_root()` falls back to
  `git rev-parse --show-toplevel` of cwd — inside a lane worktree that resolves to the
  worktree itself, so `lane_dir()` computes `<worktree>/.claude/worktrees` (never exists) and
  `path-of` silently returns empty. The other two call sites already pinned this; this was the
  one that didn't.
- `leadv2-worktree-cleanup.sh`: `--sweep-dead` — lane worktrees (named after the founder task
  id) whose lane is no longer live (`leadv2-lane-liveness.sh`) AND provably empty (clean tree,
  0 commits ahead). A live / dirty / unmerged / `merge-blocker.flag` worktree is KEPT with its
  reason — never forced.
- `tests/test-lane-worktree-isolation.sh`: R2 repro+fix, sweep-dead keep/remove, `--name`
  unmerged refusal, `merge-blocker.flag` refusal.

### fc3ab51 — reap on the direct-dispatch path + loud "left on disk" line (W-1a §3.1/§3.3)
The fanout launcher reaped dead-lane worktrees on its three terminal rc, but the
direct-dispatch path reaches `dispatch-code.sh`'s own EXIT trap instead — so a lane dispatched
that way leaked a worktree when it died without spawning a worker.

- `leadv2-dispatch-code.sh` `_reap_lane_worktree_if_unused`: a verbatim-shaped mirror of the
  launcher's reap, called from the existing `cleanup_pending_dispatch` EXIT trap.
  **Non-destructive:** a dirty tree, unmerged commits, or a `merge-blocker.flag` keep the
  worktree (`cleanup.sh --name` refuses without `--force`, and this path never passes
  `--force`). **Guarded by `_DISPATCH_WORKER_LIVE`:** set to 1 only on the confirmed-spawn path
  (`arc==0`), so a successful spawn NEVER reaps its worktree — the async worker and the close
  gate still need it. Without that guard the EXIT trap would destroy a just-spawned worker's
  empty worktree (at spawn time the tree is clean + 0 commits ahead, so the unguarded reap would
  wrongly remove it). This is exactly why the reap lives behind the spawn flag, not on the trap
  unconditionally.
- `leadv2-dispatch-code.sh` success-spawn path: emit
  `lane_worktree_left task=<sig8> founder_task=<id> path=<abs>` plus a `log` line naming the
  absolute worktree path — the stated interim behaviour (a finished lane leaves its worktree on
  disk with a loud line saying where it is).
- `tests/test-lane-worktree-isolation.sh`: source the REAL `_reap_lane_worktree_if_unused`
  function text and assert no-worker+empty → reaped, no-worker+dirty → kept, live-worker → kept.

---

## 2. Test results (honest)

All run under `/bin/bash` 3.2.57(1)-release.

**The nine named suites — exact counts unchanged:**

| suite | want | got |
|---|---|---|
| test-arm-cooldown.sh | 18 | 18 ✓ |
| test-codex-lockout-agreement.sh | 10 | 10 ✓ |
| test-dispatch-ledger-task-id.sh | 14 | 14 ✓ |
| test-status-surface.sh | 90 | 90 ✓ |
| test-status-surface-cwd.sh | 7 | 7 ✓ |
| test-supervisor-reason-honest.sh | 9 | 9 ✓ |
| test-no-work-terminal.sh | 7 | 7 ✓ |
| test-lock-busy-reresolve.sh | 5 | 5 ✓ |
| test-asked-into-void.sh | 6 | 6 ✓ |

**test-lane-worktree-isolation.sh: 23 passed, 0 failed.** New cases added this lane:
`sweep-dead` keep/remove classification (5), `--name` unmerged + merge-blocker refusal (4),
R2 repro+fix (2), and the dispatch-reap trio (no-worker+empty reaped / no-worker+dirty kept /
live-worker kept) (3).

---

## 3. Live proof — what is real, what remains

A fixture is not acceptance for this defect; the whole point is that reality differed from the
fixture. Below is what was run against the **real** canonical checkout and what could not be
reached here.

### 3a. Real, run on the actual `~/Projects/leadv2` repo
- **`ensure` creates a real isolated worktree.** `ensure w1a-probe standard` →
  `/Users/…/leadv2/.claude/worktrees/w1a-probe`; it appeared in `git worktree list`; `path-of
  w1a-probe` resolved to the same physical path. (Then reaped cleanly.)
- **A real dispatched lane that terminates without a live worker leaves NO orphan.** Ran
  `leadv2-dispatch-code.sh … --task-id w1a-deadlane2` through the real `cmd_resolve`: it hit the
  `ensure` call, classified the mission, reached a terminal no-worker exit (here: parked), and
  `git worktree list` afterwards carried **no** `w1a-deadlane2` entry and the
  `worktree-w1a-deadlane2` branch was gone. This is acceptance item 3's mechanism, for real, on
  the real dispatch path — the EXIT-trap reap fired and left nothing behind.
- **The reap refuses to destroy work.** `--name` on a worktree with unmerged commits or a
  `merge-blocker.flag` refuses (non-zero) and leaves the worktree intact; only `--force`
  overrides (proven by the unit suite on a real git repo).

### 3b. NOT reached in this session — the two-lane `review-gate.md` gate (acceptance 1, 2)
The full live proof — two lanes dispatched at once, each `review.diff.repos` listing only its
own files, each `review-gate.md` carrying a real adversarial verdict (not `unscopable_diff`)
— could **not** be driven to completion in this checkout. Reason, concretely:

- Every mission I dispatched was classified `product` and routed through the **architect
  prepass**, whose `architect` role file is not present in this checkout
  (`[claude-subsession] role file not found in agents/ or roles/: architect`). The prepass
  fails twice and **parks** the task (exit 3) before any worker spawns — so no lane reaches the
  close phase here, regardless of the isolation fix.
- A spawned worker additionally needs a working launcher (`glm-coder.sh` is not at the
  resolved path in this checkout) and the close gate needs the cross-provider Codex review.

This is the lying-GREEN check that only a real fleet run settles, and the production dispatch
environment (architect role + worker launchers + Codex) is not present in this checkout. The
**code under test is committed**, so the gate is now runnable:

```
# from the production leadv2 env (architect role + launchers + Codex present):
LEADV2_LANE_WORKTREE=on LEADV2_REVIEW_DIFF_CROSS_REPO=1 \
  <dispatch two real lanes concurrently, distinct lane_writes each>
# then for each: cat docs/handoff/dispatch-<sig8>/review-gate.md   # expect a real verdict
# kill one worker mid-run, then: git worktree list                  # expect no orphan for it
```

The relevant env switches were asserted at their defaults during probing
(`LEADV2_LANE_WORKTREE` and `LEADV2_REVIEW_DIFF_CROSS_REPO` both unset → on).

---

## 4. The one configuration that silently reproduces the original defect (§4.5)

`LEADV2_LANE_WORKTREE=off` and `LEADV2_REVIEW_DIFF_CROSS_REPO=0` are **independent** switches:
the first stops worktree *creation* (`ensure` returns `PROJECT_ROOT`); the second stops the
close gate *preferring* a lane root. **Turning off only the second while worktrees are still
created yields a diff taken in the shared tree against work that landed in a worktree — an
empty diff.** Both must be flipped together for a full revert. Any live-proof output that shows
`LEADV2_REVIEW_DIFF_CROSS_REPO=0` is testing the wrong thing and will reproduce `unscopable_diff`.

---

## 5. Out of scope — prose only, no code (per the mission)

- **Merge-back policy and conflict handling.** `leadv2-deploy-merge.sh` already does a
  divergence preflight, rebase, and FF-only merge, failing loudly with a `merge-blocker.flag`
  rather than picking a side. Sufficient for this slice; not extended.
- **The multi-repo lane.** `_pc_diff_base` already fails open to "no base" when a recorded sha
  does not resolve in a given repo — the correct conservative behaviour for a cross-repo group.
  Left alone.
- **Heavy-lane cap / lane concurrency floor or ceiling.** Owned by lane C-1, live in this same
  checkout. `leadv2-backlog-pump.sh`, `leadv2-quota-live.sh`, `test-backlog-pump.sh`, and
  `leadv2-supervisor-pump-caller.sh` were modified by other lanes and were **not touched** —
  both commits here are scoped by explicit path to only this lane's three files.
- **Serialising lanes.** Explicitly forbidden; one-lane-at-a-time is what this task exists to
  end. Not proposed.
- **Reaping a finished lane's worktree.** Deliberate interim behaviour: it stays on disk with
  the `lane_worktree_left` line naming its absolute path (§3.3).

---

## 6. Left alone on purpose (§3.4)

`leadv2-dispatch-code.sh:1176` uses `path-of` (not `ensure`) for the architect prepass, so the
prepass itself runs in the shared checkout. This is correct: the prepass writes only under
`docs/handoff/`, which is excluded from every diff by the `':(exclude)docs/handoff'` pathspec.
Recording it so a future pass does not "fix" it.

---

## 7. Constraint checklist (§4)

1. **Env var naming** — all in-scope vars use the `LEADV2_*` prefix
   (`LEADV2_LANE_WORK_ROOT`, `LEADV2_PROJECT_ROOT`, `LEADV2_LANE_WORKTREE`,
   `LEADV2_REVIEW_DIFF_CROSS_REPO`, …). No `LEADV_V2_*` drift.
2. **File paths** — this slice adds **no new file** under `plugins/leadv2/scripts/`, so the
   per-file symlink obligation into `~/.claude/leadv2-shared/scripts/` and each
   `<repo>/.claude/scripts/` does not apply. (Confirmed: both commits touch only the three
   pre-existing LANE_WRITES files.)
3. **`claude -p` commands** — none introduced.
4. **Concurrent access** — the shared git index is protected by the existing throwaway-index
   copy in `_pc_git_diff` and by `git commit <paths>` at staging; `ensure` is idempotent and
   physical-path-compared; the §3.1 reap never runs `--force`.
5. **Config contradiction** — recorded in §4.5 above.

DELIVERABLE_COMPLETE
