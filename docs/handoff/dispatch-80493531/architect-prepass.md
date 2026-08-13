# PLACEMENT-PIN-DEFAULT-01 — architect prepass

## Root cause (confirmed by read, not inferred)

`WORKTREE_PIN_LINE` is assigned in exactly ONE place: `leadv2-dispatch-code.sh:576`, inside
`_resolve_pinned_placement()` Step 6 — which returns early at line 491 unless
`--resume-lane`/`--worktree` was passed. It is consumed in exactly ONE place:
`_spawn_worker_body()` line 1707 (`mission="${WORKTREE_PIN_LINE}"$'\n\n'"${mission}"`),
which already covers all four arms (glm/kimi/sonnet/codex) and already runs AFTER
compute_sig/classify/router, so prepending never perturbs sig8/dedup/routing.

So the consumption side is correct and complete. Only the *assignment* side is
flag-gated. Two default-path branches leave `WORK_ROOT != PROJECT_ROOT` with no pin:

| # | Branch | Where | Pinned today |
|---|--------|-------|--------------|
| A | ensure-created lane worktree | `2272–2279` (`WORK_ROOT="${_lane_dir}"`) | ❌ no |
| B | launcher pre-exported `LEADV2_LANE_WORK_ROOT` | `267–269`; the `if` at 2269 is then FALSE and the whole ensure block is skipped | ❌ no |
| C | `--resume-lane` / `--worktree` | `573–576` | ✅ yes |
| D | shared tree (`WORK_ROOT == PROJECT_ROOT`) | ensure fallback `2274–2275` | ✅ correctly none |

Branch B matters: the fanout launcher `ensure`s the tree and exports it, so the four
Aug 3–4 drift reproductions ran through B or A — never through C. A fix that only
patches the `2272` assignment would leave B unpinned. **The fix must be placed after the
whole `PLACEMENT_PINNED` guard closes (line 2282), keyed on the final value of
`WORK_ROOT`, not inside either assignment branch.**

## Design

### 1. Factor the pin-line construction (one implementation, both call sites)

New helper, placed immediately after `_resolve_pinned_placement()` (i.e. after line 580,
before `emit()` at 586) so it is defined before any caller runs:

```
# PLACEMENT-PIN-DEFAULT-01: single construction site for the worker-prompt pin prefix.
# Idempotent + value-stable: safe to call from the flagged path and again from the
# default path.  No-op when WORK_ROOT is the shared tree (nothing to pin to).
_set_worktree_pin_line() {
  [[ -n "${WORK_ROOT:-}" && "${WORK_ROOT}" != "${PROJECT_ROOT}" ]] || return 0
  WORKTREE_PIN_LINE="WORKTREE PIN: all edits go in ${WORK_ROOT}; do NOT cd to the main checkout even if the mission text names it."
}
```

The string is byte-identical to the existing 576 literal — do not reword it; the shipped
test `head -1 … | grep -q '^WORKTREE PIN: all edits go in '` asserts the prefix.

### 2. Call site 1 — flagged path (behaviour unchanged)

Replace the inline assignment at `576` with `_set_worktree_pin_line`. At that point
`WORK_ROOT` is already the validated candidate (573) and cannot equal `PROJECT_ROOT`
(Step 4 requires it to be a *linked* worktree of PROJECT_ROOT, and PROJECT_ROOT is not
its own linked worktree), so the guard never changes the flagged outcome.

### 3. Call site 2 — default path (the fix)

Insert immediately after line 2282 (`fi  # LANE-PLACEMENT-01: close PLACEMENT_PINNED guard`)
and before `record_lane_start_sha "${sig8}"`:

```
  # PLACEMENT-PIN-DEFAULT-01: pin the prompt on EVERY dispatch whose work root is a lane
  # worktree — the ensure-created path (2272) and the launcher-pre-exported path (267)
  # both land here, and both were unpinned.  Idempotent w.r.t. the flagged path above.
  _set_worktree_pin_line
```

Placement constraints satisfied: after every branch that can mutate `WORK_ROOT`; before
`_spawn_worker_body`'s read at 1707; after `compute_sig` (unchanged — the prepend still
happens at 1707, so sig8/dedup/router inputs are byte-identical).

### 4. Contract table

| Condition at line 2283 | `WORKTREE_PIN_LINE` | Worker prompt first line |
|---|---|---|
| `WORK_ROOT` = ensure-created lane tree | set, names that tree | `WORKTREE PIN: all edits go in <tree>; …` |
| `WORK_ROOT` = launcher-exported lane tree | set, names that tree | same |
| `WORK_ROOT` = pinned via flag | set (already, unchanged) | same |
| `WORK_ROOT == PROJECT_ROOT` (shared / ensure fallback) | empty | mission text unchanged |

## Test plan — `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh`

Baseline today: `passed=21 failed=0`.

**(a) Existing P-h(g) assertion INVERTS.** Lines 353–358 currently assert
`prompt pin line absent with no flag` — that assertion *is* the bug, encoded. It must be
rewritten to assert presence, and strengthened to assert the line names the tree the
worker actually ran in (`CWD_G`, already captured at 345):

```
# P-h(g): pin line present on the DEFAULT ensure-created path (PLACEMENT-PIN-DEFAULT-01)
head -1 pg-mission.txt  =~ ^WORKTREE PIN: all edits go in            → ok  (+0 net)
head -1 pg-mission.txt  contains "${CWD_G}"                          → ok  (+1)
```

**(b) New case P-i — shared-tree dispatch, no pin (regression for req. 2).** Force
`WORK_ROOT == PROJECT_ROOT` by overriding the lane-worktree binary
(`LEADV2_DISPATCH_LANE_WORKTREE_BIN`, read at `leadv2-dispatch-code.sh:1566`) with a stub
whose `ensure` prints `$TARGET` — this drives the real `lane_worktree_fallback` branch at
2274–2275, exactly the production shared-tree shape. Two assertions: dispatch rc 0, and
`grep -q '^WORKTREE PIN:'` finds nothing in `pi-mission.txt`. (+2)

**(c) P-a / P-b flagged-path assertions unchanged** (lines 175, 206) — they must keep
passing byte-for-byte; that is the regression guard for the factoring.

Expected new report line: `passed=24 failed=0`.

Sandbox note: `setup_env` (121–140) already unsets `LEADV2_LANE_WORK_ROOT`, so branch B
is not directly covered by the suite; branch A coverage plus the shared helper is
sufficient — B and A read the same `WORK_ROOT` at the same line.

## Risks

| Risk | Mitigation |
|---|---|
| Fix placed inside the `2272` assignment → branch B (launcher-exported) stays unpinned; the drift reproductions recur unfixed while tests go green | Call site is *after* line 2282, keyed on final `WORK_ROOT` — spelled out above as a hard requirement |
| Pin prepended before `compute_sig` → sig8 changes, dedup ledger breaks | Do not move the 1707 consumption point; only assignment changes |
| Reworded pin string breaks the shipped `grep -q` in P-a/P-b | Reuse the 576 literal verbatim via the helper |
| Helper defined after first use (bash needs definition-before-call at *runtime*, and `_resolve_pinned_placement` is called from `cmd_resolve` far below) | Define at ~581, before both callers execute |
| `bash 3.2` (/bin/bash on macOS) | Helper uses only `[[ ]]`, `${x:-}`, plain assignment — 3.2-clean; no `local -n`, no `${x@Q}` |
| Symlinked `PROJECT_ROOT` making the `!=` compare spuriously true | Harmless — the pin would name a valid equivalent path; matches the existing idiom at 2269/2274, do not introduce a new `pwd -P` normalization here |

## Non-goals (implementing agent: ignore)

- `--resume-lane` / `--worktree` semantics, refusal codes, liveness probing (shipped 21bbdeb)
- `leadv2-lane-worktree.sh` ensure semantics
- product-close / e2e-gate / review-gate paths
- any file other than `leadv2-dispatch-code.sh` and `tests/test-lane-placement-pin.sh`
- do NOT commit

## acceptance:

```
acceptance:
  - surface: file_artifact
    observable: >
      In the recorded worker-prompt file of a default dispatch (no --resume-lane /
      --worktree) that ran in a lane worktree, the first line a human reads is
      "WORKTREE PIN: all edits go in <the lane worktree path the worker actually ran in>;
      do NOT cd to the main checkout even if the mission text names it." — and the same
      file for a shared-tree dispatch opens directly with the mission text, no PIN line.
    authored_at: 2026-08-04T00:00:00Z
  - surface: rendered_line
    observable: >
      The last line printed by the lane-placement-pin suite reads
      "[LANE-PLACEMENT-01] passed=24 failed=0" (up from passed=21), and the core-offline
      suite report shows 32 green against the 9158921 baseline.
    authored_at: 2026-08-04T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-lane-placement-pin.sh

DELIVERABLE_COMPLETE
