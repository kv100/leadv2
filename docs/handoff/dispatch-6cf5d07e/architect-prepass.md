# BUILDER-SELFCHECK-GATE-01 — round-3 finisher: scoped implementation design

Task: dispatch-6cf5d07e-architect · authored 2026-08-20T04:24:34Z
Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9c027877` (branch `worktree-9c027877`, HEAD `7ffe67c`)

## 0. Headline

**This is not a build task — it is an audit-and-close task.** The r2 worker's code is on
disk and already committed at `f2cc0bc` + merge `7ffe67c`; the only uncommitted delta is a
one-line `-x` → `-f` change in the selfcheck lib. Every r2 finding C1–C3 / H1–H3 / M1–M4 has
a locatable fix in the committed diff (classification table §2). The round-3 mission's real
deliverable is the **evidence set** the r2 acceptance block demands, plus a commit — not new
design.

The design below therefore scopes *what remains* and explicitly non-goals the rest, so the
implementer does not re-derive a 1072-line diff that is already correct.

## 1. On-disk state (verified)

```
$ git -C .claude/worktrees/9c027877 diff --stat main...HEAD
 plugins/leadv2/scripts/leadv2-dispatch-code.sh              |  17 +
 plugins/leadv2/scripts/leadv2-dispatch-product-close.sh     |  41 ++
 plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh      | 365 +++++++++++
 plugins/leadv2/scripts/tests/run-core-offline.sh            |   1 +
 plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh | 648 +++++++++++++++
 5 files changed, 1072 insertions(+)

$ git -C .claude/worktrees/9c027877 status --short
 M plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh
(remaining entries are untracked docs/handoff/* and .claude/cache/ — not lane files)
```

Uncommitted hunk (the *only* one):

```diff
@@ -258,7 +258,7 @@
-              && -x "${_scripts_dir}/leadv2-e2e-entrypoint.sh" ]]; then
+              && -f "${_scripts_dir}/leadv2-e2e-entrypoint.sh" ]]; then
```

That is the M2 idiom (`-f`, not `-x`, because persona-engine ships these 644) applied to the
delegate probe. It is correct and must be committed, not reverted.

## 2. Per-finding classification — audit against the committed diff

| # | Finding | Status | Evidence anchor (lane worktree paths) |
|---|---------|--------|----------------------------------------|
| C1 | Recursion via `tests/run-all.sh` | **done-by-r2** | `lib/leadv2-builder-selfcheck.sh:241` — comment "the repo-level runner (tests/run-all.sh) is NEVER invoked here"; `grep -n 'run-all' lib` returns only the two comment lines (15, 241), zero invocations. Depth guard: `:85` reads `LEADV2_BUILDER_SELFCHECK_DEPTH`, `:257-258` sets `LV2_SELFCHECK_DEPTH_SKIP=1` + `skipped++`, `:233` and `:284` export `LEADV2_BUILDER_SELFCHECK=0 LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth+1))` into every child spawn. |
| C2 | No-gtimeout watcher hangs the caller | **done-by-r2** | `lib:41-72` — header comment documents the R2/C2 fix; `:66/:68` use `kill -TERM -"${pid}"` / `kill -KILL -"${pid}"` (negative pid = process **group**) with a plain-pid fallback; watcher output detached. **Verify at §3.2** that the watcher subshell is `( … ) >/dev/null 2>&1 &` — that redirect is the half that actually releases the command-substitution pipe. If the redirect is absent, this is the one genuine code fix left. |
| C3 | 3 suites diff-caused red | **verification-only** | No code claim to audit — the gate must be shown non-invasive with `LEADV2_BUILDER_SELFCHECK=1`. See §3.3. |
| H1 | No baseline comparison | **done-by-r2** | `lib:199-236` `_selfcheck_baseline_verdict()`; merge-base resolved `:213-214` (`origin/main` then `main`), materialised via `git archive | tar -x` into a mktemp dir `:216-218`, `SKIP (baseline_red)` row emitted `:294-295`. Escape hatch `LEADV2_BUILDER_SELFCHECK_BASELINE=0` documented `:30-31`. |
| H2 | Register suite in run-core-offline | **done-by-r2** | `tests/run-core-offline.sh:226` — `"builder selfcheck gate (recursion/depth guard, baseline attribution)|||bash $TEST_DIR/test-builder-selfcheck-gate.sh"`. Exactly one line; delta vs main is this row only. |
| H3 | Cover the suite-runner branch | **done-by-r2** | `tests/test-builder-selfcheck-gate.sh` grew to 648 lines with a Part B (`:284` "direct lv2_selfcheck_run / _lv2_selfcheck_timeout_run coverage (H3)"): case 1 stem-from-`${diff_root}/tests` (`:338`), case 2 plugin-tests priority (`:357`), case 6 checks-nets-to-0 → DEGRADED (`:431`), case 7 child observes `FLAG=0`/`DEPTH=1` (`:456-473`), case 8 entry-depth=1 → depth_guard SKIP, no spawn (`:480-492`), case 10 `tests_mode=never` (`:515`), case 11 `always` bypasses delegate (`:528-533`). `no_matching_suite` now appears once, not five times — the r1 "all SKIP" defect is gone. |
| M1 | `checks:0` must be DEGRADED/rc2 | **done-by-r2** | `lib:12` rc contract, `:96` `no_diff_file` path prints `verdict: DEGRADED … checks: 0`; product-close `:+31` emits `status=degraded` on rc 2 and `checks=/skipped=` fields on every path. |
| M2 | `-f` not `-x` | **fix-by-you (uncommitted)** | The working-tree hunk above. `run-all.sh` detection no longer exists (C1 removed it), so the surviving `-x` risk was the e2e-entrypoint delegate probe — that is what the hunk fixes. Commit it. |
| M3 | Resolve suites from `${diff_root}/tests` | **done-by-r2** | `lib:18` contract comment; `:149-150` `${diff_root}/${p}` first, `:276-277` `${diff_root}/${test_rel}` for the suite stem; test case 1 (`:338`) asserts it. |
| M4 | Restore 2 out-of-write-set `journal.md` | **already-clean** | `git diff --stat main...HEAD -- 'docs/**'` is empty and `git log --diff-filter=D main...HEAD -- '*journal.md'` returns nothing — the lane deletes no journal. The single `?? docs/leadv2/tasks/backlog-pump/journal.md` is untracked ambient state, **not** a lane artifact; do not add it to the commit. |

Net: **one** line of code left to commit (M2), **one** thing left to actually check in code
(the C2 redirect, §3.2), and everything else is evidence production.

## 3. Work plan for the implementer

### 3.1 Sequencing (strict — later steps consume earlier artifacts)

1. Read `lib/leadv2-builder-selfcheck.sh:54-78` and confirm the C2 watcher redirect (§3.2).
   If missing, add `>/dev/null 2>&1` to the watcher subshell and nothing else.
2. `bash -n` on all four changed shell files + `shellcheck -S warning` on the same.
3. Recursion probe (§3.4) — cheapest high-value evidence, run it before the long suites.
4. Gate-ordering probe (§3.5).
5. `test-builder-selfcheck-gate.sh` red-first legs + green run (§3.6).
6. The three C3 suites with the flag on and off (§3.3).
7. `run-core-offline.sh` **foreground** in the lane (§3.7).
8. Single commit on `worktree-9c027877` (§3.8).

### 3.2 C2 residual check

Target `_lv2_selfcheck_timeout_run`, `lib:54-78`. The fallback branch must satisfy **both**:
the watcher subshell redirects its own stdout/stderr away from the inherited descriptor, and
the kill targets the negative pid. The negative-pid half is confirmed present at `:66/:68`.
Confirm the redirect; the failure mode it prevents is a 30s hang of the *caller* even after
the child dies, because the command substitution at `leadv2-dispatch-product-close.sh` keeps
waiting on a pipe the watcher still holds open.

### 3.3 C3 — the three diff-caused suites

`test-review-body-persist` (r1: 2 of 8 failing), `product-close waits-for-worker` (r1: 6 of 7),
and `test-report-only-gate.sh` case C4. Run each **twice**: once with
`LEADV2_BUILDER_SELFCHECK=0` (the byte-for-byte-today baseline) and once with
`LEADV2_BUILDER_SELFCHECK=1`. Paste both raw tails. The acceptance is not "green" in the
abstract — it is **identical pass counts across the two runs**, which is what proves the gate
is non-invasive on paths it must not alter.

### 3.4 Recursion probe

Drive a lane whose `diff_root` **is** the leadv2 repo (the self-referential case that killed
r1) through `leadv2-dispatch-product-close.sh` with the flag on. Required observable: the
journal carries a `selfcheck task=… status=…` decision line containing `depth_guard=1`
(emitted by product-close `:+27` when `LV2_SELFCHECK_DEPTH_SKIP=1`), **and** no second
`leadv2-dispatch-product-close.sh` process is spawned. Absence of `failed=suites:run-all:timeout`
anywhere in the run is the negative half of the same proof.

### 3.5 Gate-ordering probe

Stage a lane diff with a deliberate `bash -n` syntax error. Required observable: the lane's
`docs/handoff/dispatch-<id>/review-gate.md` reads `reason: selfcheck_failed`, and no review
arm sentinel is written. Test case 2 (`test-builder-selfcheck-gate.sh:123`,
`broken-sh-review-arm-never-spent`) already automates this — run it standalone and paste the
raw case output as the artifact.

### 3.6 Red-first legs

Every H3 case must be shown to fail against the pre-fix lib before it passes against the
current one. The suite's own harness (`run_case`, `:220`) prints per-case lines — capture the
red run (revert-under-`/tmp`, not in the worktree) and the green run side by side.

### 3.7 run-core-offline — foreground only

**Hard constraint, and the direct cause of the two prior worker deaths:** do not
`run_in_background` the runner and idle-wait. Run it in the foreground with a generous
timeout (~15 min solo) and continue when it returns. Expected delta vs main: exactly the one
new suite row. `dispatch refusal fallback chain` (routing-enforcement-p1) and
`plan-followups-01` are red on canonical main under this runner — they are **not** lane
regressions and must be named as such in the terminal artifact rather than chased.

### 3.8 Commit

Single commit on `worktree-9c027877` covering the M2 hunk plus any C2 residual. The four
already-committed files stay as they are — do **not** amend `f2cc0bc`. Stage by explicit
path; never `git add -A` (the worktree carries ~19 untracked `docs/handoff/*` dirs and
`.claude/cache/` that must not enter the commit). Re-`git diff <file>` immediately before
`git add` — a parallel session in this repo can revert an edit between the write and the
stage.

## 4. Risks and mitigations

| Risk | Why it bites here | Mitigation |
|------|-------------------|------------|
| **Re-doing r2's work** | The mission reads as "implement C1–M4"; the code already exists. A worker that re-implements will produce a conflicting 1000-line diff and burn its budget before any probe runs. | §2 classification is the contract: only M2 (+ possible C2 redirect) is code. Start from `git diff`, per the mission's own first instruction. |
| **Background-wait death** | Two workers already died of `worker_timeout` idling on a backgrounded runner. | §3.7 foreground-only, restated in acceptance. |
| **`git add -A` pollution** | 19 untracked handoff dirs + `.claude/cache/` sit in the worktree. | Explicit-path staging (§3.8). |
| **Main-red flakes counted as lane regressions** | Two named suites are red on canonical main under this runner. | Delta-vs-main framing; name the two flakes explicitly in the artifact. |
| **Baseline materialisation cost** | H1's `git archive | tar -x` runs per selfcheck invocation with a baseline-eligible suite; a large repo makes the gate slow enough to look hung. | Already lazy + memoised (`_baseline_tried`/`_baseline_ok`, `lib:204-222`). Verify the mktemp dir is cleaned; if it is not, that is a leak worth one line — but only if the probe surfaces it. |
| **Recursion probe is self-referential** | It runs product-close inside the leadv2 repo, i.e. against the very tree being changed. | Run it in the lane worktree, never the main checkout; the depth guard is the thing under test, so a hang *is* a finding, not an infra fault. |
| **Off-limits drift into the routing block** | `leadv2-dispatch-code.sh` also hosts a live lane's `candidate_arms`/quota work. | The +17 mission-paragraph hunk is already committed and untouched. Do not open that file again. |

## 5. Non-goals (explicitly out of scope)

- Any change to `leadv2-review-run.sh` — off_limits.
- The `candidate_arms` / quota routing block in `leadv2-dispatch-code.sh` — another live lane owns it.
- Redesigning baseline attribution, the depth-guard protocol, or the rc contract — r2 shipped them; audit, do not revise.
- Fixing the two main-red flakes.
- Trimming or restructuring the 648-line test suite beyond what a failing probe forces.
- Committing `docs/leadv2/tasks/backlog-pump/journal.md` or any `docs/handoff/*` artifact.
- Merging the lane to main — that is the lead's gate, not this lane's.

## 6. Acceptance

```yaml
acceptance:
  authored_at: 2026-08-20T04:24:34Z
  criteria:
    - id: A1-recursion
      surface: log_line
      observable: >
        In the lane journal for a product-close run whose diff_root is the leadv2 repo
        itself, a "selfcheck task=<id> status=..." decision line is present and carries
        "depth_guard=1"; the same journal contains no "failed=suites:run-all:timeout"
        line and no second product-close dispatch entry for that task.
    - id: A2-noninvasive
      surface: file_artifact
      observable: >
        The pasted raw tails of the three C3 suites (review body persist, product-close
        waits-for-worker, report-only gate C4) show the same pass/fail counts in the
        LEADV2_BUILDER_SELFCHECK=1 run as in the LEADV2_BUILDER_SELFCHECK=0 run, all green.
    - id: A3-gate-order
      surface: rendered_line
      observable: >
        For a lane staged with a deliberate bash -n syntax error, the rendered
        docs/handoff/dispatch-<id>/review-gate.md shows "reason: selfcheck_failed" and the
        review arm sentinel file is absent.
    - id: A4-red-first
      surface: file_artifact
      observable: >
        Two pasted suite runs of test-builder-selfcheck-gate.sh — one against the pre-fix
        lib showing named failing cases, one against the current lib showing every case
        passing.
    - id: A5-suite-delta
      surface: log_line
      observable: >
        The foreground run-core-offline.sh summary line in the lane reports a suite total
        one higher than the same summary on main, with the "builder selfcheck gate" row
        listed as passing, and no red row other than the two known main flakes
        (dispatch refusal fallback chain, plan-followups-01).
    - id: A6-lint
      surface: log_line
      observable: >
        bash -n and shellcheck -S warning each print no diagnostic for any of the four
        changed shell files.
    - id: A7-commit
      surface: file_artifact
      observable: >
        git log on worktree-9c027877 shows a new commit whose stat lists only the lane's
        five plugin files, with a clean working tree afterwards.
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh

DELIVERABLE_COMPLETE
