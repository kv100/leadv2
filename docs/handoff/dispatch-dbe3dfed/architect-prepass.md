# architect prepass — land `worktree-2d8a2849` on main (GATE-FALSE-SILENT-01)

Design only. No implementation. All statements below were read out of the tree with
read-only git (`git merge-tree --write-tree`, `git diff <merge-base>..<side>`), not from the
mission's framing.

## 0. Measured state (evidence)

```
$ git merge-base main worktree-2d8a2849
aed1f2bc5abefbe42fa044434a2101a6f476525a

$ git merge-tree --write-tree --name-only main worktree-2d8a2849
f5120b8432e842546c0cc8665b8b475ad9525104
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
Auto-merging plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
CONFLICT (content): Merge conflict in plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
Auto-merging plugins/leadv2/scripts/tests/run-core-offline.sh
```

Branch side (`aed1f2bc..worktree-2d8a2849`), 4 files, +501/-15:
`leadv2-dispatch-product-close.sh` +128, `tests/run-core-offline.sh` +1,
`tests/test-dispatch-silent-arm.sh` +47, `tests/test-silent-arm-commits-ahead.sh` +340 (new).

Main side (`aed1f2bc..main`), 27 files, +1841/-39; the only file overlapping the branch is
`leadv2-dispatch-product-close.sh` (+90) and `tests/run-core-offline.sh` (+1).

### FINDING that contradicts the mission's framing

The mission says "the conflict is in one file" and implies the resolution is a judgement
call across three behaviours. **Measured: there is exactly ONE conflict hunk, at
lines 1165–1270 of the merged blob, and it is purely a same-anchor insertion collision —
two disjoint blocks of NEW function definitions that both landed immediately after
`_pc_lane_dirty()`'s closing brace.** Git already auto-merged the semantically interesting
region (the interior of `pc_silent_arm_probe`) **correctly and in the safe order** — see §1.2.
The design therefore does not need to reconcile behaviour by hand; it needs to concatenate
two blocks, restore one brace, and then *verify* that the auto-merged ordering is the one we
want. §1.2 argues that it is, and that the opposite order would be a live defect.

`run-core-offline.sh` auto-merged because the two registrations are 53 lines apart
(main at the `test-dwr-resume.sh` neighbourhood, branch at the `SUITE-SPEED-01` tail).

## 1. The resolution, exactly

### 1.1 The one conflict hunk — mechanical, no content edits

Merged-blob layout around the marker:

| line | content |
|---|---|
| 1163 | `}` — closes `_pc_lane_dirty` (common) |
| 1165 | `<<<<<<< main` |
| 1166–1184 | main's block: `_pc_phys()`, `_PC_LANE_TOPLEVEL=""`, `_pc_lane_root_is_own_worktree()` **body without its closing brace** |
| 1185 | `=======` |
| 1186–1269 | branch's block: `_pc_lane_commits_ahead()`, `_pc_worker_process_alive()` **body without its closing brace** |
| 1270 | `>>>>>>> worktree-2d8a2849` |
| 1271 | `}` — common trailing brace, OUTSIDE the conflict |

Both sides end mid-function because the trailing `}` at 1271 is shared context. The
resolution is therefore **not** "pick a side" and **not** "delete the markers":

1. Keep main's block 1166–1184 verbatim.
2. **Insert a `}` and a blank line** after it — this is the brace that closes
   `_pc_lane_root_is_own_worktree`, and it does not exist anywhere in the conflict region.
3. Keep the branch's block 1186–1269 verbatim.
4. Delete the three marker lines. Line 1271's existing `}` now closes
   `_pc_worker_process_alive`.

A resolution that omits step 2 leaves `_pc_lane_commits_ahead` textually nested inside
`_pc_lane_root_is_own_worktree`. That is valid bash and `bash -n` passes, so the syntax
check does NOT catch it; the failure appears only at run time as
`_pc_lane_commits_ahead: command not found` on any lane where the identity probe was never
called first. **This is the single highest-risk mistake in this task.** Guard: after
resolving, `declare -F` must list all four of `_pc_phys`,
`_pc_lane_root_is_own_worktree`, `_pc_lane_commits_ahead`, `_pc_worker_process_alive` from
a `source`d copy of the script.

Order within the hunk (main-block first vs branch-block first) is semantically free — bash
resolves function names at call time, and neither block calls the other. Main-first is
recommended only because it keeps `git diff main` minimal.

### 1.2 The auto-merged region — verify, do not re-edit

`git` merged the interior of `pc_silent_arm_probe` without conflict, producing this order
(merged blob lines 1399–1420, verified by reading the blob):

```
  # 4) GATE-FALSE-SILENT-01: a live worker process is never silent.
  _pc_worker_process_alive && return 1
  # 5) worktree dirty-check -- no resolved lane worktree is conservative NOT-silent.
  [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] || return 1
  # REVIEW-GATE-LANEROOT-01: an unregistered lane dir makes _pc_lane_dirty grade the
  # parent repo. Unknown tree identity is never proof of silence: ...
  _pc_lane_root_is_own_worktree "${_lane_root}" || return 1
  _pc_lane_dirty "${_lane_root}" && return 1
  # 6) GATE-FALSE-SILENT-01: commits ahead of base are production ...
  commits_ahead="$(_pc_lane_commits_ahead "${_lane_root}")"
```

**This ordering is load-bearing and must be preserved.** `_pc_lane_commits_ahead` calls
`git -C "${root}"`, which walks UP exactly the way `_pc_lane_dirty` does. On an unregistered
lane directory sitting inside the canonical checkout, its `origin/main` fallback resolves
against the **parent** repository; if the parent's HEAD is at `origin/main`,
`rev-list --count` returns `0`, `_pc_lane_commits_ahead` prints `"0"` — not `"unknown"` —
and the probe concludes silence. That is a reintroduction of the exact class of bug both
lanes exist to kill. Main's identity guard standing **before** step 6 is what forecloses it.
If a resolver moves the guard below the commits-ahead probe "to keep the numbered steps
tidy", the merge is wrong even though every named test may still pass.

Nothing in this region needs editing. It needs reading and keeping.

### 1.3 Everything else — additive, no overlap

| Region | Side | Survives how |
|---|---|---|
| Header comment `died-with-work` → `died-with-work or parked` | main | untouched, auto |
| `_PARKED_DETECT_SH` source block (lines 33–39) | main | untouched, auto |
| `_pc_lane_outcome` signature + `pc_dwr_resume_once` `case … died-with-work\|parked` | main | untouched, auto |
| `_pc_lane_produced_files` (after `_pc_join_capped`) | main | untouched, auto |
| `_pc_stop_gate_resolve_reason` + `${_PC_STOP_GATE_REASON}` in the checkpoint commit message | main | untouched, auto |
| `lane_root_not_a_worktree` branch + `resolved_toplevel:` / `produced:` lines in `review-gate.md` | main | untouched, auto |
| `lane_root_shared=1` evidence suffix | main | untouched, auto |
| `_PC_SILENT_COMMITS_AHEAD` declaration + `commits_ahead=` in `_pc_silent_evidence` | branch | untouched, auto |
| growth-guard clamp `[1,3600]` + `silent_probe_growth_clamped` | branch | untouched, auto |
| absent-stream-is-not-a-veto restructure (step 2/3) | branch | untouched, auto |
| `silent_probe_base_unresolved` emission | branch | untouched, auto |

All three behaviours therefore survive by construction, not by judgement.

## 2. CALLERS / CALLEES (file:line, merged blob `/tmp/pc-merged.sh`, which mirrors the
resolved file offset-for-offset once the two markers and one brace are fixed)

Every function touched by this merge lives in
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` and has **no caller outside that
file**. Verified:

```
$ grep -rln "pc_silent_arm_probe|_pc_lane_root_is_own_worktree|_pc_lane_commits_ahead|
             _pc_worker_process_alive|_pc_lane_produced_files|_pc_phys|
             _pc_stop_gate_resolve_reason" plugins/leadv2 --include=*.sh --include=*.py --include=*.md
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh      # comment reference only
```

There is no independent copy of this mechanism on another path (no prefill/runner split).
The only "second path" risk in this repo is the shared-tree symlink farm, and that is
per-file symlinks to one inode — one edit, three views.

| Function | Callers (line) | Callees it invokes |
|---|---|---|
| `_pc_phys` | `_pc_lane_root_is_own_worktree` :1184 (×2); `blocked_reason` evidence :2092 (×2) | `cd -P`, `pwd -P` (subshell) |
| `_pc_lane_root_is_own_worktree` | `pc_silent_arm_probe` :1409; `blocked_reason` guard :~2046 (negated) | `git rev-parse --show-toplevel`, `_pc_phys` |
| `_pc_lane_commits_ahead` | `pc_silent_arm_probe` :1418 — **only** call site | `git rev-parse --is-inside-work-tree`, `git cat-file -e`, `git merge-base`, `git rev-list --count`, `git rev-parse --git-common-dir`, `git log -g`, `cat` on `${CACHE_BASE}/dispatch-${TASK}.start-sha` |
| `_pc_worker_process_alive` | `pc_silent_arm_probe` :1403 — **only** call site | `kill -0`, `_pc_run_dir_for`, `_pc_meta_value`, `_pc_process_alive` |
| `_pc_lane_produced_files` | `blocked_reason` refused branch :2053 — only call site | `find`, `head`, `_pc_join_capped` |
| `_pc_stop_gate_resolve_reason` | top level :~2196, immediately before `pc_stop_gate_autocommit` | `_pc_run_dir_for`, `_pc_lane_outcome`, `lv2_parked_text_file` (may be undefined → `declare -F` guarded) |
| `pc_silent_arm_probe` | top level :2224 (`if pc_silent_arm_probe; then`) — only call site | `_pc_arm_registered`, `_pc_stat_mtime`, `_pc_worker_process_alive`, `_pc_lane_root_is_own_worktree`, `_pc_lane_dirty`, `_pc_lane_commits_ahead`, `emit` |
| `_pc_lane_outcome` | `pc_dwr_resume_once` :~630, `_pc_stop_gate_resolve_reason` :~1518 | `_pc_meta_value`, sentinel read |

Cross-side callee note: `_pc_stop_gate_resolve_reason` (main) reads `_pc_lane_outcome`,
which main widened to include `parked`; the branch touches neither. No interference.

## 3. STATES AND RETURN CODES

### 3.1 `_pc_lane_commits_ahead <root>` — stdout channel, rc always 0

| State | stdout | `pc_silent_arm_probe` does | user-visible consequence |
|---|---|---|---|
| root empty / not a dir / not inside a work tree | `unknown` | emits `silent_probe_base_unresolved`, `return 1` | lane is NOT declared silent; it falls through to `pc_scope_diff`, which issues `empty_diff`/`unscoped_lane_work`/normal review — the human sees a normal review verdict, never "the worker produced nothing" |
| `LEADV2_LANE_START_SHA` resolves, N commits ahead, N≥1 | `N` | `return 1` | lane proceeds to review with its commits intact |
| start-sha resolves, 0 commits ahead | `0` | falls to `return 0` (silent) | review-gate.md says `reason: arm_produced_nothing`, `commits_ahead=0`; the lane is closed as no-work and the founder sees that lane as producing nothing today |
| env sha unset → cache file `${CACHE_BASE}/dispatch-${TASK}.start-sha` resolves | `N` | as above per N | as above |
| env + cache both unresolvable, `origin/main` exists | `N` from `merge-base origin/main HEAD` | as above per N | as above |
| env + cache + `origin/main` all unresolvable, root is a **linked** worktree (`${root}/.git` is a FILE), HEAD == parent HEAD, HEAD reflog has no `commit` entry | `0` (prove-zero) | silent | as the `0` row |
| same, but HEAD ≠ parent HEAD **or** reflog shows a `commit` | falls through | `unknown` → `return 1` | not silent |
| root is a **standalone** repo (`.git` is a DIRECTORY) and no base resolved | `unknown` | `return 1` | not silent |
| `rev-list --count` emits non-numeric / fails | falls through to prove-zero, then `unknown` | `return 1` | not silent |

The `[[ "${commits_ahead}" =~ ^[0-9]+$ ]] || commits_ahead=0` line at :1421 is dead code
given the two branches above it (`unknown` already returned; anything else is numeric by
construction). Harmless; do not "clean it up" in this merge.

### 3.2 `_pc_worker_process_alive` — rc only

| State | rc | probe does | user-visible consequence |
|---|---|---|---|
| `HANDLE` unset/empty | 1 | continue to step 5 | probe keeps evaluating |
| `AUTHOR=sonnet`, HANDLE numeric, `kill -0` succeeds | 0 | `return 1` | lane is not silent; gate waits for a terminal signal instead of closing the lane early |
| `AUTHOR=sonnet`, HANDLE numeric, process gone | 1 | continue | — |
| non-sonnet, run dir unresolvable | 1 | continue | — |
| non-sonnet, `meta.yaml` has a live pid | 0 (via `_pc_process_alive`) | `return 1` | as the live-sonnet row |
| non-sonnet, pid dead / meta missing pid | 1 | continue | — |

### 3.3 `_pc_lane_root_is_own_worktree <root>` — rc only, sets `_PC_LANE_TOPLEVEL`

| State | rc | probe (:1409) | blocked_reason (:~2046, negated) |
|---|---|---|---|
| root empty / not a dir | 1 | `return 1` — not silent | takes the refused branch |
| `rev-parse --show-toplevel` fails (not a repo at all) | 1 | `return 1` | refused |
| toplevel resolves but ≠ root (unregistered dir inside another checkout) | 1 | `return 1` | **refused**: `review-gate.md` carries `reason: lane_root_not_a_worktree`, `resolved_toplevel:`, `expected_lane_root:`, `produced:` — the founder sees the lane refused with the parent checkout named, and the lane's files listed, instead of the lane being graded against the wrong repository |
| toplevel == root | 0 | continue to dirty/commits checks | falls through to the normal dirty/scope partition |

### 3.4 `pc_silent_arm_probe` — the composed machine, merged order

| # | Condition | rc | terminal consequence |
|---|---|---|---|
| 0 | no arm registered | 1 | empty-lane path owns it (`empty_diff`) |
| 1 | ≥1 assistant event in stream | 1 | normal review |
| 2 | stream file exists AND mtime is inside the clamped growth window | 1 | gate treats the worker as still writing |
| 2' | stream exists, `_pc_stat_mtime` fails | 1 | fail-open, not silent |
| 3 | stream ABSENT | fall through | non-sonnet arms (glm/codex) reach steps 4–6 instead of being vetoed — this is round 3's fix and is why `test-lane-diff-single-repo.sh` Case C5 is green again |
| 4 | worker process provably alive | 1 | not silent |
| 5a | no resolved lane root | 1 | not silent |
| 5b | lane root is not its own worktree | 1 | not silent (refusal is issued elsewhere, §3.3) |
| 5c | lane worktree dirty (excluding orchestration paths) | 1 | not silent |
| 6a | commits-ahead `unknown` | 1 + `silent_probe_base_unresolved` journal line | not silent |
| 6b | commits-ahead ≥ 1 | 1 | not silent |
| 6c | commits-ahead 0 | **0 — silent** | `review-gate.md`: `status: blocked`, `reason: arm_produced_nothing`; ledger `terminal=no_work`; the lane is closed and the founder is told that arm produced nothing |

Terminal trace for 6c: `return 0` → `_pc_silent_evidence=…commits_ahead=0` → `review-gate.md`
written → `emit decision review_gate … terminal=no_work` → `_dl_note no_work
arm_produced_nothing`. There is no retry loop above this; the lane does not get a second
worker. In plain words: **a false 6c means a lane that did real work is closed as
having done none, and nobody re-runs it.** That asymmetry is why every "cannot tell" state
in §3.1–3.3 routes to rc1.

## 4. CONFIGURATION BOUNDARIES

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `LEADV2_PC_SILENT_GROWTH_S` | default 60 | `""` fails the `^[0-9]+$` regex → 60 | `0` → clamped to 1, `silent_probe_growth_clamped … used=1` journaled | `>3600` → clamped to 3600, same journal line. **Blast radius is one probe call for one lane** — the clamp does not abort the gate or touch other lanes. Correct. | non-numeric → 60. Negative (`-5`) fails `^[0-9]+$` → 60, never reaches `(( growth_s < 1 ))` |
| `LEADV2_LANE_START_SHA` | fall to cache file | same as absent | — | — | a sha not present in the lane's object DB fails `cat-file -e` → falls to cache file, then `origin/main`, then prove-zero, then `unknown`. Never aborts. Note the branch suite **scrubs all `LEADV2_*` at start-up** precisely because this var leaks from the dispatch worker's own env |
| `${CACHE_BASE}/dispatch-${TASK}.start-sha` | `cat` fails → `""` → next fallback | `""` → next fallback | — | a huge file: `cat` output goes straight into `cat-file -e` and fails → next fallback. Bounded | multi-line content: `sha` contains a newline, `cat-file -e` fails, next fallback. Bounded |
| `origin/main` ref | `cat-file -e` fails → prove-zero → `unknown` | — | — | — | — |
| `${root}/.git` | prove-zero not attempted → `unknown` | — | FILE → linked worktree, prove-zero eligible | DIRECTORY → standalone repo, prove-zero **deliberately skipped** (the comment records that a `--git-dir` vs `--git-common-dir` string compare fired on standalone repos under macOS `/var`→`/private/var` and flipped `test-dispatch-silent-arm` Case 1 to silent) | unreadable → `-f` false → `unknown` |
| `LEADV2_PC_PRODUCED_SCAN_MAX` | default 500 | `head -""` → `head` errors → `_pc_lane_produced_files` yields `none`. **Evidence-only field; no decision reads it.** Degrades the message, not the verdict | 1 | very large → `find` walks the whole lane; this is only reached on the already-refused path, once per lane | non-numeric → `head` errors → `none` |
| `LEADV2_STOP_GATE` | default on | `!= 0` → on | `0` → checkpoint skipped | — | any non-`0` string → on |
| `LEADV2_PC_DWR_RESUME` | default on | — | `0` → no resume | — | — |
| `lib/leadv2-parked-detect.sh` | `-f` false, never sourced; `declare -F lv2_parked_text_file` false → reason stays `auto-checkpoint on worker exit` | — | — | — | source failure swallowed by `|| true`; same fallback |

No input on this path can take down more than the single lane operation it belongs to.

## 5. COUNTEREXAMPLE — what still violates the invariant after this merge

The invariant is: *a lane whose worker produced work is never closed as
`arm_produced_nothing`.* After the merge, three states still violate it, and none of them is
introduced or fixed by this merge.

**(a) Work that lives only in orchestration-owned paths.** `_pc_lane_dirty` filters porcelain
through `_PC_PORCELAIN_EXCLUDE_RE`, which excludes `docs/leadv2/` and `docs/handoff/`. A
report-only lane whose entire deliverable is `docs/handoff/<task>/<role>.full.md` is therefore
"clean" at step 5c, has 0 commits at step 6c, and is closed as `arm_produced_nothing` —
while its deliverable sits finished on disk. This is the sharpest surviving hole: the very
lanes the REPORT-ONLY-GATE path exists for are the ones the silence probe cannot see.

**(b) Prove-zero versus a pruned reflog.** Step 6's prove-zero requires *both* HEAD ==
parent HEAD *and* no `commit` entry in the worktree's HEAD reflog. With
`core.logAllRefUpdates=false`, or after `git reflog expire`, the second clause is vacuously
true. It is then saved only by the first clause — which itself becomes false-friendly the
moment the parent repo is fast-forwarded onto the lane's own commit (exactly what happens
after the lead merges a sibling lane). A lane that committed, whose commit then landed on
main, reads back as `0`.

**(c) `_pc_worker_process_alive` cannot see a worker on another host or in a container.**
`kill -0` and pid-file liveness are node-local. A dispatch arm whose process is not visible
in this pid namespace is "not provably alive" (rc1, correct fail-direction) — but it then
depends entirely on (a)/(b) not firing. Combined with (a), a remote report-only lane is
closed as silent with no local signal contradicting it.

What I checked and found clean: every rc path in §3 routes "cannot tell" to not-silent; the
one lossy channel the branch was written to widen (`0` vs unresolvable) is genuinely widened;
main's identity guard sits above both the dirty check and the commits-ahead probe, so neither
can grade the parent repository; and no input in §4 escalates beyond its own lane.

(a) and (b) are out of scope for this merge and belong in a follow-up
(`docs/leadv2/open-threads.md`), not in the resolution commit.

## 6. The third `run-core-offline.sh` failure

The mission asserts exactly two known-foreign failures — `deferred-GLM ladder
(V3-GLM-LADDER-01)` and `fanout classifier/runner guard` (the latter because
`leadv2-fanout.sh:52` sources a file absent from the harness's private HOME) — and one
failure that is ours, to be named and fixed. **I did not run the suite** (prepass, read-only),
so I name the candidates ranked by mechanism, not a verdict:

1. **A newly registered suite that passes standalone but fails under the runner.**
   The branch registered `test-silent-arm-commits-ahead.sh` and main registered
   `test-parked-worker-resume.sh`. Note the branch suite's own header: it scrubs every
   ambient `LEADV2_*` at start-up specifically because "a suite that passes only under one
   caller is the defect". `test-parked-worker-resume.sh` has no such scrub and now runs
   inside the same runner env. This is the first thing to check.
2. **Registration coverage drift.** Main added `test-lane-root-not-a-worktree.sh`,
   `test-broad-status-lanes-blind.sh`, `test-lane-behind-base.sh`,
   `test-lane-worktree-no-nesting.sh`, `test-merged-sweep-orchestration-dirt.sh`,
   `test-review-fanout-visibility.sh`, `test-selfcheck-sql-comment-header.sh` — but its
   `run-core-offline.sh` diff is **+1 line only** (`test-parked-worker-resume.sh`). Those
   suites are not in `SUITE_DEFS`. That is not a failure, but it means a green
   `run-core-offline.sh` does **not** cover main's identity guard; the mission's separate
   step-4 invocation of `test-lane-root-not-a-worktree.sh` is the only coverage it gets.
   Report this in the merge report; do not fix it here.
3. **The brace defect of §1.1**, if step 2 is missed — presents as
   `_pc_lane_commits_ahead: command not found` inside whichever silent-arm suite runs first.

Procedure for the implementer: run `run-core-offline.sh` once, capture the failing suite
names, then re-run **only** the third suite standalone. If it is green standalone and red
under the runner, the fault is env leakage and the fix is the same `LEADV2_*` scrub idiom
already in `test-silent-arm-commits-ahead.sh` lines 29–34. If it is red both ways, it is a
real merge regression and belongs in `leadv2-dispatch-product-close.sh`.

## 7. Non-goals (explicit — the implementer must NOT do these)

- **Do not merge to `main`.** The resolved commit lands on the lane branch; the lead lands it.
- **Do not touch the canonical checkout** `~/Projects/leadv2`. Verify with `git worktree list`
  that the working root is registered before the first write. A bare directory with no `.git`
  is exactly today's incident.
- **No `reset --hard`, `clean`, or `stash`** anywhere — the tree is shared with live sessions.
- **Do not hoist or de-duplicate** `_pc_lane_commits_ahead`'s base resolution into
  `_pc_diff_base`. The branch comment records that the duplication is deliberate and that the
  two copies now have divergent failure semantics (`unknown` vs fail-to-HEAD).
  `pc_scope_diff` is off-limits.
- **Do not renumber or reorder** the steps in `pc_silent_arm_probe`. §1.2 is why.
- **Do not re-author `test-lane-diff-single-repo.sh` Case C5.** The open founder question
  about C5 asserting pre-fix behaviour was answered by the branch's round-3 change (absent
  stream is no longer a veto); the mission measures C5 green. Re-authoring it would remove
  live coverage.
- **Do not delete the dead `commits_ahead` regex normalisation** at :1421.
- **Do not fix counterexamples (a) and (b) of §5**, and do not register main's seven
  unregistered suites (§6.2). Both are follow-ups.
- **No refactors, no new abstractions, no comment rewrites** beyond the one inserted brace.

## 8. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      plugins/leadv2/scripts/leadv2-dispatch-product-close.sh on the lane branch contains
      no "<<<<<<<", "=======" or ">>>>>>>" line, and contains all four helper blocks:
      the lane-root identity probe, the physical-path helper, the commits-ahead probe,
      and the live-worker probe, each closed as its own top-level definition rather than
      nested inside another.
    authored_at: 2026-08-23T12:40:16Z
  - surface: log_line
    observable: >
      Running the five named suites in the foreground prints, in their own output:
      5 passed for the single-repo lane-diff suite, 15 passed for the commits-ahead suite,
      12 passed for the dispatch silent-arm suite, 4 passed for the lane-root-not-a-worktree
      suite, and 9 passed for the parked-worker-resume suite — each with zero FAIL lines.
    authored_at: 2026-08-23T12:40:16Z
  - surface: log_line
    observable: >
      The core offline runner's final tally names exactly three failing suites: the
      deferred-GLM ladder, the fanout classifier/runner guard, and no third one — the third
      failure present before the fix is absent from the tally after it.
    authored_at: 2026-08-23T12:40:16Z
  - surface: file_artifact
    observable: >
      docs/handoff/GATE-FALSE-SILENT-01/merge-report.md states, for the single conflict
      region, which lines came from which side and why the inserted brace was needed, shows
      the pasted output of all six verification runs, and shows the change summary against
      commit b680643.
    authored_at: 2026-08-23T12:40:16Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh, plugins/leadv2/scripts/tests/test-parked-worker-resume.sh

DELIVERABLE_COMPLETE
