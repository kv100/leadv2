# E2E-GATE-RESIDUE-01 — core-offline red suites fixed (rounds 1–3)

## Suite 1: dispatch arm vocabulary (kimi retirement)

### Symptom
`harness.sh: line 75: _dispatchable_arms: command not found`, then case2/case3
chains collapse to `sonnet` with `mismatch_emitted=1`. On main only: case1
"dispatch exited 1".

### Root cause (round 1 — test-only)
The test harness in `test-dispatch-arm-vocabulary.sh` extracts functions from
`leadv2-dispatch-code.sh` via `sed` into an isolated harness script. It extracted
`_filter_ladder_to_dispatchable` (which calls `_dispatchable_arms` internally)
but **did not extract `_dispatchable_arms` itself**. When `_filter_ladder_to_dispatchable`
ran, the call to `_dispatchable_arms` failed → empty dispatchable set → every arm
dropped from the ladder → candidate chain collapsed to `sonnet`.

The production function `_dispatchable_arms` exists at `leadv2-dispatch-code.sh:908`
and works correctly — it reads `DISPATCHABLE_BUILD_ARMS` from
`lib/leadv2-glm-policy-resolve.py` via importlib. The journal entries
(`dispatchable_arms_read_failed reason=importlib_read_failed`) seen on main were
from the test harness, not production dispatch.

### Fix (round 1)
Added one `sed` extraction line for `_dispatchable_arms` to the harness builder.

### Hermeticity fix (round 2)
case1 "dispatch exited 1" on main: the dispatcher inherited `LEADV2_PROJECT_ROOT`,
`LEADV2_LANE_WORK_ROOT`, `LEADV2_TASK_ID`, `LEADV2_PARENT_SESSION_ID`, and
`LEADV2_DISPATCH_LANE_NAME` from the parent lead session, leaking real registry
state into the sandbox. Fix: `unset` all five at the suite header, plus
`export LEADV2_ARM_EARLY_VERDICT_S=0` to skip the 20s post-spawn poll window
(the stub worker never reports "complete").

### Hermeticity fix (round 3)
Added global `export LEADV2_DISPATCH_CACHE_DIR="/tmp/leadv2-vocab-default-cache"`
as a belt-and-suspenders default (individual tests override with per-test
sub-dirs). `unset LEADV2_EXCLUDED_ARMS` prevents a real
`~/.claude/leadv2-excluded-arms` file from silently removing candidate arms.

**Files**: `plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh`

## Suite 2: Codex quota guardrails — f2 circuit-open test

### Symptom
`f2 codex usage-limit -> circuit opened with parsed horizon, 1 spawn` fails:
`rc=2, state='closed', jcount='1', spawns='1'`.

### Root cause (round 1 — test-only)
**Not a regression, not a flake — a hardcoded date that aged into the past.**
The f2 test fixture used `Aug 8th, 2026 08:49 AM` as the usage-limit horizon.
The runner correctly parsed it to `2026-08-08T08:49:00Z` and opened the circuit
(jcount=1 ✓, spawns=1 ✓, rc=2 ✓). But on 2026-08-12, that `until` timestamp is
4 days in the past. `codex_circuit_state` compares `now > until` lexicographically
on ISO-8601 strings → `2026-08-12 > 2026-08-08` → auto-closes → returns `closed`.

### Fix
Made the fixture date **dynamic**: compute `now+12h` as the horizon (zeroing
seconds to survive the natural-language round-trip — `%I:%M %p` drops seconds).

**File**: `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh`

## Suite 3: routing enforcement p1 — quota refusal advances chain + 5 siblings

### Symptom (round 2)
Cases "quota refusal advances chain", "launcher crash", "duplicate refusal",
"racing reserve", "lockout write" all fail on main but pass in a lane worktree.

### Root cause (round 2)
Same inherited-env problem as vocab: `LEADV2_PROJECT_ROOT` / `LEADV2_LANE_WORK_ROOT`
from the parent lead session leak real registry data and file locks into the
test sandbox.

### Fix (round 2)
- `unset` inherited `LEADV2_*` session vars at the suite header.
- `export LEADV2_ARM_EARLY_VERDICT_S=0` to skip the 20s poll window per spawn.
- Introduce a `DISPATCH_WRAPPER` bash script that derives `LEADV2_PROJECT_ROOT`
  from `CLAUDE_PROJECT_ROOT` / `PROJECT_ROOT` (same source as the dispatch code)
  so the registry never leaks. Every `DISPATCH_BIN` invocation switched to
  `DISPATCH_WRAPPER`.

### Root cause (round 3)
Case 3 "quota refusal advances chain" HANGS >25 min: the dispatcher's
`CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"` resolved to
the real shared HOME cache, and `DISPATCH_LEDGER_DIR`'s flock
(`.leadv2.dispatch.lock`) blocked on a live foreign session's lock.

### Fix (round 3)
- Global `export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache"` at the suite
  header as a safety-net default (per-test overrides still win as prefix env
  vars).
- `unset LEADV2_EXCLUDED_ARMS` to prevent `~/.claude/leadv2-excluded-arms`
  interference.

**File**: `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`

## Production code untouched

No changes to `leadv2-dispatch-code.sh`, `leadv2-codex-session-runner.sh`,
`lib/leadv2-codex-circuit.sh`, or any other production script. All fixes are
test-only hermeticity hardening.

## Proof

```
# p1 suite, isolation, run 1
$ time bash plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh
PASS: quota gate emits machine-readable reroute marker
PASS: quota gate emits machine-readable peak marker
PASS: quota refusal journals refusal and advances GLM -> Codex
PASS: peak-hours refusal journals refusal and advances GLM -> Codex
PASS: launcher crash remains a failure
PASS: duplicate dispatch is refused and journalled
PASS: record-review refuses duplicate diff hash
PASS: racing reserves admit exactly one dispatch
PASS: ladder order from yaml, dispatch:false entries excluded
PASS: quota precheck skips locked provider and journals the skip
PASS: past lockout is ignored for glm while future lockout skips codex
PASS: absent glm lockout does not block while codex lockout is enforced
PASS: dispatch from plugin repo resolves routing config (no no_routing_yaml)
PASS: degraded mode announces routing_config_degraded and still dispatches
PASS: spawn fence: no POISON marker in any test output
PASS: production yaml dry run: candidate_chain arms=glm,codex,sonnet (no kimi)
PASS: quota lockout write side: quota_lockout_recorded provider=glm
PASS: quota lockout read side: 2nd dispatch skips glm, spawns codex
1:14.27 total  rc=0

# vocab suite, isolation
$ time bash plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh
PASS: case1: resolver returns kimi → dispatch survives on sonnet with mismatch line
PASS: case2: glm chain from ladder (excludes kimi) (got: glm codex sonnet)
PASS: case3: codex chain unchanged (got: codex sonnet)
PASS: case4: sonnet chain unchanged (got: sonnet)
PASS: case4b: kimi unknown arm -> sonnet + mismatch (got: sonnet)
PASS: case5: resolver spill with kimi in tenant yaml → arm=sonnet (not kimi)
PASS: case6: router_v2.arms has 5 entries, kimi absent
5.737 total  rc=0
```

## Commits

- `b8febf4` — round 1: harness `_dispatchable_arms` extraction; f2 dynamic date
- `fcb762c` — rounds 2+3: hermetic env unset, wrapper, `LEADV2_DISPATCH_CACHE_DIR`
  sandbox default, `LEADV2_EXCLUDED_ARMS` unset, `LEADV2_ARM_EARLY_VERDICT_S=0`
