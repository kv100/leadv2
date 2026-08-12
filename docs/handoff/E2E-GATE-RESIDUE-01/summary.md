# E2E-GATE-RESIDUE-01 — two remaining red core-offline suites fixed

## Suite 1: dispatch arm vocabulary (kimi retirement)

### Symptom
`harness.sh: line 75: _dispatchable_arms: command not found`, then case2/case3
chains collapse to `sonnet` with `mismatch_emitted=1`.

### Root cause
The test harness in `test-dispatch-arm-vocabulary.sh` extracts functions from
`leadv2-dispatch-code.sh` via `sed` into an isolated harness script. It extracted
`_filter_ladder_to_dispatchable` (which calls `_dispatchable_arms` internally)
but **did not extract `_dispatchable_arms` itself**. When `_filter_ladder_to_dispatchable`
ran, the call to `_dispatchable_arms` failed → empty dispatchable set → every arm
dropped from the ladder → candidate chain collapsed to `sonnet`.

This was a **test-only** defect. The production function `_dispatchable_arms`
exists at `leadv2-dispatch-code.sh:908` and works correctly — it reads
`DISPATCHABLE_BUILD_ARMS` from `lib/leadv2-glm-policy-resolve.py` via importlib.
The journal entries (`dispatchable_arms_read_failed reason=importlib_read_failed`)
seen on main were from the test harness, not production dispatch.

### Fix
Added one `sed` extraction line for `_dispatchable_arms` to the harness builder,
between `_load_dispatch_ladder` and `_build_candidate_chain` (call-order safe —
bash resolves functions at call time).

**File**: `plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh`

## Suite 2: Codex quota guardrails — f2 circuit-open test

### Symptom
`f2 codex usage-limit -> circuit opened with parsed horizon, 1 spawn` fails:
`rc=2, state='closed', jcount='1', spawns='1'`.

### Root cause
**Not a regression, not a flake — a hardcoded date that aged into the past.**
The f2 test fixture used `Aug 8th, 2026 08:49 AM` as the usage-limit horizon.
The runner correctly parsed it to `2026-08-08T08:49:00Z` and opened the circuit
(jcount=1 ✓, spawns=1 ✓, rc=2 ✓). But on 2026-08-12, that `until` timestamp is
4 days in the past. `codex_circuit_state` compares `now > until` lexicographically
on ISO-8601 strings → `2026-08-12 > 2026-08-08` → auto-closes → returns `closed`.

### Fix
Made the fixture date **dynamic**: compute `now+12h` as the horizon (zeroing
seconds to survive the natural-language round-trip — `%I:%M %p` drops seconds).
The stub now emits a future date, and all assertions reference the computed ISO
string instead of a hardcoded one.

**File**: `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh`

### Why not a production fix
The session-runner circuit logic (`leadv2-codex-session-runner.sh` +
`lib/leadv2-codex-circuit.sh`) is correct: it detected the wall, parsed the
horizon, opened the circuit, and refused further attempts. The test was the
only thing wrong — its assertion checked `state=open` against a date that had
already expired.

## Proof

Full `run-core-offline.sh` rc=0 output attached in commit message.
