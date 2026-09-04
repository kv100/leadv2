# Critic review — V3-STOP-GATE-01 (lane e93d9162)

Reviewed: 2026-08-20. Worktree `~/Projects/leadv2/.claude/worktrees/e93d9162`, branch
`worktree-e93d9162`, base `53d4465`.

## 0. The headline: the lane never committed

`git log 53d4465..HEAD` is **empty**. Every byte of this task's work is sitting uncommitted in
the worktree:

```
 M docs/handoff/dispatch-nwcm0012/phases.d/e2e.yaml     <- junk, not this task's work
 M docs/handoff/dispatch-nwcm0012/phases.d/review.yaml  <- junk, not this task's work
 M plugins/leadv2/scripts/leadv2-dispatch-code.sh
 M plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
 M plugins/leadv2/scripts/tests/run-core-offline.sh
?? plugins/leadv2/scripts/tests/test-stop-gate.sh
```

The mission's acceptance list ends with "COMMIT on lane branch." It was not met. The task whose
entire purpose is to stop workers from exiting with uncommitted work exited with uncommitted
work — the 7th instance of the disease, and self-demonstrating proof that the paragraph added to
the worker mission preamble (item 2) is not sufficient on its own.

Because there is no commit, `git diff 53d4465...HEAD | shasum -a 256` hashes the empty string
(`e3b0c442…`). The meaningful hashes are given in §7.

Two of the six dirty paths (`docs/handoff/dispatch-nwcm0012/phases.d/{e2e,review}.yaml`, both
just `started_at` bumped to `2026-08-20T10:07`) are **test pollution**: a probe run of
product-close.sh mutated a real, unrelated lane's handoff artifacts. They are outside this
task's write-set and must not be committed. Worth noting that the new gate correctly refuses to
touch them — but nothing else in the harness prevents a human from sweeping them in with a
`git add -A`.

## 1. P0 — the gate silently no-ops whenever any declared write-set path is absent

`pc_stop_gate_autocommit` (product-close.sh:1399) gates on `git status --porcelain -- <paths>`
but then stages with `git add -- <paths>` using the same pathspec array:

```bash
_sg_status="$(git -C "${_sg_lane_root}" status --porcelain -- "${_sg_paths[@]}" 2>/dev/null || true)"
[[ -n "${_sg_status}" ]] || return 0
...
git -C "${_sg_lane_root}" add -- "${_sg_paths[@]}" >/dev/null 2>&1 || return 0
```

The two commands disagree about missing pathspecs. `git status` tolerates one and reports the
paths that *do* exist; `git add` hard-fails with `fatal: pathspec '<x>' did not match any files`,
exit 128, and **stages nothing at all** — not even the paths that matched. The `|| return 0` then
swallows it, so there is no commit, no journal line, and no stderr. The lane looks like a clean
exit.

Minimal proof:

```
$ git status --porcelain -- platform tests/unit
?? platform/
status_exit=0
$ git add -- platform tests/unit
fatal: pathspec 'tests/unit' did not match any files
add_exit=128
$ git diff --cached --name-only
(nothing staged)
```

Reproduced end-to-end through the real gate (temp repo + real lane worktree + real
product-close.sh, write-set `agent/inscope.py,tests/unit/test_never_created.py`, with
`agent/inscope.py` genuinely modified):

```
last commit: seed2                          <- STOP-GATE commit never happened
still-dirty in-scope: [ M agent/inscope.py] <- real work left uncommitted
```

This is not a corner case; it is the **dominant** shape. Real `LANE_WRITES:` declarations in this
repo are large forward-looking lists — one supervise lane declares 30 paths, several declare
`tests/fixtures/**` (which `_pc_norm_write` collapses to `tests/fixtures`, a directory that may
not exist yet). A write-set is declared *before* the work; a worker that dies partway — the exact
premise of this task, "6+ worker exits left real work UNCOMMITTED" — is precisely the case where
some declared paths were never created. The gate therefore fails hardest in the scenario it was
built for, and fails silently.

Fix direction: derive the paths to stage from the status output rather than re-using the declared
pathspec — e.g. parse `_sg_status` into a concrete file list (handling the `->` rename form and
the `??` collapsed-directory form) and `git add --` that; or, at minimum, filter `_sg_paths` to
entries that exist before calling add, and journal a distinct line when add fails instead of
`|| return 0`.

## 2. HIGH — a reaped/timed-out worker never reaches the gate

`pc_stop_gate_autocommit` is called at product-close.sh:1837, after both wait blocks. Both
`worker_timeout` branches (1801–1808 and 1820–1830) call `_pc_reap_worker` — which SIGTERMs the
worker — and then `exit 5` **before** line 1837. So a worker killed by the wait ceiling has its
work discarded exactly as before this change.

A reaped worker is among the most likely producers of uncommitted work: it did not choose to
stop, so it certainly did not commit. The mission's literal wording ("the point the worker's exit
is detected (the kill -0 wait loop region)") is satisfied for the clean-exit path only. Placing
the call before each `exit 5` (or immediately after `_pc_reap_worker`) would close it, and costs
two lines.

## 3. Correctness details that are right

Verified rather than assumed:

- **Ordering is sound.** `pc_precheck_writes` (1799) populates `_PC_SCOPE_WRITES_CSV` before the
  gate at 1837, which is before `_lane_root` resolution (1845) and `pc_scope_diff`. The gate's
  guard `[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]]` therefore sees a real value on the live path.
- **Write-set scoping is genuinely scoped.** Only declared paths are staged; the comment
  correctly reasons that auto-committing out-of-scope junk would launder a scope violation past
  `pc_scope_diff`'s `unscoped_lane_work` classifier. Case B of the suite proves this empirically.
- **`emit decision "stop_gate_autocommit task=… files=…"`** matches `emit()`'s `# type text`
  signature (product-close.sh:221) and the mission's requested line shape (`task=` is `TASK`, the
  sig8 — correct).
- **Lane-root resolution** mirrors the existing `_lane_root` idiom at 1455 exactly, including the
  `path-of` fallback keyed by `FOUNDER_TASK_ID`.
- **bash 3.2 safe.** No associative arrays; indexed arrays and `IFS=',' read -r -a` only.
  `/bin/bash -n` clean.
- **Off_limits respected.** `git status --porcelain | grep -E "supervise|builder-selfcheck"` is
  empty — no supervise\* file and no `lib/leadv2-builder-selfcheck.sh` was touched. The
  dispatch-code.sh edit sits at 4213, inside the mission-preamble region immediately after the
  BUILDER-SELFCHECK paragraph, not in the routing block.

## 4. Kill-switch

`LEADV2_STOP_GATE=0` works and does restore today's path:

- product-close.sh: `[[ "${LEADV2_STOP_GATE:-1}" != 0 ]] || return 0` is the first line of the
  function — immediate return, nothing else in the file is touched.
- dispatch-code.sh: the paragraph is appended under the same guard.

The comment claims the paragraph is "appended after the dedup sig is computed." **Verified true**:
`sig8="${sig:0:8}"` is computed at line 3946, the append is at 4216. Flipping the flag therefore
cannot change lane dedup identity — a real trap, correctly avoided.

Two nits: the comparison is a string test, so `LEADV2_STOP_GATE=false` or `=00` leaves the gate
**enabled**; this matches the `LEADV2_BUILDER_SELFCHECK` idiom the mission asked to copy, so it is
consistent rather than wrong. And the test's kill-switch case (Case C) only asserts the
product-close half; the mission-preamble half of the byte-for-byte claim is untested.

## 5. Test quality — the suite is real, but it is blind to §1 and §2

Ran foreground, solo, in the lane:

```
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] RED-then-GREEN: tracked-writeset-gets-committed (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: out-of-scope-junk-not-committed (pre_rc=1 -> post_rc=0)
[TEST] PASS: kill-switch LEADV2_STOP_GATE=0 restores old path (file stays uncommitted)
Results: 6 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
SUITE_EXIT=0
```

The red-first legs are genuine — `pre_rc=1 -> post_rc=0` against a `git archive` of the
merge-base baseline, with a `GREEN_PRE_FIX` vacuity gate that fails the suite if a case passes
against the pre-fix tree. That is the right harness shape and it is correctly copied from
`test-builder-selfcheck-gate.sh`. Case C is deliberately excluded from the red/green scorer with
an accurate rationale (pre- and post-fix are identical for a kill-switched run, so scoring it
would permanently trip the vacuity gate).

The defect is coverage, not construction. **Both** red/green cases declare a write-set of exactly
one path, and that path always exists. So:

- the multi-path pathspec-mismatch of §1 is never exercised, and the suite is green while the
  live path is broken for the common case;
- no case exercises the timeout/reap branch of §2;
- no case declares a glob (`tests/fixtures/**`) or a directory write-set entry, both of which
  appear in real `LANE_WRITES:` lines and both of which hit §1.

A third case shaped like my repro in §1 (one real path + one never-created path, assert the
STOP-GATE commit happened) would have caught the P0 and would be red-first for free.

## 6. Lower-severity findings

- **`files=<n>` undercounts.** `_sg_n` counts `git status --porcelain` lines, but an untracked
  directory collapses to a single line (`?? platform/`) regardless of how many files it holds. A
  47-file checkpoint can journal `files=1`. Cosmetic, but this number is what a future session
  will use to judge whether the gate did anything.
- **Every failure is silent.** `git add … || return 0` and the `if git … commit; then emit; fi`
  shape mean a failed add, a failed commit (e.g. no `user.email` in the lane), or an empty index
  all produce no journal line whatsoever. The mission frames an uncommitted exit as "an
  incident"; an incident that emits nothing cannot be triaged. A `stop_gate_autocommit_failed`
  emit on the error paths would cost one line each.
- **Cross-repo lanes are not covered.** The gate only ever runs `git -C "${_sg_lane_root}"`. In a
  `CROSS_REPO_DIFF=1` lane, declared paths can resolve through symlinks into another repository
  (the persona-engine `.claude/scripts` → `~/Projects/leadv2` case that `_pc_realpath` exists to
  handle); a symlink blob is unchanged in the lane, so status sees nothing and the gate no-ops.
  Arguably out of scope for this task, but it should be stated rather than left implied.
- **Doc-only lanes get no checkpoint.** `_PC_SCOPE_WRITES_CSV` deliberately excludes
  `docs/leadv2/*` and `docs/handoff/*` (the undiffable classes stripped by `pc_precheck_writes`),
  so a lane whose write-set is entirely docs gets an empty CSV and returns at the second guard.
  This is a defensible consequence of reusing the scoped CSV, but it means "commit-before-exit
  enforcement" does not apply to documentation lanes at all.
- **Redirect on a `[[ ]]` test** — `[[ -d … || -f … ]] 2>/dev/null || return 0` (line 1409). The
  redirect is inert on a bash conditional. Harmless, slightly misleading.

## 7. Hashes

- `git diff 53d4465...HEAD | shasum -a 256`
  → `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (sha256 of empty input —
  there are no commits in the range; see §0).
- Actual reviewed work (tracked diff + untracked `test-stop-gate.sh`):
  → `221fd36bf4bab44501d6934b9a582c2da5ab6f71d76e17e14a11c08dc8a80b83`
- `git diff -- plugins/` (product scripts only, excludes the two junk yaml files):
  → `3d99e875c6379f88ac8549f31a8075011e2bcc1352e1e5879b28687e43a1ae43`

## 8. Verdict rationale

The design is right and the parts that exist are careful: correct call ordering, correct scoping
philosophy, a real red-first harness with a vacuity gate, an honest kill switch that provably does
not perturb dedup identity, off_limits respected, lint clean at `-S warning` on all three touched
files including bash 3.2.

But the shipped gate does not close the disease it was built for. It silently does nothing
whenever the declared write-set names a path the worker never created (§1) — the normal shape of
a lane whose worker died — and it never runs at all when the worker was reaped on timeout (§2).
Both holes are invisible at runtime, and the test suite is green through both. Shipping this as-is
would install a gate the team believes is protecting them while the next dead worker still loses
its work, which is the lying-green pattern this repo keeps paying for. Plus the lane itself has no
commit.

VERDICT: FAIL
DIFF_HASH: e3b0c442
