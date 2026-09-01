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

## [Critical] 0 — the same leak has switched freepool OFF for real work

This is the highest-value consequence and it was found by asking why every dispatch today picked
GLM. The arbiter was excluding freepool with `util_freepool=100`. Asked directly, its gate said:

```
[freepool-gate] rolling window breach: error_rate=0.53 > max=0.3
[freepool-gate] refused: gate_broken
```

So freepool has been circuit-broken out of routing. The evidence says the breaker was tripped by our
own test suite, not by freepool:

```
~/.claude/leadv2-state/freepool-arm-state.json     200 records
failures with latency_s == 0.0                     55 of 61
failure spike                                      2026-09-01 11:00 (14 fails / 15 ok in one hour)
```

- A failure at **latency 0.0** never reached the network. Real provider failures cost time; these
  cost none, which is the signature of a synthetic record.
- The 11:00 spike is exactly when the lead ran `run-core-offline.sh`.
- **23 test files exercise freepool; exactly 1 redirects `LEADV2_FREEPOOL_STATE_DIR`.** The other 22
  write their synthetic outcomes into the real state file.

So every full test run degrades the live routing decision, and a long enough CI day disables a whole
provider arm for production work. Fixing this is what puts freepool back in the ladder — never a
hand-edit of the threshold, and never an exclusion of the arm.

Treat the state file exactly like the journal in §1: the writer refuses a test-context write to the
real path. Then report the honest error rate once fixture records stop landing in it, and say in
`report.md` whether freepool's real rate is above or below the 0.3 threshold. If it is genuinely
above, that is a separate finding — report it, do not silently raise the threshold.

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

## [Critical] 3 — the same question for every other shared sink

The journal is one shared, out-of-tree file the suite writes to. Census the others (caches, ledgers,
lock files, telemetry CSVs under `~/.claude`) and report which of them a test run can currently
mutate. Fix the ones in this lane's write set; list the rest.

## Acceptance

1. a test that emits a lane terminal ⇒ the real journal is byte-identical before and after;
2. the same test ⇒ its row IS written to the redirected fixture journal (it must still be testable);
3. the writer invoked from a test context without a redirect ⇒ refuses non-zero, does not append;
4. a production call path ⇒ still writes to the real journal (regression guard);
5. the cleanup identifies the fixture rows described above and leaves real rows untouched;
6. a freepool test writing an outcome ⇒ `~/.claude/leadv2-state/freepool-arm-state.json` is
   byte-identical before and after, and the gate's verdict is unchanged by the test run;
7. after the cleanup, `leadv2-freepool-gate.sh check` reports the rate computed from real
   traffic only — whatever that rate turns out to be.

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
