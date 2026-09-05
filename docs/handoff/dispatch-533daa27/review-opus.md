LABEL=critic-dispatch-dispatch-533daa27-review-1788021723 SESSION_ID=1b0d2090-5b56-4480-91af-c60d24e8bbb5
--- body from: docs/handoff/dispatch-dispatch-533daa27-review/critic.full.md ---
# critic — round 2 (verification-only) — dispatch-533daa27

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=1 low=1

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-active-registry.sh line=228 dimension=correctness desc=Prior H1 (two-phase registration TOCTOU) is NOT fixed in the reviewed diff — `_lv2_ws_pending` is absent from it, so an incumbent mid-prepass still admits an intersecting lane under default warn, and the diff's own H1 test fails (rc=0), turning the newly-registered run-core suite red.

## Scope / artifact identity

Reviewed artifact: `docs/handoff/dispatch-533daa27/build-attempt-2.diff`
(md5 f559724db887c1c95d765afa8d407eae, 831 lines, 601 insertions).

Verified it is byte-identical to `git diff ddc5557..HEAD` in worktree
`.claude/worktrees/533daa27` (registry section compared with difflib: 0 diff
lines, both 15029 bytes; `--stat` identical for all 7 files). So the diff ==
the lane's committed state at HEAD 7632e84.

**Important:** the worktree also carries UNCOMMITTED edits that are *not* in
the reviewed diff:

```
$ git status --porcelain -- plugins/
 M plugins/leadv2/scripts/leadv2-active-registry.sh
 M plugins/leadv2/scripts/leadv2-phase8-close.sh
$ git diff --stat HEAD -- plugins/
 leadv2-active-registry.sh | 81 +++++++++++++++-----
 leadv2-phase8-close.sh    |  8 ++-
```

Those uncommitted 81 lines are the H1 fix (`_lv2_ws_pending`, `_lv2_ws_dead`,
M6 stderr move). They are the reason the same test passes in the dirty tree and
fails on the artifact under review.

## Per-prior-finding verification (by execution)

Method: copied `plugins/leadv2/scripts` to a temp dir, restored the two files
to their HEAD (= reviewed-diff) content with `git show HEAD:…`, and ran the new
suite there; then ran the same suite unmodified in the dirty worktree.

### 1. High — two-phase registration reopens the TOCTOU → **NOT FIXED** (in this diff)

```
$ grep -n "_lv2_ws_pending\|pending_resolution" docs/handoff/dispatch-533daa27/build-attempt-2.diff
369:+      # (_lv2_ws_pending, keyed on this row's own `started_at`) refuses any   <- comment only
731:+# REFUSED (rc=5, reason=pending_resolution), not silently admitted under the  <- test comment
742:+  if [[ "$rc" == 5 ]] && grep -q 'reason=pending_resolution' <<<"$out" …      <- test assertion
```

The function the dispatch-code comment and the test both depend on is never
defined anywhere in the diff. Execution against the diff's tree state:

```
$ bash test-writeset-admission-block.sh          # HEAD (= reviewed diff) content
[TEST] PASS: live signal: rc=5, conflict names LANE-A, LANE-B not appended
[TEST] PASS: race: exactly one intersecting register wins under the registry lock
[TEST] PASS: legacy and drift re-check: warn admits, block=6, free=0, contested=5
[TEST] FAIL: H1 pending window: rc=0 out=LEADV2_WRITESET_UNKNOWN other=PENDING-A
[TEST] PASS: H2/H3: _pc_git_diff_names sees an untracked new file and excludes docs/leadv2/
[TEST] PASS: H4: writeset_drift_conflict is never reclassified landed_foreign; unscopable_diff escape still fires
[TEST] === Results: PASS=5 FAIL=1 ===
```

`rc=0` is the finding verbatim: PENDING-A registered without writes (the
architect-prepass window), PENDING-B declares an intersecting path, and the D7
unknown/warn branch (`leadv2-active-registry.sh:228` in the diff's numbering)
admits it. The second register at `leadv2-dispatch-code.sh:~6017` cannot close
this — it fires only after the prepass, i.e. after the concurrent lane has
already been admitted and spawned.

Blast radius beyond the finding itself: the diff also registers this suite in
`plugins/leadv2/scripts/tests/run-core-offline.sh:281`, so merging the diff as
committed puts run-core-offline permanently red.

For completeness, the same suite in the dirty worktree (uncommitted 81 lines
applied) is green — `PASS=6 FAIL=0`. The fix exists; it is simply not in the
artifact under review. Committing those two files into the lane branch should
clear this finding.

### 2. High — drift detector blind to untracked/NEW files → **FIXED**

`_pc_git_diff_names()` (`leadv2-dispatch-product-close.sh:1972-1989`) reuses the
`_pc_git_diff` temp-index trick with `git add -N -A -- .`, and carries the
`:(exclude)docs/leadv2` / `:(exclude)docs/handoff` pathspecs. The wire test
sources the *shipped* function body via `sed -n '/^_pc_git_diff_names() {/,/^}/p'`
and runs it against a real git repo — it passes on the reviewed diff's content
(H2/H3 PASS above), asserting an untracked `undeclared-new-file.txt` appears and
`docs/leadv2/bus.jsonl` does not.

### 3. High — landed-foreign escape swallowed writeset_drift_conflict → **FIXED**

Guard narrowed to `if [[ "${blocked_reason}" == "unscopable_diff" ]]`
(`leadv2-dispatch-product-close.sh:2272`). Confirmed exhaustive: the only three
values ever assigned are `partial_diff` (:2124), `writeset_drift_conflict`
(:2183) and `unscopable_diff` (:2189/:2196), so the narrowing subtracts exactly
the one reason that must not escape and regresses nothing. The H4 wire test
extracts the live block by regex and asserts both directions (drift-conflict
survives the block; unscopable_diff still stamps `reason: landed_foreign` into
review-gate.md) — PASS on the reviewed content.

### 4. High — zero coverage of the live wires → **MOSTLY FIXED**

Three of the four wires are now exercised against the shipped source rather than
a reimplementation: `_pc_git_diff_names` and the landed-foreign block are both
`sed`-extracted out of `leadv2-dispatch-product-close.sh`, and the registry
admission/`check_writes` ops are called through the real
`leadv2-active-registry.sh`. The suite is registered in `run-core-offline.sh`.

Residual gap (not re-raised as a separate finding — it is the same finding
partially closed): no test sources `leadv2-dispatch-code.sh`, so the two
`leadv2_active_register … "" "" "" "${lane_writes}"` call sites (:5865, :6019)
remain unverified by execution. I checked the arg order by hand and it is
correct — `$5` daemon_mode `""` still resolves to `false` via `${5:-false}`,
`$6`/`$7` empty match the previous unset defaults, `$8` is writes — but an
arg-order regression there would still ship green. The H1 test reproduces the
two-phase *pattern* at registry level, not the dispatch-code wire.

## New finding introduced by the fixes

FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=2306 dimension=correctness desc=After the H4 narrowing, writeset_drift_conflict falls into the `!= partial_diff` reclassification branch and has its cause overwritten — a clean-committed lane is stamped terminal=no_work cause=empty_diff despite a non-empty diff and a real cross-lane collision.

Detail: the H4 fix correctly stops `writeset_drift_conflict` from becoming
`landed_foreign`, so it now reaches `if [[ -n "${blocked_reason}" ]]` at :2297
and immediately enters the `!= partial_diff` branch at :2306. That branch was
written for the empty-diff family and re-derives cause purely from lane
dirtiness:

- lane committed its work (the normal end state) → `_pc_lane_dirty` false →
  else-branch at :2382 → `_pc_terminal="no_work"; _pc_cause="empty_diff"`.
- lane still dirty with undeclared paths → :2369 → `cause=unscoped_lane_work`.

Either way the D6 diagnosis is lost. The BLOCK itself survives (exit 5, lane not
passed), which is why this is Medium and not High — but `no_work / empty_diff`
tells the lead "this lane produced nothing, re-dispatch it" for a lane that
produced a full diff and collided with a live peer's write set. The stale
comment at :2372 ("this branch only runs when blocked_reason==unscopable_diff")
is now false. Suggested shape: short-circuit `writeset_drift_conflict` past the
:2306 reclassification, the way `partial_diff` already is.

Not raised: I did not execute this path (it needs a full product-close run with
a live peer row); the conclusion is from reading :2183 → :2297 → :2306 → :2382
and the exhaustive assignment set above.

## Low

FINDING (Low): `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh`
is committed mode 100644 with a `#!/usr/bin/env bash` shebang. Harmless today —
`run-core-offline.sh:281` invokes it as `bash $TEST_DIR/…` — but it is the only
new test file in the tree without the exec bit, so a direct `./test-…` run
fails. Cosmetic.

## Checks run

- `bash -n` clean on all five changed/added shell files.
- Full new suite executed twice (HEAD content → 5/1; dirty worktree → 6/0).
- No secrets, no network, no VPS paths in the diff; registry writes stay inside
  the existing flock, and `check_writes` genuinely never touches `data`/`sessions`.

DELIVERABLE_COMPLETE
