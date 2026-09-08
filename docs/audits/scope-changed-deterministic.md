# B6-SCOPE-CHANGED — `--scope changed` is deterministic and refuses instead of degrading

Row B6 of `PRE-WAVES-PLAN.md`. **This fix subsumes both filed rows:**
`SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01` (the checkpoint is no
longer read or written under `--scope changed`) and
`SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01` (the `HEAD~1..HEAD` fallback
is now a named refusal). No half-overlap remains.

Commit: `8efac28f` on `worktree-B6-SCOPE-CHANGED` (not merged — lead verifies).

## 1. The mechanism, verified against source (mission story confirmed)

Pre-fix `tests/run-all.sh` (block formerly at :270-328 — the mission's
:294-310/:308-317 numbers had drifted; mechanism exactly as described, no
divergence):

- **(a) Stateful range.** `$GIT_DIR/leadv2-run-all-last-checked-sha` was read
  as the range start whenever present and resolvable, overriding the
  merge-base; HEAD was then written back unconditionally. A second run with
  no new commits saw an empty range — a correctly registered suite selected
  on run 1 looked unregistered on run 2.
- **(b) Silent degradation.** No checkpoint + no resolvable `main`/
  `origin/main` → `HEAD~1..HEAD`, the last commit only — plausible and wrong
  on any multi-commit branch.
- **(c)** Both directions of untrustworthiness follow from (a)+(b).

Post-fix the range resolves through ONE function, `scope_changed_anchor()`
in `tests/run-all.sh` (body carries the `scope-changed-mut-1`/`-2` markers):

| caller asks | semantics | state file |
|---|---|---|
| `--scope changed` | `<merge-base(main\|origin/main)>..HEAD` + uncommitted diff | neither read nor written |
| `--scope changed-since` | checkpoint anchor, merge-base fallback on first run, HEAD recorded after | read + written (the old behaviour, explicit) |
| no anchor resolves | `FATAL no_base_ref` on stderr, exit 2, named reason + remedy | — |

`LEADV2_RUN_ALL_LIST_TRIGGERS=1` is untouched (stateless as before). The
honest alternative was weighed: instead of retiring `--scope changed` as a
selection oracle, the two semantics got explicit names — the interrogation
answer is now trustworthy AND incremental CI keeps its mechanism; cost of
the split is one new flag value plus a one-line mapping for the nested
runner.

## 2. Callers checked, and how

- `leadv2-phase8-e2e-gate.sh:446` (`--scope changed` in the lane worktree):
  main resolves in every worktree (shared refs) → new semantics is the full
  `<merge-base>..HEAD` set — a **superset** of the old incremental selection;
  it can over-run, never under-run. Gates that want the old speed can pass
  `--scope changed-since`.
- `leadv2-lane-salvage.sh:299,306`: fresh worktree, no checkpoint → first run
  was already merge-base anchored; unchanged behaviour.
- `tests/ci-gate.sh:24,33`: passes scope through; treats exit 2 as a workflow
  bug — the refusal only fires when no base ref exists at all, which in the
  real repo is a genuine config error worth failing on.
- `core_offline_scope_arg()`: `changed-since` maps to `changed` for
  run-core-offline (it validates only `changed|all` and deliberately has no
  incremental stamp — comment above `_core_offline_scope_changed_select`).
  Existing declared controls scope-mut-1/-2 kept intact (markers untouched).
- Suites that EXECUTE run-all in scratch repos, re-run green after fixture
  pins: `test-run-all-forwards-scope.sh` (2/0), `test-run-all-carrier-map.sh`
  (5/0), `test-run-all-self-registration.sh` (12/0),
  `test-known-red-allowlist-nested-match.sh` (12/0). Each got a one-line
  `git branch -m main` pin (forced minimal edits, outside LANE_WRITES) so the
  new refusal cannot make them depend on the machine's `init.defaultBranch`.
- `test-suite-selection-coverage.sh`: runs only the LIST_TRIGGERS seam (exits
  before the scope block) — parses 877 rows incl. the new suite. Its check 1
  (7 orphan suites) is PRE-EXISTING red: `git diff HEAD~1 HEAD --name-only`
  touches none of the 7 orphans nor `tests/unselected-by-design.txt`.

## 3. Negative controls (E2E-KILLRATE-01) — both applied, both red

Artifacts: `docs/audits/mutation-control/20260908T174944Z-20081.txt` (M1),
`docs/audits/mutation-control/20260908T175021Z-42711.txt` (M2).

- **M1 scope-changed-mut-1** (lie (a) reintroduced: `if true; then` on the
  changed-since guard → checkpoint visible under `--scope changed`):
  `baseline_rc=0`, `mutated_rc=1`, red on the selected set, not a log line —
  `FAIL: case1 run2 selection differs from run1 (state leaked)`.
- **M2 scope-changed-mut-2** (lie (b) reintroduced: refusal tail becomes
  `printf HEAD~1; return 0`): `baseline_rc=0`, `mutated_rc=1` —
  `FAIL: case2 expected rc=2 refusal, got rc=0`. Note the mutant still
  prints the FATAL line before answering: the suite still catches it,
  because it asserts rc + "nothing ran" + no selected set, not wording —
  exactly the "cannot tell a refusal from a plausible wrong answer" case.

Both mutations are inside `scope_changed_anchor`'s body, never top level.

## 4. Registration and selection proof

New suite `plugins/leadv2/tests/test-scope-changed-is-deterministic.sh`
declares `# run-all-triggers: run-all.sh`; `LEADV2_RUN_ALL_LIST_TRIGGERS=1
bash tests/run-all.sh` prints row 840:
`run-all.sh:plugins/leadv2/tests/test-scope-changed-is-deterministic.sh`.
Selection NOT proven with `--scope changed` itself; additionally the live
worktree answered twice identically (`run-all: 10 selected, scope=changed,
select_only=1`, twice).

## 5. Falsification set (raw)

```
$ for f in tests/run-all.sh plugins/leadv2/tests/test-scope-changed-is-deterministic.sh \
           tests/test-run-all-forwards-scope.sh tests/test-run-all-carrier-map.sh \
           tests/test-run-all-self-registration.sh tests/test-known-red-allowlist-nested-match.sh; \
  do bash -n "$f" || echo "BASH_N_FAIL $f"; done
ALL_BASH_N_OK
(no Python files changed)

$ bash plugins/leadv2/tests/test-scope-changed-is-deterministic.sh
test-scope-changed-is-deterministic: 14 passed, 0 failed   rc=0
$ bash tests/test-run-all-forwards-scope.sh
test-run-all-forwards-scope: 2 passed, 0 failed             rc=0
$ bash tests/test-run-all-carrier-map.sh
test-run-all-carrier-map: 5 passed, 0 failed                rc=0
$ bash tests/test-run-all-self-registration.sh
test-run-all-self-registration: 12 passed, 0 failed         rc=0
$ bash tests/test-known-red-allowlist-nested-match.sh
test-known-red-allowlist-nested-match: 12 passed, 0 failed  rc=0
$ bash plugins/leadv2/scripts/tests/test-suite-selection-coverage.sh
[SUITE-SELECTION-COVERAGE] pass=3 fail=1                    rc=0  (check 1 pre-existing, §2)
```

The full `run-core-offline` run was deliberately not launched in this lane:
memory row `run-all-changed-scope-runtime` (core-offline ALWAYS-ON, 900s) +
`core-offline-reds-under-concurrent-runners` (2+ concurrent lanes flip
nested suites NOT-KNOWN-RED). The changed-scope selection surface itself was
exercised directly (SELECT_ONLY + LIST_TRIGGERS + five executing suites).

## 6. Findings beyond the row

1. **`run-core-offline.sh` still carries the same lie (b) standalone**
   (`_core_offline_scope_changed_select`, HEAD~1 fallback at ~:837-839).
   Unreachable from run-all post-fix — run-all refuses first when no base
   resolves, and both use the same `main`/`origin/main` ladder in the same
   repo. Left untouched (outside LANE_WRITES); worth its own row if the
   nested runner is ever invoked standalone with no base ref.
2. Mission line numbers had drifted (:294-310/:308-317 → :270-328 pre-fix);
   mechanism matched the story exactly.
3. The `mutation-control` tool nests `mutation-control/mutation-control/`
   when handed `docs/audits/mutation-control` as task_dir; artifacts were
   flattened to the tracked convention by hand.
