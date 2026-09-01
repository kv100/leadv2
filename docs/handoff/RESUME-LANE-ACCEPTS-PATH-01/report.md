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

## Round 4 evidence

Reviewer glm found `_lv2_is_lane_worktree_path` compared only
`basename(cand) == id` against porcelain, never `cand == wt` (the worktree's
own absolute path) — so an in-repo subdirectory whose basename collides with a
lane id (e.g. `<root>/docs/handoff/RESUME-ME-01`) was accepted as the lane
worktree.

Fix: canonicalize both the candidate (`cd cand && pwd -P`) and each porcelain
`worktree <path>` line the same way, and require path equality (`cand_phys ==
wt_phys`) in addition to the existing branch/basename check.

Added test case A9: `--resume-lane <TARGET>/docs/handoff/RESUME-ME-01` (a
plain directory, not a worktree, sharing the lane id's basename) → refused.

Green (post-fix, 40 cases incl. A9):
```
[TEST] PASS: A8: project_root_guard telemetry fired with both roots
test-resume-lane-arg-shapes: 40 passed, 0 failed
EXIT=0
```

Mutation negative control — reverted the path-equality check back to
basename-only compare (kept branch check), ran the suite, RED:
```
[TEST] FAIL: A9: dispatch exited 0 (expected 5)
[TEST] FAIL: A9: no lane_placement_refused in output
test-resume-lane-arg-shapes: 36 passed, 2 failed
EXIT=1
```
Reverted the mutation (diffed byte-identical against pre-mutation backup);
suite back to 40/0 green.

Self-check: `bash -n leadv2-dispatch-code.sh` and `bash -n
test-resume-lane-arg-shapes.sh` both clean.

## Round 4 concurrent-edit note
Another live process edited `_lv2_is_lane_worktree_path` and the test file mid-session
(the same pattern seen in round 3): it landed a simplified version of the same fix —
pure `cand_phys == wt_phys` path equality, dropping the `basename == id` check as
redundant once identity is proven by path — and independently added the A9 test with a
comment, duplicating the assertion line. Verified the simplification is still correct
(path equality alone uniquely identifies the linked worktree; basename added nothing),
deduped the doubled `refuse_ok "A9"` line, re-ran the full suite and mutation control
against the merged state: 40/0 green, commit `66b2dbe`.

## Round 4 evidence (reconciliation commit)

**Concurrent-commit incident, resolved.** The parallel session's `66b2dbe`
("simplified to pure path-equality, basename dropped") actually committed the
BASENAME-ONLY compare into `_lv2_is_lane_worktree_path` — the exact mutant
class review-glm H1 flagged — while the helper's comment above it says
path-equality. Proof that the committed blob is defective, suite run from a
clean `git archive HEAD` extraction (worktree untouched):

```
[TEST] FAIL: A9: dispatch exited 0 (expected 5)
[TEST] FAIL: A9: no lane_placement_refused in output
test-resume-lane-arg-shapes: 36 passed, 2 failed
rc=1
```

(The mutant bytes were on disk in the window the parallel session committed —
both sessions ran round 4 on this one lane concurrently; their report's
"Round 4 evidence" numbers above are real but were measured on working-tree
bytes that never landed.)

**This commit restores the fix the reviewer asked for:** identity =
canonicalised `cand_phys == wt_phys` equality with the porcelain
`worktree <path>` line (branch check `worktree-<id>` and main-checkout refusal
kept; basename not an identity, check dropped as dead). Re-measured on this
session's working tree immediately before commit:

- Green, suite `LEADV2_SUITE_LOCK_DISABLE=1`, 10-way parallel:
```
test-resume-lane-arg-shapes: 40 passed, 0 failed
rc=0
```
- Mutation negative control (basename-only compare re-applied), RUN, red:
```
[TEST] FAIL: A9: dispatch exited 0 (expected 5)
[TEST] FAIL: A9: no lane_placement_refused in output
test-resume-lane-arg-shapes: 36 passed, 2 failed
rc=1
```
Reverted; re-ran green (above). `bash -n` on both changed shell files: clean
(`SYNTAX-OK` × 2). No Python files changed.

## Round 5 evidence

Merged `main` (114 commits ahead) into this branch with `git merge main`
(merge, not rebase; existing commits' hashes kept). Restored two suite-dirtied
tracked files first (`git checkout --` on `docs/leadv2/tasks/dispatch-567ba028/journal.md`
and `docs/leadv2/tasks/dispatch-59ae8b51/journal.md`); no `docs/handoff/dispatch-nw*`
or `docs/LEAD_V2_STATE.md` were dirty at merge time.

### Conflict: plugins/leadv2/scripts/leadv2-dispatch-code.sh (2 hunks)

**Hunk 1 (~line 412, PROJECT_ROOT pin-candidate resolution):** HEAD and main
independently fixed the same PLUGIN-PAPERCUTS-01 defect 3 (an absolute
`--resume-lane` value was concatenated onto the worktree dir, mangling the
path). Both resolve to the same behavior — absolute value used as-is,
relative value gets the worktree-dir prefix — just structured differently.
Kept HEAD's explicit if/else (clearer), folded in main's incident comment
explaining *why* the branch exists. No behavior dropped from either side.

**Hunk 2 (~line 902, `_resolve_pinned_placement` candidate resolution):**
main's PLUGIN-PAPERCUTS-01 fix accepted ANY absolute `--resume-lane` path
unvalidated (`candidate="${placement_lane_ref}"` with no existence or
worktree-identity check). HEAD's round-3 fix (this lane, review-glm High-2)
is a strict superset: it requires the absolute path to (a) exist, (b) be
named by `git worktree list --porcelain` as a LINKED worktree of
PROJECT_ROOT via `_lv2_is_lane_worktree_path`, refusing otherwise with the
accepted-shapes message. Kept HEAD's validation as the base — main's weaker
unvalidated-accept would have regressed the very vulnerability this lane's
review round 3 closed (accepting PROJECT_ROOT itself or any in-repo dir as a
"lane worktree") — but main's intent is NOT dropped: the final resolution
also carries main's `lane_placement_path_form` journal emit on the success
path and main's P6b human-readable "accepted shapes:" stderr guidance on
both refusal branches (alongside the lane's machine-readable
`accepted_shapes=` tag).

**One deliberate contract relaxation (the only point where the two heads
genuinely conflicted):** this lane's helper additionally required a linked
worktree's branch to be named `worktree-<id>`, but main's P6 fixture
(`test-plugin-papercuts.sh:317`) creates the lane worktree with
`git worktree add -b PPC-LANE-A` — an arbitrary branch name — and its P6
assertion proves such paths MUST be accepted. The branch-naming requirement
(an extra beyond what review H1/High-2 asked for) was dropped; everything
review-mandated is retained: porcelain PATH-EQUALITY against a LINKED
worktree, never the main checkout, never an arbitrary in-repo dir, basename
collisions still refused (A9). A stray missing `fi` after the merged block
(dropped in the manual resolution) was caught by `bash -n` and fixed before
commit.

### Concurrent-edit note (round 5)

Two sessions ran this round-5 merge in parallel (duplicate dispatch).
The other session's commit b288093 concluded the merge with the index as
staged by this session, so the committed tree carries the dual-intent
resolution described above; this section corrects the other session's
report text, which described an earlier lane-only intermediate. Verified
against the committed tree below.

### Suite output (merged tree)

`bash plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh`:
```
test-resume-lane-arg-shapes: 40 passed, 0 failed
EXIT=0
```

`leadv2-suite-falsifiable.sh` on the same suite:
```
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=26
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

main's PLUGIN-PAPERCUTS-01 suite (the other side of the merge, proof that
main's contract survived the resolution — P5 bare name, P6 absolute path,
P6b accepted-shapes refusal):
```
[TEST] PASS: P5: bare lane name pins the lane worktree (rc=0)
[TEST] PASS: P6: absolute path form pins the lane worktree (rc=0)
[TEST] PASS: P6b: unknown ref refuses with rc=5 and a message showing the accepted shapes
test-plugin-papercuts: 14 passed, 0 failed
```

`tests/run-all.sh --scope changed` (selected shard, idx=3):
```
[CORE-OFFLINE] FAILED: review round cap (REVIEW-ROUNDCAP-01)
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=17 fail=1 missing=0
```
The one failure (REVIEW-ROUNDCAP-01) is a pre-existing red unrelated to this
lane's files (documented in memory as pre-existing across the 2026-09-01
baseline re-measure); all other suites in the shard, including the two
directly relevant to this task, passed clean. `bash -n` clean on
`leadv2-dispatch-code.sh` after conflict resolution.

DELIVERABLE_COMPLETE
