# Phase-record class validation report

## Actual class casing

`phase-record` receives producer-class casing: `Strategic` and `Bulk`. The
new focused suite proves those exact values pass both `assert` and `plan-for`,
while lowercase `strategic` and `bulk` remain rejected. No case normalization
was introduced.

## Red baseline

```text
BASELINE command=assert --class Strategic rc=4
[leadv2-phase-record.sh] ERROR: assert: invalid class 'Strategic'
BASELINE command=plan-for --class Strategic rc=4
[leadv2-phase-record.sh] ERROR: plan-for: invalid class 'Strategic'
BASELINE command=assert --class Bulk rc=4
[leadv2-phase-record.sh] ERROR: assert: invalid class 'Bulk'
BASELINE command=plan-for --class Bulk rc=4
[leadv2-phase-record.sh] ERROR: plan-for: invalid class 'Bulk'
```

## Green run

```text
$ bash plugins/leadv2/scripts/tests/test-phase-record-class.sh
PASS: assert class=Strategic rc=0
PASS: plan-for class=Strategic rc=0
PASS: assert class=Bulk rc=0
PASS: plan-for class=Bulk rc=0
PASS: assert Nonsense keeps rc=4 and prior error
PASS: plan-for Nonsense keeps rc=4 and prior error
PASS: YAML override class=Strategic accepted
PASS: YAML override class=Bulk accepted
RESULT: pass=20 fail=0
```

## Mutation control

```text
$ LEADV2_BUILDER_SELFCHECK=0 bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live plugins/leadv2/scripts/tests/test-phase-record-class.sh plugins/leadv2/scripts/leadv2-phase-record.sh 's|local -r classes="Trivial Light Standard Heavy Strategic Bulk"|local -r classes="Trivial Light Standard Heavy Bulk"|' plugins/leadv2/scripts/tests
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-phase-record-class.sh file=plugins/leadv2/scripts/leadv2-phase-record.sh red_line=PASS: assert class=Trivial rc=0 diff_hash=037d6db3f93b74602b96039878d30eb93470ad35240107c17fdd1fc4814e71bb lane_diff_hash=45997e503da4d74d508ca75404ae233735f539acf9be2a5049a363ef7a92cc51 porcelain_clean=yes
```

The committed probe artifact is
`plugins/leadv2/scripts/tests/mutation-control/20260910T094646Z-live-42505.txt`.

## Syntax and changed-scope runner

```text
$ bash -n plugins/leadv2/scripts/leadv2-phase-record.sh
$ bash -n plugins/leadv2/scripts/tests/test-phase-record-class.sh
$ bash -n tests/run-all.sh
$ git diff --check
exit=0

$ timeout 60 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit=124

$ timeout 240 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit=124
```

The focused regression and syntax checks are green. The repository wrapper
never reached a suite result within either foreground bound; it is recorded as
a timeout, not claimed as a passing changed-scope run.

## Existing phase-record suite

The pre-existing `test-phase-record.sh` does not create its fixture in this
sandbox: its bare `mktemp -d` resolves to a denied system temp directory (the
same result occurred with `TMPDIR=/tmp`). This is not treated as a product
regression; the new suite uses an explicit permitted fixture path.

```text
$ timeout 120 bash plugins/leadv2/scripts/tests/test-phase-record.sh
mktemp: mkdtemp failed on .../tmp.bV4B6x2nCr: Operation not permitted
mkdir: /src: Operation not permitted
[PORE-RECORD] pass=7 fail=5
exit=1
```

---

# Mission lint brief contract

Added a decision-completeness refusal (`MISSION_NOT_DECISION_COMPLETE`, rc 9)
for briefs without a `Подход`/`Approach`/`Как делать` heading, plus a
non-blocking `MISSION_MUTATION_WITHOUT_BEHAVIOUR` warning. The new suite is
self-registered for `leadv2-mission-lint` changes.

## Evidence: red before the implementation

```text
[TEST] PASS: bash -n: mission linter parses
[TEST] FAIL: no approach heading -> expected rc=9 and named reason; rc=0; out=
[TEST] PASS: adding only an Approach heading -> exit 0
[TEST] FAIL: mutation without behaviour -> expected warning + rc=0; rc=0; out=
decision-complete function mutation anchor not found
[TEST] FAIL: negative control setup: decision-complete function mutation anchor not found
[TEST] ----
[TEST] PASS=2 FAIL=3
```

## Evidence: green target suite

```text
[TEST] PASS: bash -n: mission linter parses
[TEST] PASS: no approach heading -> MISSION_NOT_DECISION_COMPLETE, exit 9
[TEST] PASS: adding only an Approach heading -> exit 0
[TEST] PASS: mutation without behaviour -> warning and exit 0
[TEST] PASS: negative control: removing check A inside its function makes no-approach case red
[TEST] ----
[TEST] PASS=5 FAIL=0
```

## Evidence: leadv2-mutation-control.sh live run

Artifact: `mutation-control/20260910T092927Z-live-50779.txt`.

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-mission-lint-contract.sh file=plugins/leadv2/scripts/leadv2-mission-lint.sh red_line=[TEST] FAIL: no approach heading -> expected rc=9 and named reason; rc=0; out= diff_hash=0e0fab572690db687cd5151ada6700dc7d0644e1fda12f7b31c7c43a70692ca1 lane_diff_hash=9ad931ee6d680de23a0fcda5a324d96972f7b0159baae038047c66af63a8bbd4 porcelain_clean=yes
```

## Evidence: changed-scope runner

```text
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-f2c4bf8090d0.lock holder=pid=18158 host=UA-K-VLASENKO-LT-2.local since=2026-09-10T09:32:26Z (held by a concurrent run)
[CORE-OFFLINE] FATAL lock_timeout file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-f2c4bf8090d0.lock wait_s=60 holder=pid=18158 host=UA-K-VLASENKO-LT-2.local since=2026-09-10T09:32:26Z
```

The runner therefore did not execute any changed-scope suite in this lane;
the direct target suite above is green.
# §3 — seamless Claude account switching

## Answers before code

### 1. Resume break point

`leadv2-session-runner.sh` is the lead retry path.  Its attempt-zero branch
uses `--session-id`; every later attempt uses `--resume`, but the actual launch
at lines 444–452 invokes `"$CLAUDE_BIN" "${claude_args[@]}"` directly.  It
does not invoke `leadv2-claude-profile-select.sh` and does not set
`CLAUDE_CONFIG_DIR`.  Therefore a global default-account switch between
attempts changes the account used by the resumed lead session; worker
subsession selection cannot repair it.

Raw structural probe (2026-09-10):

```text
$ sed -n '402,415p;444,452p' plugins/leadv2/scripts/leadv2-session-runner.sh
if [[ "$attempt" -eq 0 ]]; then
  session_flag=(--session-id "$SESSION_ID")
else
  session_flag=(--resume "$SESSION_ID")
fi
...
( cd "$PROJECT_ROOT" && \
  "$CLAUDE_BIN" "${claude_args[@]}" ) >>"$LOGF" 2>&1
```

The resume boundary is consequently outside this lane's write set.  This lane
does not alter `leadv2-session-runner.sh`.

### 2. Can a live session's credential switch without killing it?

The process-scoped configuration mechanism is isolated: each child receives
the `CLAUDE_CONFIG_DIR` value present at its own launch.  The repository's
existing `claude-subsession.sh` integration test also launches a fake Claude
child and proves the selected directory reaches that child (`I1`, recorded in
the green transcript below).  The local two-launch probe was:

```text
$ CLAUDE_CONFIG_DIR=/tmp/.../first bash -c 'printf "first config=%s\\n" "$CLAUDE_CONFIG_DIR"'
first config=/tmp/.../first
$ CLAUDE_CONFIG_DIR=/tmp/.../second bash -c 'printf "second config=%s\\n" "$CLAUDE_CONFIG_DIR"'
second config=/tmp/.../second
```

This proves process-environment isolation, not a provider claim about
mid-request token replacement.  No live Claude session was redirected or
stopped, and no Keychain record was read or written.  A running process keeps
its inherited environment; start a new process under the other directory
instead of changing the machine default.

### 3. How can the balancer know a free account without usage polling?

It cannot derive availability from identity.  The account checker now says so
in machine-readable output: `availability=unknown(identity_only)`.  Its source
contains neither a quota-reader invocation nor an HTTP URL, and its fixture
run below used only local files.  A future balancer needs an account-scoped
reservation/lease signal (or an explicit external meter); without one it must
not label either account free.  That reservation design belongs in the
off-limits route-arbiter path, so it was not invented in this lane.

```text
$ bash plugins/leadv2/scripts/tests/test-claude-account-check.sh
[TEST] PASS: T1c: verdict names identity-only availability limit
[TEST] PASS: T9a: one slot has no two-account conclusion
[TEST] Results: PASS=24 FAIL=0
```

## Change

`same_account` now returns `profile=- reason=same_account` with exit 4.  It
cannot be mistaken for the selector's normal zero-exit single-profile
fallback.  An expired or absent inherited credential also returns exit 4 only
when the selector would otherwise fall back to that inherited slot.  A
registry profile that succeeds its configured probe remains launchable, so a
stale credential timestamp alone does not discard a proven working profile.

The account check rejects registries with fewer than two valid slots and marks
all successful two-slot verdicts as identity-only availability.

## Falsification and verification

Red run while the new T18 fixture accidentally retained only one registry row:

```text
[TEST] FAIL: T18b: selection proceeds -- no match for '^profile=alpha ' in: profile=- reason=default_token_absent
[TEST] FAIL: T18 exit -- rc=4
[TEST] Results: PASS=104 FAIL=2
```

After restoring the two-slot fixture, the focused selector suite was green:

```text
[TEST] PASS: T14: exit 4 (hard refusal; never a single-profile fallback)
[TEST] PASS: T17c: expired inherited credential refuses single-profile fallback
[TEST] PASS: T17d: refusal is explicit, not a quiet fallback
[TEST] PASS: T18: exit 0 (explicit probe-qualified alternative selected)
[TEST] PASS: T23: exit 4 (same-account is never a fallback)
[TEST] Results: PASS=106 FAIL=0
profile_select_rc=0
```

```text
$ bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh
$ bash -n plugins/leadv2/scripts/leadv2-claude-account-check.sh
$ bash -n plugins/leadv2/scripts/tests/test-claude-profile-select.sh
$ bash -n plugins/leadv2/scripts/tests/test-claude-account-check.sh
$ bash plugins/leadv2/scripts/tests/test-claude-account-check.sh
[TEST] Results: PASS=24 FAIL=0
```

The repository changed-scope runner was executed in the foreground with its
900-second cap.  It did not establish a patch failure: its core wrapper
expanded to 95 suites because the committed report has no suite mapping, then
hit its own 600-second per-suite ceiling amid unrelated sandbox-path failures.
The runner's raw terminal verdict was:

```text
[CORE-OFFLINE] scope=changed running 95 of 95 suites ...
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run_all_changed_rc=124
```

Focused changed-code evidence remains the two green suites above; the broad
runner is red/timeout and is not represented as a passing verification.

The deterministic definition-of-done gate passed on the committed lane:

```text
dod_pass check=suite_registration
dod_pass check=runtime_state
dod_report wrote=1 path=/tmp/77de6264b787-dod.md
dod_gate_rc=0
```

## Mutation control

The committed-diff-bound control restored the old quiet `same_account -> exit
0` path in a scratch copy.  The selector suite went red at the named T14
assertion; the real checkout was not mutated.

Artifact: `mutation-control/20260910T091540Z-64181.txt`

```text
$ LEADV2_MUTCTL_SNAPSHOT=worktree bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-claude-profile-select.sh \
    plugins/leadv2/scripts/leadv2-claude-profile-select.sh \
    /tmp/77de6264b787-same-account-zero.patch .
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-claude-profile-select.sh \
  file=plugins/leadv2/scripts/leadv2-claude-profile-select.sh \
  red_line=[TEST] FAIL: T14 exit -- rc=0 \
  diff_hash=61289377310d5a7344b30498adef9e5cd639e598642d848b7ec26dd2d74e56b5 \
  lane_diff_hash=73ab3a0452828bd5081e8a992d321d5cd1555a9a55a4253292a5652361a32d5e
mutation_control_rc=0
```

## §3 round 2 — caller propagates selector refusal

`claude-subsession.sh` now captures the selector's status without letting
`set -e` exit first.  An unrequested `rc=4` stops the launch with a FATAL line
and journals the selector's `reason=`; an empty refusal becomes
`reason=unparsed_refusal`.  Requested-profile failures retain their existing
`exit 5` path.  `rc=124`, a missing selector, malformed stdout, and the
multi-profile opt-out still take the prior soft fallback.  The successful
selector-line grammar is unchanged.

The existing selector suite gained hermetic caller fixtures for hard refusal,
timeout fallback, successful selection, empty refusal, and requested-profile
priority.  The fixture varies only selector stdout and exit code, and its fake
Claude records whether launch was reached.

### Raw red then green

Before the caller fix, the new hard-refusal fixture showed that the process
exited on the selector's non-zero `wait` before emitting its required caller
diagnostics:

```text
[TEST] FAIL: I10c: refusal reason reaches FATAL stderr -- no match for '^\\[claude-subsession\\] FATAL:.*reason=same_account'
[TEST] FAIL: I10d: refusal reason reaches handoff log -- no match for '\\[claude-profile\\] FATAL reason=same_account'
[TEST] FAIL: I11a -- rc=124
```

After the fix:

```text
$ bash -n plugins/leadv2/scripts/claude-subsession.sh
$ bash -n plugins/leadv2/scripts/tests/test-claude-profile-select.sh
$ timeout 120 bash plugins/leadv2/scripts/tests/test-claude-profile-select.sh
[TEST] PASS: I10a: rc=4 refusal stops the launch
[TEST] PASS: I10d: refusal reason reaches handoff log
[TEST] PASS: I11a: rc=124 remains a soft fallback that reaches launch
[TEST] PASS: I12c: successful selection journal remains byte-for-byte legacy shape
[TEST] PASS: I13c: empty rc=4 reason reaches handoff log
[TEST] PASS: I14a: requested-profile refusal keeps exit 5 priority
[TEST] Results: PASS=122 FAIL=0
```

### Mutation control

The live control replaced the new refusal branch's `exit 4` with `return 0`,
then restored the real file.  The hard-refusal fixture went red because fake
Claude was launched; the artifact records both restoration and a clean
porcelain check.

Artifact: `mutation-control/20260910T095827Z-live-24057.txt`

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-claude-profile-select.sh file=plugins/leadv2/scripts/claude-subsession.sh red_line=[TEST] FAIL: I10b -- capture=CLAUDE_CONFIG_DIR=<unset> diff_hash=961bec9ad405c57841ec508616b1c0ddf1cf68d9575f77b6eac9b5252534f9f4 lane_diff_hash=5b2bef32bf5b559df2c76038913cdb2b00a0fda0fb0aab1df43ff8d9483da40e porcelain_clean=yes
```

### Changed-scope runner (foreground, 900-second cap)

The repository runner did not establish a global green result.  It reached
unrelated suites and the outer cap returned 124; one unrelated requested-profile
suite could not create its temp fixture in this sandbox.  The focused suite
above is the passing changed-code evidence.

```text
$ timeout 900 bash tests/run-all.sh --scope changed
[PASS] .../plugins/leadv2/scripts/tests/test-balancer-every-arm.sh
[PASS] .../plugins/leadv2/scripts/tests/test-cache-truth.sh
[RUN] .../plugins/leadv2/scripts/tests/test-claude-profile-requested.sh
mktemp: mkdtemp failed on .../tmp.rmBCPQEjyt: Operation not permitted
[CLAUDE-PROFILE-REQUESTED] FAILED
[FAIL] .../plugins/leadv2/scripts/tests/test-claude-profile-requested.sh
[RUN] .../plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh
run_all_changed_rc=124
```
