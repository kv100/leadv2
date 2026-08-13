# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — architect prepass

Repo to change: `~/Projects/leadv2` (plugin). Branch only — no commit to main, no push, no merge.

## 1. Confirmed defect surface (read on disk, not from the mission)

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, function `pc_scope_diff()`:

| line | what is there today |
|---|---|
| 850 | `CROSS_REPO_DIFF="${LEADV2_REVIEW_DIFF_CROSS_REPO:-1}"` |
| 860 | `diff_root="${ROOT}"` |
| 861-868 | `if [[ "${CROSS_REPO_DIFF}" == "1" ]]; then` … resolve `LEADV2_LANE_WORK_ROOT`, else `leadv2-lane-worktree.sh path-of` … `diff_root="${_lane_root}"` … `fi` |
| 1008-1013 | `else` arm (`CROSS_REPO_DIFF != 1`) → `_pc_repo_diff "${diff_root}" "${writes[@]}"` — with `diff_root == ROOT` |
| 1014 / 1021 | `[[ -s "${diff_file}" ]] \|\| blocked_reason="unscopable_diff"` |
| 1024-1046 | blocked branch: `partial_diff` → `refused`; everything else → `terminal=no_work cause=empty_diff` (or `asked_into_void` when the marker file exists); `review-gate.md` gets `reason: no_work`; `exit 5` |

Two independent faults, both in that block:

- **F1 — lane invisibility.** `diff_root` is pinned to `${ROOT}` on any single-repo dispatch, so `_pc_repo_diff` queries the main checkout while the worker's uncommitted work sits in `.claude/worktrees/<founder-tid>`. Zero bytes by construction. The comment at 855-859 already states the invariant ("`diff_root` can never disagree with where the code actually landed") that line 861's guard violates.
- **F2 — a scoping failure retires as an outcome.** Zero bytes is unconditionally read as "the worker produced nothing" and written as `terminal=no_work cause=empty_diff` — a *lane outcome*. A lead trusting that row discards a complete lane. There is no state in which the gate says "I could not see the work."

Observed live on persona-engine `0db1da80` (2026-08-04): 221 insertions + a 193-line new test file uncommitted in the lane; `review.diff` 0 bytes; `review.diff.repos` = `persona-engine 0`; ledger `terminal=no_work cause=empty_diff`.

## 2. Blocking finding — two existing suites *assert the defect*

This is the single most important thing for the implementer. The fix cannot be landed without respec'ing both, and neither may be deleted or skipped.

| suite | case | what it asserts today |
|---|---|---|
| `tests/test-lane-writes-scoping.sh` :217-246 | `case_c3` | with `LEADV2_REVIEW_DIFF_CROSS_REPO=0` **and** `LEADV2_LANE_WORK_ROOT` set to a real worktree, a change made in `${ROOT}` must be found and the gate must `status: pass` |
| `tests/test-landing-diff-scoping.sh` :212-241 | `case_q3_pair` | flag ON → 0 bytes + blocked; flag OFF → >0 bytes + not blocked, against a **guaranteed-empty** worktree with the edit in `${ROOT}` |

Both encode "flag OFF ⇒ `diff_root` reverts to `${ROOT}` even when a lane worktree exists" — exactly the behaviour this mission calls a defect. So the mission's required fix is a deliberate, documented semantic change to `LEADV2_REVIEW_DIFF_CROSS_REPO`, and the rollback story those two cases protected must be re-homed onto a new flag, not dropped.

`tests/test-e2e-foreign-failure.sh` :117,:233 also sets the flag to 0, but passes an empty 7th arg (no task id) and never sets `LEADV2_LANE_WORK_ROOT` — under the new design no lane resolves, `diff_root` stays `${ROOT}`, and that suite is unaffected. Verify, do not assume.

## 3. Design

### D1 — split the flag's two responsibilities

`LEADV2_REVIEW_DIFF_CROSS_REPO` today conflates two unrelated things: *which root do I diff* and *do I fan the declared writes out across multiple repos*. Only the second is "cross-repo". Split them:

| env var | default | governs | effect when 0 |
|---|---|---|---|
| `LEADV2_REVIEW_DIFF_CROSS_REPO` | `1` | multi-repo fan-out over `writes[]` (the `repo_order`/`repo_of`/`rel_of` block, `partial_diff` detection) | single-repo path: one `_pc_repo_diff "${diff_root}" "${writes[@]}"` — **still against the resolved lane root** |
| `LEADV2_REVIEW_DIFF_LANE_ROOT` *(new)* | `1` | whether `diff_root` may resolve to the lane worktree | `diff_root` stays `${ROOT}` — the genuine one-flip rollback to pre-lane-worktree behaviour |

Naming conforms to the `LEADV2_*` prefix convention (checked against the existing block at :850 and against every other `LEADV2_REVIEW_DIFF_*` usage in the repo — there is exactly one, at :850). Grep across the repo found no other consumer of the cross-repo flag outside the three test suites listed above, so no config contradiction.

### D2 — lane resolution becomes unconditional (fixes F1)

Replace the `if [[ "${CROSS_REPO_DIFF}" == "1" ]]` guard at :861 with a guard on the new flag. The resolution *order* inside is unchanged and must stay unchanged:

1. `LEADV2_LANE_WORK_ROOT` if set and a directory — the same value `dispatch-code.sh` gave every worker as `--cwd`, so `diff_root` cannot disagree with where the code landed (the C1 invariant).
2. else `leadv2-lane-worktree.sh path-of "${FOUNDER_TASK_ID:-${TASK}}"` — the fallback for a close gate started outside the launcher lineage. `path-of` is already fail-safe: it prints nothing unless the dir exists *and* `git worktree list --porcelain` confirms it (`leadv2-lane-worktree.sh` :157-166), so a stale directory cannot hijack `diff_root`.
3. else `${ROOT}`.

Record the outcome in a new variable `_pc_lane_root` (empty when no lane resolved) — the dirty check in D3 needs to distinguish "diffed the lane" from "diffed ROOT because there is no lane", and `diff_root == ROOT` is ambiguous when `LEADV2_LANE_WORKTREE=off` makes the lane path *be* `${ROOT}`.

Downstream consumers of `diff_root` — `_lv2_e2e_resolve_root "${diff_root}" "${ROOT}"` at the e2e gate (:1105) — already treat `diff_root` as "where the lane's code is" and get *more* correct, not less. No change needed there.

### D3 — a dirty lane is never `no_work` (fixes F2)

New helper, defined next to `_pc_repo_diff`:

```
_pc_lane_dirty() { # <lane_root> -> rc0 iff uncommitted tracked changes OR untracked files exist
```

Contract:

- rc1 immediately if the argument is empty, is not a directory, or is the same physical path as `${ROOT}` (use the already-sourced `_lv2_realpath` for the comparison). Dirt in the shared main checkout belongs to other sessions and must never gate this lane.
- Otherwise `git -C "<lane>" status --porcelain --untracked-files=all` and treat the lane as dirty iff at least one entry survives filtering.
- **Filter the same paths `_pc_git_diff` excludes** — any entry whose path starts with `docs/leadv2/` or `docs/handoff/` — plus `.claude/worktrees/`. Without this filter a worker that wrote only handoff files reads as dirty and F2's fix silently converts "the worker did nothing" into a permanent block, which is precisely the regression the mission forbids. `git status --porcelain` renames (`R  old -> new`) and quoted paths with spaces must both survive the filter correctly; prefer `-z`-delimited parsing or an anchored path test that tolerates the 3-column prefix, not a naive `grep -v docs/`.
- Read-only. No `git add`, no index copy, no `stash`, no `clean`.

Wire it into the blocked branch at :1024-1046, **after** the existing `partial_diff` and `asked_into_void` decisions, never before:

```
partial_diff        -> refused / partial_diff              (UNCHANGED)
asked_into_void mkr -> no_work / asked_into_void           (UNCHANGED)
empty + lane dirty  -> refused / lane_diff_unscoped        (NEW)
empty + lane clean  -> no_work / empty_diff                (UNCHANGED)
```

`refused` is chosen over a new ledger terminal deliberately: `leadv2-dispatch-ledger.sh` :192 whitelists exactly `landed|parked|refused|dead|no_work`, and `refused` is already the retryable non-outcome used for `partial_diff` ("it ran past admission but produced no landable result"). Distinguishability comes from the *cause* word `lane_diff_unscoped`, which is unique in the ledger vocabulary. **Do not add a ledger terminal** — that widens blast radius to the sweep, `dispatch_terminal_exists`, and the status surface for no benefit.

`review-gate.md` gets `reason: lane_diff_unscoped` so the on-disk artifact and the ledger row agree (the invariant the comment at :1038-1040 states). Exit code stays `5` — no caller-contract change.

### D4 — non-goals (implementer: ignore these)

- No change to `partial_diff`, `asked_into_void`, `unscopable_diff`, or `worker_timeout` semantics.
- No change to `_pc_git_diff`, `_pc_diff_base`, `_pc_repo_diff`, or the never-smaller base-selection guard.
- No change to `leadv2-lane-worktree.sh`, `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh`, or `lib/leadv2-e2e-root.sh`.
- No new ledger terminal; no change to exit codes.
- Nothing under `~/.claude/leadv2-shared/`, any project's `.claude/leadv2/`, or any `.claude/worktrees/*` copy.
- No auto-commit of the lane's work. The gate reports; the lead decides.
- No loosening of any other gate to make a test pass.

## 4. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | D1 flag split, D2 unconditional lane resolution + `_pc_lane_root`, D3 `_pc_lane_dirty` + blocked-branch wiring |
| `plugins/leadv2/scripts/tests/test-lane-diff-scoping-single-repo.sh` *(to-create)* | new suite, §5 |
| `plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh` | respec `case_c3` onto `LEADV2_REVIEW_DIFF_LANE_ROOT=0`; add a sibling asserting `CROSS_REPO=0` alone now diffs the lane |
| `plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh` | respec `case_q3_pair` the same way (flag pair becomes the new lane-root flag) |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | register the new suite via `run_check` (the registry is an explicit list, :82-112 — an unregistered suite never runs) |

## 5. New suite — required cases

`tests/test-lane-diff-scoping-single-repo.sh`. Follow the sandbox discipline the two existing suites already prove: sandboxed `HOME`/`TMPDIR`, `new_repo`/`ensure_worktree` fixtures, resolver + review-pass stubs, `LEADV2_DISPATCH_TERMINAL_LEDGER=0` or a sandboxed ledger, and a mtime tripwire over `~/Projects/leadv2/plugins` and `~/.claude`. Never `git stash` / `reset --hard` / `clean`.

| case | setup | must observe |
|---|---|---|
| **A — the reported defect** | `CROSS_REPO_DIFF` unset; lane worktree holds an uncommitted edit to a declared write | `review.diff` non-empty and contains the lane's text; `review-gate.md` is not `reason: no_work` |
| **B — untracked-only lane** | as A but the lane's only work is a brand-new never-`git add`ed file | non-empty diff (proves the `add -N` path still reached, now against the lane) |
| **C — genuinely empty lane** | lane exists, worktree clean | `review-gate.md` `reason: no_work`; ledger/journal `terminal=no_work cause=empty_diff`. **This is the anti-regression case — the fix must not turn "worker did nothing" into a pass or a block.** |
| **D — handoff-only lane** | lane's only dirt is under `docs/handoff/` | same as C. Guards the D3 filter. |
| **E — dirty lane, undeclared writes** | lane dirty but the declared `LANE_WRITES` path itself is untouched → diff empty | `reason: lane_diff_unscoped`, `terminal=refused` — the new distinguishable state |
| **F — rollback flag** | `LEADV2_REVIEW_DIFF_LANE_ROOT=0`, edit in `${ROOT}`, empty lane | diff finds the ROOT edit; gate passes (the old C3/Q3 guarantee, re-homed) |
| **G — no lane at all** | no `LANE_WORK_ROOT`, no worktree for the task | `diff_root` is `${ROOT}`; behaviour byte-identical to today (protects `test-e2e-foreign-failure.sh`) |
| **H — main checkout dirty, lane clean** | unrelated dirt in `${ROOT}`, lane empty | still `no_work` — proves the `diff_root == ROOT` short-circuit in `_pc_lane_dirty` |

Red-first: A, B, E must be demonstrated FAILING against the pre-fix script (`git archive HEAD` extraction, the pattern `test-landing-diff-scoping.sh` already uses) and passing after. A case green pre-fix is not evidence.

Also required before hand-off: `bash -n` clean on every touched file, and the full output of `run-core-offline.sh` pasted, not summarised.

## 6. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | The dirty check makes every clean-but-noisy lane block, converting a real `no_work` into a permanent stall — a worse failure than the one being fixed | D3's exclusion filter + suite cases C, D, H are the guard. If the filter cannot be made exact, fail toward `no_work`, never toward blocking |
| R2 | Two shipped suites assert the old semantics; a lane that "makes the tests pass" by deleting them is a hack | §2 names both explicitly; respec is in scope, deletion is not. Critic must check both files still contain a rollback assertion |
| R3 | Blast radius: this script is symlinked into persona-engine, m3-market, respiro-ios — one inode, three views | Case G pins the no-lane path byte-identical; full `run-core-offline.sh` green is the gate |
| R4 | `git status` on a lane concurrently written by a still-running worker is racy | The check runs only after `pc_await_worker_exit` has returned; and a race here can only produce *more* dirt, i.e. err toward `lane_diff_unscoped`, which is recoverable |
| R5 | `path-of` resolving into a real production worktree during a test run | Already covered by `case_q_unset_workroot_safety` in `test-landing-diff-scoping.sh`; the new suite must keep `LEADV2_WORKTREE_DIR` inside the sandbox |
| R6 | `_pc_lane_dirty` runs a second `git` invocation on every blocked close | Only on the already-blocked path, once. Negligible |
| R7 | bash 3.2 — `dispatch-code.sh` resolves `bash` from PATH and may get `/bin/bash` 3.2 | No `declare -A`, no `${var,,}`, no `mapfile`. Indexed arrays and `while read` only (the M8/M9 constraint already documented at :961-966) |

## 7. Constraint checklist

1. **Env naming** — `LEADV2_REVIEW_DIFF_LANE_ROOT` matches the `LEADV2_*` convention and the sibling `LEADV2_REVIEW_DIFF_CROSS_REPO`. No `LEAD_V2_*` drift.
2. **Paths** — all files in §4 verified on disk except the one marked *(to-create)*.
3. **`claude -p`** — this change introduces none. N/A.
4. **Concurrent access** — `review.diff` / `review.diff.repos` / `review-gate.md` are per-`sig8` under `${HANDOFF}`, single-writer. `_pc_lane_dirty` is read-only against a tree a concurrent session may hold; see R4.
5. **Config contradiction** — `LEADV2_REVIEW_DIFF_CROSS_REPO` has exactly one production consumer (`:850`) and three test consumers (§2). Its meaning narrows; all four sites are addressed in §4. No contradiction left behind.

## acceptance

```yaml
acceptance:
  authored_at: 2026-08-04T00:00:00Z
  criteria:
    - surface: file_artifact
      observable: >
        On a single-repo close with LEADV2_REVIEW_DIFF_CROSS_REPO unset and a lane
        worktree holding uncommitted work, docs/handoff/dispatch-<sig8>/review.diff
        is a non-empty unified diff containing the lane's changed lines, and
        review-gate.md does NOT read "reason: no_work".
    - surface: log_line
      observable: >
        The close gate's decision line for that same run reads
        "review_diff task=<sig8> repo=<repo> bytes=<N>" with N greater than zero,
        where it previously read bytes=0.
    - surface: log_line
      observable: >
        For a lane whose worktree is clean, the decision line still reads
        "review_gate task=<sig8> status=blocked reason=no_work terminal=no_work
        cause=empty_diff" — a lane that did nothing is still recorded as having
        done nothing.
    - surface: file_artifact
      observable: >
        For a lane whose worktree carries uncommitted or untracked work outside the
        declared writes, review-gate.md reads "reason: lane_diff_unscoped" and the
        decision line reads "terminal=refused cause=lane_diff_unscoped" — visibly
        distinct from the no_work wording above.
    - surface: log_line
      observable: >
        run-core-offline.sh prints a PASS line for every previously-registered suite
        plus the newly registered lane-diff single-repo suite, and its final tally
        line reports zero failures.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-lane-diff-scoping-single-repo.sh, plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh, plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
