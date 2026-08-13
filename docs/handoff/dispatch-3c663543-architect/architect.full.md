# LANDED-AT-SPAWN-01 — architect prepass (scoped design)

## Verified facts (this main)

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2513` — `[[ "${product_class}" != "product" ]] && _dl_note "${sig8}" landed "spawned_${candidate}" "" "${founder_task_id}"`, inside the `0)` (spawn succeeded) branch of the arm loop, immediately before `_DISPATCH_WORKER_LIVE=1`.
- There is **no synchronous arm on this path**. Every arm that reaches rc=0 here spawned an async background worker (`_DISPATCH_WORKER_LIVE=1` is set unconditionally right after, and the lane worktree is deliberately NOT reaped). The `opus` arm never spawns — it parks earlier at :2352. Therefore requirement 1's "gate on evidence of completion" branch has **no live case**: the correct action is deletion, not gating.
- `_dl_note` (dispatch-code.sh:482) shells out to `LEDGER_BIN` (`leadv2-dispatch-ledger.sh`) with **no PROJECT_ROOT threaded**. The child resolves `PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel || pwd)}}"` (ledger:83) from the **inherited caller-session env** → `dispatch_terminal_ledger_file()` (ledger:116) passes that to `leadv2-state-path.sh`, which slugs by `basename(dirname(git-common-dir))`. A persona-engine session dispatching into a leadv2 lane writes leadv2 terminals under `~/.claude/leadv2-state/persona-engine/`. Matches both reproductions.
- The reservation ledger is a **second, separately-keyed** file: dispatch-code's own `dispatch_ledger_file()` (:416) = `${CACHE_BASE}/dispatch-ledger/$(repo_slug).jsonl`, where dispatch-code's `repo_slug()` is basename of its **own** `PROJECT_ROOT` (:260, sourced from `CLAUDE_PROJECT_ROOT|CLAUDE_PROJECT_DIR|PROJECT_ROOT` — caller session again). Same defect class; reserve/confirm/abort and `dispatch_lock_file` (:639) all inherit it.
- `WORK_ROOT` (:267–269) is the lane worktree (`LEADV2_LANE_WORK_ROOT`), falling back to `PROJECT_ROOT`. It is the only variable on this path that reliably points at the dispatch **target**.
- Tests live at `plugins/leadv2/scripts/tests/` (NOT `plugins/leadv2/tests/` as the mission states). `test-no-work-terminal.sh` is registered in `run-core-offline.sh:54`.

## Changes (exact)

### C1 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh` :2513
Delete the line. Replace the surrounding comment with the honest rule: *a non-product spawn has no terminal at spawn time; absence of a terminal row IS the state until the lane's own close/sweep path resolves it.* The already-written **confirmed reservation** row (`dispatch_confirm`, reservation ledger) remains the only spawn-time record — no new row type, no schema change. `dispatch_ledger_sweep_write_dead` (ledger:282) already exists to resolve abandoned lanes, so the honest absence is recoverable.

### C2 — `leadv2-dispatch-code.sh`, new global `LEDGER_REPO_ROOT` (insert after :269)

```
# Ledger keying follows the DISPATCH TARGET (the main checkout that owns the lane
# worktree), never the caller session's env. LANDED-AT-SPAWN-01.
LEDGER_REPO_ROOT="$(cd "${WORK_ROOT}" 2>/dev/null && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd)"
[[ -n "${LEDGER_REPO_ROOT}" && -d "${LEDGER_REPO_ROOT}" ]] || LEDGER_REPO_ROOT="${PROJECT_ROOT}"
```

The `cd` must happen **inside** `WORK_ROOT`, because `--git-common-dir` returns a path relative to cwd (`.git`) for an ordinary checkout and an absolute path for a linked worktree — resolving it from anywhere else silently yields the wrong root. bash 3.2 safe (no assoc arrays, no `<<<`, no `${var@}`).

### C3 — `_dl_note` (:482) threads it

```
PROJECT_ROOT="${LEDGER_REPO_ROOT}" LEADV2_PROJECT_ROOT="${LEDGER_REPO_ROOT}" \
  bash "${LEDGER_BIN}" write-terminal ... 9>&- || true
```

Both names, because ledger:83 prefers `PROJECT_ROOT` while other leadv2 callers key off `LEADV2_PROJECT_ROOT`. **No change to `leadv2-state-path.sh` or `leadv2-dispatch-ledger.sh`** — both already honour `PROJECT_ROOT`; the defect is purely that dispatch-code never passed it. Requirement 2's "do not change state-path semantics for other callers" is satisfied by construction.

### C4 — reserve/confirm uniformity, `repo_slug()` (dispatch-code, :~410 region)
`dispatch_ledger_file` / `review_ledger_file` / `dispatch_lock_file` all key off dispatch-code's `repo_slug()`. Change **only `repo_slug()`** to slug `LEDGER_REPO_ROOT` instead of `PROJECT_ROOT`. One edit covers reserve, confirm, abort, review-dedup and the dispatch lock — requirement 2's "uniformly", with zero callsite churn.

### C5 — sibling audit (requirement 3); report-only unless a second future-claim turns up

| line | terminal | true at write time? |
|---|---|---|
| 2169 | parked no_design_after_N_attempts | yes — prepass exhausted, no spawn |
| 2249 / 2253 | refused not_shape_eligible / diagnostic_mission_missing_evidence | yes — pre-spawn classification |
| 2257 | dead lane_shape_classify_failed | yes |
| 2292 | dead router_v2_unavailable | yes |
| 2341 | dead ledger_record_failed | yes |
| 2352 | parked resolved_opus_lead_judgment | yes — opus arm never spawns |
| 2363 / 2410 / 2441 | refused all_arms_exhausted / quota / excluded | yes — pre-spawn |
| **2513** | **landed spawned_&lt;arm&gt;** | **NO — future claim. C1.** |
| 2584 / 2593 / 2598 / 2603 | dead rollback_failed / reservation_failed / lock_timeout / unexpected_rc | yes — post-failure |
| 2616 | dead all_arms_unavailable | yes |
| 2330 / 2479 | duplicate-sig paths — deliberately write **no** row | correct, keep |

Implementer re-runs `grep -n '_dl_note' leadv2-dispatch-code.sh` on the branch and reproduces this table in the build report. Only :2513 is expected to change.

### C6 — tests: new suite `plugins/leadv2/scripts/tests/test-landed-at-spawn.sh`
New file (not an extension of `test-no-work-terminal.sh` — that suite's fixtures are product-close-shaped). Sandbox: two git fixture repos (`target/` with a linked lane worktree, `decoy/`), `LEADV2_STATE_BASE` + `LEADV2_DISPATCH_CACHE_DIR` pointed into the sandbox, stub worker/router binaries, and the decoy wired in as the caller session: `CLAUDE_PROJECT_DIR=$decoy`, `PROJECT_ROOT=$decoy`, `LEADV2_LANE_WORK_ROOT=$target_worktree`.

- **T-a** non-product async spawn → zero lines matching `"terminal":"landed"` in **either** repo's `dispatch-ledger.jsonl`; the reservation ledger DOES carry a confirmed row for the sig.
- **T-b** a genuine pre-spawn refusal → terminal row lands under the **target** slug's state dir; decoy's state dir has no such row.
- **T-c** regression: pre-spawn refused/parked still write at all (non-empty terminal file, correct `terminal`/`cause`).
- **T-d** decoy state dir holds **no** `dispatch-ledger.jsonl` line for this sig at all — proves the leak is closed, not merely duplicated.

Register next to `run-core-offline.sh:54`. Record the pre-change `run-core-offline.sh` PASS/total on THIS main **before** editing, and compare after.

## Non-goals (explicit)

- No change to write-once semantics, `dispatch_ledger_write_terminal`'s validation, or the row schema.
- No new terminal or reservation row **type**; no `no_work`-style new state.
- No changes to `leadv2-state-path.sh`, `leadv2-dispatch-product-close.sh`, supervisor, fanout, or `leadv2-codex-lead.sh` (its dup-guard is fixed transitively by the absent landed row — do not touch it).
- No purge/migration of existing mis-keyed rows (already hand-purged by the founder).
- No commit.

## Risks

| risk | mitigation |
|---|---|
| C4 changes the **reservation** ledger's slug → reservations made under the old (caller-session) slug become invisible; a retry of a still-live task could double-dispatch | dispatch is manually serialized today and both repro tasks are dead; land during a quiet window. Implementer states it in the report — do NOT add a compat dual-read (scope creep, and it would re-open the dedup ambiguity). |
| A non-product lane now has NO terminal ever if nothing else closes it → the widget shows the lane indefinitely | that is the intended honest state; `sweep` / `dispatch_ledger_sweep_write_dead` already resolve abandoned lanes by liveness. Implementer verifies sweep still fires for a non-product lane; if it does not, that is a **separate** task, not scope here. |
| `git rev-parse --git-common-dir` on a non-repo or deleted `WORK_ROOT` | guarded fallback to `PROJECT_ROOT` (C2). |
| bash 3.2 (`/bin/bash`) compatibility | nothing bash4+ added; `bash -n` under bash5 **and** `/bin/bash` is in acceptance. |

## acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: "After a non-product dispatch spawns a background worker, ~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl contains no line whose terminal reads landed with cause spawned_<arm> for that task's sig8 — the task has no terminal row at all while its worker is still running."
    authored_at: "2026-08-03T16:05:34Z"
  - surface: file_artifact
    observable: "When a dispatch is launched from a session whose CLAUDE_PROJECT_DIR points at persona-engine but whose lane worktree belongs to leadv2, the terminal row appears in leadv2's dispatch-ledger.jsonl and persona-engine's dispatch-ledger.jsonl gains no new line for that task."
    authored_at: "2026-08-03T16:05:34Z"
  - surface: rendered_line
    observable: "run-core-offline.sh prints a PASS line for the new landed-at-spawn suite, and its final PASS/total tally is no lower than the tally recorded on unmodified main."
    authored_at: "2026-08-03T16:05:34Z"
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-landed-at-spawn.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
