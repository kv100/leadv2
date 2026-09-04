verdict: APPROVE
next_action: review_round_2

# developer.full.md — SKILL-USAGE-IS-UNMEASURED-01 / dispatch-a1e6520d

## What I found on arrival

`plugins/leadv2/scripts/leadv2-skill-usage-tally.sh` (header comment edit), `tests/run-all.sh`
(EXTRA_SUITE_MAP rows), and the three new files
(`leadv2-skill-telemetry-collect.sh`, `leadv2-skill-rollup.sh`, `test-skill-telemetry.sh`) plus
`.gitattributes` already existed on disk in this worktree, apparently from earlier work in this
same task lane. `bash -n` was clean on all of them, but the test suite was **RED: PASS=23 FAIL=16**.
My job was to diagnose and fix the failures, then complete acceptance/report/commit. Full report
with all command output lives at `docs/handoff/SKILL-USAGE-IS-UNMEASURED-01/report.md` — this file
covers the diagnosis and decisions; see the report for pasted command output.

## Root causes (3 real bugs, all fixed)

**1. Non-compact JSON in the collector (real production bug, fixed in the shipped script).**
`plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh` wrote records with
`json.dumps(rec, sort_keys=False)`, Python's default separators (`", "` / `": "` — space after
colon). The mission's own record spec, quoted verbatim in the mission text, uses compact JSON
(`{"event_id":"...","ts":"...",...}`, no space). All 16 test failures traced to this: the test's
`grep -c '"skill":"fixture-skill-ok"'` (no space) never matched
`"skill": "fixture-skill-ok"` (space) that the collector actually wrote — every row-count
assertion read "0" even though the rows existed with correct field values (confirmed by directly
inspecting the JSONL file after a bare collector run — 9/9 correct rows, right outcome/lane/phase
per row, just wrong-shaped JSON text). Fix: one line,
`json.dumps(rec, sort_keys=False, separators=(',', ':'))`. This is the fix that matters most: any
downstream consumer of this file (grep, jq without `-c` awareness, a future dashboard) that assumes
compact JSON — which the mission's own spec does — would have silently seen zero rows forever.

**2. Self-contradictory fixture for `fixture-skill-stale` (test bug, fixed in test setup only).**
The suite's own header comment says this fixture row exists to prove two things at once: (a) the
collector's `--since` window genuinely excludes an old transcript line from being collected in a
given run, and (b) the rollup correctly labels a skill with all-time history outside the *current*
rollup window as `INVOKED_PAST_ONLY`, never `NEVER_INVOKED`. These can't both be true of the *same*
collector-produced row: if (a) holds (the row never enters the JSONL via the real collector run),
then the rollup has zero rows for that skill in `alltime_rows` too, and `bucket_for_skill()`
correctly (per its own documented contract) returns `NEVER_INVOKED` — which is exactly what the
test observed and reported as a failure, but the *code* was behaving correctly; it was the fixture
that asked for two incompatible things from one artifact.

Fix: kept the existing assertion `n_stale == 0` (checked right after the real collector run — still
proves the collector's window filtering). Added, *after* that assertion (so it can't mask it), one
line directly appended to `$JSONL` standing in for "this row was captured by an earlier, wider
collector run, long before it aged past the window" — i.e. simulating pre-existing history, which
is exactly what a real deployed collector running periodically would eventually accumulate. This
is fixture setup, not a fake of collector or rollup logic (the WAVE4 constraint only forbids faking
the *scripts under test*, not seeding data through their own JSONL contract). Verified: the fixed
test now shows `history-only-outside-window skill is never mislabeled NEVER_INVOKED (got:
INVOKED_PAST_ONLY)`.

**3. M2 negative control's mutated script couldn't source its lock helper (test-harness bug).**
`event_id_for()` mutation copies `leadv2-skill-telemetry-collect.sh` to a scratch file under
`$ROOT`. That script computes `SCRIPT_DIR` from its own `${BASH_SOURCE[0]}` and sources
`"$SCRIPT_DIR/leadv2-portable-lock.sh"` — which doesn't exist next to the scratch copy. Every
mutated-script invocation failed immediately with `lv2_lock_wait: command not found` before the
mutation itself could even be exercised, so the negative control was accidentally testing "does the
mutated script's sourcing fail" instead of "does idempotency break." Fix: `cp
"${SCRIPTS_DIR}/leadv2-portable-lock.sh" "$ROOT/leadv2-portable-lock.sh"` before invoking the
mutated copy. Verified: `M2 baseline(GREEN) rows_stable  mutated(RED) rc=0 n1=9 n2=18` — the
mutation now visibly breaks dedup (row count doubles on rerun) exactly as M2 is meant to prove.

No production assertion was weakened by any of these three fixes — #1 is a real script fix, #2 and
#3 are test-setup fixes that make the test measure what its own stated intent says it should
measure, not a loosened bar.

## Self-check (MD-04 / falsification)

- `bash -n` and `/bin/bash -n` (bash 5.3 vs macOS system bash 3.2.57) on every changed/created
  `.sh` file: all rc=0. No Python files were changed directly (the Python lives in heredocs inside
  the shell scripts and is exercised end-to-end by the passing suite).
- `bash plugins/leadv2/scripts/tests/test-skill-telemetry.sh`: RED (23/39, PASS=23 FAIL=16) before
  the fixes, GREEN (39/39) after. Both negative controls (M1 bucketing, M2 idempotency) confirmed
  to actually flip red under their mutation, not just "the mutated script crashed" — verified their
  RED-side output shows the *intended* wrong behavior (wrong bucket / duplicated rows), not an
  unrelated setup error.
- Live acceptance commands run for real against this repo (not simulated): 1146 real invocation
  rows collected from `~/.claude/projects` transcript history in one retroactive run, 288 hits for
  `leadv2-subagent-protocol` (mission's floor was ≥200), `universe=89` in the real rollup MD,
  `NEVER_INVOKED` count 74, a dynamically-picked NEVER_INVOKED skill (`audit-cluster`) confirmed to
  have zero JSONL rows.
- `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` (after staging only my
  files) selected exactly `test-skill-telemetry.sh` — proves the `EXTRA_SUITE_MAP` wiring works.

## Deviations from the mission's literal acceptance commands (both explained, both real findings)

- **Acceptance A** (spawn a nested `claude -p ... bypassPermissions` session) was not run: spawning
  a permission-bypassed nested Claude session from inside an already-dispatched subagent is outside
  this role's scope and this repo's nested-spawn guardrails (see `NESTED-SPAWNS.md` in the
  subagent protocol). S1a (explicit `Skill` tool_use) is instead exercised by the fixture suite
  directly against real tool_use/tool_result JSONL shapes, and the dominant S1b path is exercised
  retroactively against 1146 real rows (acceptance C, run for real).
- **Acceptance F** as literally written (`tests/run-all.sh --scope changed --dry-run`) fails:
  `run-all.sh` has no `--dry-run` flag (`run-all: unknown argument: --dry-run`). The suite's own
  §F check (and its own comment) already uses the correct mechanism,
  `LEADV2_RUN_ALL_SELECT_ONLY=1`, which I used for my own proof too. This is a stale command in the
  mission text, not a bug in the deliverable.

## Files touched (final)

Created: `plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh`,
`plugins/leadv2/scripts/leadv2-skill-rollup.sh`,
`plugins/leadv2/scripts/tests/test-skill-telemetry.sh`, `.gitattributes`,
`docs/leadv2/skill-invocations.jsonl` (real generated data, 1150 lines),
`docs/leadv2/skill-usage-rollup.md` (real generated data),
`docs/handoff/SKILL-USAGE-IS-UNMEASURED-01/report.md`,
`docs/handoff/dispatch-a1e6520d/developer.{summary,full}.md`.
Edited: `plugins/leadv2/scripts/leadv2-skill-usage-tally.sh` (header comment only, no logic
change), `tests/run-all.sh` (two `EXTRA_SUITE_MAP` rows only).

Not staged/committed: the pre-existing dirty runtime-state files under `docs/leadv2/`
(`active.yaml`, `bus.jsonl`, `merge-queue.jsonl`, `open-threads.md`, `questions`,
`.bus-offsets`, `.bus.lock`, `.merge.lock`, `active.yaml.lock`) — these were already modified in
this worktree by the live orchestrator/bus traffic before this task started and are not part of
this diff (pathspec-committed only my own files, per repo convention on shared lane worktrees).

## Left alone

Step 2 (acting on the measurement — consolidation, rewiring, promotion, PreToolUse `Skill` hook)
is untouched, as scoped. No skill was deleted, inlined, or had its content edited.

DELIVERABLE_COMPLETE
