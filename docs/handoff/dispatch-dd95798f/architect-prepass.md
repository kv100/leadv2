# BUILDER-SELFCHECK-GATE-01 — round-2 implementation design (architect prepass)

Round-1 code is **uncommitted** in worktree `.claude/worktrees/9c027877` (branch `worktree-9c027877`,
zero commits ahead of main). Round-1 write-set, confirmed on disk:

| path | state |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh` | new, untracked |
| `plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh` | new, untracked |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | +31 (source stub @72-90, gate step @1820-1849) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | +17 (mission paragraph @3627) |
| `docs/leadv2/tasks/dispatch-{567ba028,59ae8b51}/journal.md` | **stray writes — M4, restore** |

Nothing else in the tree belongs to this lane (the other `docs/leadv2/*` modifications are
bus/lock runtime state, not lane writes — do not stage them either).

---

## 1. Root cause of the round-1 FAIL, in one sentence per finding

| # | Mechanism (verified) |
|---|---|
| C1 | `lib:180` gates on `-x "${diff_root}/tests/run-all.sh"` and runs it with `--scope changed`. `tests/run-all.sh:7` **always** drives `.claude/scripts/tests/run-core-offline.sh` regardless of `--scope`; that runner executes `test-no-work-terminal.sh` / `test-dwr-resume.sh` / … which spawn `leadv2-dispatch-product-close.sh`, which now sources the selfcheck and re-enters `run-all.sh`. Unbounded except by the 900 s timeout. |
| C2 | `lib:32-44`: the watcher subshell is forked without redirecting its own stdout, so it inherits the fd of the `$(lv2_selfcheck_run …)` command substitution at `product-close.sh:1834`. `kill $watcher` kills the subshell, not its `sleep` child, and the surviving `sleep` keeps the pipe's write end open → the caller's `$( )` blocks for the FULL `timeout_s` even after a `/bin/echo` completed (30 s measured). |
| C3 | `test-review-body-persist.sh` (2/8), `test-no-work-terminal.sh` (6/7), `test-report-only-gate.sh` (C4 case) are red **only** because their fixture lanes reach the new gate with the flag defaulted ON: they inherit C1's recursion and C2's hang. All three are green with `LEADV2_BUILDER_SELFCHECK=0`. Fixing C1+C2 must return them to green **with the flag on** — the gate must add a check, never mutate the lane paths those suites assert. |
| H1 | The suite check attributes any red to the builder, including red already present at merge-base. No baseline arm exists. |
| H2 | `test-builder-selfcheck-gate.sh` is unregistered in `run-core-offline.sh`, and its own wall is ~6 min because every case inherits the 900 s default timeout. |
| H3 | All 5 existing cases land on `SKIP (no_matching_suite)` — the branch that contains C1 and C2 has zero coverage. |
| M1 | `checks=0` (report-only lane, all paths unresolved) falls into the `failed==0` arm → `verdict: GREEN`, rc 0. A gate that ran nothing must not certify. |
| M2 | `-x` on `${diff_root}/tests/run-all.sh` is false in persona-engine (mode 644). |
| M3 | Stem fallback resolves suites from `${_scripts_dir}/tests` (the **plugin** tree the lib lives in), not from the lane's `diff_root`. A lane in another repo would run canonical's suites. |
| M4 | Two journal files written outside the write-set. |

---

## 2. Design: what changes

### 2.1 `lib/leadv2-builder-selfcheck.sh` — suite check rewritten

**Decision A (C1, H1).** The suite check **never** invokes a repo-level runner. Remove the
`tests/run-all.sh` branch entirely. The only suite discovery is diff-scoped stem matching, and it
resolves **from the lane tree**:

```
for each resolved changed file f:
  stem = basename(f) without extension
  candidates (first hit wins, tested with -f, invoked as `bash <path>`):
    ${diff_root}/plugins/leadv2/scripts/tests/test-${stem}.sh
    ${diff_root}/tests/test-${stem}.sh
```

`_scripts_dir` is no longer used for suite resolution (M3). Existence probes use `-f`, invocation
is always `bash <path>` — never `-x`, never direct execution (M2).

**Decision B (C1, depth guard).** Two env facts are exported around **every** child suite
invocation:

```
LEADV2_BUILDER_SELFCHECK=0                       # any product-close a suite spawns skips the gate
LEADV2_BUILDER_SELFCHECK_DEPTH=$((depth + 1))    # depth = ${LEADV2_BUILDER_SELFCHECK_DEPTH:-0}
```

and before any suite runs at all:

```
if (( depth >= 1 )); then
  row "suites" "-" "SKIP (depth_guard:${depth})"; skipped++
  # and the caller journals it — see 2.2
fi
```

Belt and braces on purpose: the flag alone is defeated by a fixture that re-exports it, the depth
guard alone is defeated by a fixture that scrubs env. Both together make re-entry structurally
impossible at one level.

**Decision C (C2).** The no-`gtimeout`/no-`timeout` fallback becomes:

```
set -m                                    # child becomes its own process-group leader
{ "$@" >"${logfile}" 2>&1 & }
pid=$!
set +m
( sleep "${timeout_s}"
  kill -0 "${pid}" 2>/dev/null || exit 0
  kill -TERM -"${pid}" 2>/dev/null || true      # negative pid == whole process group
  sleep 2
  kill -KILL -"${pid}" 2>/dev/null || true
) >/dev/null 2>&1 </dev/null &
watcher=$!
wait "${pid}"; rc=$?
kill -TERM "${watcher}" 2>/dev/null || true; wait "${watcher}" 2>/dev/null || true
(( rc > 128 )) && rc=124                  # signal death reported as timeout(1) would
```

Three properties the round-1 version lacked: the watcher holds **no** inherited fd (`>/dev/null
2>&1 </dev/null`), the kill targets the **group** (`-"${pid}"`, valid because `set -m` made pid the
pgid), and a signal-killed child normalises to 124.

**Decision D (H1 — baseline arm).** A red suite is only the builder's fault if it is green at
merge-base. On the **first** red suite only (cost is paid lazily, once per invocation):

1. `base="$(git -C "${diff_root}" merge-base HEAD origin/main 2>/dev/null || git -C "${diff_root}" merge-base HEAD main)"`.
2. Materialise once: `baseline_dir="$(mktemp -d)"; git -C "${diff_root}" archive "${base}" | tar -x -C "${baseline_dir}"`.
3. Re-run the **baseline copy** of the same suite path, same env exports, same timeout.

Attribution table:

| lane suite | baseline copy | verdict | counted as |
|---|---|---|---|
| rc 0 | not run | `PASS` | check |
| rc != 0 | rc != 0 | `SKIP (baseline_red)` | skipped — raw output still attached |
| rc != 0 | rc 0 | `FAIL` | failed → gate blocks |
| rc != 0 | file absent at base (new suite) | `FAIL` | failed → gate blocks |
| rc != 0 | base unresolvable / `git archive` fails | `SKIP (baseline_unresolved)` | skipped — raw attached |

The last row is a deliberate fail-open: an unattributable red must not refuse a lane (that was
exactly H1's complaint). Gated by `LEADV2_BUILDER_SELFCHECK_BASELINE` (default 1; `0` = treat lane
red as FAIL directly, which is what the red-first test cases use to force a block cheaply).
`bash -n` / `py_compile` need no baseline arm — a syntax error in a file the diff touched is
categorically the builder's.

**Decision E (M1).** After all three checks:

```
if   (( failed > 0 ))  -> artifact `verdict: RED`,      rc 1
elif (( checks == 0 )) -> artifact `verdict: DEGRADED`, rc 2, `reason: no_check_ran`
else                      artifact `verdict: GREEN`,    rc 0
```

and the lib publishes counters to the caller (it is sourced, so plain globals suffice):
`LV2_SELFCHECK_CHECKS`, `LV2_SELFCHECK_FAILED`, `LV2_SELFCHECK_SKIPPED`, `LV2_SELFCHECK_DEPTH_SKIP`
(0/1). Set unconditionally on every return path, including the `no_diff_file` early return.

### 2.2 `leadv2-dispatch-product-close.sh` — caller

Same position in the file (after `pc_scope_diff`, before the e2e stage) and the same
`LEADVEV2`-free contract; three edits only:

1. rc 2 arm is explicit: `emit decision "selfcheck task=${TASK} status=degraded checks=0 skipped=${LV2_SELFCHECK_SKIPPED} reason=no_check_ran"` and the lane **proceeds** (degraded is not a block).
2. every `emit` for this gate carries `checks=${LV2_SELFCHECK_CHECKS} skipped=${LV2_SELFCHECK_SKIPPED}`; when `LV2_SELFCHECK_DEPTH_SKIP=1` it also carries `depth_guard=1` — this is the journal line the recursion probe reads.
3. the block arm (rc 1) is unchanged apart from the added fields.

`review-gate.md` on block keeps its round-1 shape plus a `checks:`/`skipped:` line.

### 2.3 `leadv2-dispatch-code.sh` — mission paragraph

Unchanged from round 1 (flag-guarded, appended after the dedup sig). No round-1 finding targets it;
it stays in the write-set only because the flag guard must keep matching the gate's flag.

### 2.4 `tests/test-builder-selfcheck-gate.sh` — coverage (H3) and wall (H2)

Every case pins `LEADV2_BUILDER_SELFCHECK_TIMEOUT_S=3` and uses trivial fixtures; target wall
**< 25 s** total. Cases, each written red-first (assert fails against the current lib, passes after
the fix):

| # | case | red-first anchor |
|---|---|---|
| 1 | stem suite resolved from `${diff_root}/tests`, not the plugin tree | M3: current lib runs canonical's suite |
| 2 | stem suite resolved from `${diff_root}/plugins/leadv2/scripts/tests` | new path |
| 3 | suite green → `checks>=1`, `verdict: GREEN`, rc 0 | — |
| 4 | suite red, baseline green → rc 1, `failed_names` contains `suites:test-<stem>` | — |
| 5 | suite red, baseline red → rc 0, row `SKIP (baseline_red)`, `failed: 0` | H1: currently rc 1 |
| 6 | baseline unresolvable (fixture is not a git repo) → `SKIP (baseline_unresolved)`, rc 0 | H1 |
| 7 | child suite observes `LEADV2_BUILDER_SELFCHECK=0` and `_DEPTH=1` (fixture suite writes its env to a probe file) | C1: currently unset |
| 8 | `LEADV2_BUILDER_SELFCHECK_DEPTH=1` on entry → `SKIP (depth_guard:1)`, no suite process spawned (probe file absent) | C1 |
| 9 | no repo-level runner is ever invoked: fixture plants an executable `tests/run-all.sh` that touches a sentinel; sentinel must **not** exist after the run | C1 |
| 10 | `tests_mode=never` → `SKIP (suite_disabled)`; `tests_mode=always` runs suites with the e2e delegate available | H3 |
| 11 | `tests_mode=auto` + delegate available → `SKIP (delegated_to_e2e)` | H3 |
| 12 | timeout wrapper, `gtimeout`/`timeout` masked out of `PATH`: a `sleep 30` fixture returns **124** within ~6 s | C2 |
| 13 | same masked `PATH`, a fast fixture (`/bin/echo`): `lv2_selfcheck_run` captured in a command substitution returns in **< 3 s** (round-1 code takes the full timeout) | C2 — the exact hang |
| 14 | `checks=0` (diff touches only unresolvable paths) → rc 2, `verdict: DEGRADED`, `reason: no_check_ran` | M1 |
| 15 | `bash -n` failure on a changed `.sh` → rc 1 regardless of baseline arm | ordering probe support |

Registration (H2), appended in `run-core-offline.sh` next to the other gate suites:

```
run_check "builder selfcheck gate (recursion/depth guard, baseline attribution)" bash "$TEST_DIR/test-builder-selfcheck-gate.sh"
```

`run-core-offline.sh` delta must be exactly this one line.

### 2.5 M4

`git -C .claude/worktrees/9c027877 checkout -- docs/leadv2/tasks/dispatch-567ba028/journal.md docs/leadv2/tasks/dispatch-59ae8b51/journal.md`
and never `git add` anything under `docs/leadv2/` or `docs/handoff/`.

---

## 3. Data flow (numbered)

1. `leadv2-dispatch-code.sh` appends the falsification paragraph to the product mission (flag-guarded).
2. Lane runs; `leadv2-dispatch-product-close.sh` reaches `pc_scope_diff` and has `diff_file`, `diff_root`, `ROOT`.
3. Gate step: flag on **and** `lv2_selfcheck_run` defined → call it with `LEADV2_E2E_GATE=${E2E_ON}`.
4. Lib parses `+++ b/<path>` lines → dedupe → resolve `diff_root` then `project_root` → unresolved = `SKIP`.
5. `bash -n` per `.sh`; `py_compile` per `.py` (pycache redirected out of tree).
6. Suite check: `never` → skip · depth ≥ 1 → depth-guard skip · `auto` + e2e entrypoint resolves → delegate skip · else stem-matched lane suites, each run through the timeout wrapper with the two env exports.
7. Any red suite → lazy baseline materialisation → attribution per the 2.4 table.
8. Lib writes `selfcheck.md` (counters, row table, capped raw tails), sets the `LV2_SELFCHECK_*` globals, prints `failed_names`, returns 0/1/2.
9. Caller: rc 1 → `review-gate.md status=blocked reason=selfcheck_failed`, `emit`, `_dl_note refused`, `_stamp_review_terminal blocked`, `exit 5` — **before** e2e and before any review arm. rc 0/2 → `emit` green/degraded and fall through to e2e.

## 4. Interface contract

| symbol | signature | contract |
|---|---|---|
| `lv2_selfcheck_run` | `<diff_file> <diff_root> <project_root> <out_md>` | stdout = comma-joined failed names (empty unless rc 1); rc 0 GREEN / 1 RED / 2 DEGRADED; writes `out_md`; sets `LV2_SELFCHECK_{CHECKS,FAILED,SKIPPED,DEPTH_SKIP}`; no `emit`, no `_dl_note`, no `exit` |
| `_lv2_selfcheck_timeout_run` | `<timeout_s> <logfile> -- <cmd...>` | rc = child rc, or 124 on deadline/signal; never leaks an fd to the caller; never returns before the child is reaped |

Env (all `LEADV2_*`, verified against the project convention; none present in
`.claude/settings.json` `env`, so all are defaults-in-code):
`LEADV2_BUILDER_SELFCHECK` (1) · `_TESTS` (auto|always|never) · `_TIMEOUT_S` (900) · `_MAX_FILES`
(200) · `_DEPTH` (0, internal) · `_BASELINE` (1) · plus `LEADV2_E2E_GATE` read-only mirror.

## 5. Risks

| risk | mitigation |
|---|---|
| A fixture lane scrubs env and re-enters | depth guard **and** flag export, independently sufficient |
| `set -m` inside a sourced function alters the caller's job control | scoped: `set -m` … `set +m` around the single fork; the caller (product-close) is non-interactive and does not rely on job control. Verified by case 13 running inside a command substitution |
| `git archive \| tar` cost on a large lane repo | lazy — only on the first red suite; cached for the invocation; `LEADV2_BUILDER_SELFCHECK_BASELINE=0` disables |
| `origin/main` absent in a fixture repo | merge-base falls back to `main`, then to `SKIP (baseline_unresolved)` (fail-open) |
| Removing the `run-all.sh` branch narrows real coverage | intentional: the repo-level runner is the e2e stage's job (step 6 delegate arm), not this gate's. Recorded as decision A |
| `run-core-offline.sh` is outside round-1's write-set | H2 explicitly authorises exactly one added `run_check` line; noted here so the reviewer does not read it as scope creep |
| Two parallel sessions in the same worktree | re-`git diff` each write-set file immediately before `git add` (global rule); commit on the lane branch only |

## 6. Out of scope

`leadv2-review-run.sh` (off_limits) · the e2e stage and `leadv2-e2e-entrypoint.sh` · any suite other
than `test-builder-selfcheck-gate.sh` (the three C3 suites are **verified**, not edited) ·
`tests/run-all.sh` and its `--scope` semantics · `docs/leadv2/**`, `docs/handoff/**` ·
`.claude/settings.json` · merging the lane branch to main.

## 7. acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      In the lane's own journal for a leadv2-repo lane, the selfcheck decision line reads
      status=green (or status=degraded) and carries depth_guard=1 with checks= and skipped=
      fields, and no nested product-close entry appears beneath it — a reader sees the gate
      completed once, with the depth guard visibly stated.
    authored_at: 2026-08-19T12:46:44Z
  - surface: rendered_line
    observable: >-
      run-core-offline.sh output shows "builder selfcheck gate ... PASS", and the three
      previously-red suites (review body persist, product-close waits for worker exit,
      report-only gate) each print PASS with the gate flag left at its default ON — the same
      three lines that printed FAIL in round 1.
    authored_at: 2026-08-19T12:46:44Z
  - surface: file_artifact
    observable: >-
      docs/handoff/<task>/selfcheck.md for a lane whose diff resolved no checkable file shows
      "verdict: DEGRADED" with "reason: no_check_ran" and "checks: 0" — never "verdict: GREEN".
    authored_at: 2026-08-19T12:46:44Z
  - surface: file_artifact
    observable: >-
      For a lane whose changed shell file has a syntax error, docs/handoff/<task>/review-gate.md
      reads "status: blocked" / "reason: selfcheck_failed" and names the failing file, and the
      same handoff directory contains no review body — the reviewer was never spent.
    authored_at: 2026-08-19T12:46:44Z
  - surface: rendered_line
    observable: >-
      With gtimeout and timeout absent from PATH, the new suite's wrapper cases print a pass
      line for a fast command finishing in under three seconds and for a hung command reporting
      124 within about six seconds, and the whole suite's wall-clock line stays under 25s.
    authored_at: 2026-08-19T12:46:44Z
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
