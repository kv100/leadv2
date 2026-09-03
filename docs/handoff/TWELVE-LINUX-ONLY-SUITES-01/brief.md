# TWELVE-LINUX-ONLY-SUITES-01

Twelve suites are green on macOS and red on Linux CI. They are the last thing between us and a
green `main`, and a green `main` is the precondition for required status checks on `kv100/leadv2`
(`SD-CI-REQUIRE-STATUS-CHECKS-01`). Two of this family were already fixed tonight
(`mktemp -d -t` and a shellcheck-version-dependent assertion) — these twelve are the rest.

## Measured

CI run `33706523661`, ubuntu-latest, commit `815627a7`:

    [CORE-OFFLINE] suites passed=57 failed=27 missing=0
    12 of the 27 print [NOT-KNOWN-RED] — i.e. they are NOT on tests/known-red-suites.txt

The same tree on macOS: `69 pass / 15 fail`, and **zero** outside the allow-list. So the delta is
entirely platform, not regression. The allow-list mechanism itself works correctly — it classified
the pre-existing reds and flagged exactly these twelve as new.

The twelve, verbatim from the run's `[NOT-KNOWN-RED]` lines:

    core:Claude plugin manifest/components
    core:Phase-8 merge/completion proof
    core:Phase-8 task schema
    core:T14 worker MCP (glm spawn role config)
    core:builder selfcheck gate (recursion/depth guard, baseline attribution)
    core:burn governor (BURN-GOVERNOR-01: 24h burn gate)
    core:e2e gate arch-01 (lane-tree testing)
    core:e2e gate lane root + suite family
    core:lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)
    core:plugin reliability (process liveness + role fallback + prepass/reorder signals)
    core:plugin sync contracts write gate
    core:status surface single-lead + census

## How to work this

Expect a small number of root causes, not twelve. The two already fixed were both "a BSD-shaped
call behaves differently under GNU". Likely siblings: `sed -i` needing an argument on BSD,
`date -r`/`date -d`, `stat -f`/`stat -c`, `readlink -f`, `mktemp` variants elsewhere, `grep -E`
vs `-P`, `sort` locale order, `ps` output columns, `/tmp` vs `$TMPDIR` path shapes, and GNU
coreutils flags absent on macOS or vice-versa. **Group the twelve by root cause first and fix the
cause, not the symptom** — a per-suite patch that papers over the same GNU/BSD difference twelve
times is the wrong answer and will be rejected in review.

Map each of the twelve names to its file via `plugins/leadv2/scripts/tests/run-core-offline.sh`
(the suite table maps label → `bash $TEST_DIR/<file>`).

## Definition of done

1. All twelve are green on Linux. The proof is a CI run, not a local run — a local macOS pass is
   what created this situation.
2. State the root-cause groups you found and which suites fall in each. If it really is twelve
   independent causes, say so and show why.
3. A negative control per root-cause group: name the mutation (restore the BSD-only form), show
   the affected suites go red, revert, show green.
4. Nothing may be added to `tests/known-red-suites.txt`. That list is for pre-existing reds we
   have consciously decided to carry; putting a fresh platform bug in it to make CI green is the
   lying-green disease this repo has an explicit rule against. If you believe a specific suite
   genuinely cannot run on Linux, do not allow-list it — make it SKIP cleanly on non-Darwin with
   a stated reason, the way `test-status-surface-bash32.sh` already does, and say so in the report.
5. Do not weaken an assertion to make it pass. Portability means the same verdict on both
   platforms, not a lower bar on one.
6. Run only the suites you touched, individually, and paste each exit code.
7. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, and any change that makes an assertion weaker
rather than platform-independent.
