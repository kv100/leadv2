# SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01 — lead acceptance, measured

The worker exited `0` at 07:20 and its closing e2e gate then **timed out after 900 s**
(`e2e-gate.md`: `leadv2-dispatch-product-close: e2e suite TIMED OUT after 900s`) — the third lane
killed at that gate today, and `E2E-GATE-BROKE-TODAY-01`, not a property of this branch. It left
**no `mutation-control/` artifacts at all**, so every negative control below was produced by the
lead, not copied.

Branch `worktree-SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01`, head `40087d46`.

## The three acceptance checks from the brief

**1. The serialisation is gone — adding a suite touches only that suite's own file.**
A scratch suite carrying `# run-all-triggers: zzscratchsource` was dropped into
`plugins/leadv2/scripts/tests/` and the discovery walker picked it up with no edit to `run-all.sh`:

```text
discovered: zzscratchsource:plugins/leadv2/scripts/tests/test-zz-scratch-selfreg.sh
run-all.sh modified by adding the suite? -> 0 change(s)
after_removal_rows=0
```

**2. Selection still works.** Covered behaviourally by the lane's own new suite
(`tests/test-run-all-self-registration.sh`, 12 cases), including filename-form and bare-form
triggers, attribution (dirt selects only its own suite), a negative control for an unmapped stem,
and `--scope changed`.

**3. No row lost — proven by enumeration, not inspection.** Every real row of main's
`EXTRA_SUITE_MAP` was parsed out and compared against the lane's discovered map
(`LEADV2_RUN_ALL_LIST_TRIGGERS=1`):

```text
real rows on main:  stems=105  pairs=219
discovered in lane: stems=105  pairs=220
STEMS LOST: 0 []
PAIRS LOST (stem kept but suite dropped): 0 []
stems gained: 0 []
```

The one extra pair is the new suite registering under the `run-all.sh` stem.

**A first, wrong measurement is recorded here on purpose:** a cruder parser reported
`stems_LOST=12`. All twelve were **comment lines inside `EXTRA_SUITE_MAP`** that the parser read as
rows (`# PHASE-GATE-IS-INVERTED-01 -> ['the inversion regression lives in its own suite']`). The
migration lost nothing; the parser did. A zero — or a loss — is derived a second way before it is
reported.

## Negative controls — one per changed function, measured

`git diff main...HEAD -- tests/run-all.sh` adds exactly two functions: `parse_suite_triggers` and
`scan_suite_triggers`. Both mutations are inside the function body, both parse clean, and both
mutants were checked to differ from the original byte for byte before running.

| function | mutation | baseline_rc | mutated_rc | restored_rc | red line |
|---|---|---|---|---|---|
| `parse_suite_triggers` | invalid-char case pattern made unreachable | 0 | 1 | 0 | `FAIL: invalid-char declaration did not fail loudly (rc=0, expected 2)` |
| `scan_suite_triggers` | `"${ROOT}/tests"` dropped from the scan roots | 0 | 1 (after the fix below) | 0 | `FAIL: scan roots: declaring root(s) missing from the map: tests` |

## The control that survived — a real coverage hole, found and closed

On the first pass the second mutation **survived**: the suite stayed `11 passed, 0 failed` while the
discovered map lost every row from `tests/`. Verified semantically, not by byte-diff alone:

```text
baseline_rows_from_tests_dir=2
mutated_rows_from_tests_dir=0
restored_rows_from_tests_dir=2
```

That root holds `test-run-all-self-registration.sh` and `test-run-all-carrier-map.sh` — the suites
that prove this feature. So the silent failure mode was "CI stops selecting the tests that guard
self-registration", with nothing red to say so.

Closed in `40087d46` with a **derived** assertion, not a hardcoded list: for every root that exists
AND holds a suite carrying a declaration, the map must carry at least one row pointing into that
root. A new root needs no edit; a dropped root reddens at once. The same mutation now kills.

## Stability and scope

```text
ten consecutive runs (bash): 0 0 0 0 0 0 0 0 0 0
three runs (zsh):            0 0 0
test-run-all-carrier-map.sh, ten runs: 0 0 0 0 0 0 0 0 0 0
```

```text
git diff --name-only main...HEAD        -> 106 files: 102 plugins/leadv2/scripts/tests,
                                           3 tests, 1 plugins/leadv2/tests
non-suite files touched                 -> tests/run-all.sh (only)
git diff --diff-filter=D --name-only main...HEAD -> (empty)
forbidden paths (dispatch-code / profile-select / route-arbiter / active-registry /
                 docs/leadv2/ / known-red-suites.txt) -> clean
```

The only uncommitted file in the worktree is `docs/LEAD_V2_STATE.md`, shared runtime state,
deliberately left out.

## Not proven

- The e2e gate never returned a verdict for this branch: `TIMED OUT after 900s`, i.e. **unknown**,
  never red.
- Acceptance #1 was proven with one scratch suite in one worktree, not with two lanes dispatched
  concurrently. The property it demonstrates — registration touches no shared file — is the one that
  removes the queue; the two-lane form would add machine load on a box that has already lost three
  lanes to the gate today.
