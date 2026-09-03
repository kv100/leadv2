# BUILDER-SELFCHECK-GATE-01 — ROUND 3 architect prepass (lane 9c027877)

Design only. No implementation performed. All line refs are to the lane worktree
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9c027877`.

## 0. On-disk state (measured, not assumed)

```
$ cd .claude/worktrees/9c027877 && git status --short
 M plugins/leadv2/scripts/leadv2-dispatch-code.sh
 M plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
 M plugins/leadv2/scripts/tests/run-core-offline.sh
?? plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh
?? plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh

$ git diff --stat
 leadv2-dispatch-code.sh          | 17 +++
 leadv2-dispatch-product-close.sh | 41 ++++++
 tests/run-core-offline.sh        |  1 +
 3 files changed, 59 insertions(+)

$ wc -l lib/leadv2-builder-selfcheck.sh tests/test-builder-selfcheck-gate.sh
     365 lib/leadv2-builder-selfcheck.sh
     648 tests/test-builder-selfcheck-gate.sh
```

Nothing is staged; nothing is committed on the lane branch. The r2 worker's output is
intact — R3 is **finish + prove + commit**, not rewrite.

## 1. Per-finding audit against the r2 spec

| r2 finding | Classification | Evidence (lane worktree) |
|---|---|---|
| **C1** recursion via `tests/run-all.sh` | **done-by-r2** | `run-all.sh` no longer appears anywhere in the lib (`grep` empty). Suite discovery is diff-scoped stem matching only, `lib:271-281`. Depth guard `lib:255-258` sets `LV2_SELFCHECK_DEPTH_SKIP=1` and skips the suite arm. Every suite/baseline spawn carries the belt-and-braces pair `LEADV2_BUILDER_SELFCHECK=0 LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth+1))` — `lib:233-234`, `lib:284-285`. Rationale recorded `lib:14-21`, `lib:241-244`. |
| **C2** no-gtimeout watcher holds the pipe | **done-by-r2** (two-sided) | Lib side: watcher fully detached `>/dev/null 2>&1 </dev/null &` and `set -m` + `kill -TERM -"${pid}"` process-group kill, `lib:58-75`. Caller side: the r2 worker also removed the command substitution that owned the inherited fd — `lv2_selfcheck_run` now runs in the caller's shell with stdout redirected to a temp file (`product-close.sh:1832-1837`), which is *also* what makes the `LV2_SELFCHECK_*` globals survive. Comment at `product-close.sh:1830-1833` states the reason. |
| **C3** 3 diff-caused suites red | **structurally addressed, NOT yet proven** | The three mechanisms that caused it are all in place (delegate-to-e2e arm `lib:260-269`, depth guard, baseline attribution). But "green with flag=1" is an empirical claim — it has no artifact on disk. R3 must run it. See §3 acceptance. |
| **H1** no baseline comparison | **done-by-r2** | `_selfcheck_baseline_verdict` `lib:205-238`: lazy `git merge-base HEAD origin/main` → fallback `main` → `git archive \| tar -x` into a temp tree, re-runs that suite's baseline copy under the same env/timeout. `SKIP_RED` (inherited) and `SKIP_UNRESOLVED` (fail-open) both decrement `checks` and never blame the builder, `lib:292-304`. `LEADV2_BUILDER_SELFCHECK_BASELINE=0` restores direct-FAIL, `lib:207-210`. A suite absent from the baseline tree (i.e. one the lane itself added) correctly returns `FAIL` — `lib:227-230`. |
| **H2** register the suite + trim the 6-min wall | **done-by-r2 in substance, STALE IN FORM — see R3-A** | Registration exists (`run-core-offline.sh` +1). Wall trimmed: the suite pins `LEADV2_BUILDER_SELFCHECK_TIMEOUT_S=3` on every fixture invocation and uses trivial fixtures — `test-builder-selfcheck-gate.sh:15`, `:307`. **But the registration is written in a form `main` no longer has.** |
| **H3** cover the suite-runner branch | **done-by-r2** | 20 cases, and the branch r2 called out as uncovered is now the majority of them: `case_stem_from_lane_tests_dir:339`, `case_stem_priority_plugin_tests_dir:357`, `case_suite_green:376`, `case_suite_red_baseline_green:393`, `case_suite_red_baseline_red:415`, `case_baseline_unresolved:440`, `case_child_env_flag_and_depth:457`, `case_depth_guard_skips:481`, `case_no_repo_runner_invoked:499`, `case_tests_mode_never:516`, `case_auto_delegates_to_e2e:540`, `case_timeout_wrapper_kills_hung_command:574`, `case_timeout_wrapper_fast_command_no_hang:586`, `case_checks_zero_degraded:598`, `case_bash_n_failure_no_baseline_arm:612`. The r1 "all 5 cases SKIP(no_matching_suite)" state is gone. |
| **M1** `checks:0` must be DEGRADED/rc2, emit `checks=`/`skipped=` | **done-by-r2** | rc contract `lib:359-364` (0 GREEN / 1 RED / 2 DEGRADED). Caller emits `checks=… skipped=…` on both the blocked and the pass path, and appends `depth_guard=1` when the guard fired — `product-close.sh:1838-1840`, `:1850`. rc=2 does **not** block. |
| **M2** `-f` not `-x` for runner detection | **moot as written, residual instance — see R3-B** | `run-all.sh` is never invoked, so M2's literal target is gone. |
| **M3** resolve suites from `${diff_root}`, never the plugin tree | **done-by-r2** | `lib:275-276` probes `${diff_root}/plugins/leadv2/scripts/tests/test-<stem>.sh` then `${diff_root}/tests/test-<stem>.sh`. `_scripts_dir` (the plugin tree) is used only for the e2e-entrypoint delegate probe, which is deliberate. |
| **M4** restore the 2 out-of-write-set `journal.md` files | **done-by-r2** | `git status --short` in the lane shows no `journal.md` entry. |

**Net: 9 of 10 r2 findings are code-complete on disk. C3 is the only one whose closure
is empirical rather than structural.** The bulk of R3 is therefore proving, not building —
plus the three new blockers below, which the r2 worker could not have known about because
they were introduced on `main` after the lane branched.

## 2. New R3 findings (introduced by main moving under the lane)

### R3-A — BLOCKING: the lane is 10 commits behind main, and main rewrote the file the lane edits

```
$ git rev-parse HEAD                    85ae886
$ git rev-parse main                    b9959aa
$ git merge-base HEAD main              85ae886
$ git rev-list --left-right --count main...HEAD
10      0
```

The merge-base *is* the lane HEAD: the lane is strictly behind, zero ahead. Of the three
files it modifies, two moved on main:

```
$ git diff --name-only 85ae886 main -- <the three lane files>
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/tests/run-core-offline.sh
```

- **`run-core-offline.sh` was restructured wholesale.** On main the suite list is a data
  array `SUITE_DEFS=( "name|||bash $TEST_DIR/test-x.sh" … )` walked by
  `_core_offline_run_entry`, plus three new machineries: a per-suite env scrub
  (`env -u LEADV2_* -u CLAUDE_* …` + per-suite `TMPDIR`), a hermeticity post-condition that
  FAILs lane-owned / WARNs other suites that dirty `docs/leadv2`, and a reverse-order mode
  `LEADV2_CORE_OFFLINE_REVERSE=1`. Main also carries 4 suites the lane's copy lacks
  (`review-round-exhaustive`, `claim-evidence-gate`, `broad-status-relay-scope`, and the
  restructured entries).
  The lane's registration is a bare `run_check "builder selfcheck gate …" bash …` line —
  **the pre-rewrite form.** As things stand, `git diff main -- run-core-offline.sh` is a
  ~120-line delta that *reverts* main's work, not "only your suite row". The r2/r3
  acceptance criterion is unsatisfiable on this base.

  → **Merge/rebase `main` into the lane branch FIRST**, then re-express the registration as
  a single `SUITE_DEFS` entry, string-for-string in main's format:
  `"builder selfcheck gate (recursion/depth guard, baseline attribution)|||bash $TEST_DIR/test-builder-selfcheck-gate.sh"`.
  Place it after the `report-only gate` entry to preserve the r2 ordering intent.

- **`leadv2-dispatch-code.sh`: no conflict expected.** Main's post-merge-base hunks are at
  `@@ -521,0 +522,14 @@`, `@@ -523 +537 @@`, `@@ -528 +542,3 @@`, `@@ -2502,0 +2519,14 @@`
  (commits `210a439`, `b18aca3`). The lane's +17 mission paragraph is at ~3630. Disjoint.
  This also keeps the lane clear of the routing block (`candidate_arms`/quota) that
  `off_limits` reserves for another live lane — **do not resolve any conflict there; if one
  appears, take main's side verbatim.**

- **`leadv2-dispatch-product-close.sh`: untouched on main since the merge-base.** Clean.

### R3-B — MEDIUM: residual `-x` gate, the exact failure class M2 named

`lib:261` gates the e2e-delegate probe on `-x "${_scripts_dir}/leadv2-e2e-entrypoint.sh"`.
In this repo the file is mode 755, so the probe fires here:

```
$ ls -l plugins/leadv2/scripts/leadv2-e2e-entrypoint.sh
-rwxr-xr-x  1 … 1938 Aug 19 13:03 …
```

But M2 exists precisely because persona-engine's checkout carries these files at 644. If
the exec bit is absent there, `delegate` silently stays 0, the gate runs suites inline
instead of delegating to the e2e stage, and the C1/C3 blast radius quietly returns on the
repo that actually dispatches. The file is invoked as `bash <path>` (`lib:262`), so the
exec bit is not load-bearing. → change to `-f`. Same one-line class of fix M2 asked for.

### R3-C — MEDIUM: the new suite must be proven *under main's env scrub*, not standalone

Post-merge, main's `run_check` wraps every `bash`-invoked suite in
`env -u <every LEADV2_*/CLAUDE_*/GIT_CONFIG*> TMPDIR=<per-suite>`. That strips exactly the
`LEADV2_BUILDER_SELFCHECK*` variables this suite's behaviour depends on. The suite already
sets its own on each fixture invocation (`test-builder-selfcheck-gate.sh:307`:
`env LEADV2_E2E_GATE=0 "$@" LEADV2_BUILDER_SELFCHECK_TIMEOUT_S="${…:-3}"`), so it is
*designed* to survive this — but a suite that passes standalone and fails inside the runner
is the documented signature of this scrub. **The green claim must come from the runner
invocation, not from a bare `bash test-builder-selfcheck-gate.sh`.**

### R3-D — MEDIUM: hermeticity post-condition applies to the new suite

Main's `run_check` snapshots `git status --porcelain -- docs/leadv2` before and after each
suite and reports `HERMETIC-VIOLATION` on any change (FAIL if lane-owned, WARN otherwise).
The new suite drives `leadv2-dispatch-product-close.sh`, whose normal side effects include
journal and phase writes. Every fixture must redirect `HANDOFF` / `docs/leadv2` into its own
temp tree. Confirm no `HERMETIC-VIOLATION` line for this suite in the runner output — its
absence is part of acceptance, not an afterthought.

### R3-E — LOW: the gate ritual is now forward *and* reverse

Recent main commits close on "fwd 53/0 + rev 53/0" (`210a439`). With `SUITE_DEFS` on main,
`LEADV2_CORE_OFFLINE_REVERSE=1` is a first-class run. Order-dependence introduced by a newly
inserted suite is exactly what it exists to catch. R3 must show both directions.

## 3. Implementation plan for the R3 finisher

Ordered; each step's output is an artifact the terminal report pastes raw.

1. **Rebase the lane onto main.** `git fetch` not needed (same repo); merge or rebase
   `main` into `worktree-9c027877`. Expect a conflict only in `run-core-offline.sh`.
   Resolve by **taking main's file whole**, then re-adding the one `SUITE_DEFS` entry
   (R3-A). Re-confirm `git diff main -- run-core-offline.sh` is exactly one added line.
   If `leadv2-dispatch-code.sh` conflicts at all, take main's side and re-apply only the
   +17 mission paragraph at its new offset.
2. **Apply R3-B**: `lib:261` `-x` → `-f`. One character class, one line.
3. **Red-first legs** of `test-builder-selfcheck-gate.sh` — each case's assertion inverted
   or its fix reverted, showing the case actually fails without the code under test. Paste
   the red output and the green output.
4. **Recursion probe** — run the gate on a lane inside the leadv2 repo itself and show the
   journal `decision selfcheck …` line carrying `depth_guard=1`, with **no** recursive
   `product-close` invocation and no `suites:run-all:timeout`.
5. **C3 probe** — the three diff-caused suites (`test-review-body-persist.sh`,
   `test-no-work-terminal.sh`, `test-report-only-gate.sh`) run with
   `LEADV2_BUILDER_SELFCHECK=1`, before/after raw.
6. **Gate-ordering probe** — a lane whose diff contains a `bash -n`-invalid `.sh` produces
   `status: blocked / reason: selfcheck_failed` in `review-gate.md` and **no** review-arm
   registration in the journal.
7. **Full runner, both directions**, in the lane: forward and `LEADV2_CORE_OFFLINE_REVERSE=1`.
   Check for `HERMETIC-VIOLATION` (R3-D) and confirm the new suite is green under the scrub
   (R3-C).
8. **`bash -n` + `shellcheck -S warning`** on all five touched shell files
   (the 3 modified + the 2 new).
9. **Commit** on the lane branch, single commit.

### Non-goals (explicitly out of scope for the implementer)

- Do **not** re-architect the selfcheck lib. 9/10 r2 findings are closed on disk; treat the
  lib as done except for the one-line R3-B fix.
- Do **not** touch `leadv2-review-run.sh` (off_limits).
- Do **not** touch the `candidate_arms`/quota routing block in `leadv2-dispatch-code.sh`
  (off_limits, another live lane) — including during conflict resolution.
- Do **not** add suites, lenses, or env vars beyond the R3-B one-liner.
- Do **not** fix any inherited-red suite the baseline arm attributes to main. That is
  precisely what H1 exists to keep off this lane's plate.
- Do **not** commit the untracked `docs/leadv2/founder-status.md`,
  `docs/leadv2/status-snapshot.json`, `.broad-status-prev.json`,
  `docs/leadv2/tasks/backlog-pump/`, or `.claude/cache/` — beat/runtime residue, not lane work.

## 4. Risks

| Risk | Mitigation |
|---|---|
| Rebase drops the r2 worker's uncommitted work (it is untracked/unstaged — a hard rebase would discard it) | **Commit the lane work to the branch BEFORE merging main.** Two commits then squashed, or commit-then-merge. Never `rebase`/`checkout` across a dirty tree holding the only copy of 1013 lines. |
| Conflict resolution in `run-core-offline.sh` silently reverts main's env-scrub/hermetic/reverse machinery | The stated acceptance — delta vs main is exactly one line — is itself the detector. Verify it after the merge, not at the end. |
| Suite passes standalone, fails under the runner's env scrub (R3-C) | Acceptance is defined at the runner surface, never the standalone one. |
| `depth_guard=1` never appears because the delegate arm short-circuits first | `lib:255` deliberately places the depth guard *before* the delegate probe, so a re-entered gate always leaves the evidence line. Probe in step 4 must land on a lane that has an e2e entrypoint, to prove the ordering rather than assume it. |
| Prefix env assignment (`LEADV2_…=0 _lv2_selfcheck_timeout_run …`, `lib:233`, `lib:284`) is applied to a *function* call — subtle bash scoping | `case_child_env_flag_and_depth:457` covers exactly this. Do not refactor it away; it works because bash exports prefix assignments into the function's environment and the eventual `bash <suite>` child inherits them. |
| The r2 worker died three times; a 4th death loses the same work again | Commit first (risk 1), then probe. Every probe after step 1 is re-runnable from a committed base. |

## 5. Notes on things that looked like bugs and are not

- `lib:35` `set -uo pipefail` in a *sourced* lib mutates the caller's shell options.
  Not a defect here: `leadv2-dispatch-product-close.sh:13` already sets the identical
  options, and the sibling lib `leadv2-review-findings.sh:30` uses the same idiom. No drift.
- `checks=$((checks - 1))` on a baseline SKIP (`lib:296`, `:302`) can drive `checks` to 0 and
  flip the verdict to DEGRADED even though a suite ran. That is the intended M1 semantics —
  rc=2, non-blocking — not an off-by-one.
- The lib returning `FAIL` for a suite missing from the baseline tree (`lib:227-230`) is
  correct attribution: a suite the lane itself added is the lane's responsibility.

## acceptance:

```yaml
acceptance:
  - surface: file_artifact
    observable: >-
      In the lane worktree, `git diff main -- plugins/leadv2/scripts/tests/run-core-offline.sh`
      shows exactly one added line and zero removed lines — the builder-selfcheck SUITE_DEFS
      entry — with main's env-scrub, hermeticity and reverse-order blocks all still present in
      the file.
    authored_at: 2026-08-20T01:52:00Z
  - surface: log_line
    observable: >-
      The lane journal contains a `decision selfcheck task=<id> status=…` line carrying
      `depth_guard=1`, and contains no second `product-close` entry for the same task and no
      `failed=suites:run-all:timeout`.
    authored_at: 2026-08-20T01:52:00Z
  - surface: rendered_line
    observable: >-
      The core-offline runner's final line reads `[CORE-OFFLINE] suites passed=N failed=0
      missing=0` in both the forward run and the LEADV2_CORE_OFFLINE_REVERSE=1 run, with the
      builder-selfcheck row present in both and no HERMETIC-VIOLATION line naming it.
    authored_at: 2026-08-20T01:52:00Z
  - surface: file_artifact
    observable: >-
      For a lane whose diff carries a syntactically invalid .sh, docs/handoff/<id>/review-gate.md
      reads `status: blocked` with `reason: selfcheck_failed`, and no review arm is recorded for
      that lane.
    authored_at: 2026-08-20T01:52:00Z
  - surface: rendered_line
    observable: >-
      test-review-body-persist.sh, test-no-work-terminal.sh and test-report-only-gate.sh each
      print their all-pass summary line when run with LEADV2_BUILDER_SELFCHECK=1, matching the
      line they print with the flag unset.
    authored_at: 2026-08-20T01:52:00Z
  - surface: file_artifact
    observable: >-
      A single commit exists on branch worktree-9c027877 containing all five touched shell files,
      and the working tree afterwards shows no modified or untracked file under
      plugins/leadv2/scripts/.
    authored_at: 2026-08-20T01:52:00Z
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh

DELIVERABLE_COMPLETE
