# WORKER-DOD-GATE-01 — architecture

Deterministic bash definition-of-done gate: runs on a worker's committed lane BEFORE any
model review, refuses the round on a missing mechanical DoD item, zero model spend.

## 0. CRITICAL pre-flight finding — LANE_WRITES path does not match the real file

`docs/handoff/WORKER-DOD-GATE-01/brief.md` LANE_WRITES lists
`plugins/leadv2/scripts/leadv2-worker-epilogue.sh`. That file does not exist at that path.
The real file (confirmed on disk) is `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh`.

This is not cosmetic: `leadv2-worker-epilogue.sh` itself owns `_lv2_epilogue_path_in_scope()`,
which decides whether a dirty file is "in LANE_WRITES scope" (auto-committed) or
`foreign_dirty` (left uncommitted, exactly the bug class WORKERS-MUST-COMMIT-01 exists to
catch). A prefix-match scoper checking a real edit at `plugins/leadv2/scripts/lib/leadv2-
worker-epilogue.sh` against a LANE_WRITES row spelled `plugins/leadv2/scripts/leadv2-worker-
epilogue.sh` (no `lib/`) does not match — the task's own edit to its own epilogue file would
self-classify as `foreign_dirty` and never get committed by this task's own worker. Every
other listed LANE_WRITES path was existence-checked and is correct:
`plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (to-create), `plugins/leadv2/scripts/leadv2-
mutation-control.sh` (to-create), `plugins/leadv2/scripts/leadv2-review-run.sh` (exists),
`plugins/leadv2/prompts/**` (dir exists, 2 files today), `plugins/leadv2/scripts/tests/test-
worker-dod-gate.sh` (to-create), `tests/run-all.sh` (exists), `docs/handoff/WORKER-DOD-GATE-
01/` (exists, has brief.md + task-class.yaml, no context.yaml yet).

**Fix:** when context.yaml / the worker mission is authored for this task, LANE_WRITES must
read `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh`. Flagging per checklist item 2
(file paths) and item 5 (this is exactly the kind of self-referential contradiction the
checklist exists to catch) — `source: architect(self-check)`.

## 1. Layers affected

| Layer | Files | Nature of change |
|---|---|---|
| Worker finalize (soft signal) | `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` | additive: one more best-effort call before `return 0` |
| Review engine (hard gate) | `plugins/leadv2/scripts/leadv2-review-run.sh` | additive block mirroring the existing SUITE-THAT-CANNOT-FAIL-01 gate, same insertion neighborhood |
| New library | `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (to-create) | 5 checks, callable in report-only or blocking mode |
| New tool | `plugins/leadv2/scripts/leadv2-mutation-control.sh` (to-create) | scratch-tree mutation runner, closes cause-row-2 (4/19 Highs) |
| Test scope registry | `tests/run-all.sh` | additive `--dry-run` flag (does not exist today — verified absent, see §6) |
| Worker-facing docs | `plugins/leadv2/prompts/**` | additive fragment describing the mutation-control contract + DoD checks (wiring into a live system prompt is unverified — see Risk R6) |
| Tests | `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` (to-create) | fixture-per-check, registered in `tests/run-all.sh` |
| Not touched | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | out of LANE_WRITES; its existing catch-all exit-code handling absorbs the new gate without edits (see §5) |

DB / Supabase / migrations: **N/A.** This task is entirely plugin-tooling bash; no schema, no
RLS, no Supabase involvement. (Noted per role template — not silently dropped.)

## 2. Data flow (numbered)

```
worker turn(s) run in lane worktree
        |
        v
[1] leadv2_worker_commit_epilogue() (lib/leadv2-worker-epilogue.sh)
        - auto-commits LANE_WRITES-scoped dirty files (existing, unchanged)
        - NEW: soft DoD probe (report-only, never blocks) -> progress.log/meta.yaml
        |
        v
[2] leadv2-dispatch-product-close.sh
        - builder-selfcheck (existing, unchanged) -> selfcheck.md
        - invokes leadv2-review-run.sh (existing, unchanged call site)
        |
        v
[3] leadv2-review-run.sh, BEFORE pool resolve (new block, same neighborhood as the
    falsifiability gate: after SUITE-THAT-CANNOT-FAIL-01 ends ~line 1318, before
    "# Step 2: pool resolve." at line 1319)
        - runs lib/leadv2-dod-gate.sh checks a-e against git diff main HEAD + report.md
        - PASS  -> falls through to pool resolve (existing code, unchanged)
        - FAIL  -> writes review-gate.md (status: fail, reason: dod_<check>), exit 7
                   (reuses the EXISTING exit code the falsifiability gate already uses for
                   status:fail -- dispatch-product-close.sh's case statement already maps
                   7 -> `_dl_note dead review_verdict_fail` + `_stamp_review_terminal fail`,
                   zero edits needed there)
        - UNDETERMINED (e.g. git diff fails, report.md unreadable) -> status: blocked,
                   exit 8 (same reuse: maps to existing `dead review_roundcap` case)
        |
        v
[4] dispatch-product-close.sh's existing case statement (UNCHANGED) journals the terminal
    state and the lead sees review-gate.md's `reason: dod_<check>` line before spending a
    reviewer arm on the round.
```

Steps [1]-[4] cover the MVP (Option A, §7). The brief's literal ask — an in-band retry loop
inside step [3] that re-invokes the worker up to 2 times before exiting — is Option B, also
specified in §7, with its own risk called out separately (R5) rather than folded silently
into the recommended path.

## 3. Capability census — what already exists and is reused

| Existing primitive | File:line | Reused for |
|---|---|---|
| Falsifiability gate shape (refuse before pool resolve, `status: fail`/`reason:`, exit 7/8) | `leadv2-review-run.sh:1264-1318` | Exact shape being mirrored for the DoD gate block |
| `leadv2-suite-falsifiable.sh` exit-code convention (0 falsifiable / 1 not / 2 undetermined / 3 usage) | `plugins/leadv2/scripts/leadv2-suite-falsifiable.sh:23-30` | Adopted verbatim for both `lib/leadv2-dod-gate.sh` and `leadv2-mutation-control.sh` |
| `mktemp -d` + `trap 'rm -rf "${WORK}"' EXIT` scratch-dir pattern | `leadv2-suite-falsifiable.sh:62-64` | Adopted for `leadv2-mutation-control.sh`'s scratch tree |
| Round-0 selfcheck consumption pattern (`status: fail\nreason: ...` written to `${HANDOFF}/review-gate.md.tmp`, atomic `mv`) | `leadv2-review-run.sh:1243-1249` | Exact write pattern reused for DoD gate output |
| `leadv2-dispatch-product-close.sh` exit-code case statement (0/6/7/8/9/`*`) | `leadv2-dispatch-product-close.sh:2763-2778` | Confirms a NEW review-run.sh exit code needs **zero edits** there only if it reuses 6/7/8; catch-all `*` case exists but buckets under the misleading `review_engine_error` cause, so reuse of 7/8 is preferred over a new code |
| `leadv2-dispatch-ledger.sh` terminal-write primitives (`dispatch_ledger_write_terminal`, attempt tracking via `_lv2_terminal_attempt_superseded`) | `leadv2-dispatch-ledger.sh:243,291` | NOT called directly by review-run.sh by design (`leadv2-review-run.sh:13`: "_dl_note ... remain lane-owned; the lane wraps this call") — confirms review-run.sh must stay a bare, self-contained script; ledger writes stay dispatch-product-close.sh's job, unchanged |
| `--resume-lane` re-dispatch (bare lane name = task-sig8/founder-id, or absolute worktree path) | `leadv2-dispatch-code.sh:408,931-932` | Candidate mechanism for Option B's retry re-entry; re-entrancy against dispatch-code.sh's own reservation/lock system is UNVERIFIED (R5) |
| `worker_exit=clean|dirty auto_committed=N foreign_dirty=N` field convention in `progress.log`/`meta.yaml` | `lib/leadv2-worker-epilogue.sh:80-137` | Mirrored exactly for the new `worker_dod=pass|fail:<checks>` soft-signal field |
| `lv2_selfcheck_run <diff_file> <diff_root> <root> <out_md> <writes_csv>` function-call convention, `verdict:`/`diff_hash:` fields | `lib/leadv2-builder-selfcheck.sh:87,104,537` | Modeled for `lib/leadv2-dod-gate.sh`'s own function signature (see §4) — different concern (mechanical DoD items, not compile/lint), not a duplicate |
| `EXTRA_SUITE_MAP` string-row format (`<changed-stem>:<suite-path>`, one per line) | `tests/run-all.sh:105` | Reused verbatim for registering `test-worker-dod-gate.sh` |
| `add_suite()` resolves `SUITES[]` before the execution loop; **no `--dry-run` flag exists today** (verified: `grep -n dry-run tests/run-all.sh` → no match, `usage()` string only shows `[--scope changed|all]`) | `tests/run-all.sh:10,37,391-406` | Gap — must be added, see §6 |
| `leadv2-phase-record.sh` (`cmd_record`/`cmd_assert`, per-phase artifact verification) | `leadv2-phase-record.sh:689,820` | NOT reused directly — different granularity (task-level phase milestones vs. per-round mechanical checks). Noted as a downstream consumer: a `review` phase's `cmd_assert` should treat `complete_with_dod_fail` as not-yet-`done`, which it already will since DoD-gate exit 7 never lets dispatch-product-close.sh reach the `_stamp_review_terminal pass` / phase `--status done` branch (`leadv2-dispatch-product-close.sh:2763-2770`) |
| Memory: "Never prune worktrees while lanes run" (a broad `git worktree prune` sweep killed 2 live lanes) | founder-lesson, 2026-08-22 | Directly shapes `leadv2-mutation-control.sh`'s scratch-tree mechanism choice (§4) — `git archive`, never `git worktree add`/`prune` |

## 4. Check list — `lib/leadv2-dod-gate.sh`

Function signature (mirrors `lv2_selfcheck_run`'s convention):
```
lv2_dod_gate_run <repo_root> <handoff_dir> <task_id> <diff_file> <out_md>
# exit 0 = pass, 1 = fail (reason: line set), 2 = undetermined, 3 = usage error
```

| Check | Reads | Exact refusal condition | Negative control (fixture) |
|---|---|---|---|
| **(a) report exists+committed+headed** | `${HANDOFF}/report.md`; `git -C ROOT show HEAD:docs/handoff/<task>/report.md` | file missing, OR not present at `HEAD` (uncommitted), OR no line matching `^##[[:space:]]+(Round[[:space:]]+[0-9]+[[:space:]]+Evidence|Evidence)[[:space:]]*$` | fixture repo with report.md deleted → red; heading line stripped → red; present+committed+headed → green |
| **(b) paste-lines answered** | `${HANDOFF}/brief.md` lines matching `/[Pp]aste/`; `${HANDOFF}/report.md` fenced blocks + nearest preceding heading (≤15 lines above) | for each brief "paste" line, extract key phrase (text after the last `:`, tokenized ≥4-char words); PASS needs a fenced block whose preceding heading/paragraph shares ≥50% of those tokens. Zero match → `dod_fail check=paste_evidence_missing`. **Sub-check:** if the brief line also matches `/mutation|negative control|RUN via the new runner/i`, the fenced block must additionally contain a literal `MUTATION-CONTROL ok suite=` line — a fenced block without it → `dod_fail check=mutation_control_not_via_runner` (this is the direct fix for cause-row-2, 4/19 Highs: a hand-typed "ran the mutation, it went red" transcript with no runner sentinel) | fixture brief.md with one paste-line, report.md with no fenced block → red; add block with mismatched heading → still red; matching heading, no `MUTATION-CONTROL ok` → red for the sub-check; both present → green |
| **(c) new suites registered** | `git diff main HEAD --name-status \| awk '$1=="A"'` filtered to the SAME suite-path regex the falsifiability gate already uses (`review-run.sh:1318`); `tests/run-all.sh --dry-run --scope changed` output (new flag, §6) | any added suite path absent from the dry-run's printed list → `dod_fail check=suite_unregistered suite=<path>` | fixture diff adds `tests/tests/test-fixture-x.sh` with no `run-all.sh` entry → red; add stem-match or `EXTRA_SUITE_MAP` row → green; remove the row again → red |
| **(d) no runtime-state paths in diff** | `git -C ROOT diff main HEAD --name-only` | any path matches `^(docs/leadv2/\|docs/LEAD_V2_STATE\.md$\|docs/handoff/dispatch-nw)` → `dod_fail check=runtime_state_in_diff paths=<csv>`. Extension point: if `lib/leadv2-land.sh` exists (LAND-PATH-IS-BROKEN-01 not yet landed — confirmed absent on disk today), source its path-list function instead of the hardcoded regex, same conditional-source idiom as `lib/leadv2-review-reroute-note.sh` at `review-run.sh` | fixture diff touching `docs/leadv2/x.yaml` → red; diff without it → green |
| **(e) external claims carry evidence** | `${HANDOFF}/report.md`, line-window ±2 around any line matching `(docs say\|macOS\|Claude Code\|Z\.AI\|endpoint\|rate limit\|version [0-9])` (case-insensitive) | no `evidence:` or `UNVERIFIED` token within the ±2-line window → `dod_fail check=unverified_claim line=<n>` | fixture report.md line "Verified on macOS." with no evidence line within 2 lines → red; add `evidence: ...` line → green |

Every check's refusal line is emitted in the exact shape the brief specifies:
`dod_fail check=<name> <key=value ...>` — one line per failing check, all failing checks
listed (not just the first), so a worker fixing blind gets the full list in one round.

## 5. `leadv2-mutation-control.sh` — contract

```
leadv2-mutation-control.sh <suite> <file> <sed-or-patch>
# exit 0 = mutation applied, suite went red as required (ok)
# exit 1 = mutant survived -- suite stayed green despite the mutation (the exact
#          cause-row-2 failure this script exists to prevent)
# exit 2 = control_not_applied -- anchor matched 0 or >1 times, or the edit was a no-op
# exit 3 = usage error
```

Mechanism (chosen specifically to avoid the worktree-prune hazard — see Risk R2):
1. `scratch="$(mktemp -d ...)"`, `trap 'rm -rf "${scratch}"' EXIT` — same idiom as
   `leadv2-suite-falsifiable.sh:62-64`.
2. Snapshot **committed** content only: `git -C "${ROOT}" archive HEAD | tar -x -C
   "${scratch}"`. Deliberately NOT `git worktree add` — a real worktree registers in
   `.git/worktrees/`, and a broad `git worktree prune` (the exact action that killed 2 live
   lanes on 2026-08-22 per founder-lesson) is one careless cleanup command away in a repo
   where several other scripts touch worktrees. `git archive` never registers anything to
   prune; cleanup is a plain `rm -rf` of the scratch dir, nothing shared to race on.
3. For a `sed` expression: `grep -c <anchor-pattern>` on the scratch file's ORIGINAL content
   must equal exactly 1 before applying — anything else is `control_not_applied` (this is
   the literal "anchor does not match exactly once" requirement from the brief). For a
   unified-diff patch: `patch -p1 --dry-run` first: nonzero → `control_not_applied`.
4. Apply, then `cmp -s` before/after content — identical → `control_not_applied` (a matched
   anchor whose replacement is a no-op is still not a real mutation).
5. Run the suite from the scratch tree (`cd "$(dirname "${scratch_suite}")" && bash
   "${scratch_suite}"`). Exit 0 despite the mutation → exit 1 with `mutant_survived` and the
   suite's own last output lines (so the caller can see WHY it didn't catch the mutation).
   Non-zero → success: print `MUTATION-CONTROL ok suite=<path> mutant=<file>:<anchor>
   red_line=<first failing assertion line>` — this exact line is what DoD check (b)'s
   sub-check greps for.

## 6. `tests/run-all.sh` — required `--dry-run` addition

Verified absent today (no match for `dry-run`/`DRY_RUN` anywhere in the file; `usage()` only
lists `[--scope changed|all]`). Brief step (c) assumes this flag exists — it does not, and
`tests/run-all.sh` is in this task's own LANE_WRITES, so this is an in-scope, additive fix,
not a blocker to hand back.

Insertion points (both verified by line number):
- Arg parser, in the existing `while [[ $# -gt 0 ]]; do case "$1" in ...` block
  (`tests/run-all.sh:29-38`): add `--dry-run) DRY_RUN=1; shift ;;` and update the `-h`
  usage string to `[--scope changed|all] [--dry-run]`.
- Execution loop (`tests/run-all.sh:~406`, immediately before `for suite in
  "${SUITES[@]:-}"; do printf '[RUN] %s\n' ...`): when `DRY_RUN=1`, print each resolved
  `SUITES[]` entry (repo-relative) one per line and `exit 0` — never execute a suite.
  Additive only: `DRY_RUN` unset preserves today's behavior byte-for-byte.

## 7. Retry mechanism — two options, one recommended

The brief's item 3 (`up to 2 times, then exit complete_with_dod_fail`) requires the failing
worker to get another turn before the round is refused to the lead. Two designs, presented
because they trade off differently and I will not fold the riskier one in silently:

**Option A — recommended for this task.** No in-band auto-retry. DoD-gate fail writes
`review-gate.md` immediately (`status: fail`, `reason: dod_<check>`), reusing exit 7 exactly
like the falsifiability gate — **zero new orchestration, zero edits outside LANE_WRITES,
zero re-entrancy risk.** The "next turn" happens at the lead level: the lead reads
`reason: dod:<check>`, appends the gate's reason lines to the mission, and re-dispatches via
the already-proven `--resume-lane <sig8>` flow — the exact same motion the lead already
performs for every other review refusal today. This delivers the full mission goal (mechanical
misses caught before a reviewer model is spent) with no new failure surface.

**Option B — as literally specified in the brief.** An in-band loop inside the new DoD block
in `leadv2-review-run.sh` (before the `exit 7`/`exit 8` terminal writes): on fail, if a
`${HANDOFF}/.dod-attempt` counter is `< LEADV2_DOD_GATE_MAX_RETRIES:-2`, write
`${HANDOFF}/dod-feedback.md` (the failing check lines), increment the counter, and
synchronously re-invoke `leadv2-dispatch-code.sh --resume-lane <TASK>` to get one more worker
turn in the SAME worktree, then loop back and re-evaluate the gate against the freshly
committed HEAD. Only after 2 failed retries does it write the terminal `status: fail` and
exit. This is closer to the brief's literal ask but carries Risk R5 (below) — **unverified**
whether `leadv2-dispatch-code.sh`'s own reservation/lock system (`leadv2-dispatch-code.sh` has
extensive "pending-and-fresh -> refused" logic for concurrent calls on the same sig) permits a
recursive `--resume-lane` call from a process THAT SAME sig's outer dispatch already spawned,
without a probe. I have not run that probe (out of this design task's read/discovery budget
and would require executing dispatch-code.sh against a live fixture lane, which is
implementation, not design).

Recommendation: ship Option A now (closes the mission's stated goal — mechanical Highs caught
for free), and gate Option B behind a follow-up spike whose FIRST step is exactly that
re-entrancy probe, before any retry-loop code is written.

## 8. Wiring — file:line

| Hook | File:line | Shape |
|---|---|---|
| Soft signal (non-blocking) | `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh`, insert before the final `return 0` at line 138, inside `leadv2_worker_commit_epilogue()` | best-effort call to `lib/leadv2-dod-gate.sh` in report-only mode; writes `worker_dod=pass\|fail:<checks>` to `progress.log`/`meta.yaml` using the exact `>> ... 2>/dev/null \|\| true` idiom already used at lines 80-137; never changes the function's `return 0` contract |
| Hard gate | `plugins/leadv2/scripts/leadv2-review-run.sh`, new block after the SUITE-THAT-CANNOT-FAIL-01 block ends (that block's closing `done < <(...)` is immediately before line 1319 `# Step 2: pool resolve.`) | same shape as `review-run.sh:1264-1318`: `if [[ -f "${_DOD_GATE_SH}" ]]; then ... fi`, writes `${HANDOFF}/review-gate.md.tmp` then atomic `mv`, `exit 7`\|`8` |
| Suite registration | `tests/run-all.sh:105` (`EXTRA_SUITE_MAP` string block) | append `leadv2-dod-gate.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` and `leadv2-mutation-control.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` rows so a change to either new script re-selects the suite under `--scope changed` |
| `--dry-run` flag | `tests/run-all.sh:29-38` (parser), `~406` (execution loop) | see §6 |

## 9. Output contract — English sentinels

`review-gate.md` (unchanged schema from the existing falsifiability/selfcheck writers):
```
status: fail
reason: dod_<check>
check: <a|b|c|d|e short name, e.g. paste_evidence_missing>
detail: <one line>
attempt: <n>              # Option B only
max_retries: <n>          # Option B only

<human-readable explanation, same printf-block convention as review-run.sh:1274-1281>
```
`status: blocked` for the rc=2/undetermined path (e.g. `git diff` fails, report.md
unreadable) — same "visible blocked state, never an implicit pass" doctrine already stated
at `review-run.sh:1258`.

`dod-gate.md` (new, full diagnostic — same role as `selfcheck.md`): one line per check with
its own pass/fail and the offending path/line, written by `lib/leadv2-dod-gate.sh` regardless
of overall verdict, so a human can see all 5 checks' individual status, not just the first
failure. Parser contract (REVIEW-SENTINELS-LANGUAGE-01, sibling task, not duplicated here):
every emitted line is English; the DoD gate MUST NOT emit a Russian sentinel, and per that
task's contract a parser encountering a non-English status line fails loud rather than
guessing — the DoD gate satisfies this by construction (all `printf`/literal strings above
are English-only, matching the existing `review-gate.md` writers verbatim).

`progress.log`/`meta.yaml` soft-signal field (epilogue, Option A/B both):
```
worker_dod=pass
# or
worker_dod=fail:paste_evidence_missing,runtime_state_in_diff
```

## 10. Plan steps

1. **Fix the LANE_WRITES path before dispatch.** Reads: `docs/handoff/WORKER-DOD-GATE-01/brief.md`,
   live filesystem check of `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh`. Writes:
   the task's context.yaml/mission (whichever artifact the orchestrator authors next) with
   the corrected `lib/` path. Acceptance (observable): the worker's own edit to its epilogue
   file, at commit time, is classified `in_scope` (not `foreign_dirty`) by
   `_lv2_epilogue_path_in_scope()` — verifiable by running the epilogue's own commit step
   against a fixture diff touching the corrected path and confirming `auto_committed=1
   foreign_dirty=0` in `progress.log`.

2. **Add `lib/leadv2-dod-gate.sh` with checks a-e.** Reads: `docs/handoff/WORKER-DOD-GATE-01/brief.md`
   (cause table + check specs), `plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` (exit-code
   and mktemp-trap conventions to mirror), `plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh`
   (function-call signature convention). Writes: `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`
   (new file, `lv2_dod_gate_run` function per §4's signature). Acceptance (observable): invoking
   the function against a hand-built fixture missing report.md returns rc=1 with `reason:
   dod_report_missing` on stdout/`dod-gate.md`; against a fully-compliant fixture returns rc=0;
   both runs complete in comfortably under the "bash + grep + git only, under 5s" budget the
   brief mandates (time the invocation, print the wall-clock in the test suite's own output).

3. **Add `leadv2-mutation-control.sh`.** Reads: brief.md item 2's exact contract, this
   document's §5 mechanism spec, `leadv2-suite-falsifiable.sh` for the scratch-dir idiom.
   Writes: `plugins/leadv2/scripts/leadv2-mutation-control.sh` (new file). Acceptance
   (observable): run it against a real fixture suite + a sed expression whose anchor exists
   exactly once in a fixture file — prints `MUTATION-CONTROL ok suite=... red_line=...` and
   exits 0; re-run against the SAME suite with an anchor that does not exist in the file —
   exits 2 with `control_not_applied` printed; re-run with a sed expression that matches but
   whose target suite has no assertion covering the mutated code — exits 1 with
   `mutant_survived` printed. All three observable via captured stdout + `$?`, no manual
   interpretation needed. Confirm the scratch tree never appears in `git -C ROOT status
   --porcelain` after the run (proves the mutation never touched the lane).

4. **Wire the hard gate into `leadv2-review-run.sh`.** Reads: `leadv2-review-run.sh:1230-1330`
   (exact insertion neighborhood, already read in full for this design), §7's Option A
   pseudocode. Writes: `plugins/leadv2/scripts/leadv2-review-run.sh` (new block, additive,
   between the falsifiability gate's closing and `# Step 2: pool resolve.`). Acceptance
   (observable): run `leadv2-review-run.sh --task <fixture> --root <fixture-repo> --handoff
   <dir> --diff <diff-with-a-known-dod-violation> --author <x>` and confirm `review-gate.md`
   is written with `status: fail` and `reason: dod_<check>` BEFORE any `resolve_review_pool_call`
   log line appears (grep the script's own stderr/decision-log output for the absence of
   `review_security`/`review_gate ... status=fail round=0 reason=selfcheck` — i.e. prove the
   pool was never reached), and the process exits 7.

5. **Wire the soft signal into `leadv2-worker-epilogue.sh`.** Reads: this document's §8 exact
   line target, the corrected path from step 1. Writes:
   `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` (one additive best-effort call before
   the final `return 0`). Acceptance (observable): run `leadv2_worker_commit_epilogue` against
   a fixture worktree with a report.md missing its round heading — `progress.log` gains a
   `worker_dod=fail:report_no_heading` line, AND the function's own return code is still 0
   (never aborts the caller), matching the file's documented "always returns 0" contract.

6. **Add `--dry-run` to `tests/run-all.sh`.** Reads: this document's §6 exact insertion points
   (lines 29-38 and ~406, already verified against the live file). Writes: `tests/run-all.sh`.
   Acceptance (observable): `tests/run-all.sh --scope changed --dry-run` against a fixture diff
   that adds one new `test-*.sh` prints that suite's path and exits 0 without any `[RUN]`/`[PASS]`
   line appearing in its output; the SAME invocation without `--dry-run` on an unmodified
   checkout still runs and passes exactly as it does today (regression check).

7. **Build `test-worker-dod-gate.sh` and register it.** Reads: brief.md item 4, this
   document's §4 negative-control column (one row per check). Writes:
   `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` (new suite: one red+green fixture pair
   per check a-e, plus the two `leadv2-mutation-control.sh` cases — anchor-applies vs
   anchor-absent), `tests/run-all.sh` (append the two `EXTRA_SUITE_MAP` rows from §8).
   Acceptance (observable): `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh
   plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` exits 0 (verdict: falsifiable) —
   i.e. the new suite itself passes the SAME falsifiability gate it is designed to feed;
   `tests/run-all.sh --scope changed --dry-run` on a diff touching only
   `leadv2-mutation-control.sh` lists `test-worker-dod-gate.sh` in its output (proves the
   `EXTRA_SUITE_MAP` row actually resolves, not just exists as text).

8. **Write `report.md` for THIS task, and run its own gate against itself.** Reads: all
   artifacts above. Writes: `docs/handoff/WORKER-DOD-GATE-01/report.md` with a `## Round N
   Evidence` heading, the cause-row table with which check catches each historical failure
   shape, and an explicit "what this gate does NOT catch" section (design disagreement,
   reviewer hallucination — routed to GATE-PROVES-ITS-OWN-CONTROL-01 per the brief). Acceptance
   (observable): running `lib/leadv2-dod-gate.sh` against THIS task's own committed diff and
   report.md returns rc=0 (the gate passes its own gate) — paste that exact invocation and its
   stdout into report.md as the closing proof.

## 11. Off-limits (for the implementing agent to ignore/not touch)

- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — not in LANE_WRITES; its existing
  exit-code case statement absorbs the new gate without edits (§3, §7). Touching it is a scope
  violation for this task; if the `complete_with_dod_fail` ledger-cause distinctness (§9) is
  wanted later, that is a separate, explicitly-scoped follow-up task.
- `plugins/leadv2/scripts/glm-coder.sh`, `kimi-coder.sh`, `freepool-coder.sh`,
  `claude-subsession.sh` — the actual coder-wrapper turn loops. Not in LANE_WRITES. Option B's
  "same conversation, next turn" phrasing would only be literally deliverable by editing these;
  Option A (recommended) avoids the need entirely.
- `lib/leadv2-land.sh` — does not exist yet (LAND-PATH-IS-BROKEN-01 not landed, verified
  absent). Check (d)'s runtime-state list stays hardcoded until that task lands; do not invent
  or stub the file here.
- `REVIEW-SENTINELS-LANGUAGE-01`'s own parser/contract work — consume the English-sentinel
  contract (§9), do not re-implement or duplicate its language-detection logic.
- Any model call inside the gate itself — brief is explicit: "bash + grep + git only, under 5s."
  `leadv2-mutation-control.sh` runs a suite, never an LLM.

## 12. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | LANE_WRITES path mismatch (§0) causes the task's own epilogue edit to self-classify as `foreign_dirty` and never commit | CRITICAL | Correct the path to `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` before dispatch (plan step 1) |
| R2 | `leadv2-mutation-control.sh` using `git worktree add` for its scratch tree risks the same class of incident as the 2026-08-22 "pruned 2 live lanes" lesson if any cleanup path ever calls a broad `prune` | HIGH | Use `git archive HEAD \| tar -x` instead (§5) — no worktree registry entry ever created, nothing to prune |
| R3 | `tests/run-all.sh --dry-run` does not exist; brief's check (c) verification method is unusable as literally written | HIGH | Add the flag (§6, in-scope since the file is in LANE_WRITES); flagged here so it is not silently discovered mid-implementation and treated as scope creep |
| R4 | Check (b)'s token-overlap fuzzy match (≥50% of key-phrase tokens) is a heuristic — a legitimately-answered paste-line with very different wording from the brief could false-positive as `paste_evidence_missing` | MEDIUM | Threshold is explicitly a tunable, not a fixed law (§4); `test-worker-dod-gate.sh`'s fixtures (plan step 7) must include a "differently-worded but valid" case to calibrate it before shipping, not just exact matches |
| R5 | Option B's recursive `leadv2-dispatch-code.sh --resume-lane` call from inside a process that dispatch-code.sh's own reservation/lock system may see as a concurrent call on the same sig — re-entrancy safety UNVERIFIED | CRITICAL (if Option B is chosen) | Ship Option A now; gate Option B behind a dedicated re-entrancy probe as its first implementation step, not an assumption |
| R6 | `plugins/leadv2/prompts/**` currently holds only 2 unrelated files (`fork-session-mission.md`, `memory-gc-verdict.md`); no inclusion/wiring mechanism into a live worker system prompt was found within this design's discovery budget | MEDIUM | Implementing developer must confirm HOW (or whether) files under `prompts/` reach a running worker's system prompt before relying on a new fragment there to change worker behavior — do not assume it is live just because the directory accepts writes |
| R7 | Two concurrent lanes both appending `EXTRA_SUITE_MAP` rows to `tests/run-all.sh` is a known, pre-existing merge-conflict surface (already hit per the file's own `PHASE-DISCIPLINE-01 rows migrated ... at the 2026-08-28 merge` comment) | LOW (pre-existing, not introduced by this task) | No new mitigation proposed here — same ordering discipline (rebase before commit) already governs every other lane touching this file |
| R8 | Check (e)'s external-claim regex (`docs say\|macOS\|Claude Code\|Z\.AI\|endpoint\|rate limit\|version [0-9]`) is necessarily a fixed list and will miss claim shapes not yet seen | MEDIUM | Treat the regex as a living list (same posture as `ENGINE-REFERENCE.md`'s flag registry in the sibling repo) — extend it when a new untagged-claim shape is caught by a human review instead of by this gate |

## 13. Mandatory constraint checklist — results

1. **Env var naming.** All proposed flags (`LEADV2_DOD_GATE`, `LEADV2_DOD_GATE_MAX_RETRIES`)
   follow the `LEADV2_*` convention observed everywhere else in this file set
   (`LEADV2_REVIEW_MACHINE_ROUND0`, `LEADV2_BUILDER_SELFCHECK`,
   `LEADV2_SUITE_FALSIFIABLE_TIMEOUT`) — no drift. No `.claude/settings.json` cross-check
   applies here (that rule is persona-engine-specific; this task is entirely inside the
   leadv2 plugin repo). PASS.
2. **File paths.** One CRITICAL mismatch found and flagged (§0/R1). All other LANE_WRITES
   paths existence-checked against the live tree; to-create paths explicitly marked as such
   throughout this document. `lib/leadv2-land.sh` confirmed absent, treated as a future
   extension point, not fabricated. DONE, with the one finding surfaced, not silently fixed.
3. **`claude -p` commands.** None proposed by this design — the gate is bash + grep + git
   only, no model calls, per the brief's explicit "Do NOT" list. N/A.
4. **Concurrent access.** `tests/run-all.sh` EXTRA_SUITE_MAP append is a known, pre-existing,
   already-lived-with race (R7, LOW, no new mitigation needed). The mutation-control scratch
   tree is per-invocation-unique (`mktemp -d`) with no shared state via `git archive` (R2's
   fix also removes the only shared-state concern a `git worktree add` approach would have
   introduced). `report.md`/`dod-gate.md` are single-writer-single-reader within one lane's
   sequential pipeline — no race. DONE.
5. **Config contradiction check.** New env vars (`LEADV2_DOD_GATE*`) have zero prior usage
   (confirmed: `leadv2-dod-gate.sh` and `leadv2-mutation-control.sh` are both to-create, so no
   existing semantics to contradict). PASS.

## 14. Acceptance (top-level)

**Surface:** `plugins/leadv2/scripts/leadv2-review-run.sh` refuses a round with `review-gate.md`
`status: fail`/`reason: dod_<check>` and exit 7, BEFORE `resolve_review_pool_call` is ever
invoked, whenever a worker's committed lane is missing report.md/its evidence heading, has an
unanswered "paste" instruction, adds an unregistered test suite, carries a runtime-state path
in its diff, or contains an external-system claim with no `evidence:`/`UNVERIFIED` tag.

**Human-observable line:** running `leadv2-review-run.sh` against a fixture lane built to
violate exactly one of checks (a)-(e) prints a `review_gate task=<x> status=fail round=0
reason=dod_<check>` decision line and produces zero calls to any reviewer model (verifiable by
the absence of any `review_security`/pool-resolve log line in the same run) — the round is
refused for the price of one bash invocation, not a 30-45 minute model round.

DELIVERABLE_COMPLETE
