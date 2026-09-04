# V3-STOP-GATE-01 — architect prepass (design only, no implementation)

Repo: `~/Projects/leadv2` (canonical plugin repo). No `context.yaml` exists for this
task id (`ls` returned nothing) — mission text is therefore the sole contract; its
`Off_limits` list is treated as binding.

## 0. Verified anchors (all line numbers from the live tree, read this run)

| Anchor | File:line | What it is |
|---|---|---|
| `emit()` | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:221` | journal append helper, `emit decision "<text>"`; no vocabulary allowlist gates the text (grep for `selfcheck task=` in `leadv2-dispatch-ledger.sh` / `tests/test-arm-ladder-vocabulary-drift.sh` returned nothing) |
| `CACHE_BASE` | `…product-close.sh:131` | `${LEADV2_DISPATCH_CACHE_DIR:-$HOME/.claude/cache}` |
| `WRITES_CSV` | `…product-close.sh:31` | top-level, `${LEADV2_DISPATCH_LANE_WRITES:-}` — the declared write-set, available before any function call |
| `_pc_lane_dirty()` | `…product-close.sh:1133` | `git status --porcelain -uall`, minus `docs/leadv2/` + `docs/handoff/` |
| `_pc_diff_base()` | `…product-close.sh:1456` | start-sha → `origin/main` merge-base resolver; empty stdout ⇒ caller uses HEAD |
| `_pc_repo_diff()` | `…product-close.sh:1483` | never-smaller guard: keeps `max(len(diff HEAD), len(diff start-sha))` |
| `pc_scope_diff()` body start | `…product-close.sh:1389` | `writes=()` normalization at `:1503`; `_pc_norm_write` is **defined inside this function**, so it is NOT callable before `:1811` |
| `pc_await_worker_exit()` | `…product-close.sh:1056`; called `:1758` and `:1780` (DWR second wait) | worker-exit detection |
| post-wait `_lane_root` re-resolve | `…product-close.sh:1796-1799` | idempotent copy of pc_scope_diff's resolution |
| `pc_scope_diff` invocation | `…product-close.sh:1811` | first point the diff exists |
| selfcheck gate (guard idiom) | `…product-close.sh:1843` / `:1850` | `[[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]]` |
| selfcheck mission paragraph | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:4199-4221` | guarded preamble block; appended AFTER the dedup sig is computed |
| suite registry | `plugins/leadv2/scripts/tests/run-core-offline.sh:224` | `"<label>|||bash $TEST_DIR/test-<name>.sh"` |

## 1. Insertion point — and why it is exactly there

**Insert a new top-level function `pc_stop_gate_autocommit`, and call it on the line
immediately before `pc_scope_diff` (currently `…product-close.sh:1811`).**

This is after both `pc_await_worker_exit` call sites (`:1758` bare, `:1780` DWR resume)
and after the post-wait `_lane_root` re-resolution at `:1796-1799`, so `_lane_root` is
already resolved by existing code and the gate adds no new resolution logic. It is
before `pc_scope_diff`, so the review diff, the e2e phase, the selfcheck gate and the
`unscoped_lane_work` classifier all observe a **committed** tree — which is the whole
point of the mission ("review phase sees a committed tree").

Not inside `pc_await_worker_exit`: that function is entered twice (DWR resume) and a
commit after the first exit would checkpoint a half-written tree while the resumed
worker is still editing. One call, one commit, after the last wait returns.

## 2. Design

### 2.1 Kill switch
`LEADV2_STOP_GATE` — default `1`. The entire call site is wrapped:

```
if [[ "${LEADV2_STOP_GATE:-1}" != 0 ]]; then pc_stop_gate_autocommit; fi
```

Same idiom and same default as `LEADV2_BUILDER_SELFCHECK` (`:1843`). `=0` restores
today's path byte-for-byte in **both** files (gate + mission preamble), matching mission
item 3. Naming complies with the `LEADV2_*` convention (checked against the existing
`LEADV2_BUILDER_SELFCHECK`, `LEADV2_LANE_SHAPE`, `LEADV2_PC_*` family in the same
scripts); no `LEAD_V2_*` variant exists anywhere in these files.

### 2.2 Algorithm (`pc_stop_gate_autocommit`, top-level, ~55 lines)

1. **Preconditions — skip silently (journal a `status=skipped reason=<x>` line) when:**
   - `_lane_root` empty / not a directory → `reason=no_lane_root` (main-checkout lanes
     are never auto-committed; founder edits live there).
   - not a git work tree → `reason=not_a_worktree`.
   - `WRITES_CSV` empty → `reason=no_declared_writes` (nothing scoped to commit).
   - `git symbolic-ref -q HEAD` fails → `reason=detached_head` (a commit would dangle).
   - report-only lane (`_pc_report_rel`/report mode already detected upstream at
     `:1594`) → `reason=report_lane`, mirroring the selfcheck gate's own
     `reason=report_lane` skip at `:1846`.
2. **Diff-base pre-flight (the load-bearing safety step — see Risk R1).** Resolve a
   base the way `_pc_diff_base` will: `${LEADV2_LANE_START_SHA:-}` → else
   `${CACHE_BASE}/dispatch-${TASK}.start-sha` → else `origin/main` merge-base.
   - If none resolves, write the current `git rev-parse HEAD` of the lane worktree to
     `${CACHE_BASE}/dispatch-${TASK}.start-sha` **only if that file does not already
     exist** (never overwrite — overwriting an older start sha would shrink a
     legitimate diff).
   - If a base *still* cannot resolve after that (e.g. `CACHE_BASE` unwritable), **do
     not commit**: journal `status=skipped reason=no_diff_base` and return. Committing
     without a resolvable base would turn visible work into an invisible empty diff.
3. **Stage only the declared write-set.** For each CSV entry (trim whitespace, strip a
   leading `./` and a trailing `/`; do *not* call `_pc_norm_write` — it is scoped inside
   `pc_scope_diff` and not yet defined):
   `git -C "$_lane_root" add -A -- "<entry>" ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null || true`
   Per-entry, tolerating failure, so a declared-but-absent path (`pathspec did not
   match`) cannot abort the gate. `-A` picks up modifications, additions **and**
   deletions. Git pathspec semantics cover both literal paths and the glob forms lanes
   declare. Everything outside the write-set is left unstaged → mission item (b)
   satisfied by construction, and `unscoped_lane_work` keeps seeing it.
4. **Commit iff something staged.** `git diff --cached --quiet` → rc0 means nothing;
   return with `status=noop`. Otherwise:
   `git -c user.name=… -c user.email=… commit --no-verify -m "wip(<TASK>): auto-checkpoint on worker exit (STOP-GATE)"`
   - `--no-verify` is **required**: this repo enforces a close-ritual pre-commit hook
     (standing decision "Enforce close ritual completion on git commit"); a wip
     checkpoint has no close ritual and would be rejected.
   - Explicit `-c user.name/user.email` makes the commit hermetic under a test harness
     with no configured identity.
5. **Journal.** `emit decision "stop_gate_autocommit task=${TASK} files=${n} sha=${short}"`,
   where `n` = `git diff --cached --name-only | wc -l` captured **before** the commit.
   On the skip/noop paths: `stop_gate_autocommit task=${TASK} status=skipped reason=<x>`
   / `status=noop`. Exactly the `stop_gate_autocommit task=<sig> files=<n>` shape the
   mission names, extended with the sha (free diagnosability, no parser depends on the
   line).
6. **Never fail the lane.** Every git invocation is `|| true`; the function always
   returns 0. A stop-gate fault must never convert a good lane into a blocked one.

### 2.3 Mission preamble (`leadv2-dispatch-code.sh`)

Immediately after the closing `fi` of the selfcheck paragraph block (`:4221`), a
structurally identical block:

```
if [[ "${LEADV2_STOP_GATE:-1}" != 0 ]]; then
  mission="${mission}
<one paragraph>"
fi
```

Paragraph content (intent, not exact keystrokes): commit your work on the lane branch
before ending your session; an uncommitted exit is treated as an incident — the gate
will checkpoint for you, but a checkpoint commit is an incident record, not a
deliverable. Same placement rule as the selfcheck block: **after** the dedup signature
is computed, so lane dedup identity is unchanged. The routing block below is untouched
(off_limits honoured).

## 3. Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | new top-level `pc_stop_gate_autocommit()` (place near `_pc_lane_dirty`, `:1133-1142`, so it is defined well before use) + guarded call immediately above `pc_scope_diff` (`:1811`) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | one guarded mission-preamble paragraph after `:4221` |
| `plugins/leadv2/scripts/tests/test-stop-gate.sh` | **(to-create)** red-first suite, legs (a)(b)(c) below |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | one registry row next to `:224` |

## 4. Test design — `tests/test-stop-gate.sh`

Offline, hermetic: build a throwaway git repo in `$(mktemp -d)` as the fake lane
worktree, set `LEADV2_LANE_WORK_ROOT`, `LEADV2_DISPATCH_LANE_WRITES`,
`LEADV2_DISPATCH_CACHE_DIR`, `LEADV2_LANE_START_SHA`; `source` product-close.sh with a
guard, or (preferred, matching the sibling suites' style) drive the function through a
small harness that stubs `emit` to append to a temp journal file. No network, no real
dispatch.

- **(a) happy path** — lane worktree has a modified tracked file *and* an untracked file,
  both inside the declared write-set. Assert: `git log -1 --format=%s` on the lane
  branch is `wip(<task>): auto-checkpoint on worker exit (STOP-GATE)`; the journal
  contains `stop_gate_autocommit task=<task> files=2`; `git status --porcelain` for
  those paths is empty afterwards (the review phase would see a clean, committed tree).
- **(b) junk outside the write-set** — add `junk/scratch.txt` (undeclared) alongside one
  declared change. Assert the commit's `--name-only` list contains the declared path and
  **not** `junk/scratch.txt`, and that `junk/scratch.txt` is still untracked afterwards
  (so `unscoped_lane_work` can still fire on it).
- **(c) `LEADV2_STOP_GATE=0`** — same fixture as (a). Assert: no new commit
  (`git rev-parse HEAD` unchanged), tree still dirty, journal has zero
  `stop_gate_autocommit` lines.
- **(d, recommended, guards R1)** — no start sha, no cache file, no `origin/main`:
  assert either that a start-sha file was written (base now resolvable) or that the
  journal says `status=skipped reason=no_diff_base` and no commit happened.

Red-first: each leg must be shown failing against the unmodified scripts before the
implementation lands (legs (a)(b)(d) fail on "function not found"; leg (c) passes
trivially pre-change and is the byte-for-byte-rollback witness).

Registration: one row in `run-core-offline.sh` beside `:224`, form
`"stop gate (auto-checkpoint on worker exit, write-set scoping, kill switch)|||bash $TEST_DIR/test-stop-gate.sh"`.

## 5. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **Committing makes the work invisible.** `_pc_repo_diff` (`:1483`) keeps `max(diff HEAD, diff start-sha)`. Once the gate commits, `diff HEAD` is empty; if no start sha and no `origin/main` merge-base resolve, `_pc_diff_base` returns empty and the lane collapses to `no_work`/`empty_diff` — the gate would *cause* the exact loss it exists to prevent. **This is the single highest-severity risk in the change.** | Step 2 above: resolve-or-seed the base *before* committing; refuse to commit when no base resolves. Test leg (d) locks it. |
| R2 | Overwriting an existing `dispatch-<TASK>.start-sha` would shrink a legitimate diff | Seed the file only when absent; never overwrite. |
| R3 | Pre-commit hook (close-ritual enforcement) rejects the wip commit → gate silently noops | `--no-verify`; leg (a) run inside a fixture that installs a rejecting `pre-commit` hook proves it. |
| R4 | Detached HEAD in the lane worktree → dangling commit, work still invisible | `symbolic-ref -q HEAD` precondition; skip with `reason=detached_head`. |
| R5 | Double-commit across the DWR resume path | Single call site after the last `pc_await_worker_exit`, never inside it. |
| R6 | A declared path that does not exist aborts `git add` under `set -e` | Per-entry `git add … || true`; function always returns 0. |
| R7 | Concurrent writer in the same worktree | Lane worktrees are per-task (standing decision: per-task worktree isolation), so single-writer. No new lock. The gate runs after the worker has exited, so worker/gate interleaving is impossible by ordering; documented in a comment rather than defended with a lock. |
| R8 | `docs/leadv2` / `docs/handoff` churn gets committed | `:(exclude)` pathspecs on every `git add`, matching `_pc_lane_dirty`'s exclusion set (`:1138`) and `_pc_git_diff`'s (`:1441`). |
| R9 | Journal vocabulary drift check rejects a new decision word | Verified: no allowlist gates `emit decision` text (grep of `leadv2-dispatch-ledger.sh` and `tests/test-arm-ladder-vocabulary-drift.sh` for `selfcheck task=` found no vocabulary table). Implementer should re-confirm if `test-arm-ladder-vocabulary-drift.sh` goes red. |
| R10 | Cross-repo lanes: work landed in a sibling repo, not the lane worktree | Explicit non-goal (§6). `cross_repo_elsewhere` already classifies it (`:1704`). |

Constraint checklist: env naming ✅ (`LEADV2_STOP_GATE`, no `LEAD_V2_*` drift, no
conflicting existing usage — grep of both scripts shows the name is unused today);
paths ✅ (all four exist except `tests/test-stop-gate.sh`, marked *(to-create)*);
`claude -p` ✅ (n/a — this change introduces no `claude -p` invocation); concurrent
access ✅ (R7); config contradiction ✅ (new name, no prior semantics).

## 6. Non-goals / out of scope

- Committing anything **outside** the declared write-set (that stays
  `unscoped_lane_work`'s job — mission item 1 says so explicitly).
- Pushing, merging, rebasing, or fast-forwarding the lane branch. Checkpoint commit only.
- Cross-repo sibling checkouts (R10).
- The main checkout — the gate never commits when no lane worktree resolves.
- Any change to `pc_scope_diff`'s classifier, the `unscoped_lane_work` /
  `declared_no_bytes` / `empty_diff` verdict paths, `_pc_diff_base`'s own logic, the
  selfcheck gate internals (`lib/leadv2-builder-selfcheck.sh` — off_limits), `supervise*`
  (off_limits), or the routing block of `leadv2-dispatch-code.sh` (off_limits).
- Making an uncommitted exit *blocking*. The gate repairs; it does not refuse.

acceptance:
  - surface: log_line
    observable: "In the lane's dispatch journal, a line reading `stop_gate_autocommit task=<sig> files=2` appears between the worker's exit and the review-gate line, where before there was no such line."
    authored_at: 2026-08-20T08:52:00Z
  - surface: file_artifact
    observable: "`git log --oneline -1` on the lane branch of the lane worktree shows a commit titled `wip(<task>): auto-checkpoint on worker exit (STOP-GATE)`, and `git status` in that worktree lists no modified or untracked files under the declared write-set — whereas the same worktree previously ended the run dirty."
    authored_at: 2026-08-20T08:52:00Z
  - surface: file_artifact
    observable: "After the same run, `git status` in the lane worktree still lists the undeclared file `junk/scratch.txt` as untracked, and it is absent from the checkpoint commit's file list."
    authored_at: 2026-08-20T08:52:00Z
  - surface: log_line
    observable: "With LEADV2_STOP_GATE=0 the run's journal contains no `stop_gate_autocommit` line at all, the lane branch tip is the same commit it was before the run, and the worker's mission text shown in the run directory has no commit-before-exit paragraph."
    authored_at: 2026-08-20T08:52:00Z
  - surface: rendered_line
    observable: "`bash tests/run-core-offline.sh` prints a green PASS row labelled `stop gate (auto-checkpoint on worker exit, write-set scoping, kill switch)` in its suite list."
    authored_at: 2026-08-20T08:52:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-stop-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
