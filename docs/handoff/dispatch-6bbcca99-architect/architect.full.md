# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — implementation design (architect prepass)

Repo to change: `~/Projects/leadv2` (the plugin). Branch only — no commit to main, no push, no merge.

## 1. Layers affected

| Layer | File | Nature of change |
|---|---|---|
| Close gate (dispatch control plane) | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | 2 edits inside `pc_scope_diff()` + 1 new helper |
| Test harness | `plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` *(to-create)* | new red-first suite |
| Suite registry | `plugins/leadv2/scripts/tests/run-core-offline.sh` | 1 `run_check` line |

No other script reads `diff_root`, `CROSS_REPO_DIFF`, or `review-gate.md` `reason:` by value except
`leadv2-dispatch-ledger.sh` (vocabulary, see §4) and the lead's own journal reading. No schema, no
DB, no migration, no env-var addition.

## 2. Current data flow (defective)

1. `pc_scope_diff()` sets `diff_root="${ROOT}"` (`:861`).
2. **Only if** `CROSS_REPO_DIFF == 1` (`:862`) it resolves the lane worktree — first from
   `LEADV2_LANE_WORK_ROOT` (the exact value `dispatch-code.sh` passed as the worker's `--cwd`),
   else from `leadv2-lane-worktree.sh path-of <FOUNDER_TASK_ID>` (`:863-867`).
3. `_pc_repo_diff "${diff_root}" ...` (`:1010` single-repo branch / `:994` multi-repo branch)
   produces the diff, written to `${HANDOFF}/review.diff`.
4. Empty diff → `blocked_reason=unscopable_diff` (`:1015`/`:1022`).
5. `:1034-1039` maps any non-`partial_diff` empty result to `terminal=no_work cause=empty_diff`
   (or `asked_into_void` when the marker exists), writes `review-gate.md`, calls `_dl_note`, exits 5.

**Fault:** step 2 is conditional, but step 3 is not. With `CROSS_REPO_DIFF=0`/unset, `diff_root`
remains the main checkout while the worker's uncommitted work lives in
`.claude/worktrees/<founder_tid>`. Step 3 returns 0 bytes and step 5 retires a complete lane as
`no_work` — an outcome a lead is expected to trust and re-dispatch from. Observed live on
persona-engine `0db1da80` (2026-08-04): 221 insertions + a 193-line new test file discarded.

The comment block at `:851-860` already states the invariant the code violates: *"diff_root can
never disagree with where the code actually landed."* The flag was meant to be a one-flip revert of
**cross-repo grouping**, not of lane-root resolution.

## 3. Target data flow

1. Resolve the lane worktree **unconditionally**, before any `CROSS_REPO_DIFF` branch. Same
   two-source precedence as today (`LEADV2_LANE_WORK_ROOT` → `path-of`), same `-d` existence guard,
   same silent fallback to `${ROOT}` when no lane exists.
2. `CROSS_REPO_DIFF` retains exactly one job: choosing the multi-repo per-write grouping branch
   (`:960-1008`) vs. the flat single-`diff_root` branch (`:1009-1013`). `partial_diff` semantics
   are untouched.
3. On an empty diff, before mapping to `no_work`, probe the resolved lane root for dirt. Dirty ⇒
   the gate could not scope work that demonstrably exists ⇒ its own reason. Clean (or no lane
   resolved) ⇒ `no_work`/`empty_diff`/`asked_into_void` exactly as today.

## 4. Interface contracts

### 4.1 `_pc_lane_dirty <root>` (new, private to the close gate)

| Item | Contract |
|---|---|
| Input | absolute path; may be empty or nonexistent |
| rc 0 | `root` is a git work tree AND has ≥1 uncommitted tracked change or untracked file, after excluding `docs/leadv2/` and `docs/handoff/` |
| rc 1 | empty/nonexistent/not-a-git-tree, or clean |
| Side effects | none; never mutates the index or working tree |
| Impl note | `git -C "$r" status --porcelain --untracked-files=all` filtered with `grep -vE` on the two doc prefixes — **not** pathspec magic, which behaves inconsistently across the git versions in play. Must tolerate quoted porcelain paths (`"docs/handoff/x y"`). |

The exclusion set must match `_pc_git_diff`'s `':(exclude)docs/leadv2' ':(exclude)docs/handoff'`
(`:890-896`), otherwise a lane whose *only* churn is its own handoff artifacts flips from `no_work`
to the new reason — a false rescue on every parked lane.

### 4.2 Terminal / reason vocabulary

`leadv2-dispatch-ledger.sh:192` validates `landed|parked|refused|dead|no_work`. **Do not add a new
terminal word** — a new one is rejected by the ledger and the row is lost.

| Case | terminal | cause | `review-gate.md` reason |
|---|---|---|---|
| mixed empty/non-empty repos | `refused` | `partial_diff` | `partial_diff` *(unchanged)* |
| empty diff, lane resolved and **dirty** | `refused` | `unscoped_lane_work` | `unscoped_lane_work` **(new)** |
| empty diff, void marker present | `no_work` | `asked_into_void` | `no_work` *(unchanged)* |
| empty diff, lane clean or absent | `no_work` | `empty_diff` | `no_work` *(unchanged)* |

`refused` is the correct terminal: the ledger treats `landed|dead` as write-once-final and
`refused|parked` as retryable non-final (`:312-316`), which is precisely the semantics a
diff-scoping failure needs — the lane must remain re-openable, and the lead must not be told the
worker produced nothing.

`_dl_note` evidence field carries the diagnosis: `lane_root=<basename> dirty=<n>` where `<n>` is
the filtered porcelain line count. `review-gate.md` gains a `dirty:` line beside the existing
`base:` line. Exit code stays **5** — no caller-contract change.

## 5. Edits, precisely

### E1 — `leadv2-dispatch-product-close.sh:861-868`, hoist lane resolution

Replace the `if [[ "${CROSS_REPO_DIFF}" == "1" ]]` wrapper with an unconditional block; keep the
body verbatim (`LEADV2_LANE_WORK_ROOT` → `path-of` fallback → `-d` guard). Update the `:851-860`
comment to record that the flag no longer gates root resolution and why (this mission id).
`_lane_root` must remain readable after the block — it is the §5-E2 gate condition.

### E2 — `leadv2-dispatch-product-close.sh:1034-1039`, dirty-lane branch

Inside `if [[ "${blocked_reason}" != "partial_diff" ]]`, before the existing `no_work` assignment:
if `[[ -n "${_lane_root}" && -d "${_lane_root}" ]]` **and** `_pc_lane_dirty "${_lane_root}"`, set
`refused` / `unscoped_lane_work`; otherwise fall into the existing `no_work` path untouched.

Gate on `_lane_root`, **not** on `diff_root != ROOT`: when no lane worktree exists the workers write
into the main checkout, and unrelated founder edits sitting there must never be mistaken for lane
work.

Order matters: the dirty check precedes the `asked_into_void` sub-case. A lane that both asked into
the void and left dirt is a scoping failure first — the question is answerable later; the discarded
diff is not recoverable once the lead re-dispatches.

### E3 — helper placement

`_pc_lane_dirty` goes beside `_pc_diff_base` (`:908-921`), inside `pc_scope_diff`'s helper cluster,
so it is defined before its only call site.

### E4 — new suite `tests/test-lane-diff-single-repo.sh`

Reuse the fixture pattern already proven in `tests/test-landing-diff-scoping.sh` (sandboxed
`HOME`/`TMPDIR`, `new_repo`, `ensure_worktree`, mtime tripwire over `~/Projects/leadv2/plugins` and
`~/.claude`, never `git stash`/`reset --hard`/`clean`). Four cases, all with
`LEADV2_REVIEW_DIFF_CROSS_REPO=0`:

| # | Fixture | Required outcome |
|---|---|---|
| C1 | lane worktree with an uncommitted **tracked** modification | `review.diff` non-empty; no `no_work` terminal |
| C2 | lane worktree with a new **untracked** file matching `LANE_WRITES` | `review.diff` non-empty; no `no_work` terminal |
| C3 | lane worktree **clean** (worker did nothing) | `terminal=no_work cause=empty_diff` — the anti-rescue case |
| C4 | lane dirty **only** under `docs/handoff/` | `terminal=no_work` — the exclusion-set case |

Each case runs red-first against a `git archive HEAD` extraction of the pre-fix script; a case green
pre-fix is reported `GREEN-PRE-FIX` and does not count as evidence. C1/C2 must be red pre-fix.

### E5 — register in `run-core-offline.sh`

One `run_check "product-close scopes a single-repo lane worktree" bash "$TEST_DIR/test-lane-diff-single-repo.sh"`
beside the existing product-close checks (`:86-87`).

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **`CROSS_REPO_DIFF=0` is no longer a full revert.** `tests/test-landing-diff-scoping.sh` Q3 asserts the flag "actually flips the outcome" — for a lane whose writes are single-repo, it now will not. | Expected and mission-ordered. Run that suite; if Q3 fails, its assertion must be re-scoped to "flips the *grouping*", not weakened away. Report the delta to the lead; do **not** re-conditionalise E1 to make it pass. |
| R2 | **False rescue.** A lane that wrote nothing but whose worktree carries stray dirt (editor swapfiles, `.DS_Store`, its own handoff docs) now reports `unscoped_lane_work` instead of `no_work`, hiding real worker failures. | Exclusion set mirrors `_pc_git_diff` exactly (§4.1); C4 pins it. Accepted residual: unrelated non-doc dirt. `refused` is retryable, so the cost is a re-dispatch, not a lost lane — strictly better than today's discard. |
| R3 | **`_lane_root` scope.** It is currently set inside an `if` inside a function; if a future refactor makes it `local` to the wrong block, E2's condition silently reads empty and the fix reverts to `no_work` with no error. | Keep `_lane_root` unqualified (no `local`), as today. C1/C2 fail loudly if it is ever lost. |
| R4 | **`path-of` keying.** Worktrees are keyed by `FOUNDER_TASK_ID`, not this script's `sig8` `TASK`. Making the call unconditional means it now runs on every single-repo close — a path that never exercised it before. | `path-of` is documented rc-0-always with empty output on miss (`leadv2-lane-worktree.sh:45,64`); the `-d` guard already handles empty. No new failure mode, only a new caller. |
| R5 | **`git status` cost.** One extra `git status -uall` per blocked close, on a possibly large tree. | Only runs on the empty-diff path, which already exits immediately after. Negligible. |
| R6 | **Shared-tree blast radius.** These scripts are symlinked into persona-engine, m3-market, respiro-ios; a regression breaks dispatch in all three. | `bash -n` on every touched file; full `run-core-offline.sh` green with output pasted; branch only, lead merges. |
| R7 | **Harness self-defect.** `run-core-offline.sh` sub-suite "review body persist" already fails when run from inside a lane worktree with this exact symptom. | Per mission: it must go green *because of* the fix. If it does not, that is a finding to report, not a fixture to weaken. |

## 7. Out of scope

- `partial_diff`, `asked_into_void`, `unscopable_diff` semantics — unchanged.
- The multi-repo grouping branch (`:960-1008`) — untouched.
- `_pc_git_diff` / `_pc_diff_base` / `_pc_repo_diff` internals — untouched.
- `leadv2-lane-worktree.sh`, `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh` — no edits.
- Removing `LEADV2_REVIEW_DIFF_CROSS_REPO`, or the duplicated `.claude/scripts/tests/` tree.
- `~/.claude/leadv2-shared/`, any project's `.claude/leadv2/`, persona-engine — do not touch.
- Any other gate. Do not loosen anything to make a test pass.

## 8. Constraint checklist

1. **Env vars** — no new env var. `LEADV2_REVIEW_DIFF_CROSS_REPO`, `LEADV2_LANE_WORK_ROOT`,
   `LEADV2_PROJECT_ROOT` all already exist with `LEADV2_*` prefix; semantics of the first are
   *narrowed*, documented in-comment (§5-E1) and in R1. No `LEAD_V2_*` drift introduced.
2. **Paths** — `leadv2-dispatch-product-close.sh`, `tests/run-core-offline.sh`,
   `tests/test-landing-diff-scoping.sh`, `leadv2-lane-worktree.sh` verified present;
   `tests/test-lane-diff-single-repo.sh` marked `(to-create)`.
3. **`claude -p`** — none introduced.
4. **Concurrent access** — `_pc_lane_dirty` is read-only and, unlike `_pc_git_diff`, never touches
   the index, so it is safe against a concurrent session sharing the tree. `review.diff` /
   `review-gate.md` writers are unchanged.
5. **Config contradiction** — `CROSS_REPO_DIFF` is read at `:850`, `:862`, `:960` only. After E1 the
   `:862` read disappears and the remaining two agree on one meaning (grouping). No contradiction.

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      In the dispatch journal for a single-repo close (LEADV2_REVIEW_DIFF_CROSS_REPO
      unset or 0) whose lane worktree holds uncommitted work, the reviewer reads
      "review_gate ... status=blocked reason=unscoped_lane_work terminal=refused
      cause=unscoped_lane_work" — the words "no_work" and "empty_diff" do not appear
      for that task.
    authored_at: 2026-08-04T11:16:48Z
  - surface: file_artifact
    observable: >-
      docs/handoff/dispatch-<sig8>/review.diff for that same close is a non-empty
      unified diff containing the worker's changed lines, and review.diff.repos shows
      a byte count greater than zero for the repo.
    authored_at: 2026-08-04T11:16:48Z
  - surface: log_line
    observable: >-
      For a lane worktree whose working tree is clean, the journal still reads
      "dispatch_terminal ... terminal=no_work cause=empty_diff" — a worker that did
      nothing is still reported as having done nothing.
    authored_at: 2026-08-04T11:16:48Z
  - surface: rendered_line
    observable: >-
      The run-core-offline.sh summary printed to the terminal lists the new
      "product-close scopes a single-repo lane worktree" check as PASS, the
      previously-failing "review body persist" sub-suite as PASS, and reports zero
      failures overall.
    authored_at: 2026-08-04T11:16:48Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
