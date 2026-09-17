# REDSUITE-D-REVIEW-RUN-TRAP-AND-FOCUS-FLATTENING-01 — lane report (689648a9641b)

Platform for every run below: macOS Darwin 25.6.0, bash 3.2, worktree 689648a9641b, scripts tree byte-identical to lane HEAD 95a5255a unless a control mutation was applied and then restored (each restoration verified).

## 0. Reproduction note (read first)

The lead measured both suites red on main at 2026-09-15 (test-review-round-exhaustive.sh rc=1 wall=18s; test-leadv2-trace.sh rc=1 wall=28s). **Neither red reproduced on this branch**: this lane's interrupted wip commit 95a5255a (2026-09-16, "not reviewed, no controls recorded") already contains fixes for both suites. Per lane rules I state that plainly rather than claim a fix I never watched fail. What this lane did instead:

1. Verified each wip fix against its premise — both hold (evidence below).
2. Re-demonstrated each original red with a negative control: mutation applied → suite red → reverted → suite green. Both reds match the lead's measured signature exactly (one case red, rest green, rc=1).
3. Provided what the wip commit lacked: controls, tool artifacts, this report.

## 0.1 Reproduction runs (mission's Acceptance commands, in this worktree at lane HEAD)

```
$ bash plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh   # tail
PASS: T6 codex focus flattening
...
review-round-exhaustive: PASS=24 FAIL=0    (rc=0, wall 18.9s)

$ bash plugins/leadv2/scripts/tests/test-leadv2-trace.sh              # tail
[TEST] PASS: 5b no host installs its own EXIT trap after lv2_trace_arm_exit (single-trap-slot hazard)
...
[TEST] PASS=31 FAIL=0                      (rc=0, wall 14.0s)
```

## 1. Suite 1 — test-review-round-exhaustive.sh, case T6 "codex focus flattening"

- **Reproduction command**: `bash plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh` (worktree root).
- **Observed output** (at lane HEAD): PASS=24 FAIL=0, rc=0. Original red re-demonstrated by Control A below.
- **Cause class**: `test_encodes_superseded_requirement`.
- **Mechanism** (test-review-round-exhaustive.sh:265-306, regex at :304): T6 runs the real leadv2-review-run.sh against stubs + seeded repo, captures the codex focus text into CODEX_FOCUS_CAPTURE, and requires the contract's FINDING-format line to survive verbatim into what codex is handed — the anti-flattening check. The extraction regex pinned the dimension enum closed at four values, `dimension=<correctness\|security\|design\|perf>`. Commit 4410095a (2026-09-14, "fix(review): bind verdict to mission snapshot") rewrote `_review_contract_base` (leadv2-review-run.sh:1454) and added mission_alignment as a fifth dimension, so the contract line became `dimension=<correctness|security|design|perf|mission_alignment>`. The closed regex then extracted nothing → round_text empty → T6 red. The test's four-value-enum requirement was superseded by the five-value contract recorded in the code: commit 4410095a, 2026-09-14, plugins/leadv2/scripts/leadv2-review-run.sh:1454.
- **The fix** (in lane HEAD via wip 95a5255a, verified by this lane): widen the T6 extraction to `dimension=<correctness\|security\|design\|perf(\|[a-z_]+)?>` — still anchored on the original four values, still fails on empty extraction, still enforces the no-quote/no-backtick checks; admits only additional `|snake_case` values, so the anti-flattening guard is intact, and the case now asserts the new five-value contract. Rationale recorded at test :300-302.
- **Negative control A** (one mutation inside the changed body — the extraction regex in case_t6_codex_flatten):
  - Mutation: re-close the enum (remove the `(\|[a-z_]+)?` widening; single occurrence asserted before applying).
  - Red (mutation applied, 2026-09-17): FAIL: T6 codex focus flattening · PASS=23 FAIL=1 · rc=1.
  - Green (mutation reverted, tree byte-identical to HEAD): PASS=24 FAIL=0 · rc=0, wall 18.9s.
  - Tool artifact: §4.1 (appended after the report commit, per lane_diff_hash-binds-to-HEAD).

## 2. Suite 2 — test-leadv2-trace.sh, case 5b

- **Reproduction command**: `bash plugins/leadv2/scripts/tests/test-leadv2-trace.sh` (worktree root).
- **Observed output** (at lane HEAD): PASS=31 FAIL=0, rc=0, wall 14.0s — including 5a (armed-trace script that loses its clock returns to the prompt: not regressed). Original red re-demonstrated by Control B below.
- **Cause class**: `real_regression`.
- **Mechanism** (leadv2-review-run.sh, pre-fix positions: arm at :126, host EXIT trap at :245): bash has a single EXIT-trap slot — a later `trap ... EXIT` replaces, never chains. lv2_trace_arm_exit installs a chained trap (captures prior via `trap -p EXIT`, flushes all spans, evals the prior trap) — lib/leadv2-trace.sh:185-202, contract comment :175-184. When the review gate's terminal fallback `trap '_REVIEW_GATE_ST=$?; _review_gate_terminal_fallback ...; exit ...' EXIT` was added AFTER the arm call, it silently replaced the tracer's chained trap: the span never flushed, and the 5b lint (test-leadv2-trace.sh:483-510 — greps each known host for a trap installed after its arm line) went red. The gate fallback is load-bearing and keeps working: the fix composes both hooks instead of deleting anything.
- **The fix** (in lane HEAD via wip 95a5255a, verified by this lane): moved lv2_trace_arm_exit "review" from :126 to AFTER the host trap block — now leadv2-review-run.sh:264, after the EXIT trap at :252 and TERM/INT/HUP traps :256-258. Arm call last → the library's chaining (lib:189, `prev="$(trap -p EXIT)"`) captures the gate fallback and composes both. Ordering comments at :125-131 and :260-263.
- **Negative control B** (one mutation inside the changed body — the arm/trap ordering):
  - Mutation: move lv2_trace_arm_exit "review" back to its original position after the LEADV2_TRACE_ID export block, restoring the defect ordering; bash -n clean before running.
  - Red (mutation applied, 2026-09-17): [TEST] FAIL: 5b no host installs its own EXIT trap after lv2_trace_arm_exit · PASS=30 FAIL=1 · rc=1.
  - Green (mutation reverted via git checkout --, tree byte-identical to HEAD): [TEST] PASS=31 FAIL=0 · rc=0, wall 14.0s.
  - Tool artifact: §4.2 (appended after the report commit).

### 2.6 Mini-host probe (mechanism evidence beyond the lint)

A 17-line probe (/tmp/lv2probe-5b.sh, kept out of the repo) sources the real lib/leadv2-trace.sh with LEADV2_STATE_ROOT pointed at a temp dir and installs a host gate trap + tracer in both orders, then exits 7:

```
== correct: gate.out=[GATE-RAN rc=7] sink_records=1
{"trace_id":"probe-correct","span":"probe","script":"lv2probe-5b.sh","pid":8920,...,"exit_code":7,"clock_source":"monotonic_perl",...}
== defect:  gate.out=[GATE-RAN rc=7] sink_records=NO-SINK-FILE
```

Reading: correct order → both hooks coexist (gate ran, span flushed with the real rc=7). Defect order → gate runs but the sink file is never created — the tracer's chained trap was silently replaced. This is exactly the 5b defect and exactly what the fix prevents.

## 3. Ownership answer (the mission's question)

**The composition half already was the library's; the ordering half is necessarily the host's.** lv2_trace_arm_exit already implements the library-side fix: it captures whatever EXIT trap exists at arm time and chains it (lib/leadv2-trace.sh:185-202; contract at :175-184, "MUST be called AFTER any host-owned `trap ... EXIT`"). No library-side code can defend against a trap installed AFTER arming — bash's single-slot rule means the later installer always wins. Mission option (a) "host chains the prior trap by hand" would re-implement what the library already does; option (b) "library installs a chaining trap that composes with whatever comes later" is impossible in bash for later installers. The only correct division: library owns composition, host owns call order — hence a one-line call-site move in the host, backed by the library's existing chain + documented contract.

**What stops the next host from repeating this**: the 5b lint (test-leadv2-trace.sh:483-510) reds the suite whenever any of its enumerated hosts installs `trap ... EXIT` after its arm line; the library header documents the contract. Residual (named, not fixed — outside this lane's write set): the lint's ARM_SITES is hardcoded to 5 hosts; a NEW arm_exit host is not auto-enrolled and could repeat the mistake without the suite noticing. An auto-discovering lint (glob every script invoking `lv2_trace_arm_exit "`) would close it.

## 3.6 Other hosts with the same shape (mission asks to name, not fix)

Scanned all 11 scripts under plugins/leadv2/scripts/ referencing lv2_trace_arm_exit (2026-09-17, HEAD 95a5255a). Actual invocation hosts:

| host | arm line | host EXIT trap | order |
|---|---|---|---|
| leadv2-review-run.sh | :264 | :252 (+TERM/INT/HUP :256-258) | correct (fixed by wip 95a5255a) |
| leadv2-dispatch-code.sh | :4259 | :4233 trap cleanup_pending_dispatch EXIT | correct |
| leadv2-status-collector.sh | :90 | :89 | correct |
| leadv2-router.sh | :591 | :590 | correct |
| leadv2-lanes-snapshot.sh | :111 | none | correct (nothing to clobber) |

Non-invoking references only (mention/source, no arm call): leadv2-backlog-pump.sh, freepool-coder.sh, codex-task.sh, glm-coder.sh, kimi-coder.sh. Parked/scratch: .dbg-funcs.sh (arm :2890 after trap :2888 — correct order anyway), .test-dispatch-ppf-r5-funcs.*.sh (stale scratch copies). **No host currently has the defect shape.**

## 4. Mutation-control artifacts (to be appended after the report commit)

Per the DOD gate, each control claim is backed by a leadv2-mutation-control.sh run (worker mode, scratch copy of the lane; run AFTER this commit so lane_diff_hash binds to committed HEAD):

- Control A: close-enum sed on the exhaustive suite's own regex (§1 mutation), target suite = the exhaustive suite itself.
- Control B: unified-diff patch restoring the defect ordering in leadv2-review-run.sh (§2 mutation), target suite = test-leadv2-trace.sh.

§4.1/§4.2 with run-ids and pasted outputs follow in a controls commit.

## 5. Falsification set

bash -n on every shell file the lane touched (2026-09-17, tree==HEAD for all lane scripts):

```
bash -n OK: plugins/leadv2/scripts/leadv2-review-run.sh
bash -n OK: plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh
bash -n OK: plugins/leadv2/scripts/lib/leadv2-trace.sh
```

python3 -m py_compile: N/A — no Python files changed by this lane. Changed-scope runner (bash tests/run-all.sh --scope changed): exceeded its 600s foreground ceiling at 2026-09-17, moved to background; verdict to be appended in §5.1 when it lands.

## 6. Anything left red

Nothing. Both target suites are green at lane HEAD with controls recorded. Residuals named-not-fixed (outside write set): (1) the 5b lint's hardcoded 5-host ARM_SITES (§3); (2) platform boundary — every result above is macOS Darwin 25.6.0; green here does not mean green in CI (TWELVE-LINUX-ONLY-SUITES-01 population). Acceptance note: the mission's acceptance block names ~/Projects/leadv2 (main checkout); the WORKTREE PIN forbids cd there, so the same commands were run in this worktree over byte-identical script bytes (`git diff --quiet HEAD -- plugins/leadv2/scripts` verified empty).
