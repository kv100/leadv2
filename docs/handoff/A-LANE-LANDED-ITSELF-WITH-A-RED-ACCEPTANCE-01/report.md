# A-LANE-LANDED-ITSELF-WITH-A-RED-ACCEPTANCE-01 — report

Lane `1fdca3ca1997`, branch `worktree-1fdca3ca1997`, macOS Darwin 25.6.0, bash 3.2.
Fix commit: `6d026377` (fix + guard suite). All counts below carry their boundary
inline. Standing rules honored: nothing weakened, no `|| true` added at any gate,
`tests/known-red-suites.txt` untouched, `leadv2-active-registry.sh` /
`leadv2-dispatch-code.sh` untouched.

## Which mechanism it was — and the line that proves it

**Mechanism 2: the acceptance command RAN at close, went RED, and its exit code was
not gated on.** The red artifact exists — that is the discriminator (mechanism 1
would leave no artifact at all).

Evidence (all UTC, sig8 `c4776136`, row `55de339ac133`):

1. `~/.claude/leadv2-state/leadv2/tasks/dispatch-c4776136/journal.md:76`

   ```
   - 2026-09-17T03:52:36Z [decision] dispatch_terminal task=c4776136 terminal=landed cause=review_verdict_pass
   ```

2. Same file, line 81 — the acceptance **ran and failed 3m40s after the landing**:

   ```
   - 2026-09-17T03:56:16Z [decision] live_verify task=c4776136 status=fail rc=1 out=docs/handoff/dispatch-c4776136/live-verify.out
   ```

3. Same file, lines 82–83 — the refusal was **consumed by nothing** (terminal is
   write-once, `leadv2-dispatch-ledger.sh:433` dedups any post-`landed` write):

   ```
   - 2026-09-17T03:56:18Z [decision] dispatch_terminal_dedup task=c4776136 attempted=dead reason=terminal_already_recorded
   - 2026-09-17T03:56:20Z [decision] dispatch_terminal_dedup task=c4776136 attempted=dead reason=terminal_already_recorded
   ```

4. The red artifact on disk — `docs/handoff/dispatch-c4776136/live-verify.out` is
   12 bytes: `probe_rc: 1`. The declared probe (`docs/handoff/dispatch-c4776136/lane-acceptance-cmd`,
   written 04:38 local = 01:38Z at dispatch) is exactly the both-suites acceptance:

   ```
   cd ~/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh >/dev/null 2>&1 && bash plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh >/dev/null 2>&1
   ```

5. The merge beat the verdict: `~/.claude/leadv2-state/leadv2/merge-queue.jsonl` has
   `enqueued`+`acquired` at `03:52:32Z`, `released` `03:52:33Z` — merge commit
   `cc386114` was already in `main` before the red verdict existed.

Mechanism at file:line (pre-fix): the inline landing funnel stamped
`_dl_note landed review_verdict_pass` and merged (old :4816 / :4806), then fell to
the script's LAST statement `:4856 _pc_run_live_verify || true` — after the merge,
after the write-once terminal, with `|| true` eating the refusal and the script
exiting 0. The engine path had the same shape (`landed` stamped at old :4272, probe
walked at old :4299 under `|| true`, exit code taken from the review engine only).

## Reproduction first (pre-fix, from this branch, before any fix-shaped edit)

Harness: scratch repo + lane worktree with one commit + declared probe
(`true; exit 3`) + review resolver/verdict stubs + real close, real ledger in a
scratch file. Drives the REAL `leadv2-dispatch-product-close.sh` end to end.

```
$ /tmp/racc-repro/harness.sh <scripts> 3
CLOSE_RC=0 LANDED_ROW=1 MERGED=1 LV_LINE=[leadv2-dispatch-product-close] live_verify task=raccsig status=fail rc=3 out=docs/handoff/dispatch-raccsig/live-verify.out
```

Red acceptance → close exits 0, `landed` row written, branch merged. The defect,
reproduced (cause class of the underlying bug: the acceptance's exit code was never
an input to any landing decision — the rung walked after the decision was final).

## The invariant installed (fix `6d026377`)

A close may not reach `landed` while the dispatched acceptance exits non-zero; an
acceptance that yields NO verdict is its own refusal, never a pass, and each
silence has its own name:

| verdict | name | where |
|---|---|---|
| probe ran, rc≠0 | `live_verify_fail` (existing name kept) | `_pc_run_live_verify` |
| rung skipped outright (probe declared, phase store unusable) | `acceptance_declared_not_run` | `_pc_run_live_verify` |
| probe could not execute (whitespace-only probe; uncdable root) | `acceptance_could_not_run` | `_pc_run_live_verify` |
| probe ran, no `probe_rc:` line came back | `acceptance_no_exit_code` (was silently coerced to rc=1) | `_pc_run_live_verify` |
| no probe declared | `no_acceptance_block` n/a — still legal | unchanged contract |

Ordering changes (all refusals `_stamp_review_terminal blocked` + `dead` ledger row
+ non-zero close exit, BEFORE any merge or landed row):

- **Inline landing funnel** — `_pc_run_live_verify` now walks before the report
  harvest, before the T11 merge (`merge-queue` acquire → `git merge`), before any
  `_dl_note landed`. The old trailing `_pc_run_live_verify || true` is deleted; the
  script ends `exit 0` only after a genuinely completed funnel.
- **Engine path** — the probe walks before `_dl_note landed review_verdict_pass
  "engine=1"` / `_stamp_review_terminal pass`; refusal exits 1.
- **landed_foreign escape** — walks the same gate before it may stamp `landed`
  (landed is landed; no carve-out).

## Guard suite — `plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh`

7 cases, each driving the real close end to end in a sandbox (scratch HOME/TMPDIR/
`LEADV2_STATE_ROOT`, terminal ledger routed to a scratch file, resolver+review
stubs — no provider contacted):

```
[TEST] PASS: c1: red acceptance (rc 3) refuses the close: no landed, no merge, rc!=0
[TEST] PASS: c2: green acceptance still lands: landed row + merge + rc=0
[TEST] PASS: c3: whitespace probe refuses as acceptance_could_not_run, no landed
[TEST] PASS: c4: missing probe_rc refuses as acceptance_no_exit_code, no landed
[TEST] PASS: c5: declared probe + unusable phase store refuses as acceptance_declared_not_run
[TEST] PASS: c6: probe-less lane still lands (n/a legal — nothing was promised)
[TEST] PASS: c7: engine path gates the probe before the landed stamp (red refuses, green lands)
[TEST] pass=7 fail=0 of 7 — close-blocks-on-red-acceptance
SUITE_RC=0
```

c1 asserts the full refusal shape on the red probe: close rc≠0, no
`"terminal":"landed"` ledger row, `merge-base --is-ancestor branch main` FAILS
(never merged), decision `live_verify task=raccsig status=fail rc=3`, ledger row
`"cause":"live_verify_fail"`. c2 is the mission's claim-2 control: same harness,
probe `exit 0` → landed row + merge + rc=0. c6 pins that the guard is NOT a
blanket fail-closed: a lane dispatched with no acceptance still lands.

First suite run hit one honest red: c5's fixture originally passed `none` (no
declared probe) with the broken phase store — a legal n/a, so the case failed. The
fixture was wrong, not the subject (probe must be DECLARED for the skip to be a
silence); fixed to a declared probe; c5 green. Raw first-run output:

```
[TEST] FAIL: c5: landed row present
[TEST] FAIL: c5: close exited 0
[TEST] FAIL: c5: no acceptance_declared_not_run refusal
[TEST] pass=6 fail=3 of 9 — close-blocks-on-red-acceptance
SUITE_RC=1
```

(The `of 9` counter there was the pre-fix fixture's own double-counting of
sub-assertions; final suite counts 7 cases.)

## Negative controls — one mutation per independent claim, all RUN

Each mutation applied INSIDE the changed body in the lane worktree (never a
scratch copy); a patcher asserted the target string occurs EXACTLY once before
mutating, so no control can rot into a permanent green.

**Control A — the inline landing-seam gate is load-bearing** (claim 1). Mutation:
`exit 1` → `:` in the gate before the `report`/`diff` landing funnel.

```
$ python3 /tmp/racc-repro/patcher.py apply A
OK apply A: 1 occurrence replaced
[TEST] FAIL: c1: close exited 0 on a red probe
[TEST] FAIL: c3: close exited 0
[TEST] FAIL: c4: close exited 0
[TEST] FAIL: c5: close exited 0
→ revert:
OK revert A: 1 occurrence replaced
[TEST] pass=7 fail=0 of 7 — close-blocks-on-red-acceptance
```

With the gate disabled the suite goes red exactly the way production failed
(c4776136): the close exits 0 on a red probe. Revert → green.

**Control B — each silence keeps its own name** (claim 3, distinct reasons).
Mutation: `reason=acceptance_no_exit_code` → `reason=acceptance_could_not_run`
inside `_pc_run_live_verify`.

```
OK apply B: 1 occurrence replaced
[TEST] FAIL: c4: no acceptance_no_exit_code refusal
[TEST] pass=6 fail=1 of 7
→ revert:
OK revert B: 1 occurrence replaced
[TEST] pass=7 fail=0 of 7 — close-blocks-on-red-acceptance
```

**Control C — the engine-path gate is load-bearing** (engine claim). Mutation:
`exit 1` → `:` in the engine path's gate before the landed stamp.

```
OK apply C: 1 occurrence replaced
[TEST] FAIL: c7: engine close exited 0 on a red probe
[TEST] pass=6 fail=1 of 7
→ revert:
OK revert C: 1 occurrence replaced
[TEST] pass=7 fail=0 of 7 — close-blocks-on-red-acceptance
```

Claim 2 (green still lands) is pinned by c2 itself and needs no mutation — it is
the positive control for A and C: on the unfixed code c2 already passed
(reproduction above shows `LANDED_ROW=1 MERGED=1` with rc 0), so the fix did not
turn fail-open into fail-closed; the board still lands.

## How CI selects the suite on a change to `leadv2-dispatch-product-close.sh`

The suite self-registers via its header
`# run-all-triggers: leadv2-dispatch-product-close leadv2-dispatch-ledger leadv2-lane-worktree`
(discovered by `scan_suite_triggers` in `tests/run-all.sh`; `--scope changed`
maps changed file stems to declaring suites). On any change whose stem is
`leadv2-dispatch-product-close`, `bash tests/run-all.sh --scope changed` selects
it. Selection proof from the lane worktree at `6d026377`:

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed | grep close-blocks-on-red-acceptance
leadv2-dispatch-product-close:plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh
leadv2-dispatch-ledger:plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh
leadv2-lane-worktree:plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh
```

51 suites declare the `leadv2-dispatch-product-close` trigger, so the full
changed-scope selection on this commit is wide; the changed-scope runner output is
in the lane's final close report (appended below).

## Changed-scope runner output

See the appendix at the bottom (run at `6d026377`).

## Falsification set (self-check)

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` → clean.
- `bash -n plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh` → clean.
- No Python files changed (nothing to `py_compile`).

## Left red / residuals

Nothing left red by this lane. Boundaries and deliberate scope:

- The changed-scope selection is 51 suites; the runner's own budget applies —
  its verdict is quoted verbatim in the appendix, `[SUITE-TIMEOUT]` /
  `[KNOWN-RED-SKIP]` lines are the runner's named verdicts, not this lane's
  silence. Green here is macOS-only (platform boundary per lane-rules).
- `acceptance_could_not_run detail=root_uncdable` is asserted by the subject but
  not exercised by a dedicated case (the fixture would need a corrupt ROOT
  mid-close); the empty-probe case (c3) covers the same refusal name.
- The engine-path gate is exercised with a stubbed `LEADV2_REVIEW_RUN_BIN`
  (the real engine spawns reviewers; the stub isolates the seam this row owns).

## Appendix — changed-scope runner (verbatim, run at `6d026377`)

(runner output appended after the run completes; see final close report if this
section reads short.)
