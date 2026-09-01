# TESTS-POLLUTE-REAL-JOURNAL-01 — the offline test suite writes worker_terminal rows into the REAL event journal

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TESTS-POLLUTE-REAL-JOURNAL-01`

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-events.sh,plugins/leadv2/scripts/tests/,tests/run-all.sh,docs/handoff/TESTS-POLLUTE-REAL-JOURNAL-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured, 2026-09-01

The lead ran `plugins/leadv2/scripts/tests/run-core-offline.sh` on main. Within three minutes,
`~/.claude/cache/leadv2-events/leadv2.jsonl` — the **real, shared, cross-repo** event journal — grew
fourteen `worker_terminal` rows for tasks that do not exist:

```
9929fa65 dead:all_arms_unavailable          0d04b7c6 dead:all_arms_unavailable
9528bf08 refused:all_arms_exhausted_v2      0afecbb1 refused:all_arms_not_dispatchable_v2
41f5903f refused:all_arms_quota_locked      97f029b5 refused:all_arms_excluded
6ff36155 refused:all_arms_capped            812a0d0d refused:all_arms_exhausted_quota
fb2461e6 659d221e 872cc544 4913e85d         dead:all_arms_unavailable
```

These are fixture task ids from the dispatch arm-exhaustion tests. They are indistinguishable, in the
journal, from a real production lane dying with every arm unavailable.

## Why this is not cosmetic

1. **It fakes a catastrophic signal.** "All arms unavailable" is the shape of a total dispatch
   outage. Anything that reads the journal — a monitor, a pulse, a status table, the lead — now sees
   a fleet-wide outage that never happened. The lead was watching this journal at the time and took
   fourteen false alarms.
2. **It corrupts every metric derived from the journal.** Arm-health, failure rates, and any future
   routing decision that learns from outcomes are all trained on fixture rows.
3. **It is cross-repo.** The journal lives under `~/.claude/cache`, not in a worktree, so running the
   suite in one repo poisons the signal in all of them.

## [Critical] 1 — a test must never write to the real journal

Find every path by which a test reaches the real journal and close it at the writer, not at each
call site. The writer should refuse — loudly, non-zero — when it is asked to append to the real
journal from a test context, rather than relying on each suite to remember to redirect.

Decide from the runtime how a test context is identified, and say so in `report.md`. An env var that
the suite sets is fine; an env var that the suite *forgets* to set is the bug being fixed, so the
default must be safe, not the exception.

## [Critical] 2 — clean what is already there

The fourteen rows above are in the journal now, along with however many earlier runs left behind.
Provide a way to identify fixture-origin rows and remove them, and report how many were found. If
they cannot be distinguished from real rows after the fact, say that plainly in `report.md` — that
is itself the argument for §1.

## [Medium] 3 — the same question for every other shared sink

The journal is one shared, out-of-tree file the suite writes to. Census the others (caches, ledgers,
lock files, telemetry CSVs under `~/.claude`) and report which of them a test run can currently
mutate. Fix the ones in this lane's write set; list the rest.

## Acceptance

1. a test that emits a lane terminal ⇒ the real journal is byte-identical before and after;
2. the same test ⇒ its row IS written to the redirected fixture journal (it must still be testable);
3. the writer invoked from a test context without a redirect ⇒ refuses non-zero, does not append;
4. a production call path ⇒ still writes to the real journal (regression guard);
5. the cleanup identifies the fixture rows described above and leaves real rows untouched.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the test-context refusal must turn case 3 red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Never delete or truncate the real journal wholesale; §2 is surgical or it is not done.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

Running the test suite leaves the shared event journal untouched, a test that tries to write to it
fails loudly instead of silently, the fixture rows already in it are gone, and a monitor watching
that journal only ever reports things that really happened.
