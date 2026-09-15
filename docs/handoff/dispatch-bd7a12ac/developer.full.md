verdict: APPROVE
next_action: continue

# Round 2 — DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01

## Mission recap

Round 1 (commits `14fa47bf`, `88d17a6b`) fixed D1/D2/D3 (dispatch-refusal
diagnostics) and, as a side effect, migrated ~27 legacy test files' `--kind
code`/`--kind safety` call sites to `--kind product`. Round 2's task: since
`product` is the only kind not in `LEADV2_NON_PRODUCT_KINDS` and therefore
the only one that can trigger the ~420s `architect_prepass()`, determine
whether each migrated caller needs a non-product `--kind`, verify (not
assume) that `--no-spawn` skips the prepass, measure the changed-scope
runner before/after, and run a real timing negative control — with an
explicit instruction to report "nothing to fix" and change nothing if the
underlying concern turns out to be false.

## Result: the concern is false. Nothing was changed.

Full writeup, per-caller mootness table, before/after runner output, and the
timing control are all in
`docs/handoff/DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01/report.md` under
`## Round 2`. Summary of the reasoning:

### 1. `--no-spawn` claim was wrong, corrected with line numbers

`spawn=0` is set at `leadv2-dispatch-code.sh:8780` but first read at
line 10283+ (worker-launch gating only). `architect_prepass()` is invoked
earlier, at line 9402 inside `cmd_resolve`. So `--no-spawn` has zero effect
on whether the prepass runs. This was the mission's own stated premise and
it does not hold — disclosed prominently so future rounds don't repeat it.

### 2. Every migrated caller is moot, via one of three mechanisms

Traced all ~27 files directly (grep + read, not assumption):

- **`ARCHITECT_GATE=0`** explicit in the test's own env (15 files) — the
  dominant mechanism. `architect_prepass()` line 6125 returns immediately
  with `status=disabled reason=kill_switch` when the gate isn't `1`.
- **`provably_one_file`** (7 files) — single-path `--writes` trips the
  count-based skip at ~line 6157-6164 before any subprocess spawn.
- **Never reaches `leadv2-dispatch-code.sh`** (4-5 files) — calls
  `leadv2-launch-registry.py` directly, or the `--kind product` text is an
  inert heredoc literal fed to an embedded Python static-analysis detector.

One file (`test-fg-dispatch-guard-reads-the-command.sh`) was classified from
the round-1 census rather than independently re-verified line-by-line — this
is disclosed rather than silently trusted, since the census's other central
claim (`--no-spawn`) turned out to be wrong.

No caller needs a `--kind` change. Changing one to `tooling` would be a
no-op diff — same behavior, different label — which the mission explicitly
said not to do "just to be tidy."

### 3. Changed-scope runner: same red before and after

Command: `LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 timeout 130 bash
tests/run-all.sh --scope changed` (60s per-suite ceiling, 130s outer bound),
darwin, Bash 3.2, worktree `7344367e`.

- Before: `161 of 93 suites` selected (`base=main@5da9324f27`, 33 changed
  files), 150 suites/4 shards after 11 known-red skips,
  `[SUITE-TIMEOUT] run-core-offline.sh exceeded 60s ceiling`, exit 124.
- After (identical command, zero files changed in between): identical
  selection, identical `[SUITE-TIMEOUT]` on the same suite, exit 124.

`run-core-offline.sh` aggregates many nested suites in-process and does not
fit a 60s ceiling regardless of `--kind` labeling — pre-existing
ceiling/runtime mismatch, not something either round introduced or could fix
via relabeling. Ceiling was not raised to force green; this is reported as
the honest (red) result.

### 4. Timing negative control: mechanism is real, unreachable via any migrated fixture

Built `/tmp/round2-negctrl-single.sh` (uncommitted, not part of the repo): a
throwaway one-commit git repo per arm, `LEADV2_DISPATCH_ARCHITECT_BIN`
pointed at a bounded stub (`sleep 3`) instead of a live model call, all
other network-facing arms/quota reads stubbed, `--writes src/a.py,src/b.py`
(2 files, so `provably_one_file` does not apply), `ARCHITECT_GATE` left at
production default.

First attempt shared one repo between both arms; control B (`tooling`)
refused with `writeset_overlap` against control A's still-active lane row —
a confound, disclosed and then corrected by giving each arm its own isolated
repo:

```
isolated product: elapsed=54s rc=0
  dispatch_classified class=product kind=product
  architect_prepass status=ran arm=claude artifact=docs/handoff/dispatch-a08a422e/architect-prepass.md

isolated tooling:  elapsed=53s rc=0
  dispatch_classified class=non_product kind=tooling
  (no architect_prepass line, in any of 3 separate runs across both versions of the control)
```

Qualitative mechanism proof is solid across 3 independent runs: product +
2-file writes + default gate genuinely invokes `ARCHITECT_BIN`; tooling with
identical writes/env never does. Quantitative magnitude is honestly
disclosed as inconclusive in this synthetic setup: the delta is ~1s against
a ~53s shared baseline (dispatcher startup/route-arbiter/registry overhead
identical in both arms) that was not further diagnosed. Production risk is
whatever the real architect model call costs, bounded above by
`ARCHITECT_PREPASS_TIMEOUT_SEC` (420s, off-limits to touch) — not directly
measured here since that requires an actual model call, out of scope for a
bounded reproducible control.

### 5. Out-of-scope findings, flagged not fixed

Round 1's find/replace also touched a different `--kind` namespace
(`leadv2-event.sh emit --kind`, dispatch-journal event typing, unrelated to
`leadv2-dispatch-code.sh` classification):

- `plugins/leadv2/scripts/codex-task.sh:1837` — `codex_worker_died` →
  `productx_worker_died` inside `_dw_announce()` (JS/Python call site at
  ~line 2024 still emits the original correct value — now inconsistent).
- `plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh` —
  `codex_fitting_dev` → `productx_fitting_dev`.
- `plugins/leadv2/scripts/tests/test-st2-question-protocol.sh` —
  `codex-test` → `productx-test`.

Real bugs, but a different subsystem and out of this round's mission scope.
Not fixed here — flagged for the lead to dispatch separately.

### 6. Protocol deviation, disclosed

A nested `Agent(subagent_type=Explore, model=haiku)` census spawn defaulted
to background execution (missed setting `run_in_background: false`), which
the mission said never to do. No turn was ended on the pending wait — other
independent verification continued until the notification arrived — and
every claim it fed into this report was independently re-verified against
source (the census's own "--no-spawn skips prepass" claim was in fact wrong
and caught by that re-verification). Disclosed rather than omitted.

### 7. Boundaries respected

- `test-dispatch-refusal-truth.sh`'s six assertions: not read for editing,
  not touched.
- No `--kind` call site changed anywhere.
- `LEADV2_NON_PRODUCT_KINDS` and the 420s timeout: not touched.
- No ceiling raised to force green; the after-run reproduced the same red as
  before, honestly.
- No `|| true` / `2>/dev/null` added anywhere.
- `git status --short` on `plugins/` and the two `docs/handoff/` dirs was
  empty immediately before writing this report — confirming zero repo code
  files were modified prior to this documentation commit.

## Commit

This documentation-only change (report.md `## Round 2` section + these two
deliverable files) will be committed to the lane branch per task binding
("commit before ending session; uncommitted exit is treated as an
incident"). No `.sh`/`.py` files changed, so `bash -n`/`py_compile`
self-checks are not applicable; the changed-scope runner was run and
reported per the mission's explicit before/after requirement (see §3).

DELIVERABLE_COMPLETE
