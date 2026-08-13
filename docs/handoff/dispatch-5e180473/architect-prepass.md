# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — architect prepass, fix round 2

## 0. Headline

**The three "regressed" suites are not a regression in `a8abb02`. They are a stale lane
base.** The lane worktree `6bbcca99` was branched before `1a23a4a chore(agents): add a
developer role to the plugin repo`, so `.claude/agents/developer.md` does not exist in that
checkout. `leadv2-dispatch-code.sh:1808` spawns every build worker with a hardcoded
`--role developer`; with the role file absent the launcher exits non-zero, dispatch rolls
back all arms, and the worker never runs.

That failure mode produces exactly the symptom set in the mission — verbatim.

The mission's stated hypothesis ("something in your lane-root resolution now returns an
empty string") is **wrong**, and implementing against it would mean adding a fallback to
code that is not broken.

## 1. Evidence

| Check | Command | Result |
|---|---|---|
| Lane base ancestry | `git merge-base --is-ancestor 1a23a4a a8abb02` | **NO** |
| Main ancestry in lane | `git merge-base --is-ancestor 0b22f89 a8abb02` | **NO** |
| Commits on main missing from lane | `git log a8abb02..0b22f89` | `0b22f89`, **`1a23a4a`** |
| Role file in lane tree | `git ls-tree -r a8abb02 \| grep agents/developer` | *(empty)* |
| Role file on main tree | `git ls-tree -r 0b22f89 \| grep agents/developer` | `.claude/agents/developer.md` |
| Lane working tree clean? | `git -C .claude/worktrees/6bbcca99 status --porcelain` | only `?? docs/handoff/dispatch-6bbcca99/` — the committed diff *is* `a8abb02`, nothing uncommitted |

`1a23a4a`'s own commit message names the failure verbatim:

> Dispatching code work from inside ~/Projects/leadv2 failed with
> 'role file not found in agents/ or roles/: developer' — the repo carried only
> architect/critic/security-auditor (all symlinks into agents-shared).

Observed live while investigating (running a dispatch-driving suite against a fixture):

```
[leadv2-dispatch-code] spawn_failed by=router model=sonnet task=0aa7889a rc=1 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(sonnet) failed rc=1:  [claude-subsession] role file not found in agents/ or roles/: developer
[leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable task=0aa7889a attempts=sonnet_failed_launcher
```

### 1a. Symptom-to-cause mapping (each mission assertion explained)

| Mission assertion | Explained by missing `developer.md` |
|---|---|
| `T-a/P-a: dispatch exited 4 (expected 0)` | `all_arms_unavailable` after `dispatch_rolled_back` — 4 is the all-arms-declined exit, not a close-gate code |
| `P-a/P-b/P-g: worker cwd='' != RESUME=...` | The worker was never spawned, so nothing ever recorded a cwd. Empty ≠ "lane-root resolution returned empty" |
| `P-h(a/b/g): prompt pin line MISSING` | The prompt is written by the launcher at spawn; spawn aborted before writing it |
| `P-h(g2): pin line does NOT name the worktree (expected '')` | Same — no prompt file at all |
| `T-a: TARGET terminal ledger has 0` | Rolled-back dispatch writes no terminal row |
| `T-a: reservation row is NOT confirmed` | Reservation is confirmed on successful spawn; rollback releases it |

Every one is downstream of "no worker was spawned". None requires `_lane_root` to be empty.

### 1b. Why the three baselines differ the way they do

| Where | HEAD | has `developer.md` | Result |
|---|---|---|---|
| clean `main` | `0b22f89` | yes | 34 / 0 |
| worktree of `main` | `0b22f89` | yes | 33 / 1 (codex lockout only) |
| lane `6bbcca99` | `a8abb02` | **no** | 30 / 4 |

The delta between the two green runs and the lane is one commit, and that commit is the
role file. The `a8abb02` source change (`leadv2-dispatch-product-close.sh`) is not on the
code path any of the three suites fail on — `dispatch refusal fallback chain` is registered
at `run-core-offline.sh:86`, *before* the new suite at line 88, so test-ordering pollution
from `test-lane-diff-single-repo.sh` is also excluded.

### 1c. What was audited and found NOT guilty

- `leadv2-lane-worktree.sh cmd_path_of` is strictly read-only (`-d` test + `worktree list`
  + `printf`). It has no side effect on the lane registry, so calling it unconditionally
  cannot perturb placement for a later dispatch.
- The removed `if [[ "${CROSS_REPO_DIFF}" == "1" ]]` wrapper only ever guarded `diff_root`
  assignment inside `leadv2-dispatch-product-close.sh`. `diff_root` is local to the close
  gate; it is never exported and never reaches `--cwd`.
- The new `_pc_lane_dirty` / `unscoped_lane_work` branch runs only inside the
  `blocked_reason` arm and exits 5, not 4.

## 2. Scope of the implementation

### Primary change — one line of git history, no source edit

Bring the lane up to the current `main` so the lane checkout contains
`.claude/agents/developer.md`, then re-measure.

- Merge `main` into `worktree-6bbcca99` (or rebase `a8abb02` onto `0b22f89`). Merge is
  preferred: the two commits on `main` touch files (`.claude/agents/developer.md`,
  open-threads capture) disjoint from `a8abb02`'s three files, so it is a trivially clean
  merge and preserves the reviewed `a8abb02` SHA in history.
- Do **not** cherry-pick `1a23a4a` alone. That leaves the lane still behind `main` and the
  same class of stale-base failure recurs on the next suite that lands on `main`.

### Contingency — only if suites still fail after the base refresh

Re-run `run-core-offline.sh` from inside the lane *first*. Only if one of the three suites
still fails does the mission's original hypothesis become live. In that case:

- Instrument, do not patch blind. Capture the actual `--cwd` value handed to the launcher
  in the failing fixture (`leadv2-dispatch-code.sh` around the spawn call) and the
  `_lane_root` value the close gate resolved, and report both before changing behaviour.
- Any fallback added must preserve `a8abb02`'s target fix: when `LEADV2_LANE_WORK_ROOT` is
  set and is a directory, it wins unconditionally — that is the whole mission.

### Non-goals (explicit — the implementing agent ignores these)

1. **Do not touch** `test-routing-enforcement-p1.sh`, `test-landed-at-spawn.sh`, or
   `test-lane-placement-pin.sh`. Their assertions are correct; they were describing a real
   absence, just not the one the mission attributed it to.
2. **Do not revert** any part of `a8abb02`. The `CROSS_REPO_DIFF` de-gating, `_pc_lane_dirty`,
   the `unscoped_lane_work` terminal, and `test-lane-diff-single-repo.sh` all stay.
3. **Do not attempt** `product-close waits for worker exit`. Environmental: codex quota
   lockout until 2026-08-08 (`~/.claude/cache/codex-lockout.state`).
4. **Do not** add a `developer.md` copy inside the lane by hand. Global CLAUDE.md
   shared-trees policy: the file already exists on `main`; it arrives by merge, not by copy.
5. No commit to `main`, no push, no merge *of the lane into main*. Branch-only.
6. Do not add a lane-root fallback speculatively "to be safe". If the base refresh turns the
   suite green, there is nothing to fall back from, and a defensive branch there would
   silently re-introduce the exact wrong-tree diffing `a8abb02` fixed.

## 3. Risks

| Risk | Mitigation |
|---|---|
| Merge conflict on `run-core-offline.sh` if `main` also registered a suite | Both commits on `main` are disjoint from the three lane files; if a conflict appears, keep **both** registration lines — never drop one to resolve |
| Base refresh fixes only 2 of 3 suites, and the third is a genuine `a8abb02` regression | Re-run and read the tail before concluding. Contingency section above governs; report the surviving failure with its verbatim assertion rather than patching toward green |
| Suites are order-dependent and the lane's new suite still perturbs a later one | `dispatch refusal fallback chain` is registered *before* the new suite, so it cannot be pollution; if only `landed-at-spawn`/`lane placement pin` (lines 110–111, after 88) survive, re-run each standalone to separate pollution from a real defect |
| A standalone suite run disagrees with `run-core-offline.sh` | `run-core-offline.sh` is authoritative — it exports the `LEADV2_*` fixture env the suites assume. Direct invocation is diagnostic only, never evidence of pass/fail |
| Someone "fixes" the empty-cwd symptom directly | Non-goal 6. The cwd is empty because no worker ran; defaulting it would make a rolled-back dispatch look placed |

## 4. Constraint checklist

1. **Env var naming** — no new env vars introduced. Existing referenced names
   (`LEADV2_LANE_WORK_ROOT`, `LEADV2_PROJECT_ROOT`, `LEADV2_WORKTREE_DIR`,
   `LEADV2_REVIEW_DIFF_CROSS_REPO`) all carry the `LEADV2_` prefix. No `LEAD_V2_*` drift.
2. **File paths** — `.claude/agents/developer.md` exists on `main` (`0b22f89`), absent in
   the lane tree (`a8abb02`); it is what the merge delivers.
   `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`,
   `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
   `plugins/leadv2/scripts/leadv2-lane-worktree.sh`,
   `plugins/leadv2/scripts/tests/run-core-offline.sh` all exist on disk. Verified.
3. **`claude -p` commands** — none introduced by this plan.
4. **Concurrent access** — the lane worktree and `main` share one object store. The merge
   writes only the lane's branch ref and worktree; nothing else in this plan writes to a
   file another step reads. `run-core-offline.sh` fixtures are per-run tmpdirs.
5. **Config contradiction** — `CROSS_REPO_DIFF` semantics changed in `a8abb02` (it no longer
   gates `diff_root`, only the multi-repo grouping branch). That change is being kept, and
   this plan adds no further semantic change to it.
6. **bash 3.2** — no new shell constructs proposed; the merge introduces none.

## 5. Acceptance

```
acceptance:
  - surface: log_line
    observable: >
      Running plugins/leadv2/scripts/tests/run-core-offline.sh from inside the lane
      worktree prints a final tally line reading 33 passed / 1 failed, and the single
      FAIL line names "product-close waits for worker exit".
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: log_line
    observable: >
      In that same run the line for "product-close scopes a single-repo lane worktree"
      reads PASS, and the line for "review body persist" reads PASS — no
      "review_diff repo=<sig8> bytes=0 base=HEAD" appears anywhere in the output.
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: log_line
    observable: >
      In that same run the lines for "dispatch refusal fallback chain",
      "landed-at-spawn (no terminal=landed at spawn; target repo keying)" and
      "lane placement pin (--resume-lane/--worktree)" each read PASS, and no
      "role file not found in agents/ or roles/: developer" text appears in the output.
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: file_artifact
    observable: >
      .claude/agents/developer.md is present in the lane worktree checkout, and
      `git log --oneline` inside the lane shows both a8abb02 and 1a23a4a in its history.
    authored_at: 2026-08-04T00:00:00+03:00
```

Note on the primary path: if it holds, the implementing agent writes **no source file at
all** — the deliverable is a merge plus the pasted suite tail. The `LANE_WRITES` line below
covers the contingency path so the lane is not blocked from writing if the base refresh
proves insufficient.

LANE_WRITES: .claude/agents/developer.md, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh

DELIVERABLE_COMPLETE
