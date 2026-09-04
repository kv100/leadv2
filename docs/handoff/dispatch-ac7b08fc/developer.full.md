# CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 — developer report

## Starting state

This lane was resumed per the RESUME NOTE: a previous worker was killed mid-task and the lead
committed its uncommitted work verbatim as `wip(...)` rescue commits, most recently
`3918df0e` ("rescue — worker died mid-task (repeat)"). Per instructions I judged that commit
rather than trusting or reverting it.

`git diff --diff-filter=D --name-only main...HEAD` (three dots) returned empty — the large
deletion list under two-dot `main..HEAD` is main having advanced independently on files this
lane never touched, not real deletions by this lane. No restoration needed.

## Review of the rescued fix (`plugins/leadv2/scripts/leadv2-task-judge.sh`,
`plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh`)

Read the full diff (`git diff main...HEAD -- leadv2-task-judge.sh`) and the full new test file.
Findings, checked against the blueprint:

- **Matcher surface (§3):** `_fallback_estimate`'s new `SAFETY_TOKENS = ('safety', 'publish',
  'payment', 'payments')` is matched only against `title_tokens` — the whole-hyphen/underscore
  token set of the mission's first `#` heading line — never against `text_lower` (the body). This
  is exactly the id/title-only arm the blueprint mandates. The old whole-body `SAFETY_KEYWORDS`
  substring scan is gone.
- **Third arm (protected_path_patterns against real paths) correctly NOT built.** The rescued
  code's own comment documents verifying first: 0/324 lane missions carry `Reads:`/`Writes:`/
  `Touches:` lines (blueprint 2b-a), and the judge's only inputs are `--mission-file`/`--task-id`/
  `--class` — no path list reaches this process — so shipping that arm would be decorative. The
  comment also notes a *prior* uncommitted draft (from an earlier rescue) had built exactly that
  decorative arm against `Reads:`/`Writes:`/`Touches:`, and it was correctly removed in this
  version, not carried forward. This matches the blueprint's explicit instruction: "if no such
  list is reachable from the judge, ship the id+title arm alone and say so — never ship an arm
  that cannot fire."
- **Floor location (§4):** `_apply_safety_floor()` is called as the first statement inside
  `_emit()`, before `printf` and before `_journal` — the single choke point all 5 exit paths pass
  through, including the cache-hit path (self-heals stored pre-fix estimates with no migration,
  since the raw cache write itself is untouched).
- **Floor target:** floors `complexity` to `standard` (never `complex`), touches only
  `complexity` (not `duration_class`/`work_kind`/`subsystems_touched`), never downgrades (only
  applies when `complexity in ('trivial','simple')`), and on any internal error passes the
  estimate through unchanged and journals `safety_floor=error`.
- **No `LEADV2_*` bypass flag** exists anywhere in the diff — confirmed by re-reading the whole
  changed block; the only new env-shaped surface is `SAFETY_FLOOR_STATUS`, an internal shell
  variable, not an env var read by the script.
- **Journal:** `route_v2_estimate` line gained `safety_floor=${SAFETY_FLOOR_STATUS:-none}`.
- Arbiter/dispatch-code.sh and `leadv2-route-arbiter.sh` are untouched (confirmed below) — the fix
  stays a routing-quality/shape decision, never an arm decision, as required.

Conclusion: the rescued fix is correct and complete against the blueprint. **I made no code
changes** — the previous worker's implementation already satisfies §3/§4/§8 as written. My work
this session was verification: run the suite, run both mandated negative controls, and produce
the acceptance evidence the brief requires.

## Test run (baseline)

```
$ bash plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
...
[TEST] PASS: T10 (no --class, judge path): risk_class=safety_publish_payments, complexity=standard (floored, not trivial)
[TEST] PASS: T10 (--class Light, fallback path): risk_class=safety_publish_payments, complexity=standard (floored, not simple)
[TEST] PASS: T11: cache pre-seeded complexity=trivial emits complexity=standard (floor at the choke point)
[TEST] PASS: T11: cache hit — judge never invoked (0 calls)
[TEST] PASS: T12: README-typo mission -> risk_class=none
[TEST] PASS: T12: README-typo mission -> complexity=trivial (exact, never over-floored)
[TEST] PASS: T13: safety mission -> risk_class=safety_publish_payments
[TEST] PASS: T13: --class Heavy -> complexity=complex (floor never downgrades)
[TEST] PASS: T14: id-only 'SAFETY' token -> risk_class=safety_publish_payments (d552b9ab regression fixed)
[TEST] PASS: T14: complexity=standard (not trivial/simple — floor applied)
[TEST] PASS: T15: body-only 'publish' homograph -> risk_class=none (79a9c5b7 regression fixed)
[TEST] PASS: bash -n syntax OK on leadv2-task-judge.sh

=== Results: 29 passed, 0 failed ===
```
`baseline_rc=0`.

## Mandatory negative control #1 — floor mutation, INSIDE `_apply_safety_floor`'s body

Mutated the trigger condition inside the function body (never at file top level), per §5:
```
-    if est.get('risk_class') == 'safety_publish_payments' and est.get('complexity') in ('trivial', 'simple'):
+    if est.get('risk_class') == 'safety_publish_payments_NEVER' and est.get('complexity') in ('trivial', 'simple'):
```
Result:
```
[TEST] FAIL: T10 (no --class, judge path): got risk_class=safety_publish_payments complexity=trivial
[TEST] FAIL: T10 (--class Light, fallback path): got risk_class=safety_publish_payments complexity=simple
[TEST] FAIL: T11: expected complexity=standard from floored cache-hit, got trivial
[TEST] PASS: T11: cache hit — judge never invoked (0 calls)
[TEST] PASS: T12: README-typo mission -> risk_class=none
[TEST] PASS: T12: README-typo mission -> complexity=trivial (exact, never over-floored)
[TEST] PASS: T13: safety mission -> risk_class=safety_publish_payments
[TEST] PASS: T13: --class Heavy -> complexity=complex (floor never downgrades)
[TEST] PASS: T14: id-only 'SAFETY' token -> risk_class=safety_publish_payments (d552b9ab regression fixed)
[TEST] FAIL: T14: expected complexity outside {trivial,simple}, got trivial
[TEST] PASS: T15: body-only 'publish' homograph -> risk_class=none (79a9c5b7 regression fixed)

=== Results: 25 passed, 4 failed ===
```
`mutated_rc=1`. Exactly the brief's expectation: **T10, T11, T14 red; T12 and T15 stay green.**

Reverted via clean file copy (`diff` against pre-mutation backup returned empty — clean revert).

## Mandatory negative control #2 — matcher mutation, INSIDE `_fallback_estimate`'s body

Restored the body-wide substring scan inside the function body:
```
-title_hit = bool(title_tokens & set(SAFETY_TOKENS))
+title_hit = bool(title_tokens & set(SAFETY_TOKENS)) or any(k in text_lower for k in SAFETY_TOKENS)
```
Result:
```
...
[TEST] PASS: T14: complexity=standard (not trivial/simple — floor applied)
[TEST] FAIL: T15: expected risk_class=none, got safety_publish_payments
[TEST] PASS: bash -n syntax OK on leadv2-task-judge.sh

=== Results: 28 passed, 1 failed ===
```
`mutated_rc=1`. **T15 red (the homograph returns), T12 stays green** — exactly the brief's second
control.

Reverted via clean file copy (`diff` against pre-mutation backup returned empty). Final rerun:
`29 passed, 0 failed`, `FINAL_RC=0`.

## §2 acceptance reproduction — real lane missions

`docs/handoff/dispatch-79a9c5b7/lane-mission.md` and `docs/handoff/dispatch-d552b9ab/lane-mission.md`
no longer exist in this worktree (per-task handoff artifacts are ephemeral and these two are from
an earlier lane cycle not present on this branch). T14 and T15 in the test suite reproduce the
identical id/title/body content the blueprint measured against those two missions (see the suite
excerpts above — both pass), so the §2 regression is proven via the committed test fixtures rather
than the original transient files.

## CI selection proof — `tests/run-all.sh --scope changed`

The runner persists a per-worktree "last checked SHA" state file
(`$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha`) so a suite already seen on a prior
run of this script doesn't reselect on every later invocation. That file already equalled this
lane's HEAD (`3918df0e...`) from an earlier local invocation, so a same-state rerun legitimately
selected 0 new suites for this diff. To prove genuine `--scope changed` selection (the "first run
on a lane" path, using the merge-base with `main`), I moved the state file aside, reran, and moved
it back afterward (no lane state was permanently altered):

```
$ mv leadv2-run-all-last-checked-sha leadv2-run-all-last-checked-sha.bak
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
run-all: 5 selected, scope=changed, select_only=1
$ mv leadv2-run-all-last-checked-sha.bak leadv2-run-all-last-checked-sha   # restored
```
`test-leadv2-task-judge.sh` is selected — no new `EXTRA_SUITE_MAP` row was needed, confirming the
stem-convention path (`leadv2-task-judge.sh` → `test-leadv2-task-judge.sh`) the brief predicted.

## Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-task-judge.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh && echo OK2
OK2
```
No Python files were changed by this lane (all matcher/floor logic is inline `python3 -c` inside
the bash file), so no standalone `py_compile` target applies.

## Scope / off-limits check

```
$ git diff --stat main...HEAD -- plugins/leadv2/scripts/leadv2-task-judge.sh plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
 plugins/leadv2/scripts/leadv2-task-judge.sh        | 123 +++++++++++++++-
 .../leadv2/scripts/tests/test-leadv2-task-judge.sh | 161 +++++++++++++++++++++
 2 files changed, 280 insertions(+), 4 deletions(-)

$ git diff --stat main...HEAD -- plugins/leadv2/scripts/leadv2-dispatch-code.sh plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh tests/known-red-suites.txt
(empty — untouched)

$ git diff --diff-filter=D --name-only main...HEAD
(empty — no real deletions on this lane)
```
Matches acceptance §9.4 exactly: only the judge script and its test suite changed. `tests/run-all.sh`
required no edit (stem convention already covers it — verified above, not assumed).

## What I kept vs. changed from the rescued commit

Kept everything: the matcher restriction to id/title tokens, the deliberate omission of the
path-glob arm (with its documented removal of an earlier draft's decorative version), the floor
placement/semantics in `_apply_safety_floor`/`_emit`, the journal field, and all of T10–T15. I
made **zero code edits** this session — my role was verification (test run, both mandated
mutation controls, `--scope changed` selection proof, off-limits/scope check) since the rescued
work already satisfied the blueprint. No `LEADV2_*` bypass flag exists; no credential values were
printed or logged at any point.

## Adjacent items (blueprint §7) — confirmed still out of scope, not touched

Verified via `git diff --stat` above that `leadv2-dispatch-code.sh` and
`leadv2-route-arbiter.sh` are untouched. Items 1–5 in blueprint §7 (safety-pin/arm-binding gap,
`floor_mode=bulk_only`, `util_codex=unknown_capped` handling, `agent/safety/` path-pattern miss,
row 3.5) remain unaddressed by design — they are separate rows, and two of the referenced files
are explicitly off-limits to this lane.

## Nothing left uncommitted

Only pre-existing runtime-state bus/lock files (`docs/leadv2/*`, `docs/LEAD_V2_STATE.md`) show as
modified in the working tree — these are lead-owned and explicitly off-limits per the gate (item
d) and the lane rules ("State files are lead-owned... never write them"); I did not stage or
commit them. This deliverable pair is the only new commit from this session.

DELIVERABLE_COMPLETE
