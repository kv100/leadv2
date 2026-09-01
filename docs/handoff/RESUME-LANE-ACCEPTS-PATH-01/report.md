# RESUME-LANE-ACCEPTS-PATH-01 — round 2: make the suite depend on the fix

Round 1 shipped `test-resume-lane-arg-shapes.sh` at 21 passed / 0 failed while a
mutation of the lane's own branch (`if [[ "${_LV2_PIN_VALUE}" == /* ]]` → `if false`)
stayed green — the suite proved nothing about the change. Round 2 closes that.

## The production change has TWO shape branches, in two resolvers

1. **Early guard** (`leadv2-dispatch-code.sh` ~line 380, FOREIGN-PROJECT-ROOT-GUARD-01
   pin preflight): `if [[ "${_LV2_PIN_VALUE}" == /* ]]` — decides whether an absolute
   `--resume-lane` value is used as the pin candidate or concatenated onto the
   worktrees dir. This branch has no dedicated output; its effect is whether the guard
   pins `PROJECT_ROOT` or discards the pin with
   `WARN: foreign project root detected … using cwd-derived root`.
2. **Placement resolver** (`_resolve_pinned_placement`, ~line 855):
   `if [[ "${ref}" == /* ]]` — the absolute branch that pins WORK_ROOT and emits
   `lane_placement_pinned`, vs the bare-name branch that resolves via `path-of`.

## Mutation matrix (real call path: `bash leadv2-dispatch-code.sh --resume-lane …`)

Baseline after the round-2 edit (rc measured without a pipeline, `cmd > log 2>&1; echo $?`):

```
FINAL_EXIT=0
test-resume-lane-arg-shapes: 22 passed, 0 failed
```

### M1 — early-guard absolute branch → `if false`

```
380:            if false; then  # MUTANT-M1
M1_RED_EXIT=1
[TEST] FAIL: A2: foreign-root guard discarded the absolute-path pin (cwd-derived-root fallback WARN)
test-resume-lane-arg-shapes: 21 passed, 1 failed
```

**The killing assertion** (the only one added this round, at the end of case A2 in
`test-resume-lane-arg-shapes.sh`):

```
A2: foreign-root guard accepted the absolute-path pin   # green when the branch lives
A2: foreign-root guard discarded the absolute-path pin (cwd-derived-root fallback WARN)  # red under M1
```

It asserts the ABSENCE of `foreign project root detected` on A2's real stderr: with the
branch live the preflight proves the pin belongs to the env repo and pins `PROJECT_ROOT`;
without it, the candidate becomes `<worktrees-dir>/<abs-path>`, `cd` fails, the pin is
discarded and the control-plane root degrades to the cwd-derived root — measured stderr
delta between baseline and M1:

```
> [leadv2-dispatch-code] WARN: foreign project root detected (env=…/target cwd=…/RESUME-LANE-ACCEPTS-PATH-01) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
```

(plus `lane_plan_missing source=` switching from the pinned-root spelling to `/tmp/...` —
the same degradation, visible in the journal source path.)

### M2 — `_resolve_pinned_placement` `ref == /*` → `if false`

Already covered by the round-1 suite; no new assertion was needed (none added):

```
855:    if false; then  # MUTANT-M2
M2_RED_EXIT=1
[TEST] FAIL: A2: dispatch exited 5 (expected 0)
[TEST] FAIL: A2: expected pinned line 'path=…/RESUME-ME-01 key=RESUME-ME-01'
test-resume-lane-arg-shapes: 20 passed, 2 failed
```

Killed by A2's two pre-existing assertions: with the branch dead, the absolute value
falls into the bare-name arm, `path-of` returns empty, and the dispatcher refuses
(exit 5) instead of pinning.

### Per-branch coverage (honest)

| Branch | Covered by | Kills |
|---|---|---|
| early guard `_LV2_PIN_VALUE == /*` (abs) | **new** A2 no-fallback-WARN assertion | M1: 21/1, exit 1 |
| `_resolve_pinned_placement` `ref == /*` (abs) | pre-existing A2 rc + pinned-line assertions | M2: 20/2, exit 1 |
| early-guard bare-name arm (`else`, line 383) | A1 (rc 0 + pinned line) — mutates only with the bare arm itself; not separately mutated this round | — |
| `_resolve_pinned_placement` bare-name arm (`else`) | A1 + A5 (refusal `looked_for=<worktrees>/<name>`) | not separately mutated this round |

Both targeted branches are now mutation-verified. The bare-name arms are regression
guards for the pre-existing behaviour and were not mutation-tested this round (scope:
the two arms this lane introduced).

## Suite discipline (Critical 3)

Exactly ONE assertion was added (the A2 no-fallback-WARN check); 21 existing assertions
all still pass (22/0 final). The A4 doubled-segment assertion was NOT modified; no other
case was touched.

## run-all.sh repair (disclosure — out-of-band defect found and fixed)

The round-1 commit (0d61b3c) rewrote the `--scope changed` selection loop in
`tests/run-all.sh` and **reverted main's PLUGIN-PAPERCUTS-01 repair**: the branch's copy
had an unterminated `$(basename "${cf}" .sh)` (line ~295) and a stray `continue"`,
leaving the rest of the loop body swallowed by one command substitution
(`bash -n` passed — the quotes balanced across lines — but the loop was dead at runtime).
Repair: restored main's repaired loop verbatim (`git checkout main -- tests/run-all.sh`)
and re-inserted this lane's `EXTRA_SUITE_MAP` row:

```
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
```

## EXTRA_SUITE_MAP selection proof (--scope changed)

In-repo full `--scope changed` was not executed: it always adds run-core-offline.sh
(>10 min per prior measurement) plus ~25 dispatch-code mapped suites, and lands on
known pre-existing reds. Selection was proven instead with the REAL, unmodified
runner file in a scratch mirror (`/private/tmp/rlap-sel`: tests/run-all.sh +
plugins/leadv2/scripts/ mirrored, only this lane's suite present, `leadv2-dispatch-code.sh`
made dirty):

```
SEL_EXIT=0
[RUN] /private/tmp/rlap-sel/plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
[PASS] /private/tmp/rlap-sel/plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
run-all: 1 passed, 0 failed, scope=changed
```

Exactly one suite selected (the map row firing for the changed dispatch-code stem), and
it passes. A first scratch attempt failed A1 because the mirror lacked
`leadv2-lane-worktree.sh` (`path-of` → 127 → refusal); mirroring the full scripts dir
fixed it — recorded here because it shows the suite genuinely exercises `path-of` on the
bare-name path.

## Acceptance

1. `--resume-lane <absolute path>` ⇒ pins that worktree — **A2** (`lane_placement_pinned
   … path=<RESUME_PHYS> key=RESUME-ME-01`), green.
2. `--resume-lane <bare name>` ⇒ resolves under the worktrees dir — **A1**, green.
3. `--resume-lane <nonexistent path>` ⇒ rc 5, refusal names accepted shapes — **A3/A4/A5**, green.
4. Absolute-path branch mutated to `if false` ⇒ suite RED non-zero — **M1: exit 1** (and M2: exit 1).
5. The 21 existing cases still pass — **final run: 22 passed, 0 failed, exit 0**.

## Self-check

- `bash -n` on `tests/run-all.sh` → `N2_OK`; on the suite → SYNTAX_OK after edit.
- `leadv2-dispatch-code.sh` is byte-identical to HEAD (`git diff HEAD --stat` over
  plugins/leadv2/scripts shows only the suite, +15); it additionally executed 7× per
  suite run, green.
- No Python files changed.
- Changed-scope runner: scratch-mirror proof above (full in-repo run skipped for runtime,
  stated above rather than hidden).
- Mutations were applied INSIDE the production body on the real call path, run RED,
  reverted, run GREEN; `git diff HEAD --stat` clean afterwards.

## Round 3 evidence (review-glm High-1 + High-2)

NOTE: a concurrent process wrote to this lane's `leadv2-dispatch-code.sh` and its
test file mid-session (helper function `_lv2_is_lane_worktree_path` + test cases
A6/A7/A8 + `LEADV2_DISPATCH_TERMINAL_LEDGER=0` perf flag). Verified correct and
adopted rather than reverted, per working-tree-collision policy.

- High-1 (half-deleted mechanism): fixed by keeping the cwd-derived-root fallback
  live, matching WARN text, and live `_LV2_FOREIGN_ROOT_ENV/CWD` telemetry
  assignments consumed by `project_root_guard`. Grep-gated in the suite (round3
  checks).
- High-2 (absolute-path branch over-accepted): fixed via
  `_lv2_is_lane_worktree_path()` — accepts only a path `git worktree list
  --porcelain` names as a LINKED worktree of PROJECT_ROOT (never the main
  checkout), on branch `worktree-<id>`, basename == `<id>`. New cases A6
  (`--resume-lane <PROJECT_ROOT>` refused) and A7 (`--resume-lane
  <PROJECT_ROOT>/plugins` refused) plus A8 (foreign-root WARN text/telemetry
  match).

Green run (36 cases, prior rounds + round 3):
```
test-resume-lane-arg-shapes: 36 passed, 0 failed
```

Mutation negative control — relaxed the absolute-path branch back to bare
"common-dir parent == PROJECT_ROOT" (dropping the linked-worktree/branch/basename
check):
```
[TEST] FAIL: A6: dispatch exited 0 (expected 5)
[TEST] FAIL: A6: no lane_placement_refused in output
[TEST] FAIL: A7: dispatch exited 0 (expected 5)
[TEST] FAIL: A7: no lane_placement_refused in output
test-resume-lane-arg-shapes: 28 passed, 4 failed
```
Reverted; suite back to 36/0 green (diffed against the pre-mutation copy to
confirm byte-identical restore).

Suite wall time (this run): 1:29.85 — still above the review's 40s target. Root
cause investigated: a standalone single-case run floors at ~13s CPU inside the
dispatcher itself (measured with no contention), and a real 2-live-lane
admission cap limits usable parallelism to 2 concurrent invocations. With 8
cases at a 2-wide cap the floor is ~4×13s = 52s before any per-call
environment/ledger overhead. Bringing it under 40s needs dispatcher-side perf
work (e.g. a test-only fast path skipping more subsystems) that is out of scope
for this fix — left as a known gap rather than claimed met.
