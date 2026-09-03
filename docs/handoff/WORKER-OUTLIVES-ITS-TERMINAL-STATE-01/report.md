# WORKER-OUTLIVES-ITS-TERMINAL-STATE-01 evidence report

## Evidence

The existing three production fixes remain intact: `claude-subsession.sh` records the
post-exit finalizer PID, `leadv2-dispatch-code.sh` normalizes continuation handles, and
`leadv2-dispatch-product-close.sh` resolves and reaps the exact Sonnet producer pair.
The new mutation-control format uses `diff_hash` for the applied scratch mutation and
`lane_diff_hash` for the independently reproducible committed lane diff.

The bounded terminal contract is 15 seconds: the test configures a 2-second close-gate
ceiling, allows two 5-second TERM grace windows, and reserves 3 seconds for scheduling
and filesystem visibility. The terminal test asserts both recorded PIDs are gone before
accepting the terminal decision.

### Red mutation control

```text
suite=plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
file=plugins/leadv2/scripts/claude-subsession.sh
anchor=/^[[:space:]]*printf.*finalizer_pid/ d
baseline_rc=0
mutated_rc=1
red_line=FAIL: Sonnet launcher does not record the finalizer PID
```

The two prior mutation controls remain present for continuation-handle normalization and
product-close finalization. Their regenerated artifacts, plus the finalizer artifact,
are committed under `mutation-control/` below this report. Each artifact contains both
hash fields; the helper rejects the SHA-256 empty-string value for `diff_hash`.

### macOS focused green

```text
test-worker-outlives-terminal-state: 11 passed, 0 failed
test-worker-outlives-terminal-state_rc=0
test-worker-dod-gate: 35 passed, 0 failed
test-worker-dod-gate_rc=0
```

### Linux container focused green

```text
test-worker-outlives-terminal-state: 11 passed, 0 failed
test-worker-dod-gate: 35 passed, 0 failed
linux_test_worker_rc=0
linux_test_dod_rc=0
```

### Syntax and Python falsification

```text
bash_n file=plugins/leadv2/scripts/claude-subsession.sh rc=0
bash_n file=plugins/leadv2/scripts/leadv2-dispatch-code.sh rc=0
bash_n file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh rc=0
bash_n file=plugins/leadv2/scripts/leadv2-mutation-control.sh rc=0
bash_n file=plugins/leadv2/scripts/lib/leadv2-dod-gate.sh rc=0
bash_n file=plugins/leadv2/scripts/tests/test-worker-dod-gate.sh rc=0
bash_n file=plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh rc=0
python_changed_files=none
py_compile_skipped_rc=0
```

### Changed-scope selection

```text
scope_select file=plugins/leadv2/scripts/leadv2-dispatch-code.sh rc=0
run-all: 5 selected, scope=changed, select_only=1
scope_select file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh rc=0
run-all: 5 selected, scope=changed, select_only=1
scope_select file=plugins/leadv2/scripts/claude-subsession.sh rc=0
run-all: 5 selected, scope=changed, select_only=1
scope_select_all_rc=0
```

The isolated macOS changed-scope run selected and executed six suites (core probe plus
the affected regression suites):

```text
run-all: 6 passed, 0 failed, scope=changed
changed_scope_macos_probe_rc=0
```

The full lane changed-scope attempt was bounded and stopped after the core start marker
with rc=130; that ambient runner result is not represented as green evidence. The
focused suites and isolated changed-scope execution above are the passing proofs.

### Hash-collision assertion

`test-worker-dod-gate.sh` runs two distinct mutations (`+ -> -` and `+ -> %`) through
`leadv2-mutation-control.sh`, reads both generated `diff_hash` fields, and fails unless
the hashes differ. This assertion passed in both macOS and Linux runs.
