# architect prepass — GATE-FALSE-SILENT-01 round 3

Design only. Validated by prototype before hand-off: the exact shape below was applied to a
throwaway copy of the gate (`/tmp/arxG/scripts/`) and all three named suites are green
against it (evidence in §5). The implementer's job is to reproduce this shape in the lane
worktree `.claude/worktrees/2d8a2849`, not to re-derive it.

---

## 0. The mission's framing is incomplete — corrected against the code

The mission states C5 breaks because round 2's `unknown` fallback fires. **That is only one
of two independent breakages this lane introduced, and fixing only that one leaves C5 red.**

Falsification run (four variants of the lane's `leadv2-dispatch-product-close.sh`, each run
through `test-lane-diff-single-repo.sh --pre-fix <dir>`):

| variant | change vs lane HEAD | C5 |
|---|---|---|
| A | none (lane as-is) | FAIL |
| B | step 6 `unknown` → treated as `0` (the mission's fix, alone) | **FAIL** |
| C | step 2 absent-stream veto removed, alone | FAIL |
| D | step 2/3 restored to main's structure **and** `unknown`→`0` | PASS |

```
=== A ===  Results: 4 passed, 1 failed   FAIL: C5-registered-arm-silent
=== B ===  Results: 4 passed, 1 failed   FAIL: C5-registered-arm-silent
=== C ===  Results: 4 passed, 1 failed   FAIL: C5-registered-arm-silent
=== D ===  Results (single-pass against /tmp/arxD/scripts): 5 passed, 0 failed, 0 skipped
```

Reason: C5's fixture has **no `developer.stream.jsonl` at all**. Round 1 added
`leadv2-dispatch-product-close.sh:1332` — `[[ -f "${stream}" ]] || return 1` — which returns
"not silent" *before* execution ever reaches step 6. Round 2's `unknown` branch (l.1366) is
the *second* gate C5 dies at. Both must be separated, or the round produces a fix whose test
still fails.

### The three-way test conflict this exposes

| test | fixture | expected |
|---|---|---|
| `test-lane-diff-single-repo.sh:181` C5 | arm registered, **no stream**, clean **linked worktree**, no base resolvable | `terminal=no_work cause=arm_produced_nothing` |
| `test-dispatch-silent-arm.sh:64` Case 1 | arm registered, **no stream**, clean **standalone repo** (`git init` in `$tmp/lane`) | NOT `arm_produced_nothing`, ledger `empty_diff`, no `arm_advance` |
| `test-silent-arm-commits-ahead.sh:111` Case B | same as Case 1 | NOT `arm_produced_nothing` |

On the mission's stated axis (stream present/absent) these are *contradictory* — same inputs,
opposite verdicts. They are only reconcilable on a different axis: **C5's lane is a linked git
worktree with a reachable creation point; Case 1/B's lane is a standalone repository with
none.** That, not the stream, is the discriminator the design must be built on. This is also
exactly the mission's own "provably zero vs. genuinely unknown" split, made operational.

---

## 1. Design

Two changes in one file. Non-goal: everything else (see §6).

### Change 1 — `pc_silent_arm_probe`, restore main's absent-stream structure (l.1328–1352)

Round 1's blanket veto is redundant once §Change 2 lands, and it is what makes C5 unreachable.
Re-wrap the freshness guard in `if [[ -f "${stream}" ]]; then … fi` (main's shape) and delete
the standalone `[[ -f "${stream}" ]] || return 1` line. Round 1's actual protections survive
intact and are the ones that carry Case 1/B:

- step 4 `_pc_worker_process_alive` — "too early to tell" for a still-running worker;
- step 5 `_pc_lane_dirty` — uncommitted work;
- step 6 (below) — a lane whose history cannot be reasoned about at all.

Rationale to record in the comment: an absent stream is not *evidence of* silence, but neither
is it a *veto* — a `glm`/`codex` arm structurally never writes `developer.stream.jsonl`, so
under round 1's rule `arm_produced_nothing` was unreachable for every non-sonnet arm, which is
the very chain-advance path this mechanism exists to drive.

### Change 2 — `_pc_lane_commits_ahead`, prove-zero before `unknown` (after l.1204)

Insert immediately after the `if [[ -n "${base}" ]] … fi` block and before `printf 'unknown'`:

```sh
    # GATE-FALSE-SILENT-01 round 3: a base is not required to prove ZERO. A linked
    # worktree whose HEAD is the same commit as the repository it hangs off, and whose
    # HEAD reflog records no commit of its own, provably has no commits of its own --
    # "0", not "unknown". `${root}/.git` as a FILE is the linked-worktree test: a
    # standalone repo has a .git DIRECTORY. Deliberately NOT a path comparison of
    # --git-dir vs --git-common-dir -- on macOS TMPDIR is /var -> /private/var, so the
    # two strings differ for a standalone repo and prove-zero fires on lanes it must
    # never fire on (observed: test-dispatch-silent-arm Case 1 flipped to silent).
    local head_wt head_parent
    if [[ -f "${root}/.git" ]]; then
      head_wt="$(git -C "${root}" rev-parse HEAD 2>/dev/null || true)"
      head_parent="$(cd "${root}" 2>/dev/null && git --git-dir="$(git rev-parse --git-common-dir 2>/dev/null)" rev-parse HEAD 2>/dev/null || true)"
      if [[ -n "${head_wt}" && "${head_wt}" == "${head_parent}" ]] && \
         ! git -C "${root}" log -g --format=%gs HEAD 2>/dev/null | grep -q '^commit'; then
        printf '0'; return 0
      fi
    fi
```

The reflog conjunct is not cosmetic — it is the mitigation for the counterexample in §4.
Round 2's `unknown` return and the caller's `silent_probe_base_unresolved` journal line are
kept **verbatim** for everything that does not prove zero.

---

## 2. Mechanism closure

### 2.1 Callers and callees (file:line, lane worktree `2d8a2849`)

`_pc_lane_commits_ahead` — `leadv2-dispatch-product-close.sh:1183`
- callers: exactly one — `pc_silent_arm_probe:1365`. No other file in `plugins/leadv2/scripts`
  references it (`grep -rn _pc_lane_commits_ahead plugins/leadv2/scripts` → this file + the
  two suites only).
- callees: `git rev-parse --is-inside-work-tree` / `cat-file -e` / `merge-base` /
  `rev-list --count`; reads `LEADV2_LANE_START_SHA`, `${CACHE_BASE}/dispatch-${TASK}.start-sha`,
  `origin/main`. New callees: `git rev-parse --git-common-dir`, `git log -g --format=%gs`.

`pc_silent_arm_probe` — `:1313`
- caller: exactly one — top level `:2125`, which runs **before** `pc_scope_diff` (`:2135`).
- callees: `_pc_arm_registered:1279` → `_pc_arm_registered_file:1266`; `_pc_stat_mtime:1232`;
  `_pc_worker_process_alive:1215` → `_pc_run_dir_for`/`_pc_meta_value`/`_pc_process_alive`;
  `_pc_lane_dirty:1156`; `_pc_lane_commits_ahead:1183`; `emit`.
- verdict consumers at `:2126–2132`: `review-gate.md` (`reason: arm_produced_nothing`), the
  `review_gate … terminal=no_work cause=arm_produced_nothing` journal line, `_dl_note` ledger
  row, `_pc_arm_advance:1381` → `bash "${DISPATCH_BIN}" advance-arm` in
  `leadv2-dispatch-code.sh`, then `exit 5`.

**Independent copy on a different path — named, and deliberately not touched.**
`_pc_diff_base` duplicates the same three-tier base resolution and is reached by a *different*
route: `pc_scope_diff` → `_pc_repo_diff` → `_pc_diff_base`, i.e. only on the fall-through after
this probe declines. It fails to empty/HEAD rather than to `unknown`. It is `off_limits` this
round. Recorded divergence: prove-zero exists in `_pc_lane_commits_ahead` only; a future edit to
base resolution must be applied to both or they drift (the round-2 comment at :1166–1174 already
carries this warning — extend it, don't replace it).

No second gate emits `arm_produced_nothing`: `grep -rn arm_produced_nothing plugins/leadv2/scripts`
outside this file and `tests/` returns nothing.

### 2.2 States and return codes

`_pc_lane_commits_ahead <root>` — stdout only, **rc is always 0**, never aborts the gate.

| state of the lane | stdout | caller does | user-visible end state |
|---|---|---|---|
| base resolved, ≥1 commit ahead | `N≥1` | `return 1` at :1371 | probe declines; `pc_scope_diff` runs; lane is reviewed normally |
| base resolved, 0 commits ahead | `0` | falls to :1372, `return 0` | gate writes `reason: arm_produced_nothing`, ledger `no_work/arm_produced_nothing`, next arm in the chain is dispatched, `exit 5` |
| no base, **linked worktree, HEAD == parent HEAD, no commit in reflog** *(new)* | `0` | as above | same as above — this is C5 and every real lane whose worker never committed |
| no base, linked worktree, HEAD ≠ parent HEAD | `unknown` | `emit silent_probe_base_unresolved`, `return 1` | probe declines; `pc_scope_diff` owns the verdict; operator sees the named degradation line and knows *why* no silent verdict was reached |
| no base, linked worktree, HEAD == parent HEAD but reflog shows a `commit` entry | `unknown` | as above | as above (conservative; §4) |
| no base, standalone repo (Case 1/B/E fixtures, multi-repo lanes) | `unknown` | as above | as above |
| `root` empty / missing / not a work tree | `unknown` | as above | as above |
| `rev-list` output non-numeric | `unknown` | as above | as above |

`pc_silent_arm_probe` — rc0 = silent, rc1 = not silent. rc1 is **never** terminal on its own:
control falls through to `pc_scope_diff`, which still reaches `no_work/empty_diff` on an empty
lane (`test-dispatch-silent-arm.sh` Case 1 asserts `rc=5` on exactly this route). The only
difference rc0 vs rc1 makes to a human is the **cause** written to the ledger and whether the
**next arm is dispatched at all** — an rc1 on a genuinely dead silent arm means the chain never
advances and the task sits with no work produced and no successor arm, which is the failure
this whole mechanism exists to prevent.

### 2.3 Configuration boundaries

| input | absent | empty | minimum | maximum / over-cap | malformed |
|---|---|---|---|---|---|
| `LEADV2_LANE_START_SHA` | tier 2 tried | `[[ -n ]]` false → tier 2 | any valid sha | n/a | `cat-file -e` fails → tier 2. A leaked ambient sha from an enclosing lane resolves to no object here → tier 2 → tier 3 → `unknown` (Case E). Never aborts. |
| `${CACHE_BASE}/dispatch-${TASK}.start-sha` | `cat` fails, `|| true` → tier 3 | → tier 3 | — | multi-line file → embedded newline → `cat-file -e` fails → tier 3 | same |
| `origin/main` | `cat-file -e` fails → prove-zero → `unknown` | — | — | — | — |
| `${root}/.git` *(new read)* | not a git tree; the outer `rev-parse --is-inside-work-tree` guard already declined | — | **file** ⇒ linked worktree, prove-zero eligible | **directory** ⇒ standalone repo, prove-zero refused | unreadable → `git` calls fail → `unknown` |
| HEAD reflog *(new read)* | disabled/pruned (`core.logAllRefUpdates=false`, bare fixtures) → no `^commit` match → prove-zero allowed, i.e. degrades to the parent-HEAD signal alone | — | — | huge reflog: `log -g` is streamed into `grep -q`, bounded by the pipe's early exit | — |
| `LEADV2_PC_SILENT_GROWTH_S` | 60 | 60 | clamped to 1, `silent_probe_growth_clamped` emitted | clamped to 3600, same line — an over-cap value cannot make `arm_produced_nothing` permanently unreachable | non-numeric → 60 |
| `LEADV2_LANE_WORK_ROOT` / `_lane_root` | resolved via `leadv2-lane-worktree.sh path-of`; still unresolved ⇒ probe `return 1` at :1356 | same | — | — | points at the **main checkout** (worktree fallback): `.git` is a directory ⇒ prove-zero refused ⇒ `unknown`. Correct: a lane sharing the main tree has no creation point. |

No new env var is introduced, so the `LEADV2_*` naming and `.claude/settings.json` cross-check
are vacuous this round. No `claude -p` invocation is added. No file is read+written by two
parallel steps: `_pc_lane_commits_ahead` is read-only on git state.

### 2.4 Counterexample — what still violates the invariant after this round

Invariant: *a lane that produced work is never labelled `arm_produced_nothing`.*

One real hole survives, and it is why the reflog conjunct is mandatory rather than optional.
Suppose a worker commits its work in the lane worktree and the merge queue lands those commits
onto the parent repo's checked-out branch **before** the close gate runs (this repo has a live
`docs/leadv2/merge-queue.jsonl`, so the ordering is not hypothetical). The parent's HEAD is now
the lane's HEAD, no configured base resolves, and parent-HEAD equality alone would return `0` —
labelling a lane that produced real, already-landed work as silent, and advancing the arm chain
on top of it. The `git log -g --format=%gs HEAD | grep -q '^commit'` conjunct closes this: a
worktree that committed has a `commit:` reflog entry, so it returns `unknown` instead. Where the
reflog is disabled or pruned the hole reopens; the design accepts that residual because such a
lane is indistinguishable from a fresh one by any local signal, and the fallback (`unknown`) is
only reachable when a lane also has no start-sha, no cache file and no `origin/main` — a
configuration a production lane does not have. A second, smaller hole: prove-zero requires the
parent's HEAD to still be the worktree's creation point, so a lane created from `origin/main`
while the main checkout sits elsewhere yields `unknown` rather than `0` — conservative, not
unsafe. Checked and found clean: no second copy of this probe on another dispatch path; the
`_pc_diff_base` duplicate is downstream of this decision and cannot re-label the verdict.

---

## 3. Files

- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — both changes above.
- `plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` — **add** two cases; do not
  weaken A–E:
  - **Case F (prove-zero positive):** lane is a real linked worktree (`git worktree add`),
    arm registered, no stream, clean, no start-sha/cache/origin ⇒ `arm_produced_nothing`, and
    **no** `silent_probe_base_unresolved` line.
  - **Case G (prove-zero must not fire):** same linked worktree but with one commit made in it
    ⇒ NOT silent, and `silent_probe_base_unresolved` emitted. This is the regression lock for
    the merge-queue counterexample in §2.4.

`test-lane-diff-single-repo.sh` and `test-dispatch-silent-arm.sh` are read-only this round.

---

## 4. Acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      For a lane worktree whose HEAD is still the commit it was created from and which
      committed nothing, the close gate's journal line reads
      "review_gate ... terminal=no_work cause=arm_produced_nothing", and no
      "silent_probe_base_unresolved" line appears for that lane.
    authored_at: 2026-08-23T11:02:00Z
  - surface: log_line
    observable: >-
      For a lane whose history cannot be placed against any reachable reference, the journal
      shows "silent_probe_base_unresolved" and no arm_produced_nothing verdict for that lane.
    authored_at: 2026-08-23T11:02:00Z
  - surface: file_artifact
    observable: >-
      docs/handoff/dispatch-<sig>/review-gate.md for the silent lane contains
      "reason: arm_produced_nothing"; for the unresolvable lane it does not.
    authored_at: 2026-08-23T11:02:00Z
```

---

## 5. Prototype evidence (this design, already run)

`/tmp/arxG/scripts/` = the lane's scripts with exactly §1's two changes applied.

```
=== commits-ahead (test-silent-arm-commits-ahead.sh) ===
[TEST] 11 passed, 0 failed
=== silent-arm (test-dispatch-silent-arm.sh) ===
[TEST] 12 passed, 0 failed
=== single-repo (test-lane-diff-single-repo.sh --pre-fix /tmp/arxG/scripts) ===
Results (single-pass against /tmp/arxG/scripts): 5 passed, 0 failed, 0 skipped
```

Intermediate variant `/tmp/arxE` — identical except the linked-worktree test was
`--absolute-git-dir != --git-common-dir` instead of `[[ -f "${root}/.git" ]]` — produced:

```
FAIL: Case E: unresolvable-base lane classified arm_produced_nothing
FAIL: Case 1: arm_advance decision emitted for an absent (unproven) stream
```

because macOS resolves `TMPDIR` through `/var → /private/var`, so the two path strings differ
for a *standalone* repo. Do not implement the path-comparison form.

The implementer must still run all four verifications named in the mission in the lane
worktree, in the foreground, and paste the output — this prototype ran outside the lane and is
design evidence, not the round's verification.

---

## 6. Out of scope

`pc_scope_diff`, `_pc_diff_base`, `_pc_repo_diff`, the e2e gate, the review-gate ladder,
hoisting the duplicated base resolution, `test-lane-diff-single-repo.sh`,
`test-dispatch-silent-arm.sh`, Cases A–E of `test-silent-arm-commits-ahead.sh`, the two
genuinely pre-existing `run-core-offline.sh` failures (`deferred-GLM ladder (V3-GLM-LADDER-01)`,
`fanout classifier/runner guard`), and main's unrelated dirty files.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh

DELIVERABLE_COMPLETE
