# STATUS-SURFACE-T6B-IS-LOAD-DEPENDENT-01 — report

Lane: `53e7c176f3f6` · macOS Darwin 25.6.0 · `/bin/bash` 3.2.57 · suite file `tests/test-status-surface-bash32.sh` · renderer `plugins/leadv2/scripts/leadv2-status-surface.sh` (mutated only temporarily for control 2, byte-clean vs HEAD afterwards — `git diff --stat` on it prints nothing).

## Shape chosen: freeze the input

`_t6b`/`_t6c` compared two LIVE renders (minimal-env vs full-env wrapper invocation). Nothing held the board still between the captures, so the assertion demanded a load-independent outcome from a load-dependent measurement (observed 2026-09-16: `min=2 full=3` on a 3-lane board, lane `81aeab93` killed as a false `e2e_regression`).

Fix: both T6 captures now read **one frozen sandbox lane set** (own `active.yaml` with one live-pid session, one ledger row, one run dir, fixed `LEADV2_STATUS_NOW=1780000000`), injected via the renderer's existing `LEADV2_STATUS_STATE_DIR / LEDGER_DIR / RUNS_ROOT / REPO / NOW / TASKS_YAML / HANDOFF_DIR` pins — the same injection mechanism T5's `render_fix` already uses. The minimal-env capture passes the pins through `env -i` (pins placed after `env -i`, since assignments before `env -i` are discarded); the full-env capture gets the same pins as prefix assignments. The comparison is now two renderers over identical input, not two moments in time. Also added a vacuous-pass guard: 0 rows on either side is a `bad`, not a parity pass.

**Rejected alternative:** comparing a board-invariant projection of the render (header shape only). It keeps a weaker claim and lets a real reader disagreement hide in the un-projected remainder.

## Cause class

`environment_dependent` — the criterion, not the code under test. The renderer was never broken; the test compared two wall-clock moments.

## Suite counts, before and after

| run | boundary | result |
|---|---|---|
| before (fix absent) | 15 cases, 600s ceiling, Darwin 25.6.0, commit `03643693` | `test-status-surface-bash32: 15 passed, 0 failed, 0 skipped`, `_t6b … (min=2 full=2)` — green only because the board happened to be still |
| after (fix present) | same | `test-status-surface-bash32: 15 passed, 0 failed, 0 skipped`, `_t6b … (min=4 full=4)` from the frozen fixture, unpiped `SUITE_RC=0` |

Nothing else in the suite moved: T1–T5, T7, T8 identical across both runs.

Caveat recorded honestly: `_t6c` (urgent parity) now reads `-1/-1` — the pinned sandbox render has fewer `---` sections than the live board, so the section-5 `urgent:` line is absent from both. Parity still holds and a divergence would still red it, but the case is weaker than before; if urgent parity over frozen input is wanted, it needs the fixture to grow a limits snapshot. Left as-is, named here.

## Negative control 1 — the case is load-independent (old criterion red under a changed board, new one green)

Mutation inside the lane worktree's suite file (not a scratch copy): temporarily pointed the two captures at two DIFFERENT frozen boards (board A = 1 lane, board B = 2 lanes) — the deterministic equivalent of "the lane set changed between the captures". Mutation-target string asserted present before the run (`grep -c 'CONTROL-1 TEMP MUTATION'` → `1`).

```
== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  FAIL - _t6b: lane row-count drift (min=4 full=5)
  ok   - _t6c: urgent parity (min=-1 full=-1)
test-status-surface-bash32: 14 passed, 1 failed, 0 skipped
```

Red under differing input, exactly the 2026-09-16 failure mode (there `2` vs `3`, here `4` vs `5`). Reverted (python patcher asserted the block removal and `T6_STATE-b` absence); with the fix restored the case cannot see differing input — one frozen source feeds both captures — and the full suite is green (run above).

## Negative control 2 — the case still detects a genuine renderer disagreement

Mutation inside the renderer's `_load_yaml` **PyYAML branch** (the path only the full-env python3 takes; verified `python3 -c "import yaml"` → `PyYAML OK 6.0.3` in full env, `ModuleNotFoundError: No module named 'yaml'` under the minimal PATH): append a phantom session so the full-env render grows one extra lane row while the mini-parser render does not. Mutation string asserted present (`grep -c 'CONTROL-2 TEMP MUTATION'` → `1`).

```
== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  FAIL - _t6b: lane row-count drift (min=4 full=5)
  ok   - _t6c: urgent parity (min=-1 full=-1)
test-status-surface-bash32: 14 passed, 1 failed, 0 skipped
```

Reverted afterwards; `git diff --stat plugins/leadv2/scripts/leadv2-status-surface.sh` prints nothing (byte-identical to HEAD), `bash -n` clean.

Honest account of control-2 attempts that did NOT land (each reverted before the next):
- `raise ValueError(...)` at the top of `_mini_yaml` → both envs lost the lane row equally (`min=3 full=3`), `_t6b` stayed green. Reverted.
- Same mutation, but the target string occurred TWICE (the `render_questions` heredoc copy) — the presence-assertion fired (`AssertionError: 2`), nothing was applied, and the suite ran clean 15/15. Re-applied against the first occurrence only.
- `pop(0)` on sessions in the PyYAML branch → the two paths diverged in row CONTENT (full rendered `unnamed worker` vs min `t6feedbac lane`) but not row COUNT, so `_t6b` (a count-parity case) stayed green. That probe is what located the right lever; switched to append.

## bash-3.2 coverage intact — how I checked

- T1/T2 (`/bin/bash -n` on renderer + wrapper), T3 (real `/bin/bash` launch shape), T7 (single-lead loop under `/bin/bash`), T8c (param-expansion under `/bin/bash -c`) are untouched and all pass — the suite still hardcodes `/bin/bash` everywhere it did.
- The new T6 code uses only bash-3.2-safe constructs: `[ ]` tests, `printf`, `env`-prefix assignments, `$( )`, `grep -c`, `awk`/`sed` as before. No arrays, no `declare -A`, no `${var,,}`, no `mapfile`, no `&>>`. The suite itself runs 15/15 under the machine's default bash with `/bin/bash` at 3.2.57 asserted by its own guard (lines 68–75).

## Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-status-surface.sh && echo RENDERER_SYNTAX_OK
RENDERER_SYNTAX_OK
$ bash -n tests/test-status-surface-bash32.sh && echo SUITE_SYNTAX_OK
SUITE_SYNTAX_OK
```
(no Python files changed; `python3 -m py_compile` not applicable)

Changed-scope runner: not run — this lane changed only `tests/test-status-surface-bash32.sh`, which is itself the suite under test; the full-suite runs above ARE the verification (15/15, boundary in the table). No production file is modified at HEAD of this lane.

## Left red

Nothing. All 15 cases green with the fix; both controls demonstrated red where they should and were reverted.
