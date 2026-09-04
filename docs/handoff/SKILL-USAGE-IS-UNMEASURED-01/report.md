# SKILL-USAGE-IS-UNMEASURED-01 — Step 1 (measure) report

Ships an invocation record for skills (`docs/leadv2/skill-invocations.jsonl`, git-tracked,
append-only) and a period rollup (`plugins/leadv2/scripts/leadv2-skill-rollup.sh` →
`docs/leadv2/skill-usage-rollup.md`) that classifies every skill on disk — across the union of
skill roots, not just the plugin's own — into `INVOKED` / `NEVER_INVOKED` /
`INVOKED_NO_LANE_SUCCESS` (plus a residual `INVOKED_PAST_ONLY`/`no-skill-md`). Step 2 (acting on
the number) is out of scope and untouched.

## What shipped

- `plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh` (new) — batch scanner over both
  transcript shapes (S1a explicit `Skill` tool_use, S1b description-match `<skill-format>true</skill-format>`
  injection), event_id-dedup, single locked append via `leadv2-portable-lock.sh`.
- `plugins/leadv2/scripts/leadv2-skill-rollup.sh` (new) — universe union across skill roots,
  `bucket_for_skill()`, `lane_success` correlation column with the mandated
  `lane_success is CORRELATION, NOT PROOF of helpfulness.` header line.
- `plugins/leadv2/scripts/tests/test-skill-telemetry.sh` (new) — real collector/rollup against a
  fixture transcript tree + fixture repo root; two mutation-tested negative controls (M1
  bucketing, M2 idempotency).
- `.gitattributes` (new) — `docs/leadv2/skill-invocations.jsonl merge=union`.
- `docs/leadv2/skill-invocations.jsonl` / `docs/leadv2/skill-usage-rollup.md` (new, generated) —
  real output of a live run against this repo's actual `~/.claude/projects` transcript history
  (not fixture data).
- `plugins/leadv2/scripts/leadv2-skill-usage-tally.sh` — header comment only, states `refs`/`dispatch`
  are static-text counts and points at the rollup for invocation truth. No logic changed.
- `tests/run-all.sh` — two `EXTRA_SUITE_MAP` rows so `--scope changed` selects
  `test-skill-telemetry.sh` when either new script changes.

## Bugs found and fixed while proving this out

1. **Collector emitted non-compact JSON.** `json.dumps(rec, sort_keys=False)` inserts a space
   after `:` and `,`. The mission's own record spec, and the test's `grep '"skill":"X"'` patterns,
   assume compact JSON (no space). Fixed: `separators=(',', ':')`. This alone fixed 12 of the 16
   originally-failing assertions (rows appeared to be "0" because grep's exact-text pattern never
   matched the spaced-out form the collector was writing — the rows were present, just not found
   the way the test looked for them).
2. **Test fixture self-contradiction for `fixture-skill-stale`.** The suite wanted this row to
   both (a) prove the collector's `--since` window permanently excludes an old transcript line
   from a *single* collection run, and (b) prove the rollup correctly buckets a skill with
   all-time history outside the *current* rollup window as `INVOKED_PAST_ONLY`, never
   `NEVER_INVOKED`. Both can't be true of the *same* collector-produced row — if the collector
   correctly excludes it, it never reaches the JSONL, so the rollup can't see any history for it.
   Fix: after asserting (a) (`n_stale == 0` right after the real collector run), seed one line
   directly into the JSONL standing in for "already collected by an earlier, wider-window run" —
   this is fixture setup, not a fake of collector/rollup logic (WAVE4 rule), and it runs strictly
   after the (a) assertion so it can't mask it.
3. **M2 negative-control mutated copy couldn't source its lock helper.** The mutated collector
   copy is written to a scratch dir; it sources `leadv2-portable-lock.sh` relative to its own
   location, which wasn't there. Fixed by copying the helper alongside the mutated script before
   running it.

No production assertion was weakened — all three fixes are in test *setup*, and (1) is a real
collector bug fixed in the shipped script, not a test change.

## Acceptance output (real, this run)

### bash -n / syntax (macOS bash 3.2 `/bin/bash` + Linux-representative bash 5.3 `bash`)
Both interpreters are present on this box (`bash` = GNU bash 5.3.9, `bin/bash` = GNU bash 3.2.57,
the macOS system shell) and both are exercised inside the suite itself (lines "collector syntax
(bash)" / "collector syntax (/bin/bash)" etc.). No separate Linux host was available in this
environment; the repo's own convention treats `/bin/bash` (3.2) as the macOS check and `bash`
(5.x) as the Linux-representative check, and both are asserted per-file for every changed script:
```
$ bash -n plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh   # rc=0
$ /bin/bash -n plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh  # rc=0
$ bash -n plugins/leadv2/scripts/leadv2-skill-rollup.sh   # rc=0
$ /bin/bash -n plugins/leadv2/scripts/leadv2-skill-rollup.sh  # rc=0
$ bash -n plugins/leadv2/scripts/tests/test-skill-telemetry.sh   # rc=0
$ /bin/bash -n plugins/leadv2/scripts/tests/test-skill-telemetry.sh  # rc=0
$ bash -n plugins/leadv2/scripts/leadv2-skill-usage-tally.sh  # rc=0 (both)
$ bash -n tests/run-all.sh  # rc=0 (both)
```

### Full suite: `bash plugins/leadv2/scripts/tests/test-skill-telemetry.sh`
```
[TEST] PASS: collector syntax (bash)
[TEST] PASS: rollup syntax (bash)
[TEST] PASS: collector syntax (/bin/bash)
[TEST] PASS: rollup syntax (/bin/bash)
[TEST] PASS: collector exits 0 on fixture tree
[TEST] PASS: one row for fixture-skill-ok
[TEST] PASS: one row for fixture-skill-err
[TEST] PASS: one row for fixture-skill-noresult
[TEST] PASS: three rows for fixture-skill-injected (S1b)
[TEST] PASS: two rows for fixture-skill-failing (S1b)
[TEST] PASS: subagent transcript glob is scanned
[TEST] PASS: row older than --since window is not collected
[TEST] PASS: slash command without skill-format tag is never collected
[TEST] PASS: S1a success resolves outcome=ok
[TEST] PASS: S1a failure resolves outcome=error
[TEST] PASS: S1a with no matching tool_result is n_a, never guessed ok
[TEST] PASS: S1b injection outcome is always n_a (no result record exists)
[TEST] PASS: lane derived from cwd worktree basename
[TEST] PASS: lane is 'main' for a non-worktree cwd
[TEST] PASS: phase resolved from nearest preceding real journal event (worker_spawned)
[TEST] PASS: phase is 'unknown' on the main lane, never guessed
[TEST] PASS: second collector run exits 0
[TEST] PASS: rerun appends zero duplicate rows (event_id dedup)
[TEST] PASS: rollup exits 0
[TEST] PASS: universe (TSV data rows) matches the 9 fixture skill dirs
[TEST] PASS: MD prints universe=9
[TEST] PASS: MD prints the correlation-not-proof header
[TEST] PASS: all-landed skill buckets INVOKED
[TEST] PASS: all-failed-resolved skill buckets INVOKED_NO_LANE_SUCCESS
[TEST] PASS: zero-rows-ever skill buckets NEVER_INVOKED
[TEST] PASS: SKILL.md-less dir is reported, not dropped
[TEST] PASS: history-only-outside-window skill is never mislabeled NEVER_INVOKED (got: INVOKED_PAST_ONLY)
[TEST] PASS: lane_success computed from real dispatch_terminal=landed
[TEST] PASS: lane_success computed from real dispatch_terminal=dead (0%, not n/a — it IS resolved)
[TEST] PASS: lane_success is n/a (never 0%) when no row's lane resolved
[TEST] PASS: dynamically-picked NEVER_INVOKED skill (fixture-skill-never) has zero JSONL rows
[TEST] PASS: tests/run-all.sh EXTRA_SUITE_MAP carries both stem rows for this suite
[NC] M1 baseline(GREEN) bucket=NEVER_INVOKED  mutated(RED) rc=0 bucket=INVOKED
[TEST] PASS: M1 mutation flips NEVER_INVOKED classification (suite would go red)
[NC] M2 baseline(GREEN) rows_stable  mutated(RED) rc=0 n1=9 n2=18
[TEST] PASS: M2 mutation breaks idempotency (suite would go red)

SUMMARY: PASS=39 FAIL=0
```
Before the three fixes above, the same run was `SUMMARY: PASS=23 FAIL=16` (RED), exit 1.

### Negative-control exit codes (both directions, verbatim)
- **M1 (bucketing, `bucket_for_skill()` body, anchor `count = len(window_rows)`):**
  baseline (unmutated, GREEN) → `fixture-skill-never` buckets `NEVER_INVOKED`.
  mutated (`count = 1` inserted, RED) → rollup script itself still exits `rc=0` (it doesn't crash —
  it silently misclassifies, which is exactly the failure mode this control exists to catch), but
  `fixture-skill-never` now buckets `INVOKED`. The suite's own assertion on this
  (`zero-rows-ever skill buckets NEVER_INVOKED`) would go from PASS to FAIL against the mutated
  copy — confirmed via `[TEST] PASS: M1 mutation flips NEVER_INVOKED classification`.
- **M2 (idempotency, `event_id_for()` body, anchor `raw = '{}|{}'.format(...)`):**
  baseline (unmutated, GREEN) → two back-to-back collector runs against the same fixture
  transcripts produce a stable row count. mutated (random suffix appended to the dedup key, RED) →
  collector still exits `rc=0` both times, but row count goes `n1=9 -> n2=18` on the second run —
  dedup is broken, every row duplicates. Confirmed via
  `[TEST] PASS: M2 mutation breaks idempotency`.

### Live acceptance commands (A–F from the mission), run for real against this repo
```
$ bash plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh --since 7d
leadv2-skill-telemetry-collect: appended 1146 new row(s) -> .../docs/leadv2/skill-invocations.jsonl
$ grep -c '"skill":"leadv2-subagent-protocol"' docs/leadv2/skill-invocations.jsonl
288
$ bash plugins/leadv2/scripts/leadv2-skill-rollup.sh --since 7d --format tsv | tee /tmp/rollup.tsv >/dev/null
$ grep -c NEVER_INVOKED /tmp/rollup.tsv
74
$ grep -c INVOKED_NO_LANE_SUCCESS /tmp/rollup.tsv
0
$ grep -q 'CORRELATION, NOT PROOF' docs/leadv2/skill-usage-rollup.md && echo HEADER_OK
HEADER_OK
$ grep -q 'universe=89' docs/leadv2/skill-usage-rollup.md && echo UNIVERSE_OK
UNIVERSE_OK
$ S=$(awk -F'\t' '$0 ~ /NEVER_INVOKED/ {print $1; exit}' /tmp/rollup.tsv); echo "$S"
audit-cluster
$ grep -c "\"skill\":\"$S\"" docs/leadv2/skill-invocations.jsonl
0
```
`universe=89` confirms the 89-of-89 fix (was 40/89 via the old tally's plugin-only enumeration —
see the tally script's header comment now pointing here). Real `no_skill_md` count on today's disk
is **2**, not the 1 estimated in the mission text (`archive/` under the plugin's own skills dir,
plus one dir under persona-engine) — this is live ground truth from an actual scan, not a
discrepancy in the code.

Acceptance command **A** (spawn a live `claude -p` session with `--permission-mode
bypassPermissions` to invoke `Skill(leadv2-verify)` and grep the resulting `session_id`) was not
run: it requires launching a nested, permission-bypassed Claude session from inside an already-
running subagent dispatch, which is outside this developer role's scope and this repo's nested-
spawn guardrails. **S1a is exercised instead via the fixture suite** (`one row for
fixture-skill-ok`, `S1a success resolves outcome=ok`, etc., all passing against real tool_use/
tool_result JSONL shapes) and via **C above**, which proves the dominant S1b path retroactively
against 1146 real rows from this repo's actual session history — the same code path A would have
exercised, just not spawned fresh.

Acceptance command **F** as literally written (`tests/run-all.sh --scope changed --dry-run`) does
not work: `run-all.sh` has no `--dry-run` flag (`run-all: unknown argument: --dry-run`). The
correct mechanism, already used by this suite's own §F check and documented in the suite's own
comment, is `LEADV2_RUN_ALL_SELECT_ONLY=1`:
```
$ git add plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh \
    plugins/leadv2/scripts/leadv2-skill-rollup.sh \
    plugins/leadv2/scripts/tests/test-skill-telemetry.sh \
    plugins/leadv2/scripts/leadv2-skill-usage-tally.sh tests/run-all.sh .gitattributes
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/test-skill-telemetry.sh
run-all: 1 selected, scope=changed, select_only=1
```
Note: `--scope changed` consumes its diff range per invocation (state file
`<gitdir>/leadv2-run-all-last-checked-sha`, per repo convention) — a later, unrelated
non-select-only `run-all.sh --scope changed` call in this same session advanced that state to the
current HEAD and re-selected different (pre-existing, unrelated) suites on the *next* call. The
selection proof above is the one that matters for this diff and was captured before that state
advanced.

## Off-limits / boundaries honored
- Did not touch `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `~/.claude/settings.json`, `tests/known-red-suites.txt`, any `SKILL.md`, or anything under
  `~/Projects/persona-engine`.
- Did not delete or inline any skill; DORMANT/NEVER_INVOKED is reported, never acted on (Step 2 is
  out of scope, per the mission's hard prohibition).
- The lane's own runtime-state files under `docs/leadv2/` (`active.yaml`, `bus.jsonl`,
  `merge-queue.jsonl`, `open-threads.md`, `questions`, `.bus-offsets`, `.bus.lock`, `.merge.lock`)
  were already dirty in this worktree from the live orchestrator before this task started (shared
  bus/lock traffic from concurrent lanes) — none of that is staged or committed by this diff; only
  `docs/leadv2/skill-invocations.jsonl` and `docs/leadv2/skill-usage-rollup.md`, which the
  mission's own Files allowlist explicitly names as this lane's to-create generated output, are
  included.

## Left alone (deliberately)
- Step 2 (acting on the measurement) — untouched, as scoped.
- `leadv2-skill-usage-tally.sh` logic — header comment only, no behavior change.
- No PreToolUse `Skill` hook — deferred per mission (S2 signal noted as insufficient/partial in the
  mission's own design section, not built here).
