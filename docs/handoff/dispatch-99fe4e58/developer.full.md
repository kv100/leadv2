verdict: APPROVE
next_action: deploy

# GATE-FALSE-SILENT-01 fix round 2 — developer report

Implemented the architect prepass's design verbatim (`.claude/worktrees/2d8a2849`,
HEAD `fb97555` → new commit `0fe9c47`). The prepass's census correction stands: both
reds in the round-1 selfcheck reproduce purely from ambient `LEADV2_*` env leakage into
non-hermetic test suites, not from a defect in the product change itself. I did not
falsify anything further in the census during implementation — the design's caller/callee
map, state table, and configuration boundaries all matched the live code.

## Changes (file:line references are post-edit)

### C1 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

1. **`_pc_lane_commits_ahead` (:1183-1215)** — widened output from a lossy `0`/`N`
   channel to `unknown`/`N`. `unknown` is printed whenever no base resolves (root
   invalid, env sha present but its object absent from this repo, cache-file sha
   invalid, no `origin/main`); an integer is printed only when a base actually
   resolved (including the genuine "0 commits ahead" case). Also added a real
   fallback chain: env sha → (on failure) cache-file sha → (on failure)
   `origin/main`, so an unresolvable env sha no longer skips the cache file the way
   it silently did before.
2. **Call site inside `pc_silent_arm_probe` (:1358-1369)** — `commits_ahead == "unknown"`
   now returns 1 (NOT silent) and emits one journal line:
   `silent_probe_base_unresolved task=<T> arm=<A> lane=<basename>`. The lane falls
   through to `pc_scope_diff`, which owns the empty/unscoped verdicts from there.
3. **Comment at :1159-1181** — replaced the round-1 census claim ("_pc_diff_base is
   defined INSIDE pc_scope_diff's body... does not exist as a callable function at
   call time") with the corrected one: `_pc_diff_base` (:1735) is top-level, reached
   via `_pc_repo_diff` → `pc_scope_diff` (:1663), which runs AFTER this probe — a call
   would in fact resolve today. The duplication is kept because `pc_scope_diff` is
   off-limits and the two copies now have deliberately divergent failure semantics
   (this one: `unknown`/fail-open; `_pc_diff_base`: unchanged fail-to-empty). No
   change to `_pc_diff_base` or `pc_scope_diff` — out of scope per the design.

### C2 — `plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh`

1. Hermetic preamble added right after `set -uo pipefail`: scrubs every ambient
   `LEADV2_*` var via `compgen -e` before the first fixture runs (mirrors
   `run-core-offline.sh:101-114`'s denylist for this one prefix).
2. Tightened both `arm_advance` greps (Case A negative assertion, Case D count) to
   `arm_advance task=` so `arm_advance_skipped ... reason=...` can no longer satisfy
   or inflate them.
3. Added **Case E** — the exact regression state the fix exists for: registered arm,
   stale stream, clean worktree, `LEADV2_LANE_START_SHA` set to a sha absent from the
   fixture's throwaway repo, no `origin/main`. Asserts NOT `arm_produced_nothing` and
   that `silent_probe_base_unresolved task=` is emitted.
4. Fixture fix (uncovered while making the D-assertion tightening meaningful): Case D
   never actually reached the `arm_advance task=` line — with no `lane-mission.md`,
   `_pc_arm_advance` short-circuits to `arm_advance_skipped ... reason=no_mission_file`,
   which contains the substring "arm_advance" and was silently satisfying the old
   loose grep. Added a `lane-mission.md` to Case D's fixture so it exercises a real
   advance, matching the design's stated intent ("silent arm still parks, advances
   exactly once").

### C3 — `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh`

1. Same hermetic preamble as C2 (same rationale, cited inline).
2. Case 2 (:108-117): added `LEADV2_DISPATCH_LANE_WRITES=""` to the explicit env
   block, declaring "no write-set" as intent instead of inheriting whatever the
   enclosing shell happened to export. Did NOT declare `newfile.txt` — that would
   have changed what the case tests, per the design's explicit instruction.
3. Fixture fix (uncovered by the base-resolution change, in scope as a natural
   consequence of C1): Case 4 ("stale stream + clean worktree -> silent") had no
   start-sha cache file and no resolvable `origin/main`, so under the new semantics
   its base is genuinely `unknown` — correctly NOT silent, but that broke the case's
   intent to test genuine silence. Added a start-sha cache file pointing at the
   fixture LANE's own HEAD (0 commits ahead of itself), so Case 4 now tests the
   state it always meant to: a resolvable base with zero commits ahead.

## Verification (pasted, foreground, with timeout)

### 1. test-silent-arm-commits-ahead.sh
```
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case A: a committed lane (clean worktree) is NOT classified arm_produced_nothing
[TEST] PASS: Case A: no arm_advance decision for a committed lane
[TEST] PASS: Case B: absent stream is NOT classified arm_produced_nothing
[TEST] PASS: Case C: fresh stream is NOT classified arm_produced_nothing
[TEST] PASS: Case D: genuinely silent arm still classified arm_produced_nothing
[TEST] PASS: Case D: ledger row is no_work/arm_produced_nothing
[TEST] PASS: Case D: exactly one arm_advance decision line
[TEST] PASS: Case D: .arm-advanced-glm marker present
[TEST] PASS: Case E: unresolvable-base lane is NOT classified arm_produced_nothing
[TEST] PASS: Case E: degradation line emitted for unresolvable base

[TEST] 11 passed, 0 failed
```

### 2. Hermeticity proof — same two suites, `LEADV2_LANE_START_SHA` and
`LEADV2_DISPATCH_LANE_WRITES` deliberately exported to foreign values beforehand
(the exact leak that caused round 1's reds):
```
$ export LEADV2_LANE_START_SHA=$(git rev-parse HEAD)
$ export LEADV2_DISPATCH_LANE_WRITES="plugins/leadv2/scripts/leadv2-dispatch-product-close.sh"
$ bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
... (identical 11 PASS lines as above) ...
[TEST] 11 passed, 0 failed
$ bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
... (identical 12 PASS lines as below) ...
[TEST] 12 passed, 0 failed
```
Both suites stayed green under contamination — the hermeticity fix holds.

### 3. test-dispatch-silent-arm.sh
```
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case 1: exits 5 (falls through to the existing empty_diff terminal)
[TEST] PASS: Case 1: absent stream is NOT classified as arm_produced_nothing
[TEST] PASS: Case 1: ledger row is no_work/empty_diff (existing path, not the silent-arm path)
[TEST] PASS: Case 1: no arm_advance decision for an absent stream
[TEST] PASS: Case 2: review-gate.md not arm_produced_nothing (assistant events present)
[TEST] PASS: Case 2: ledger row lands as before (regression lock, both gates off)
[TEST] PASS: Case 3: fresh (within growth window) stream falls through as NOT silent
[TEST] PASS: Case 3: existing empty-diff path still produces reason: no_work
[TEST] PASS: Case 4: stale stream + clean worktree classified as silent
[TEST] PASS: Case 5: no arm_produced_nothing when arm not registered (empty_diff path owns it)
[TEST] PASS: Case 5: no arm_advance decision without arm registration

[TEST] 12 passed, 0 failed
```

### 4. run-core-offline.sh
```
[CORE-OFFLINE] suites passed=58 failed=3 missing=0 repo=.../2d8a2849
```
Three failures, all confirmed NOT caused by this change:
- `deferred-GLM ladder (V3-GLM-LADDER-01)` — pre-existing, named in the mission as
  known-not-mine.
- `fanout classifier/runner guard` — pre-existing, named in the mission as
  known-not-mine. Root cause visible in the log: a missing
  `~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh` under the sandbox
  home, unrelated to this diff.
- `product-close scopes a single-repo lane worktree` (`test-lane-diff-single-repo.sh`,
  case `C5-registered-arm-silent`) — NOT named in the mission, so I verified it
  independently: `run-core-offline.sh`'s own "pass 2/2: red-first pre-fix (git
  archive HEAD)" step re-ran this suite against the committed HEAD (i.e. before any
  of this round's edits) and it failed identically there too. Ran the suite
  standalone and confirmed the same pre-fix/post-fix FAIL pair. This is a
  pre-existing defect in that suite/gate interaction, orthogonal to
  `_pc_lane_commits_ahead` — I did not touch `pc_silent_arm_probe`'s registration
  gate (gate 0) or anything `test-lane-diff-single-repo.sh` exercises. Left alone
  per the design's out-of-scope list (no assertion outside the two named suites).

### 5. bash -n on every changed shell file
```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh && echo OK
OK
```
No Python files changed.

### 6. git diff --stat (this lane's own commit, `0fe9c47`)
```
 plugins/leadv2/scripts/leadv2-dispatch-product-close.sh    | 58 +++++++++++--------
 plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh   | 21 +++++++
 plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | 65 ++++++++++++++++++++-
 3 files changed, 120 insertions(+), 24 deletions(-)
```
The six pre-existing modified `docs/handoff/dispatch-nw*sig*/phases.d/{e2e,review}.yaml`
files shown in the worktree's initial `git status` were NOT touched by me and are NOT
part of this commit — left alone per "main's unrelated uncommitted files: no
stash/reset/clean".

## Non-goals honored

Did not touch `pc_scope_diff`, `_pc_diff_base`'s body, the e2e gate, the ledger schema,
`_pc_arm_advance`'s chain logic, the env-var precedence order (env still beats cache
file), any other suite under `tests/`, or main's unrelated uncommitted files. No merge.

## Committed

Commit `0fe9c47` on branch `worktree-2d8a2849`, scoped to exactly the three files listed
in LANE_WRITES.

DELIVERABLE_COMPLETE
