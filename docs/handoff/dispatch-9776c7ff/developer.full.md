verdict: APPROVE
next_action: continue

# CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 — developer report

## Root cause (confirmed, not re-derived from the mission text)

`leadv2-phase8-assert.sh`'s A2 check and `leadv2-tasks-lib.sh`'s `release` op (the
function behind `leadv2_tasks_release`, which A2's own failure message tells the caller
to run) both matched a `docs/tasks.yaml` row with `str(it.get("id","")) == task_id`
only. A fingerprint-keyed backlog (persona-engine: row `id` is an opaque hash, e.g.
`ca2177b9451b`) never carries the human milestone name (`V5-M0-SKELETON-01`) in `id` —
that name only appears inside `intent`, before the first `:`. The comparison could
never match, so A2 blocked forever, and the printed remedy hit the identical mismatch
one layer down (verified live, see "Remedy verification" below).

## Fix

1. `plugins/leadv2/scripts/leadv2_tasks_yaml_common.py` — added `resolve_task(items,
   task_id)`: matches a row by `id` first, else by `intent`'s colon-anchored prefix
   (`intent.split(":", 1)[0].strip() == task_id`). Anchored on the full segment before
   `:`, never a substring/startswith, so `"V5-M1"` cannot false-match a row whose
   `intent` begins `"V5-M10:"`.

2. `plugins/leadv2/scripts/leadv2-phase8-assert.sh` — A2's embedded python block now
   imports and calls `resolve_task` instead of the inline `for it in items: if
   str(it.get("id","")) == task_id` loop. The `# Not found in tasks.yaml — check lane
   yamls as fallback` comment was false (that fallback lives in a sibling `else`
   branch gated on `[[ -f "$TASKS_YAML" ]]`, which this code path can't reach once
   tasks.yaml exists) — replaced with an accurate comment, and the `rc==2` bash
   message now says plainly that only `tasks.yaml` was searched (by id or
   intent-prefix), with no lane-yaml fallback.

3. `plugins/leadv2/scripts/leadv2-tasks-lib.sh` — added `resolve_iid(items, iid)`
   (identical semantics, separate copy because this file's dispatcher is a
   self-contained heredoc with its own `load_tasks()`, not a module that imports from
   `leadv2_tasks_yaml_common`). The `release` op now resolves the row via
   `resolve_iid` before mutating it. The original `iid` string (the human name) is
   still what gets passed to `write_closed_sentinel()`, unchanged — A2's
   `RELEASE_RECEIPT` path is built from `TASK_ID` (the human name), so the sentinel
   filename must stay keyed by that name, not the resolved fingerprint id. Verified
   this wiring live (below).

## Remedy verification (live, not inferred)

```
$ cat docs/tasks.yaml
tasks:
  - id: ca2177b9451b
    lane: action
    status: in_progress
    intent: 'V5-M0-SKELETON-01: veha M0 plana v5'
$ source leadv2-tasks-lib.sh
$ leadv2_tasks_release 'V5-M0-SKELETON-01' --outcome success
RC=0
$ cat docs/tasks.yaml   # status: done, id unchanged (still ca2177b9451b)
$ cat docs/leadv2/closed/.tasks-sentinel-V5-M0-SKELETON-01.yaml
outcome: completed_success
```
Before the fix this call printed `[tasks-lib] V5-M0-SKELETON-01 not found` (rc=3) — the
exact behaviour the mission reported.

## Scope note — call sites surveyed but NOT changed

Grepped every `it.get("id","")) == iid` site in `leadv2-tasks-lib.sh`: `by_id`,
`claim`, `unclaim`, `update`, plus the `by_id` dependency-graph dict in
`top_n`/`next_for_lane` (5 sites total, `release` now fixed as #6 of the original 6
id-only sites). Every live caller of `by_id`/`claim`/`unclaim`/`update` (grepped across
the whole `plugins/leadv2/scripts/` tree, non-test callers) passes an `iid` sourced
either from a prior `top_n`/`next_for_lane`/`queue-claim` listing (already the row's
real `id`) or from a lane's own `$TASK_ID` env var. The latter is worth flagging: in
`leadv2-codex-lead.sh:139,410` and similar dispatch-path callers, `$TASK_ID` **is** the
human milestone name in a fingerprint-keyed repo, so `leadv2_tasks_by_id`/
`leadv2_tasks_claim` are reachable with the same scheme mismatch. I did not touch
these — `claim`/`unclaim` back the live fanout/dispatch claim-lease loop, changing
their matching semantics without a dedicated regression suite is out of this task's
declared scope (`LANE_WRITES` names only `leadv2-phase8-assert.sh` +the new test file
+`tests/run-all.sh`; I extended to `leadv2-tasks-lib.sh`/`leadv2_tasks_yaml_common.py`
only because the mission explicitly required fixing the printed remedy). Recommend a
follow-up task if `by_id`/`claim` need the same resolution.

## Test suite: plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh

Covers all 5 acceptance items plus a mutation-kill proof:
- Test 1: fingerprint-keyed row, intent starts with the milestone name → A2 PASS (the
  real-repo case)
- Test 2: row whose `id` already equals the task id → still PASS (regression guard)
- Test 3: `V5-M1` vs a fixture containing both `V5-M1:` and `V5-M10:` rows — each
  resolves its own row, neither cross-matches (both directions)
- Test 4 / 4b: absent task → exit 2; E2E message names id-or-intent-prefix search and
  that no lane-yaml fallback ran
- Test 5: the printed remedy (`leadv2_tasks_release`), executed against a fingerprint
  fixture, clears A2 end-to-end (rc 1→0)
- Test 6: `bash -n` / `py_compile` on all three touched files
- Test M: mutation-kill — reverts `leadv2-phase8-assert.sh`'s row lookup to the
  original id-only comparison **on the real production file, in place**, proves the
  fingerprint fixture (not an id-equals-name fixture) goes RED (rc=2), reverts, proves
  GREEN (rc=0) again. Baseline-green precondition checked before mutating.

```
[TEST] === Results: PASS=8 FAIL=0 ===
[TEST] All tests passed.
```//run captured below verbatim

## Full raw test output

### bash -n / py_compile (all changed files)
```
$ bash -n plugins/leadv2/scripts/leadv2-phase8-assert.sh && echo "assert OK"
assert OK
$ bash -n plugins/leadv2/scripts/leadv2-tasks-lib.sh && echo "tasks-lib OK"
tasks-lib OK
$ python3 -m py_compile plugins/leadv2/scripts/leadv2_tasks_yaml_common.py && echo "common py OK"
common py OK
$ bash -n tests/run-all.sh && echo "SYNTAX OK"
SYNTAX OK
$ bash -n plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh && echo "SYNTAX OK"
SYNTAX OK
```

### New suite (RED before fix / GREEN after — mutation-kill test is inline, see Test M)
```
[TEST] === GATE-A2-ID-SCHEME-MISMATCH-01 regression tests ===
[TEST] Test 6: bash -n / py_compile syntax checks
[TEST] PASS: Test 6: leadv2-phase8-assert.sh + leadv2-tasks-lib.sh + leadv2_tasks_yaml_common.py syntax OK
[TEST] Test 1: fingerprint-keyed row, intent starts with milestone name -> A2 PASS
[TEST] PASS: Test 1: fingerprint id + intent-prefix match -> exit 0 (PASS)
[TEST] Test 2: row whose id equals the task id -> still A2 PASS (regression guard)
[TEST] PASS: Test 2: id==task_id -> exit 0 (PASS, unchanged)
[TEST] Test 3: V5-M1 must not match V5-M10's row, and vice versa
[TEST] PASS: Test 3: V5-M1 -> its own row (exit 0); V5-M10 -> its own row, non-terminal (exit 1) -- no cross-match either direction
[TEST] Test 4: genuinely absent task -> A2 FAILS (exit 2, not-found, distinct code)
[TEST] PASS: Test 4: absent task -> exit 2
[TEST] Test 4b (E2E): shipped script's rc==2 message names id-or-intent-prefix search, and that only tasks.yaml was consulted
[TEST] PASS: Test 4b: rc!=0, message names id-or-intent-prefix search and that no lane-yaml fallback ran
[TEST] Test 5: leadv2_tasks_release (the printed remedy) executed against a fingerprint fixture clears A2
[TEST] PASS: Test 5: A2 FAILed before remedy (rc=1); leadv2_tasks_release resolved the fingerprint row by intent-prefix; A2 PASSes after (rc=0)
[TEST] Test M: reverting A2's row lookup to an id-only comparison must go RED on the fingerprint fixture
[TEST] PASS: Test M: id-only mutation -> RED (rc=2, not-found) on the fingerprint fixture; revert -> GREEN (rc=0) again
[TEST] === Results: PASS=8 FAIL=0 ===
[TEST] All tests passed.
```

### Pre-existing sibling suites (proves no regression)
```
$ bash plugins/leadv2/scripts/tests/test-leadv2-phase8-assert-a2-schema.sh
[TEST] === Results: PASS=12 FAIL=0 ===
[TEST] All tests passed.

$ bash plugins/leadv2/scripts/tests/test-leadv2-tasks-release-store-guard.sh
[TEST] === Results: PASS=5 FAIL=0 ===
[TEST] All tests passed.
```

### `--scope changed` selection proof (EXTRA_SUITE_MAP rows added)
Traced `bash -x tests/run-all.sh --scope changed` (the always-on `run-core-offline.sh`
execution itself was blocked on a machine-wide `/tmp/leadv2-core-offline.lock` held by
*other, unrelated* concurrent lane sessions on this box the whole session — see below —
so the trace was captured up through `SUITES` array construction, before the execution
loop):
```
+ [[ -n leadv2-phase8-assert.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh ]]
+ add_suite .../plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
+ [[ -f .../plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh ]]
+ [[ -n leadv2-tasks-lib.sh:plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh ]]
+ add_suite .../plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh   # 2nd match, deduped by add_suite's existing-path check
+ for suite in "${SUITES[@]}"
+ printf '[RUN] %s\n' .../plugins/leadv2/scripts/tests/run-core-offline.sh
```
Both changed-file stems (`leadv2-phase8-assert`, `leadv2-tasks-lib`) independently
select the new suite via their `EXTRA_SUITE_MAP` rows; `add_suite`'s dedup guard
collapses the double-match to one entry, confirmed by the trace's `[[ ... == ... ]]`
comparison at the second `add_suite` call.

### Note: full `tests/run-all.sh --scope changed` (83-suite offline pass) not obtained
`run-core-offline.sh` takes a single machine-wide lock
(`/tmp/leadv2-core-offline.lock`). For the duration of this session at least 4 other
concurrent Claude lane sessions on this same machine (worktrees
`ANTI-SILENCE-BEAT-ABORT-03`, `LEAD-WORKER-CHANNEL-01`, and others) were also invoking
`tests/run-all.sh --scope changed` and contending for the same lock and, incidentally,
the same `/tmp` scratch filenames I initially reused — confirmed by `ps aux` showing
their distinct `CODEX_COMPANION_SESSION_ID`s and worktree paths, and by `[RUN]` lines
from their worktrees appearing in a shared log file before I switched to session-scoped
tracing. This is a pre-existing shared-resource constraint, not caused by this change.
In its place I ran the two pre-existing suites that directly exercise the touched code
paths (`test-leadv2-phase8-assert-a2-schema.sh`, `test-leadv2-tasks-release-store-guard.sh`
— both green, above) plus `test-backlog-pump.sh`, which also sources
`leadv2-tasks-lib.sh`.

`test-backlog-pump.sh` showed 5 pre-existing failures (`control: mutation NOT caught`,
`floor_dispatches_then_refuses`, `duplicate_signature_refused`,
`judgment_class_excluded: opus-arm...`, `auto_dispatch`). I verified these are **not**
caused by this change: swapped `leadv2-tasks-lib.sh` back to the exact `HEAD` (pre-fix)
content via `git show HEAD:...`, re-ran the same suite — identical 5 failures,
identical messages. Restored my fixed version afterward (`diff` confirmed byte-identical
to the pre-swap copy). Left this suite alone per the "never weaken a fixture to get
green" rule — it is a pre-existing baseline red, unrelated to A2/id-scheme-mismatch,
and out of this task's scope.

## Files changed
- `plugins/leadv2/scripts/leadv2-phase8-assert.sh` (A2 lookup + rc==2 message)
- `plugins/leadv2/scripts/leadv2-tasks-lib.sh` (`resolve_iid` + `release` op) — not in
  the declared `LANE_WRITES` list; touched because the mission explicitly required
  fixing the printed remedy (`leadv2_tasks_release`), which lives here
- `plugins/leadv2/scripts/leadv2_tasks_yaml_common.py` (`resolve_task`) — same
  rationale, shared helper A2's python block imports
- `plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh` (new)
- `tests/run-all.sh` (2 new `EXTRA_SUITE_MAP` rows)

`git diff --stat`:
```
 plugins/leadv2/scripts/leadv2-phase8-assert.sh     | 28 ++++++++++++++-----------
 plugins/leadv2/scripts/leadv2-tasks-lib.sh         | 29 ++++++++++++++++++++++++--
 plugins/leadv2/scripts/leadv2_tasks_yaml_common.py | 25 ++++++++++++++++++++++
 tests/run-all.sh                                   |  4 +++-
 plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh | new file
```

Committed on `worktree-CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01` as `8443392`. Working tree
otherwise carries pre-existing uncommitted drift in shared control-plane files
(`docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`) from other
concurrent lane sessions — present at session start, not touched by this commit
(verified via targeted `git add` of only the 5 files above, never `git add -A`/`.`).

DELIVERABLE_COMPLETE
