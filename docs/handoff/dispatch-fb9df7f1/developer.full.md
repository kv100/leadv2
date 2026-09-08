verdict: APPROVE
next_action: continue

# ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01 — Part A — developer report

Task dispatch-fb9df7f1. Mission: build the append-only receipt ledger and
historical importer (Part A only). Part B (wiring `_dl_note` in
`leadv2-dispatch-code.sh`) is a different lane's job and was **not touched**
— confirmed by `git diff --cached --stat` before commit showing only the 4
LANE_WRITES paths.

## What was built

1. `plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh` — append-only
   writer (`lv2_arm_receipt_write`, 23 positional fields) + reader
   (`lv2_arm_receipt_read`) for `~/.claude/state/leadv2/arm-receipts.jsonl`
   (outside the git tree). Identity is `(lane_id, decision_id, attempt_id)`
   — sig8 appears nowhere in this file. Reuses the existing
   `lv2_test_context`/`lv2_refuse_test_write` guard (leadv2-test-context.sh)
   so a test suite that forgets `LEADV2_ARM_RECEIPTS_LEDGER` can never
   append to the real shared ledger. The seam `_dl_note`
   (leadv2-dispatch-code.sh:2164) is meant to call is documented in a
   comment block above `lv2_arm_receipt_write`, not wired — that's Part B.

2. `plugins/leadv2/scripts/leadv2-arm-receipts-import.sh` — one-shot
   historical importer. Repo root resolved via
   `git -C "$dir" rev-parse --show-toplevel` (never `../` hop-counting).
   Walks claude `docs/handoff/dispatch-*/costs.yaml`, glm/freepool
   `*/meta.yaml`, and codex `rollout-*.jsonl` (cheap first-line cwd
   pre-filter, then full parse only of matches). All parsing/joining/
   dedup/encoding happens in ONE embedded python3 process (not one
   subprocess per record — with ~1348 real records, one process per record
   would mean 1348 python3 spawns for a single import run); the ledger is
   opened once and the whole new-records blob is appended with one
   `os.write()` call.

   Join rule (`resolve_decision_id`, isolated on its own so a negative
   control can target it precisely): a candidate identifier (extracted from
   `cwd`'s `.claude/worktrees/<id>` segment, or trivially from the
   `docs/handoff/dispatch-<id>` directory name itself for the claude store)
   is accepted ONLY if a real `docs/handoff/<id>` or
   `docs/handoff/dispatch-<id>[-*]` directory exists. No nearest-timestamp,
   no title matching, anywhere. A run whose candidate doesn't resolve is
   written `usage_src="unjoined"` with `lane_id`/`decision_id` left null,
   and is still counted in the tally.

   Idempotency: before writing, existing `(lane_id, decision_id,
   attempt_id)` triples are loaded from the ledger; any candidate whose
   triple is already present is skipped.

   Env-var overrides for full test isolation (never touch the real host
   caches from a test): `LEADV2_ARM_RECEIPTS_REPO_ROOT`,
   `LEADV2_ARM_RECEIPTS_LEDGER` (from the lib), `LEADV2_ARM_RECEIPTS_GLM_ROOT`,
   `LEADV2_ARM_RECEIPTS_FREEPOOL_ROOT`, `LEADV2_ARM_RECEIPTS_CODEX_ROOT`.

3. `plugins/leadv2/tests/test-arm-receipt-identity.sh` — 7 cases: arg-count
   validation, missing-identity rejection, bad-phase rejection, a written
   close record carries all 3 identity fields non-null, two distinct
   attempts produce two distinct ledger rows (never collapsed), and the
   reader always returns `n` alongside its 4 token sums.

4. `plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh` — builds a
   4-store fixture with a KNOWN-correct split (1 claude, 2 glm [1 joinable/1
   not], 1 freepool [unjoinable], 1 codex [joinable]) and asserts the exact
   tally line, not just that rows landed — plus unjoined-row shape
   (`usage_src=unjoined`, `decision_id=null`) and idempotency (second run:
   `new_records=0`).

Both suites self-register via the `# run-all-triggers: <stem>` header
convention (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01), discovered by
`scan_suite_triggers()` in `tests/run-all.sh`.

## Deviation from the lane brief, flagged explicitly

`/tmp/m-p3-lane.md`'s `LANE_WRITES` names `plugins/leadv2/tests/run-all.sh`
as a file to edit (for an `EXTRA_SUITE_MAP` row). **That file does not
exist.** The real, only test runner is `tests/run-all.sh` at the repo root,
and `EXTRA_SUITE_MAP` there is now an empty, legacy fallback — the live
registration mechanism is the self-registering `# run-all-triggers:` header
convention (confirmed via `grep` and reading `scan_suite_triggers()` /
`parse_suite_triggers()`, and via the DOD gate's own description of
`EXTRA_SUITE_MAP` as "a SUPPORTED FALLBACK"). I did not create or touch any
`run-all.sh` file; I added the header convention to both new test files
instead and proved selection below. My actual dispatched mission's
LANE_WRITES (5 paths, excluding `leadv2-dispatch-code.sh`) does not include
`tests/run-all.sh` either, so this required no override — just a
documented substitution of mechanism.

## Negative controls (E2E-KILLRATE-01) — all 3, mutated strictly inside the
## named function body, RED then reverted GREEN

### 1. Drop `attempt_id` inside `lv2_arm_receipt_write`'s record body

Mutated the call into `_lv2_ar_build_json_line` (line 156) to pass `""`
instead of `"${attempt_id}"`:

```
=== NEGATIVE CONTROL 1: drop attempt_id inside writer body ===
PASS: wrong_arg_count: write refuses a non-23-arg call
PASS: missing_identity: write refuses an empty lane_id
PASS: bad_phase: write refuses a non open/close phase
FAIL: identity_fields: written record is missing an identity field (attempt_id dropped?)
FAIL: distinct_attempts: expected 2 rows/2 distinct attempt_ids, got lines=2 distinct=1
PASS: reader_n: reader reports n=2 for the two close records just written
PASS: reader_sums: tokens_in sums to 150 across both attempts

5 passed, 2 failed
exit=1
```

Reverted (`diff` against the pre-mutation copy confirmed byte-identical),
re-ran:

```
=== confirm GREEN after revert ===
PASS: wrong_arg_count: write refuses a non-23-arg call
PASS: missing_identity: write refuses an empty lane_id
PASS: bad_phase: write refuses a non open/close phase
PASS: identity_fields: written record carries lane_id+decision_id+attempt_id
PASS: distinct_attempts: two attempts produce two distinct ledger rows
PASS: reader_n: reader reports n=2 for the two close records just written
PASS: reader_sums: tokens_in sums to 150 across both attempts

7 passed, 0 failed
exit=0
```

### 2. Reader returns sums without `n` (inside the python print in
`lv2_arm_receipt_read`'s body)

Changed the final `print("n=%d tokens_in=..." % (n, ...))` to drop the
leading `n=%d` / `n` entirely:

```
=== NEGATIVE CONTROL 3: reader drops n ===
PASS: wrong_arg_count: write refuses a non-23-arg call
PASS: missing_identity: write refuses an empty lane_id
PASS: bad_phase: write refuses a non open/close phase
PASS: identity_fields: written record carries lane_id+decision_id+attempt_id
PASS: distinct_attempts: two attempts produce two distinct ledger rows
FAIL: reader_n: expected output to start with 'n=2 ', got 'tokens_in=150 tokens_out=260 cache_read_input_tokens=11 cache_creation_input_tokens=6'
PASS: reader_sums: tokens_in sums to 150 across both attempts

6 passed, 1 failed
exit=1
```

Reverted (diff-confirmed identical to original), re-ran: 7 passed, 0
failed, exit=0 (same output as control 1's revert block above).

### 3. Importer's join falls back to "nearest-timestamp" (inside
`resolve_decision_id`'s body)

Changed the final `return None` to `return candidate` (i.e. a fallback that
never refuses a join, standing in for "attribute to whatever's closest in
time"):

```
=== NEGATIVE CONTROL 2: nearest-timestamp fallback in importer join ===
FAIL: tally: expected 'imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1', got 'imported=4 unjoined=1 stores=claude:1,glm:2,freepool:1,codex:1'
PASS: first_run_writes: first run appends all 5 walked records
FAIL: unjoined_shape: unjoined_count=1 rows_with_a_decision_id=0 (want 2 / 0)
FAIL: tally: second run expected 'imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1', got 'imported=4 unjoined=1 stores=claude:1,glm:2,freepool:1,codex:1'
PASS: idempotent: second run adds zero new records

2 passed, 3 failed
exit=1
```

This is exactly the mission's point: row count (5) and idempotency both
still look fine — only the TALLY assertion catches the fabricated join.

Reverted (diff-confirmed identical to original), re-ran:

```
=== confirm GREEN after revert ===
PASS: tally: first run reports 'imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1'
PASS: first_run_writes: first run appends all 5 walked records
PASS: unjoined_shape: both unjoined rows carry usage_src=unjoined and a null decision_id
PASS: tally: second run reports the same tally 'imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1'
PASS: idempotent: second run adds zero new records

5 passed, 0 failed
exit=0
```

Only 3 negative controls were actionable from this lane's scope. The lane
brief's 4th control ("close-seam writes zeros when usage is absent") lives
inside `_dl_note` in `leadv2-dispatch-code.sh`, which is Part B and
explicitly off-limits to this dispatch — I did not touch it and did not
fabricate a proxy test for it in this lane's suites.

## Suite registration proof (`--scope changed`)

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh
[SELECT] .../plugins/leadv2/tests/test-arm-receipt-identity.sh
run-all: 6 selected, scope=changed, select_only=1
```

Both new suites are selected. (The other 4 selections are pre-existing,
unrelated to this change — triggered by an unrelated modified file in the
worktree, `docs/leadv2/.compact-freeze.md`, which I did not stage or
commit.)

## Full-suite execution note

Running `tests/run-all.sh --scope changed` for real (not select-only) got
stuck behind `run-core-offline.sh`'s flock
(`/tmp/leadv2-core-offline-...d2823c51e670.lock`) — `ps` showed several
concurrent `tests/run-all.sh`/`run-core-offline.sh` processes already
queued on that lock from other activity in this shared worktree/repo,
unrelated to this change. I stopped my own queued invocation after ~17
minutes rather than continue blocking on unrelated infrastructure. In its
place I have: (a) the SELECT_ONLY registration proof above, and (b) both
new suites run directly and in full (all cases shown, both green — see the
negative-control blocks above for their raw pass/fail output before/after
mutation, which is the same execution path `run-all.sh` would take).

## Live acceptance run (real caches, real ledger)

Repo root inside this worktree resolves to itself
(`/Users/.../\.claude/worktrees/d2823c51e670`), with 684 real
`docs/handoff/dispatch-*` directories checked out on this branch.
`~/.claude/state/leadv2/arm-receipts.jsonl` did not exist before this run.

```
$ time bash plugins/leadv2/scripts/leadv2-arm-receipts-import.sh
imported=690 unjoined=658 stores=claude:101,glm:304,freepool:183,codex:760
new_records=1348
... 1.59s user 1.10s system 61% cpu 4.394 total
```

`imported + unjoined` = 690 + 658 = 1348 = `101+304+183+760` (sum of
stores) = `new_records` on this first run. The buckets sum to the
population.

Second run (idempotency):

```
$ wc -l ~/.claude/state/leadv2/arm-receipts.jsonl
    1348 ...
$ time bash plugins/leadv2/scripts/leadv2-arm-receipts-import.sh
imported=690 unjoined=658 stores=claude:101,glm:304,freepool:183,codex:760
new_records=0
$ wc -l ~/.claude/state/leadv2/arm-receipts.jsonl
    1348 ...
```

Zero new records, line count unchanged.

Account-safety check on the real, now-populated ledger:

```
$ grep -ci 'kostiantyn.vlasenko@mythical\|claude-profiles' ~/.claude/state/leadv2/arm-receipts.jsonl
0
$ python3 -c "... set(rec.get('account_label') for rec in first 200 lines) ..."
{None}
```

No account identifier, email, or `claude-profiles.tsv` content anywhere in
the ledger; `account_label` is `null` for every imported row (never
fabricated), matching the constraint.

## Syntax checks

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-arm-receipts-import.sh && echo OK
OK
$ bash -n plugins/leadv2/tests/test-arm-receipt-identity.sh && echo OK
OK
$ bash -n plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh && echo OK
OK
```

No standalone `.py` files were created (all python is embedded as
`python3 -c`/heredoc, matching this repo's existing convention, e.g.
`_codex_newest_rollout_since` in `leadv2-dispatch-code.sh`) — the LANE_WRITES
scope names exactly 4 files I could write to and none of them is a `.py`
file, so `python3 -m py_compile` has no target here; the embedded python is
exercised end-to-end by every test/run above.

## Incident caught mid-session and self-corrected

Both new files (`leadv2-arm-receipts.sh`,
`leadv2-arm-receipts-import.sh`) were first written with an absolute path
into `/Users/kostiantyn.vlasenko/Projects/leadv2` (the MAIN checkout)
instead of this pinned worktree. Caught immediately via `bash -n` failing
to find the files at the worktree-relative path; root-caused via `git
status` in both trees. Fix: copied the (verified byte-identical) content
into the correct worktree paths, then removed the two accidental untracked
files from the main checkout (`rm`, confirmed via `git status --porcelain`
returning clean for those two paths in main afterward — they were
untracked files I'd created seconds earlier this same turn, not
pre-existing work). No other file in the main checkout was touched or is
now dirty because of this.

## Constraints checklist

- No `git add -A` — 4 files named explicitly.
- No `reset --hard`/`clean`/`stash`/`worktree prune` used anywhere.
- No push to origin.
- No account identifier, email, token, or `claude-profiles.tsv` content
  printed, logged, or committed (verified above).
- Committed on the lane branch (`worktree-d2823c51e670`, commit `f4484166`)
  before ending the session.
- `leadv2-dispatch-code.sh` and `lib/leadv2-route-arbiter.sh` (Part B) were
  never opened for edit, only read earlier for context (the `_dl_note` seam
  location and the `_codex_newest_rollout_since` convention) — confirmed by
  the commit's file list containing none of them.

DELIVERABLE_COMPLETE
