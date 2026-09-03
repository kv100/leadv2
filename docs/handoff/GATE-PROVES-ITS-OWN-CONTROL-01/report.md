# GATE-PROVES-ITS-OWN-CONTROL-01 — round 2 report

## Files touched
- `plugins/leadv2/scripts/lib/leadv2-control-prover.sh` (production)
- `plugins/leadv2/scripts/tests/test-control-prover.sh` (fixtures only)
- `tests/run-all.sh` — **no diff**; round 1 already wired `leadv2-control-prover.sh` and
  `test-control-prover.sh` into `EXTRA_SUITE_MAP`. Nothing new needed here.

## Fixture audit (mission's "check the fixtures for a legalised fail-open")

`grep -n 'suite=' plugins/leadv2/scripts/tests/test-control-prover.sh` → **0 matches** before
this round, and the catalog format uses `suite:` as a positional pipe-delimited field, not a
`suite=` key, so I also checked every `suite.sh`/`suite2.sh` fixture body by hand: all seven
pre-existing catalog entries (c1, c2, c3, c4, c5, c6a/c6b, c7a/c7b) point `suite` at a real,
executing `.sh` file that genuinely sources or greps the mutated production file — none is a
`does/not/matter.py`-style placeholder. **Zero fixtures found encoding the bug as correct.**
The V5 session's finding does not apply to this file; it must have been observed against a
different runner or an earlier draft. Regression-guarded anyway: new test 8 proves a `suite:`
pointing at a genuinely nonexistent path is still `[BLOCKED] reason=suite_missing`, never scored
as a kill.

## The `unscored` outcome — what I chose and why

Bash has no equivalent of pytest's rc 4/5 usage-error exit codes, so three independent,
mechanical checks were added, each producing `[UNSCORED] id=<id> reason=<reason>`:

1. **`baseline_not_green`** — before ever touching the target, the declared suite is run once
   on the untouched tree via `bash "${suite}" >file 2>&1`; a non-zero exit here means the suite
   was already broken and cannot possibly tell us anything about the mutation. Chosen because
   it's the literal reading of "proven RUN and GREEN before the mutation" — no heuristic
   involved, same exit-code-is-the-only-signal contract as the existing kill/no-kill logic.

2. **`zero_tests_collected`** — the same baseline run's combined stdout+stderr is checked for
   non-empty (`[[ -s file ]]`). A suite that exits 0 with zero bytes of output is, by this
   contract, a suite that asserted nothing observable. This is the direct equivalent of
   pytest's "0 collected" — bash has no built-in item counter, so "did anything even run"
   stands in for "did anything get collected". This is a size check, not a text/content grep,
   so it does not reopen the "never grep the suite's PASS/FAIL text for red/green" rule — it
   only gates entry into the mutation phase, it never decides red vs green.
   Because this check is new, the pre-existing `mk_diagnostic_suite` fixture helper (used by
   most of round 1's catalog entries) was silent by design — it had no output at all. I added
   one `printf 'ran: ...'` line to that helper and to the two inline `suite2.sh` bodies so they
   keep passing under the new rule; this is a fixture change only, the assertion logic (the
   final `[[ "${result}" == ... ]]`) is untouched. Test 2's "stays green regardless of the
   mutation" fixture also got one `echo` line for the same reason — it was previously
   simultaneously an example of "silent suite" AND "non-diagnostic suite", and the new baseline
   check would otherwise have intercepted it as `zero_tests_collected` before it ever reached
   the `control_not_diagnostic` check test 2 is meant to prove.

3. **`target_unparseable`** — after the mutation is applied, `bash -n "${target_abs}"` is run
   before the suite. If the mutated file fails to parse, the entry is `unscored` regardless of
   what the suite's exit code would have been — a syntax-broken target makes any suite crash
   infrastructural, not diagnostic. This is deterministic (no text heuristics on suite output)
   and directly matches the mission's example ("mutation makes the target unparseable").

All three are pre-conditions or a post-mutation gate that short-circuit before the existing
kill-scoring logic; none of them touch the existing `control_not_diagnostic` / `shared_gate_kill`
/ revert-must-be-green rules, which still fire exactly as before for entries that pass the new
checks.

`UNSCORED` is a new tally, reported in the summary line as
`scored=%d killed=%d unscored=%d product_killed=%d self_test_killed=%d invariant=%s`, and is
never added to `KILLED`, `PRODUCT_KILLED`, or `SELF_TEST_KILLED`. `SCORED` still counts every
catalog line attempted (unchanged), so an `unscored` entry still breaks `killed==scored` and the
prover still exits non-zero — "unscored" means "not proven", not "ignored".

## Self-falsification (evidence, not claims)

Three separate falsification passes, each showing the assertion actually asserts:

1. **Round 1 regression guard** — removed the `shared_gate_kill` block, reran
   `test-control-prover.sh`: `FAIL: 4: shared-gate kill not counted (rc=0) out=<<[KILLED]
   id=c4 kind=product ... invariant=ok>>`. Restored, reran: all 11 pass. Round 1 still enforced.
2. **Round 2 fix (baseline-green + zero-tests)** — removed that block, reran:
   `FAIL: 9 (rc=3) out=<<[HARDFAIL] id=c9 reason=revert_not_green ...>>` and
   `FAIL: 10 (rc=1) out=<<[BLOCKED] id=c10 reason=control_not_diagnostic ...>>`. Restored, reran:
   all 11 pass, byte-identical to the pre-mutation script (`diff` empty).
3. **Round 2 fix (target_unparseable)** — removed that block, reran: `FAIL: 11 (rc=0)
   out=<<[KILLED] id=c11 kind=product ... invariant=ok>>` — i.e. without the guard, the
   syntax-broken-target mutation is wrongly counted as a legitimate kill. Restored, reran: all
   11 pass, byte-identical.

## Acceptance checklist
1. green→red→green ⇒ killed — unchanged, test 1 still passes.
2. suite red before mutation ⇒ unscored — test 9.
3. suite collects zero tests ⇒ unscored — test 10.
4. mutation makes target unparseable ⇒ unscored, summary says so — test 11.
5. `suite:` nonexistent path ⇒ still `[BLOCKED] suite_missing` — test 8 (new regression
   guard; this case had no prior fixture).
6. summary line reports scored/killed/unscored/product_killed/self_test_killed/invariant,
   unscored excluded from all kill tallies — every test's grep now checks the full
   `unscored=%d` field explicitly.

## Deliberately left alone
- `tests/run-all.sh` — already correct from round 1, no diff.
- No changes to the catalog line format (7 pipe-delimited fields, unchanged) — `unscored` is
  derived entirely from suite behavior, not a new catalog field.
- Did not add a fixture for "suite prints a fake `unscored` marker to fool the exit-code
  check" — out of scope; the exit-code-is-the-only-signal contract for RED/GREEN itself is
  unchanged from round 1 and still the sole authority the mission asked me to preserve.
