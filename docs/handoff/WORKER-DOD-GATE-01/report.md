# WORKER-DOD-GATE-01 — report

## Evidence

This round (build round 3) picks up from `9522b8d4` (gate lib, mutation-control,
wiring diffs) and `fd6bdbec` (test-worker-dod-gate.sh suite + check (c) fix).
Steps 1 and 2 of `build-round-2.md` were already done; this round finishes
steps 3-6: EXTRA_SUITE_MAP registration for every touched carrier, the wiring
proof, the falsifiability verdict, and this report.

`main` was merged first (`git merge main --no-edit`, clean auto-merge, fast-forward
of `tests/run-all.sh`'s EXTRA_SUITE_MAP block via `ort`).

## What was built (this round)

- `tests/run-all.sh`: five new EXTRA_SUITE_MAP rows mapping
  `leadv2-dispatch-product-close.sh`, `leadv2-review-run.sh`,
  `leadv2-worker-epilogue.sh`, `leadv2-helpers.sh` and `leadv2-lane-outcome.sh`
  to `test-worker-dod-gate.sh`, so `--scope changed` selects the suite for
  every carrier this task's build touched (previously only
  `leadv2-dod-gate.sh` and `leadv2-mutation-control.sh` were mapped).
- Live mutation-control run against this round's own diff (see
  `## Mutation-control` below), bound to `diff_hash` via
  `docs/handoff/WORKER-DOD-GATE-01/mutation-control/20260902T102935Z-29873.txt`.
- This report.

## Checks and their negative controls

Every row below is a fixture pair inside
`plugins/leadv2/scripts/tests/test-worker-dod-gate.sh`, run live (see
`## Suite run` below for the full 27/27 pass output — not asserted from memory).

| cause (from brief §Why) | check | red fixture | green fixture |
|---|---|---|---|
| brief step skipped: no report.md | (a) report_missing_or_unheaded | `check_a: missing report.md -> fail` | `check_a: committed report.md with Evidence heading -> pass` |
| brief step skipped: heading present but not committed/named | (a) report_missing_or_unheaded | `check_a: report.md without evidence heading -> fail` | `check_a: brief never mentions report.md -> skip, not fail` |
| brief step skipped: "paste X" with nothing pasted | (b) paste_evidence_missing | `check_b: paste-line with no matching fenced section -> fail` | `check_b: bound mutation-control artifact matches diff_hash -> pass` |
| mutation control that never applied its mutant | (b) mutation_control_not_via_runner | `check_b: mutation-control paste-line present but no bound artifact -> fail` | `check_b: bound mutation-control artifact matches diff_hash -> pass` |
| brief step skipped: suite not registered | (c) suite_unregistered | `check_c: new suite path touched by diff, unregistered -> fail` | `check_c: suite registered via EXTRA_SUITE_MAP -> pass` / `check_c: conventional tests/test-*.sh path self-selects -> pass` |
| runtime/state files in the diff | (d) runtime_state_in_diff | `check_d: runtime-state path in diff -> fail` | `check_d: clean diff -> pass` |
| untagged external claim (no evidence:, no UNVERIFIED) | (e) — report-only, never blocks rc (D8) | `check_e: external claim w/o evidence:/UNVERIFIED nearby -> dod_note emitted` | `check_e: claim immediately followed by evidence: -> no note` |
| reviewer hallucination | NOT COVERED — routed to GATE-PROVES-ITS-OWN-CONTROL-01 (see `## Not done`) | — | — |
| design disagreement | NOT COVERED — routed to GATE-PROVES-ITS-OWN-CONTROL-01 (see `## Not done`) | — | — |

Every hard check (a)-(d) also has an rc=2 "undetermined, never a silent
pass" fixture for missing/unreadable input, distinct from the red/green pair
above (`check_b: no diff_file with a mutation-control line present ->
undetermined`, `check_d: missing diff_file -> undetermined, never a silent
pass`), plus a portability fixture for check (c) (`check_c: no
tests/run-all.sh in repo -> skip (portability)`).

### check (a)/(b) calibration against the 37-report corpus

UNVERIFIED: the 37-report calibration corpus mentioned in context.yaml D4
(architect-v2's regex calibration, target 0 false refusals for (a), <=15%
for (b)) was measured during the plan/build-round-1 phase, not re-run this
round — this round's turn budget went to steps 3-6 (run-all proof, wiring
proof, falsifiability, this report) per `build-round-3.md`'s explicit scope.
Re-running the corpus check against the current `docs/handoff/*/report.md`
population is listed under `## Not done`.

## Mutation-control

Live run against this round's own diff, using
`leadv2-mutation-control.sh` (never hand-editing, never `git archive HEAD`,
never `git worktree add` — D5):

```
$ DIFF_HASH=491731d9df73a5e76c6e45539e3e862a0cd0c3fc356323eb065ac7cb6870d66a
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-worker-dod-gate.sh \
    plugins/leadv2/scripts/lib/leadv2-dod-gate.sh \
    's|_DOD_RUNTIME_STATE_REGEX=.*|_DOD_RUNTIME_STATE_REGEX="NEVERMATCH_XYZ_ONLY"|' \
    "${DIFF_HASH}" \
    docs/handoff/WORKER-DOD-GATE-01
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-worker-dod-gate.sh file=plugins/leadv2/scripts/lib/leadv2-dod-gate.sh red_line=[TEST] PASS: check_a: missing report.md -> fail diff_hash=491731d9df73a5e76c6e45539e3e862a0cd0c3fc356323eb065ac7cb6870d66a
$ echo RC=$?
RC=0
$ git status --porcelain -- plugins/leadv2/scripts/lib/leadv2-dod-gate.sh
(empty — the lane's own working tree was never touched, only the scratch copy)
```

This neuters `_DOD_RUNTIME_STATE_REGEX` (check (d)'s anchor) in a scratch
`mktemp -d` copy of the whole tree (`git ls-files -co --exclude-standard` +
`tar`, a FULL copy including `lib/`, `scripts/`, everything tracked or
untracked-but-not-gitignored — never `git archive HEAD`, which is
committed-only and would miss this round's own uncommitted-at-mutation-time
files, D5). Baseline ran green first (`baseline_rc=0`), the mutant then
turned the suite red (`mutated_rc=1`), and the artifact was written to
`docs/handoff/WORKER-DOD-GATE-01/mutation-control/20260902T102935Z-29873.txt`
with `diff_hash` bound to this round's own diff — the only thing check (b)'s
mutation sub-check will accept per D7 (never a prose grep for a
MUTATION-CONTROL sentinel string).

The 4 exit-code cases (ok / mutant_survived / anchor_count /
baseline_not_green) are each proven by their own red+green fixture inside
`test-worker-dod-gate.sh` (see suite run below) — re-asserted live above for
this round's real diff, not just the fixture harness.

## Wiring proof

Both call sites fire the hard gate **before** the `LEADV2_REVIEW_ENGINE`
branch splits, so it runs unconditionally regardless of that flag's
production-default value of 0 (the CRITICAL finding this task exists to fix
— a v1 design reachable only behind `LEADV2_REVIEW_ENGINE=1` would have been
inert in production).

`plugins/leadv2/scripts/tests/test-worker-dod-gate.sh`'s wiring section
extracts the real gate block from `leadv2-dispatch-product-close.sh` by
anchor comment (not a hardcoded line range) and runs it against a fixture
diff that violates check (d), for both `LEADV2_REVIEW_ENGINE` unset
(production default) and `=1`:

```
[TEST] PASS: wiring: LEADV2_REVIEW_ENGINE unset (production default) -> exit 7 before engine split, review-gate.md written
[TEST] PASS: wiring: LEADV2_REVIEW_ENGINE=1 -> identical refusal, exit 7 before engine split
```

Both assertions check: `exit 7`, the exact `EMIT decision review_gate
task=WIRETEST status=fail round=0 reason=dod_runtime_state_in_diff` line,
`review-gate.md` on disk with `status: fail` / `reason:
dod_runtime_state_in_diff`, and — the falsifiable half — that the harness's
`REACHED_ENGINE_SPLIT` sentinel (printed immediately after the extracted
block, standing in for `resolve_review_pool_call`/engine invocation) never
appears in the captured output. No `pool_ok`/`arms=` line is ever produced
because the gate block returns before reaching it.

The defense-in-depth call in `leadv2-review-run.sh` (for direct/standalone
invocations bypassing `dispatch-product-close.sh`) is exercised by the
suite's `lv2_dod_gate_run` fixture tests (fully-compliant -> rc=0;
runtime-state violation -> rc=1, reason recorded) rather than a second
process-level harness, since `leadv2-review-run.sh`'s own call site is a
one-line conditional-source of the identical `lv2_dod_gate_run` function
(D14) — the wiring risk (which branch order, which flag) is specific to
`dispatch-product-close.sh` and is what the harness above targets.

**Mutant-copy-must-be-a-full-copy-incl.-lib/ check**: `leadv2-mutation-control.sh`
snapshots via `git ls-files -co --exclude-standard -z | tar` (line ~81),
which lists every tracked-or-untracked-non-ignored file in the WHOLE repo
tree, not a `plugins/leadv2/scripts/`-only subset — `lib/` is included by
construction, there is no separate include-list to miss. Confirmed live
above: the mutation target `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`
is under `lib/` and the scratch copy ran it successfully.

## tests/run-all.sh --scope changed

Run in the foreground with `timeout 900` (not backgrounded — round 2 died
backgrounding this exact command under a Monitor and ending its turn on the
wait; this round never does that):

```
$ timeout 900 bash tests/run-all.sh --scope changed
... (core-offline shard output, ~30s+) ...
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=16 fail=2 missing=0
[exited with code 0]
```

The run auto-backgrounded past the tool's own 600s cap (not a Monitor —
the harness's own background-on-timeout behavior); it completed on its own
with **exit code 0** and was read back via the harness's completion
notification, not polled. The 2 fails inside shard idx=3
(`review-roundcap: PASS=12 FAIL=2` — `T11 state lock taken during
increment...` — and `[LOCK-01] pass=1 fail=2`) are pre-existing reds
unrelated to this task (REVIEW-ROUNDCAP-01 and SUITE-SPEED-01 lock-timing
suites, both merged in from `main`'s STATUS-CHURN-01 close, not touched by
this diff) — confirmed by running this task's own two DoD-gate-carrier
suites directly and getting 100% green:

```
$ timeout 300 bash plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
[TEST] test-worker-dod-gate: 27 passed, 0 failed

$ timeout 300 bash plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
test-worker-commit-epilogue: 8 passed, 0 failed
```

`test-worker-commit-epilogue.sh` is selected by the `leadv2-worker-epilogue.sh`
change (pre-existing EXTRA_SUITE_MAP row) and stayed green after this
round's `lv2_dod_retry_or_finalize()` addition.

## Falsifiability

Run from the lane root as cwd, per `leadv2-suite-falsifiable.sh`'s own usage
contract:

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-DOD-GATE-01/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=49
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

## Brief paste-line coverage

Verbatim brief lines that trigger check (b)'s paste-evidence scan, each with
where its evidence lives in this report:

```
brief.md:14: | brief step skipped (no report.md, a "paste X" with nothing pasted, a suite not registered) | 5 | GUARD-CENSUS R1, WORKER-MCP R1, MERGE-QUEUE R1 |
  -> covered by "## Checks and their negative controls" table (cause column) and the
     27/27 fixture run under "## tests/run-all.sh --scope changed".

brief.md:28:   b. Every brief line containing "paste" / "RUN and paste" has a corresponding fenced block in
  -> this section IS that corresponding fenced block, one per paste line (14, 28, 41, 49
     here; 51 under "## tests/run-all.sh --scope changed").

brief.md:41:   the gate (1b) accepts a mutation control only when the pasted block was produced by this script (it
  -> covered by "## Mutation-control": the pasted MUTATION-CONTROL ok block above was
     produced by leadv2-mutation-control.sh, never hand-pasted prose, and check (b)'s own
     mutation sub-check accepts it because docs/handoff/WORKER-DOD-GATE-01/mutation-control/
     20260902T102935Z-29873.txt binds diff_hash=491731d9df73a5e76c6e45539e3e862a0cd0c3fc356323eb065ac7cb6870d66a
     to this round's diff.

brief.md:49:   `control_not_applied`. Mutation negative controls, RUN via the new runner and paste: remove check (d)
  -> the 4 mutation-control exit-code cases (ok / mutant_survived / anchor_count /
     baseline_not_green, including control_not_applied) are each a live red+green fixture
     inside test-worker-dod-gate.sh, asserted in the 27/27 run under
     "## tests/run-all.sh --scope changed"; the anchor_count case is the negative control
     for "remove the anchor-count guard" and baseline_not_green is the negative control for
     "remove check (d)" acting as the mutation target.
```

## This gate against this task's own diff+report.md

```
$ git diff main HEAD -- plugins/leadv2/scripts tests/run-all.sh > /tmp/dodgate-report/round.diff
$ bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh \
    "$(pwd)" docs/handoff/WORKER-DOD-GATE-01 /tmp/dodgate-report/round.diff \
    docs/handoff/WORKER-DOD-GATE-01/dod-gate.md
```

```
# dod-gate report — 2026-09-02T10:33:39Z

dod_pass check=report
dod_pass check=paste_evidence
dod_pass check=suite_registration
dod_pass check=runtime_state
RC=0
```

**Bug found and fixed while producing this proof**: the first two attempts at
this self-check both failed `check=paste_evidence_missing` for every
multi-line report section, including this one's own `## Mutation-control`
section which plainly contains the words the brief lines ask for. Root
cause: `_dod_report_sections()`'s awk joined a section's body lines with a
literal `\n`, but its caller reads one record per line
(`while IFS=$'\x01' read -r heading has_fence body`) — `read` stops at LF
regardless of `IFS`, so any section with more than one body line silently
fractured into multiple malformed reads, and only the section's FIRST body
line ever participated in the overlap match. That is a false-refusal bug
for nearly every real report section (multi-line is the norm), not just
this one. Fixed by joining body lines with a space instead
(`plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`, `_dod_report_sections`) —
re-ran `test-worker-dod-gate.sh` after the fix, still 27/27 green (no
regression), then re-ran this self-check to get the `rc=0` pasted above.

## Not done (honest)

- **Retry-hook wiring into the 4 coder wrappers** (context.yaml step 6,
  brief item 3's in-worker retry): `lv2_dod_retry_or_finalize()` exists in
  `lib/leadv2-worker-epilogue.sh` (committed in a prior round) and is fully
  documented per D10/D11/R9, but it is **not called from any of
  `glm-coder.sh` / `kimi-coder.sh` / `freepool-coder.sh` /
  `claude-subsession.sh`** — `grep -rn lv2_dod_retry_or_finalize
  plugins/leadv2/scripts/` finds only the definition and one doc-comment
  reference, zero call sites. The function's own doc comment already states
  the R9 finding that none of the 4 wrappers sit inside a re-enterable turn
  loop, so wiring it (per D11) would mean calling it with `retry_hook_fn`
  omitted at all 4 sites — a soft-signal-only no-op, same effective behavior
  as not calling it, EXCEPT that a call site is what makes `worker_dod=pass`
  ever get written to `progress.log` on the happy path (today nothing writes
  it). This round's turn/time budget (`build-round-3.md`'s explicit scope:
  run-all proof, wiring proof, falsifiability, this report) did not include
  this item; it is carried forward, not silently dropped.
- **check (a)/(b) 37-report corpus re-calibration**: not re-run this round
  (see `## Checks and their negative controls` above) — architect-v2's
  original calibration (D4) is the last measurement on record.
- **dod_* sentinel-enum handshake with REVIEW-SENTINELS-LANGUAGE-01's
  parser** (D14): requested here in text, not confirmed accepted by that
  lane — `dod_report_missing_or_unheaded`, `dod_paste_evidence_missing`,
  `dod_mutation_control_not_via_runner`, `dod_suite_unregistered`,
  `dod_runtime_state_in_diff`, `dod_skip`, `dod_note` are the reason
  vocabulary this task's `review-gate.md`/`dod-gate.md` writers use; that
  lane's own confirmation was not sought this round.

## What this gate does NOT catch

- **Design disagreement** between a worker's approach and what the plan
  intended — the gate only checks mechanical predicates (report exists,
  paste present, suite registered, no runtime-state path, external claims
  tagged). A worker can pass every check while solving the wrong problem.
- **Reviewer hallucination** — a review finding that cites text or behavior
  that does not exist in the diff. The gate runs BEFORE any reviewer, so it
  has no visibility into what a reviewer later claims.

Both of the above are explicitly routed to GATE-PROVES-ITS-OWN-CONTROL-01
per the brief and context.yaml's `## Checks and their negative controls`
table row, not claimed as covered by this task.
