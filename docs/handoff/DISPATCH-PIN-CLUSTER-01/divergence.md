# DISPATCH-PIN-CLUSTER-01 — divergence

Not a generated ideation panel. This records the forks the Phase-2 pass actually opened
and closed, each with the evidence that killed the losing branch. Three of the four
defects had a plausible obvious fix that turned out to be wrong.

## Fork 1 — D1: how do you enforce a worktree pin?

- **A. Path-prefix write fence on the worker** (the form the backlog row was written in).
  REJECTED. A lane worktree's `.git` is a *file* pointing at
  `/Users/.../leadv2/.git/worktrees/<id>`, so every legitimate lane commit writes into the
  main checkout's object store — the fence blocks the very commit D2 demands. The control
  plane (journals, active registry, event ledger, question store, `docs/handoff`) is
  deliberately rooted at `PROJECT_ROOT` (`dispatch-code.sh:406-414`), and `WORK_ROOT` fails
  **open** to `PROJECT_ROOT` at `:412-413`. The dispatcher also cannot enforce it: the
  worker is a separate process handed `--cwd`.
- **B. Child-side PreToolUse guard** in the worker session. DEFERRED, not rejected — it is
  the right long-term shape but a separate blast radius (it would fire in every lead
  session too). Scoped out; we export `LEADV2_WRITE_ROOT` now so it has a value to consume.
- **C. Post-hoc containment verdict.** CHOSEN. Baseline the main checkout's porcelain at
  spawn, set-diff at the close gate, refuse `landed` when a non-excluded path appeared.
  Detects the contamination without forbidding any legitimate write.

## Fork 2 — D2: dirty lane — commit it, or fail the round?

- **A. Dispatcher auto-commits.** REJECTED. Both existing autocommitters already prove the
  shape is wrong: `leadv2-turncap-checkpoint-commit.sh:54` guards on `$PROJECT_ROOT/.git`
  being a directory, so it silently no-ops in *every* lane worktree; and
  `pc_stop_gate_autocommit` stages only `_PC_SCOPE_WRITES_CSV` — which is exactly the
  3-of-5 incident, by design rather than accident. A correct auto-commit would also have to
  decide what to sweep (untracked scratch, backups, other lanes' files), and that decision
  has no safe default.
- **B. Fail the round at the ledger funnel.** CHOSEN, with a bound. `landed` is downgraded
  to the existing `pass_unlanded` terminal inside `dispatch_ledger_write_terminal` — the one
  funnel all six success surfaces pass through, so no arm and no future caller can route
  around it.
- **B's own trap, found by the concern pass and mitigated:** `pass_unlanded` is retryable
  and routes into `advance-arm`, re-running the same mission on the next arm while the
  reservation stays confirmed for `CONFIRMED_TTL=7200`. Unbounded, this converts one silent
  failure into an arm-burning loop. Hence the per-sig8 attempt cap, after which the terminal
  is final.

## Fork 3 — D3: copy the plan into the lane, or commit it?

- **A. Force-commit the plan onto the lane branch.** REJECTED. `.gitignore:40` is
  `docs/handoff/*/*`, and the path is excluded from the writes grammar (`:3425`) — a
  force-commit lands the plan outside `LANE_WRITES` and PARKs the round as
  `unscopable_diff` (`:596-601`). The fix would convert BLOCKED into PARKED: a different
  word for the same wasted cycle.
- **B. Copy, uncommitted.** CHOSEN. Pollutes no branch, cannot conflict at land time, and
  resolves the path the codex arm was looking for.

## Fork 4 — D4: is the class carrier missing, or discarded?

The backlog row assumed the carrier had to be built. It does not: `dispatch-code.sh:5977-5983`
already reads `intake_cls` from the admission receipt and then assigns only `sig`/`sig8`.
The receipt is keyed on `sig8 = sha256(normalised mission text)`, so a short resume mission
is a different key and misses it entirely. So: no new subsystem — a second, task-keyed
receipt plus a floor comparison.

The concern pass also found a **second demotion site** the plan pass had missed:
`advance-arm` (`:7345-7351`) `sed`-scrapes the class out of the ledger row and defaults to
`Standard`. Fixing only the classifier would have left the chain-advance path demoting, and
the task would have looked fixed while still routing Heavy work to freepool. Both sites are
in scope.

## What was NOT diverged

Step 1 (extract `lib/leadv2-lane-guard.sh`) has no fork — `lv2_lane_dirty` and its exclude
regex already exist and have already diverged once between call sites (see the comment at
`dispatch-product-close.sh:1290-1296`). A pure move is the only option that does not create
a third copy.
