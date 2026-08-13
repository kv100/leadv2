# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — implementation design (architect prepass)

Repo to change: `~/Projects/leadv2` (plugin), branch only, no commit to main.

## 1. Confirmed defect surface (read from live code)

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

| Line(s) | Current behaviour | Consequence |
|---|---|---|
| 861-868 | `diff_root="${ROOT}"`; lane worktree consulted **only** inside `if [[ "${CROSS_REPO_DIFF}" == "1" ]]` | With `LEADV2_REVIEW_DIFF_CROSS_REPO=0`, `diff_root` is the main checkout, where the lane's uncommitted work does not exist |
| 934-956 | `_pc_repo_diff "${diff_root}" …` | Returns 0 bytes; `review.diff.repos` records `<repo> 0` |
| 1015, 1020 | `[[ -s "${diff_file}" ]] \|\| blocked_reason="unscopable_diff"` | Empty-by-scoping is indistinguishable from empty-by-idleness |
| 1026-1046 | `blocked_reason != partial_diff` → `terminal=no_work cause=empty_diff` | Complete lane work is retired as "the worker did nothing" |

The comment block at 853-860 already states the invariant the code violates: *"diff_root can never disagree with where the code actually landed"*. The `CROSS_REPO_DIFF` gate around it conflates two unrelated things: **(a)** which root to diff, **(b)** whether to split the write-set across multiple git repos. Only (b) is what the flag was ever about.

Terminal vocabulary is a **closed set** validated in `leadv2-dispatch-ledger.sh:192` — `landed|parked|refused|dead|no_work`. The new outcome must reuse one of these; extending the enum is out of scope.

## 2. Changes

### C1 — unconditional lane-root resolution (`pc_scope_diff`, ~861-868)

Replace the flag-gated block with an always-on resolution that records whether a **lane worktree** (as opposed to the plain `${ROOT}` fallback) was actually used:

| Element | Contract |
|---|---|
| `diff_root` | `${LEADV2_LANE_WORK_ROOT}` if set and a directory; else `leadv2-lane-worktree.sh path-of "${FOUNDER_TASK_ID:-${TASK}}"` if it resolves to a directory; else `${ROOT}` |
| `_pc_lane_root_used` | `1` iff `diff_root` came from either lane source and `diff_root != ROOT`; else `0` (new global, no `local`) |
| `CROSS_REPO_DIFF` | Retains its **only** remaining job: gating the multi-repo write-set split at 959-1009. Behaviour on `=0` is single-repo diffing **at the lane root** |

The 853-860 comment must be rewritten in the same edit — the current text asserts "flag OFF is a genuine one-flip full revert", which stops being true and is exactly the drift that produced this defect. New comment states: root resolution is unconditional; the flag scopes repo-splitting only.

### C2 — dirty-lane guard before the `no_work` verdict (~1015-1046)

New helper, placed beside `_pc_repo_diff`:

```
_pc_lane_dirty_count <repo_abs> -> integer on stdout
```

Contract:

| Aspect | Decision |
|---|---|
| Command | `git -C "${repo}" status --porcelain --untracked-files=all -- . ':(exclude)docs/leadv2' ':(exclude)docs/handoff'` |
| Counts | Modified/staged tracked files **and** untracked files (`??`), matching `_pc_git_diff`'s tracked+untracked coverage and its exclusion set |
| Ignored files | Not counted (`--porcelain` default) — build artifacts must not fake work |
| Failure | Non-zero git exit or unparseable output → prints `0` (fail-toward-current-behaviour; never invents work) |

Guard placement: inside the `if [[ -n "${blocked_reason}" ]]` block, **only** on the branch that would otherwise become `no_work` (`blocked_reason != partial_diff`) and **only** when `_pc_lane_root_used == 1`:

```
no_work branch:
  if _pc_lane_root_used==1 and _pc_lane_dirty_count(diff_root) > 0:
      terminal = refused
      cause    = unscoped_lane_work
      rg_reason= unscoped_lane_work
  else keep no_work/empty_diff (or asked_into_void) exactly as today
```

Rationale for `refused` as the terminal word: it is the existing **retryable** disposition already used for `partial_diff` (a gate-side scoping failure where work does exist), and it is explicitly *not* a true terminal in `dispatch_terminal_exists()` — so the lead may re-close or re-scope without a poisoned ledger. `dead` would be wrong (no crash), `no_work` is the lie being fixed, `parked` is reserved for asked-into-void.

**The `_pc_lane_root_used` predicate is load-bearing.** Without it, a plain-`${ROOT}` dispatch in a repo dirtied by a concurrent session would flip every genuine `no_work` to `unscoped_lane_work` — the mission's second Done criterion inverted.

### C3 — evidence and artifacts

| Surface | Change |
|---|---|
| `review-gate.md` | `reason: unscoped_lane_work` on the new branch; `status: blocked`, `base:` line unchanged |
| Journal `review_gate` decision line | `status=blocked reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work` |
| New journal line before the verdict | `review_diff_scope task=<sig8> lane_root=<basename> lane_used=<0\|1> dirty=<n>` — makes the resolution auditable without re-running the gate |
| `_dl_note` evidence arg | `lane_root=<abs> dirty=<n>` |
| Exit code | Stays `5`. No caller-contract change |

### C4 — tests

New file `plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh`, following the sandboxed-HOME/TMPDIR + `new_repo`/`ensure_worktree` fixture pattern proven in `tests/test-landing-diff-scoping.sh` (mtime tripwire over `~/Projects/leadv2/plugins` and `~/.claude` included; never `git stash`/`reset --hard`/`clean`).

| # | Fixture | `CROSS_REPO_DIFF` | Expected |
|---|---|---|---|
| T1 | Lane worktree with an uncommitted edit to a tracked declared write | unset | `review.diff` non-empty; no `no_work` terminal |
| T2 | Lane worktree with a brand-new untracked declared write | `0` | `review.diff` non-empty; no `no_work` terminal |
| T3 | Lane worktree completely clean | unset | `terminal=no_work cause=empty_diff` (regression guard on the fix) |
| T4 | Lane worktree dirty **outside** the declared write-set | unset | `terminal=refused cause=unscoped_lane_work`, not `no_work` |
| T5 | No lane worktree at all, main checkout dirty from an unrelated file | unset | `terminal=no_work cause=empty_diff` (proves the `_pc_lane_root_used` predicate) |
| T6 | `CROSS_REPO_DIFF=1` multi-repo mixed group | `1` | `partial_diff` / `refused` unchanged |

Red-first: T1/T2/T4 must be demonstrated failing against the pre-fix script (`git show HEAD:<path>` extraction, as the existing suite does) and reported as `GREEN-PRE-FIX` if they are not.

Registration: one `run_check "lane diff single-repo (lane root unconditional + unscoped_lane_work)" bash "$TEST_DIR/test-lane-diff-single-repo.sh"` line in `plugins/leadv2/scripts/tests/run-core-offline.sh`, adjacent to the existing `review body persist` entry (line ~113).

Expected side effect the implementer must verify and report: the four `review body persist` fixture cases that currently fail from inside a lane worktree (`review_diff repo=<sig8> bytes=0 base=HEAD`) should go green **without touching that suite's fixtures**. If they do not, the fix is incomplete — do not weaken them.

## 3. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Dirty-lane guard fires on harness/state noise (`.claude/` run dirs, editor temp files) inside the worktree → `unscoped_lane_work` where `no_work` is truthful | Exclusion set matches the diff's (`docs/leadv2`, `docs/handoff`); ignored files excluded. If `.claude/` noise is observed in T3, add `':(exclude).claude'` and record it as a decision — do **not** widen to a heuristic allowlist |
| R2 | Always-on lane resolution changes behaviour for the 3 repos sharing the symlinked script | `diff_root` only ever moves to a path that `leadv2-lane-worktree.sh` itself created for this founder task id; when no worktree exists the value is byte-identical to today's |
| R3 | `path-of` fallback returns a stale worktree from a previous attempt | Already the pre-existing fallback path; unchanged semantics. `-d` check retained; the new journal line makes a wrong root visible |
| R4 | `refused` is consumed elsewhere as "declined at admission" | `partial_diff` already sets `refused` post-admission (1033); no new precedent. Grep `unscoped_lane_work` before adding — it must be a fresh cause string |
| R5 | Concurrent access: `${HANDOFF}/review.diff`, `review.diff.repos`, `review-gate.md` are written by this gate only, single-threaded per lane | No lock needed; do not add one |
| R6 | `git status` on a large worktree adds latency to every close | Runs only on the already-terminal empty-diff path, at most once per lane |

## 4. Constraint checklist

1. **Env vars** — no new env vars introduced. Existing `LEADV2_REVIEW_DIFF_CROSS_REPO`, `LEADV2_LANE_WORK_ROOT`, `LEADV2_LANE_START_SHA` keep their names and `LEADV2_*` prefix. ✅
2. **Paths** — `leadv2-dispatch-product-close.sh`, `tests/run-core-offline.sh`, `tests/test-landing-diff-scoping.sh` verified on disk; `tests/test-lane-diff-single-repo.sh` is **(to-create)**. ✅
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — see R5. ✅
5. **Config contradiction** — `CROSS_REPO_DIFF`'s meaning narrows; the 853-860 comment that asserts the old meaning is rewritten in the same edit (C1). Implementer must grep `LEADV2_REVIEW_DIFF_CROSS_REPO` across the plugin and reconcile every doc/comment hit. ✅

## 5. Out of scope

- Editing the `review body persist` suite or its fixtures.
- Extending the ledger terminal enum.
- `partial_diff`, `asked_into_void`, `worker_timeout`, `unscopable_diff`-with-declared-writes semantics.
- The multi-repo split logic at 959-1009 beyond leaving it flag-gated.
- De-duplicating `.claude/scripts/tests/` copies (separate open thread).
- Any commit, push, or merge — branch work only.

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      For a single-repo dispatch with LEADV2_REVIEW_DIFF_CROSS_REPO unset or 0 whose lane
      worktree holds uncommitted work, the dispatch journal shows a review_diff line with a
      non-zero bytes= count, and shows no "terminal=no_work cause=empty_diff" line for that task.
    authored_at: 2026-08-04T09:50:11Z
  - surface: file_artifact
    observable: >
      docs/handoff/<task>/review.diff for that same dispatch is a non-empty file containing the
      lane's changed hunks, and review.diff.repos lists the repo with a byte count greater than 0.
    authored_at: 2026-08-04T09:50:11Z
  - surface: log_line
    observable: >
      For a dispatch whose lane worktree is dirty only outside the declared write set, the journal
      shows "review_gate ... reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work"
      instead of a no_work line.
    authored_at: 2026-08-04T09:50:11Z
  - surface: file_artifact
    observable: >
      docs/handoff/<task>/review-gate.md for a genuinely empty lane still reads
      "status: blocked" with "reason: no_work" — the fix does not turn an idle worker into a pass.
    authored_at: 2026-08-04T09:50:11Z
  - surface: rendered_line
    observable: >
      The run-core-offline test-suite output prints a passing line for the new "lane diff
      single-repo" check and a passing line for "review body persist", with no FAIL lines.
    authored_at: 2026-08-04T09:50:11Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
