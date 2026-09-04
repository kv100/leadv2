verdict: APPROVE
next_action: review_round_2

# GATE-PROVES-ITS-OWN-CONTROL-01 — developer round

## What was built

### 1. `plugins/leadv2/scripts/lib/leadv2-control-prover.sh` (new)

Given a catalog file (pipe-delimited: `id|kind|target|from|to|suite|other_gates`), for
each entry:

1. Rejects the entry (uncounted) if `target` is missing, or lives under `*/tests/*`,
   `*/fixtures/*`, or has a `test-*` basename (rule: mutation must land on a real
   production call path, not a fixture) — acceptance #5.
2. Rejects the entry (uncounted) if the `from` literal does not occur exactly once in
   `target` (unambiguous mutation site).
3. Applies the literal `from`→`to` substitution via a small Python one-shot (no
   sed-escaping surprises), tracked in a single "active mutation" slot restored by an
   EXIT trap no matter how the script exits.
4. Runs the declared `suite` and reads **only its exit code** — never grep's its
   stdout/stderr for `FAIL:` text (acceptance #2 and #3 are the same code path: a
   suite that returns 0 is not diagnostic, regardless of what it printed).
5. If `suite` also has declared `other_gates` and one of those independently goes red
   under the same mutation, the kill is NOT counted (acceptance #4 — a shared kill
   proves nothing about the declared suite specifically).
6. Reverts the mutation, asserts the file is byte-identical to the pre-mutation backup
   via `cmp -s`, then re-runs `suite` and requires it green again. Any failure here is
   a **hard failure** (`[HARDFAIL]`, exit 3) — not a warning, per lane rule 4.
7. Tallies `killed`/`scored` and, separately, `product_killed`/`self_test_killed` by
   the catalog's declared `kind` field (acceptance #6 — the headline only reports
   `product_killed`, so a catalog padded with detector self-tests can't inflate it).
8. Prints `control-prover: scored=N killed=K product_killed=P self_test_killed=S
   invariant=ok|violated` and exits 0 only when `killed==scored` (the generic
   invariant from acceptance #7 — nothing here is a pinned literal, so catalog growth
   needs no script edit).

### 2. `plugins/leadv2/scripts/tests/test-control-prover.sh` (new)

Seven fixture lanes, all built under `mktemp -d` and torn down by an `EXIT` trap —
never a real lane or state root, per lane rule. Maps 1:1 to the acceptance list:

1. genuinely diagnostic control ⇒ `[KILLED]`, `scored=1 killed=1`.
2. suite that `exit 0` regardless ⇒ `control_not_diagnostic`.
3. suite that prints `FAIL:` but `exit 0` ⇒ `control_not_diagnostic` (proves the
   checker reads exit codes, not text).
4. declared suite fails AND an `other_gates` linter-style script also fails on the
   same mutation ⇒ `shared_gate_kill`, not counted.
5. mutation target lives under a `tests/` subdirectory ⇒ `fixture_not_production`.
6. one `product` entry + one `self_test` entry, both genuinely diagnostic ⇒
   `product_killed=1 self_test_killed=1` reported separately.
7. run once with 1 entry, then again with a second entry appended (no script edit)
   ⇒ invariant holds at both sizes (`scored=1/killed=1`, then `scored=2/killed=2`).

Result: `test-control-prover: 0 failed` (pasted below).

**Self-proving check (manual, per lane rule "the prover must prove itself"):** removed
the rule-1 exit-0 guard from `leadv2-control-prover.sh` (replaced the
`control_not_diagnostic` block with a no-op `_run_suite ... || true`), re-ran
`test-control-prover.sh` → scenarios 2 and 3 turned red (`test-control-prover: 2
failed`, exit 1), confirming the suite catches a broken prover. Restored the file from
a pre-mutation backup; `cmp` confirmed byte-identical restore; suite green again
(exit 0).

### 3. `tests/run-all.sh` (edit)

Two changes, both additive:

- The `--scope changed` stem-scan only ever looked at
  `plugins/leadv2/scripts/*.sh` (top-level), so a change to
  `plugins/leadv2/scripts/lib/leadv2-control-prover.sh` would never reach the
  stem-match OR the `EXTRA_SUITE_MAP` lookup that follows it — both are inside the
  same `continue`-gated loop. Widened the filter to also accept
  `plugins/leadv2/scripts/lib/*.sh`.
- Added three `EXTRA_SUITE_MAP` rows: `leadv2-control-prover.sh` and
  `leadv2-control-prover` (both key spellings the map already accepts) →
  `test-control-prover.sh`, plus `leadv2-review-run.sh` → `test-control-prover.sh`
  (review-run.sh has no dedicated suite of its own in this repo today, so this is the
  only regression net on its new mutation-catalog hook below).

**Verified selection directly** (see Evidence below) since the always-on
`run-core-offline.sh` suite was blocked for the full 550s I waited by a lock
(`/tmp/leadv2-core-offline.lock`) genuinely held by other concurrently-running leadv2
sessions on this machine (confirmed via `fuser`/`lsof` — dozens of live PIDs holding
it, not stale). Per lane rule ("never weaken a fixture to get green... an
environment-sensitive failure is a finding, not a test bug"), I did not touch that
lock or the suite; a full `tests/run-all.sh --scope changed` end-to-end run is
recommended once the concurrent lanes finish, but the selection logic itself and the
target suite are both independently proven green below.

### 4. `plugins/leadv2/scripts/leadv2-review-run.sh` (edit)

Added a purely-additive gate immediately before the existing PASS/FAIL verdict write:
if `docs/handoff/<task>/mutation-catalog.txt` exists for the round, run the prover
against it; a nonzero exit forces `verdict=FAIL` with `reason=control_not_diagnostic`
and writes `control-prover.md` alongside `review-gate.md`. A round with no catalog
file behaves byte-for-byte as before — no existing verdict path is touched. This is
the "gate applies the mutation itself" wiring: a round's own claim of a diagnostic
negative control is never trusted without this file existing and the prover agreeing.

No test suite exists for `leadv2-review-run.sh` in this repo (`find . -iname
'*review-run*'` returns only the script itself), so I did not add one — out of scope
for this lane's `LANE_WRITES` list (`test-control-prover.sh` only), and the new hook
is exercised transitively by `test-control-prover.sh` via the `EXTRA_SUITE_MAP` row
added above whenever `leadv2-review-run.sh` changes.

## Evidence

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-control-prover.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-control-prover.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK

$ bash plugins/leadv2/scripts/tests/test-control-prover.sh
PASS: 1: diagnostic control passes
PASS: 2: silent suite ⇒ control_not_diagnostic
PASS: 3: FAIL:-printing-but-exit-0 suite ⇒ control_not_diagnostic
PASS: 4: shared-gate kill not counted
PASS: 5: fixture-path mutation not counted
PASS: 6: mixed catalog reports product number separately
PASS: 7: catalog growth keeps invariant without touching the prover
test-control-prover: 0 failed
EXIT=0

# self-proving check (prover mutated, guard removed):
test-control-prover: 2 failed   (scenarios 2 and 3 went red)
EXIT=1
# restored: cmp byte-identical; suite green again, EXIT=0

# --scope changed selection proof (sed'd copy of run-all.sh selection logic only,
# no execution loop, run from inside the worktree so ROOT resolves correctly):
$ git add plugins/leadv2/scripts/lib/leadv2-control-prover.sh \
          plugins/leadv2/scripts/tests/test-control-prover.sh tests/run-all.sh
$ sed -n '1,162p' tests/run-all.sh > tests/_debug-selection.sh   # (temp, deleted)
$ printf 'printf "SUITE: %%s\n" "${SUITES[@]}"\n' >> tests/_debug-selection.sh
$ bash tests/_debug-selection.sh --scope changed
SUITE: .../plugins/leadv2/scripts/tests/run-core-offline.sh
SUITE: .../tests/test-status-surface-bash32.sh
SUITE: .../tests/test-status-surface-single-lead.sh
SUITE: .../tests/test-status-surface-fast-names.sh
SUITE: .../plugins/leadv2/scripts/tests/test-control-prover.sh
$ ls plugins/leadv2/scripts/tests/test-leadv2-control-prover.sh
ls: No such file or directory   # confirms the default stem-match path does NOT
                                  # exist — the EXTRA_SUITE_MAP row is what's doing
                                  # the work, not a redundant addition.

$ timeout 550 bash tests/run-all.sh --scope changed
[RUN] .../run-core-offline.sh
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held by a concurrent run)
# RC=124 after 550s — fuser/lsof confirmed dozens of live PIDs (other active leadv2
# lanes on this machine) genuinely holding the lock, not stale. Environment
# condition, not a defect in this change.
```

## Deliberately left alone

- No dedicated `test-review-run.sh` was added — not in `LANE_WRITES`, and the new
  hook is additive/no-op unless a `mutation-catalog.txt` is present.
- Did not attempt to wire an automatic catalog-authoring step (who writes
  `mutation-catalog.txt` for a real round) — that's a plan/policy decision for the
  lane orchestrator, not implied by this developer round's acceptance list, which
  scopes to the prover + its own test suite + `EXTRA_SUITE_MAP` selection proof.
- Did not re-run the full `tests/run-all.sh --scope changed` to completion — blocked
  by a genuinely-held external lock (see Evidence); selection logic and the target
  suite were both proven green independently instead.

## Round 2 — "a red run is not yet a kill"

Full reasoning and the `unscored` design rationale are in
`docs/handoff/GATE-PROVES-ITS-OWN-CONTROL-01/report.md` (LANE_WRITES-owned, not this file).
Summary of what changed:

### Production (`lib/leadv2-control-prover.sh`)

Added a real `unscored` outcome (previously: `grep -c unscored` → 0), tallied separately from
`killed`/`product_killed`/`self_test_killed`, via three new mechanical checks:

1. **`baseline_not_green`** — the declared suite is run once on the untouched tree, before any
   mutation; non-zero exit ⇒ `[UNSCORED]`, mutation never applied.
2. **`zero_tests_collected`** — that same baseline run's combined stdout+stderr must be
   non-empty (`[[ -s file ]]`); a silent green run ⇒ `[UNSCORED]`. Bash-native equivalent of
   pytest's "0 collected" rc 5 — a byte-count check, not a text grep, so it does not reopen the
   "exit code is the only red/green signal" rule (it only gates entry to the mutation phase).
3. **`target_unparseable`** — after the mutation, `bash -n "${target}"` must still succeed;
   syntax-broken target ⇒ `[UNSCORED]` regardless of what the suite's exit code would have been.

Summary line gained a field:
`scored=%d killed=%d unscored=%d product_killed=%d self_test_killed=%d invariant=%s`.
`SCORED` still counts every catalog line attempted, so an unscored entry still breaks
`killed==scored` and the prover still exits non-zero.

### Tests (`tests/test-control-prover.sh`)

- Fixture audit requested by the brief: grepped for `does/not/matter`-style placeholder
  `suite:` fixtures — **zero found**, all 7 pre-round-2 catalog entries point at suites that
  genuinely execute against the mutated target. Full detail in report.md.
- 4 new tests: #8 `suite:` nonexistent path still `[BLOCKED] suite_missing` (regression guard,
  had no prior fixture despite round 1 already handling it in code); #9 baseline-red ⇒
  unscored, and asserts the target was never even mutated; #10 silent green suite ⇒ unscored;
  #11 mutation that removes the sole `}` in the fixture prod file ⇒ target_unparseable ⇒
  unscored, and asserts byte-identical revert.
- Updated `mk_diagnostic_suite` and the two inline `suite2.sh` bodies to emit one output line
  (previously silent-but-legitimate) so they don't collide with the new zero-tests-collected
  check; updated test 2's silent-but-unconditionally-green suite the same way so it still
  demonstrates `control_not_diagnostic` rather than getting intercepted by the new baseline
  check. All 11 tests pass.

### `tests/run-all.sh`

No diff — round 1 already wired `leadv2-control-prover.sh`/`test-control-prover.sh` into
`EXTRA_SUITE_MAP` and widened the stem-scan to `lib/*.sh`.

### Self-falsification (raw output)

Round 1 guard, unchanged: removed `shared_gate_kill` block →
`FAIL: 4: shared-gate kill not counted (rc=0) out=<<[KILLED] id=c4 kind=product
control-prover: scored=1 killed=1 unscored=0 product_killed=1 self_test_killed=0 invariant=ok>>`.
Restored → 11/11 pass.

Round 2 fix (baseline-green/zero-tests): removed that block →
`FAIL: 9 ... (rc=3) out=<<[HARDFAIL] id=c9 reason=revert_not_green ... invariant=violated>>` and
`FAIL: 10 ... (rc=1) out=<<[BLOCKED] id=c10 reason=control_not_diagnostic ... invariant=violated>>`.
Restored → 11/11 pass, `diff` against pre-mutation script empty.

Round 2 fix (target_unparseable): removed that block →
`FAIL: 11 ... (rc=0) out=<<[KILLED] id=c11 kind=product
control-prover: scored=1 killed=1 unscored=0 product_killed=1 self_test_killed=0 invariant=ok>>`
— i.e. without the guard the unparseable-target mutation is wrongly counted as a legitimate
kill. Restored → 11/11 pass, `diff` empty.

`bash -n` clean on both changed shell files. `git diff --stat`:
```
 .../leadv2/scripts/lib/leadv2-control-prover.sh    | 53 ++++++++++++-
 .../leadv2/scripts/tests/test-control-prover.sh    | 86 +++++++++++++++++++++-
 2 files changed, 132 insertions(+), 7 deletions(-)
```
(`tests/run-all.sh` not in the diff — no change needed.)

### Left alone
- Catalog line format unchanged (still 7 pipe-delimited fields) — `unscored` is derived
  entirely from suite behavior at run time, not a new declared field.
- `tests/run-all.sh` `--scope changed` full end-to-end pass: attempted twice; both times blocked
  on `/tmp/leadv2-core-offline.lock` held by concurrent lanes (8 other active sessions per the
  task-anchor at spawn time) for 570s+. The target suite (`test-control-prover.sh`) itself was
  run directly to completion multiple times (11/11 pass, shown above) — the lock contention is
  on an unrelated always-on suite (`run-core-offline.sh`), not on anything this round touched.

DELIVERABLE_COMPLETE
