# BUILDER-SELFCHECK-GATE-01 — adversarial final review (critic, Opus)

- Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9c027877`
- HEAD: `0537906`
- Diff: `git diff main...HEAD` — 6 files, +1153/-1
- Diff hash: `a1a860888b3a7a0962d23f359fb01fa819ee6fc022210ec58632704cfbf4d407`
- Method: execution only (no repowise, no code-reading verdicts)

## VERDICT: PASS_WITH_NITS

Every round-2 finding I was asked to re-check is genuinely closed, and each one is
closed by a mechanism I could trigger myself, not by a comment asserting it. The four
nits below are lint/test-design, none blocking.

---

## Item-by-item

### 1. C1 — recursion via run-all → product-close → selfcheck: CLOSED

Three independent mechanisms, all executed:

**(a) The lib never invokes the repo-level runner.** `grep run-all.sh` over
`lib/leadv2-builder-selfcheck.sh` returns only comment lines (15, 241). The suite
check is diff-scoped stem matching against two fixed relative paths
(`lib/leadv2-builder-selfcheck.sh:275`), resolved from `diff_root`.

**(b) The e2e delegate probe does not execute what it resolves.**
`lib/leadv2-builder-selfcheck.sh:262` captures `leadv2-e2e-entrypoint.sh`'s stdout
into `delegate_cmd` and uses it only as a table cell (line 268). I confirmed
`leadv2-e2e-entrypoint.sh` is a pure printer (53 lines, only `printf` + `exit`).

**(c) Flag+depth guard reaches the grandchild.** This is the load-bearing claim, so I
tested the bash semantics directly rather than trusting it — an env prefix on a
*function* call is exactly the case where bash's behaviour is non-obvious:

```
$ bash -c 'f(){ bash -c "echo child_sees=[\$FOO]"; }; FOO=0 f; echo after=[${FOO:-UNSET}]'
child_sees=[0]
after=[UNSET]
```

The prefix at `lib/leadv2-builder-selfcheck.sh:284` (`LEADV2_BUILDER_SELFCHECK=0
LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth+1))`) does propagate into the spawned suite's
environment and does not leak back into the caller. The gate in
`leadv2-dispatch-product-close.sh:1839` reads `${LEADV2_BUILDER_SELFCHECK:-1} != 0`,
so a re-entered product-close is a no-op. The depth guard
(`lib/leadv2-builder-selfcheck.sh:255`) is the second belt.

Suite legs, all green and all sentinel-based (not tautological):
- `child-suite-observes-flag-and-depth (C1)` — child writes `FLAG=0` / `DEPTH=1` to a probe file, asserted.
- `depth-guard-skips-no-spawn (C1)` — sentinel file must NOT exist.
- `repo-level-runner-never-invoked (C1/decision-A)` — plants a `tests/run-all.sh` that `touch`es a sentinel; asserts the sentinel is absent and the row is `SKIP (no_matching_suite)`.

### 2. C2 — no-gtimeout watcher hang: CLOSED, verified beyond the suite

This box has gtimeout, so the suite's own legs mask both binaries out of `PATH`
(`mask_timeout_path`, test lines 621-630) — a real fallback exercise, not a
gtimeout run in disguise. I re-ran the shape myself with a harsher deadline, because
the original bug was "caller blocks for the FULL timeout" and the suite's 5s budget
makes that weak:

```
masked has timeout? NO
stress: 45s timeout, fast cmd, inside command substitution
  out=RC=0 elapsed=0s
stress: hung cmd that forks children (process-group kill)
  rc=124 elapsed=3s
orphan `sleep 300` still alive? 0
```

The 45s case is decisive: under the old bug the surviving watcher `sleep` held the
command-substitution pipe's write end open and the caller would have blocked 45s. It
returns in 0s. The forking case confirms `set -m` + `kill -TERM -"${pid}"`
(`lib/leadv2-builder-selfcheck.sh:60-69`) reaps the whole process group — zero
orphans — and reports 124 like `timeout(1)`. Watcher I/O is fully detached at line 69
(`>/dev/null 2>&1 </dev/null`).

### 3. The three previously-broken suites, run IN THE WORKTREE with the gate at its default (flag=1): ALL PASS

| suite | rc | result |
|---|---|---|
| `test-no-work-terminal.sh` (= run-core-offline row "product-close waits for worker exit") | 0 | 43 passed, 0 failed |
| `test-report-only-gate.sh` | 0 | 8 passed, 0 failed; red-first 0/5; then 2 passed, 0 failed |
| `test-review-body-persist.sh` | 0 | 13 passed, 0 failed |

New suite `test-builder-selfcheck-gate.sh`: **26 passed(red->green), 0 failed, 0
green-pre-fix, 0 could-not-run** — and it reproduces identically on a second run.

### 4. Report-only fall-through with a journaled skip-reason: CONFIRMED

`leadv2-dispatch-product-close.sh:1846`:

```bash
emit decision "selfcheck task=${TASK} status=skipped reason=report_lane"
```

The skip is a real ledger event, not silence. The sibling no-arm skip is line 1848
(`reason=no_arm`). The skip predicate is line 1839-1840: report lanes skip
unconditionally; a diff lane skips only when **both** arms are off **and** `HANDLE` is
non-empty — so a manual/direct dispatch (empty `HANDLE`) still gets checked, which is
the correct reading of "selfcheck is the only safety net there". Tests:
`report-lane-skips-selfcheck` and `no-arm-skips-selfcheck`, both scored red→green.

### 5. M1 — checks=0 never GREEN: CONFIRMED

Code: `lib/leadv2-builder-selfcheck.sh:336-339` sets `verdict=DEGRADED` +
`reason: no_check_ran` when `checks == 0`, and lines 361-363 return rc 2. The verdict
ladder is ordered `failed>0 → RED` first, so DEGRADED can never mask a red.

Caller: only `rc == 1` blocks (line 1850); rc 2 emits
`status=degraded` (line 1861) and falls through — DEGRADED is visible, not fatal.
Test leg `checks-zero-yields-degraded (M1)` asserts rc==2 **and** both `verdict:
DEGRADED` and `reason: no_check_ran` in the artifact.

### 6. Fixture-fix honesty: LEGITIMATE REPAIR, not assertion-weakening

I verified the premise instead of accepting the commit message:

```
old seed 'seed\nedited-in-worktree-for-golden\n'   -> SyntaxError, rc=1
new seed '# seed\n# edited-in-worktree-for-golden\n' -> rc=0
base commit content 'seed\n'                        -> rc=0
```

The old line 2 is a genuine syntax error because `in` and `for` are reserved words —
`py_compile` was right to reject it. The base commit (`new_repo`,
`test-report-only-gate.sh:52`) already seeds valid Python, so the fixture, not the
gate, was the broken thing.

The golden case's purpose survives intact. `case_4_diff_golden` asserts (a) `status:
pass` on a tracked lane modification with no deliverable — i.e. a diff lane is not
misclassified as report-only — and (b) byte-identical `review-gate.md` against the
pre-change scripts. The seed change keeps a real 2-line tracked modification, so the
diff is still non-empty and the classifier is still exercised. If anything (a) is now
a *stronger* claim: it proves the gate is behaviour-neutral on a valid diff rather
than avoiding the gate.

### 7. bash -n + shellcheck: NO NEW WARNINGS on the changed pre-existing scripts

`bash -n` clean on all six touched files (both `bash` 5.3 and `/bin/bash` 3.2 — the
suite itself asserts 3.2 syntax compatibility for the two shipped scripts).

shellcheck `-S warning`, head vs `git show main:`:

| script | main | HEAD | delta |
|---|---|---|---|
| `leadv2-dispatch-product-close.sh` | 11 | 11 | none (code classes identical) |
| `leadv2-dispatch-code.sh` | 10 | 10 | none (code classes identical) |

New files carry 5 warnings total, all benign — see nits N1/N2.

### 8. run-core-offline delta = exactly one row: CONFIRMED

`git diff main...HEAD -- tests/run-core-offline.sh` is `1 insertion(+), 0 deletions`,
the `builder selfcheck gate (...)` row at line 224. No hardcoded suite-count assertion
exists in that runner that a new row could break, and it exports no `SELFCHECK`/`E2E`
variable that would perturb the gate.

---

## Additional checks I ran that were not on the list

**Caller variable scope.** `diff_file` (`:1390`) and `diff_root` (`:1411`) are assigned
inside `pc_scope_diff()` *without* `local`, so they are globals; `pc_scope_diff` is
invoked at `:1811`, before the gate at `:1826`. `HANDOFF` is set at `:125`. All
helpers the gate calls exist: `emit` (`:221`), `_dl_note` (`:102`),
`_stamp_review_terminal` (`:252`), `_pc_join_capped` (`:1321`). `exit 5` matches the
established blocked-terminal convention (`:1606`, `:1616`, `:1742`, `:1764`).

**Gate placement is coherent with the delegate arm.** The caller passes
`LEADV2_E2E_GATE="${E2E_ON}"`. I confirmed on the live tree that for a real leadv2
lane the entrypoint resolves (`bash <root>/tests/run-all.sh`), so with `E2E_ON=1` the
suite half delegates and the gate reduces to `bash -n` + `py_compile` — the broad
suites are then run by the e2e stage, which still sits *before* review. With
`E2E_ON=0` and `REVIEW_ON=1` the delegate is off and the suites run here. The two arms
are complementary, so "no review arm is spent on an unproven diff" holds in both
configurations. This is by design (D2) and is not a hole.

**Test hermeticity.** I snapshotted `git status --porcelain` before and after an
isolated re-run of the new suite: 51 lines before, 51 after, zero delta. The new suite
leaves the repo clean. (The 51 dirty entries are pollution from the *pre-existing*
`test-no-work-terminal.sh`, which writes `docs/handoff/dispatch-nw*` and
`docs/leadv2/bus.jsonl` into the real tree — pre-existing behaviour, outside this
diff's scope, but worth a separate row.)

**Harness honesty.** `run_selfcheck` pins `LEADV2_E2E_GATE=0` by default and documents
exactly why (otherwise `auto` mode delegates away the very suite check the cases
exist to exercise); case 11 overrides it to assert the delegate arm positively. The
pin is disclosed, not hidden.

---

## Nits (non-blocking)

- **N1 — 4× SC2034 in the new lib** (lines 258, 329, 330, 331):
  `LV2_SELFCHECK_DEPTH_SKIP/CHECKS/FAILED/SKIPPED` are consumed cross-file by
  product-close, which shellcheck cannot see. The header already documents them; add
  `# shellcheck disable=SC2034` above the block so the lib lints clean.
- **N2 — SC2206** at `test-builder-selfcheck-gate.sh:625` (`local -a dirs=(${PATH})`).
  The word-splitting is deliberate under `local IFS=':'`; `IFS=: read -ra dirs <<<"${PATH}"`
  would be equivalent and lint-clean.
- **N3 — C4's "live vs pre" comparison arm is now tautological in-worktree.**
  `case_4_diff_golden` builds its baseline via `git -C "${LEADV2_REPO}" archive HEAD`.
  When the suite runs from inside this worktree, HEAD already contains the gate, so
  live and pre are the same code and `cmp` cannot fail. The primary `status: pass`
  assertion is independent and unaffected, so this is not a false green today — but
  the arm silently stopped measuring what it was built to measure. Pre-existing test
  design; worth a follow-up row, not a block.
- **N4 — kill-switch is a literal string compare.** `${LEADV2_BUILDER_SELFCHECK:-1} != 0`
  (product-close `:1839`, dispatch-code `:4040`) means only the exact string `0`
  disables the gate; `false` / `no` / `off` silently leave it on. Consistent with the
  documented contract, just easy to get wrong from a shell.

## Evidence commands (re-runnable)

```bash
W=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9c027877
git -C "$W" diff main...HEAD | shasum -a 256
cd "$W/plugins/leadv2/scripts/tests"
for s in test-no-work-terminal.sh test-report-only-gate.sh test-review-body-persist.sh \
         test-builder-selfcheck-gate.sh; do bash "$s" >/tmp/$s.log 2>&1; echo "$s rc=$?"; done
```
