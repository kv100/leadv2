# Phase-record class validation report

## Receipt-freshness round-cap adjudication

`leadv2-judge` mode `review` returned `APPROVE` at confidence `0.90` in
`docs/handoff/41d918c32ef0/judge-review.md`. The capped GLM review was
explicitly scoped to `build-attempt-2.diff`; the current lane includes the
later `build-attempt-3.diff` remedies. The required fresh Codex
reconfirmation was attempted but returned `codex_skipped_by_policy` because
this lane disables Codex.

### Raw red output

```text
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=1 low=4
```

### Raw green output after the recorded fixes

```text
$ bash -n plugins/leadv2/scripts/leadv2-codex-session-runner.sh plugins/leadv2/scripts/leadv2-glm-session-runner.sh plugins/leadv2/scripts/leadv2-kimi-session-runner.sh plugins/leadv2/scripts/leadv2-session-runner.sh plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh
$ timeout 180 bash plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh
[TEST] PASS: bash -n receipt-freshness lib
[TEST] PASS: case1: queued -> rc 0 (stale)
[TEST] PASS: case2: pending -> rc 0 (stale)
[TEST] PASS: case3: claimed_done -> rc 1 (honour)
[TEST] PASS: case4: task absent -> rc 1 (honour)
[TEST] PASS: case5: no tasks.yaml -> rc 1 (honour)
[TEST] PASS: case6: mapping-shape + queued -> rc 0 (stale)
[TEST] PASS: case7: kill-switch=0 + receipt untouched
[TEST] PASS: case8: read-only dir -> rc 2, receipt retained, no stale artifact
[TEST] PASS: wiring: leadv2-kimi-session-runner.sh sources receipt-freshness lib
[TEST] PASS: wiring: leadv2-glm-session-runner.sh sources receipt-freshness lib
[TEST] PASS: wiring: leadv2-session-runner.sh sources receipt-freshness lib
[TEST] PASS: wiring: leadv2-codex-session-runner.sh sources receipt-freshness lib
[TEST] PASS: case9: leadv2-kimi-session-runner.sh exits rc 2 after failed rotation
[TEST] PASS: case9: leadv2-glm-session-runner.sh exits rc 2 after failed rotation
[TEST] PASS: case9: leadv2-session-runner.sh exits rc 2 after failed rotation
[TEST] PASS: case9: leadv2-codex-session-runner.sh exits rc 2 after failed rotation
[TEST] === 26 passed, 0 failed ===
syntax_rc=0 focused_test_rc=0
```

### Changed-scope runner — raw output

```text
$ timeout 240 bash tests/run-all.sh --scope changed
[CORE-OFFLINE] scope=changed running 10 of 95 suites (base=main@45910f2646, 6 changed files, 0 unmapped)
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh (scope-selected ad-hoc)
[TEST] === 26 passed, 0 failed ===
[CORE-OFFLINE] plugins/leadv2/tests/test-lane-state-wiring.sh (scope-selected ad-hoc)
FAIL dispatch admission snippet did not exit 3 for a full cap (rc=0)
[CORE-OFFLINE] Codex quota guardrails (effort/circuit/hook)
[CODEX-QUOTA-GUARDRAILS] pass=26 fail=3
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-writes-overlap.sh (scope-selected ad-hoc)
[TEST] 14 passed, 3 failed
[CORE-OFFLINE] suites passed=6 failed=3 missing=0 known_red_skipped=1 repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/41d918c32ef0
[NOT-KNOWN-RED] core:plugins/leadv2/tests/test-lane-state-wiring.sh (scope-selected ad-hoc)
[NOT-KNOWN-RED] core:Codex quota guardrails (effort/circuit/hook)
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-writes-overlap.sh (scope-selected ad-hoc)
```

The changed-scope gate is red in suites outside this receipt-freshness lane;
deployment and close remain blocked by the deploy precondition that all tests
pass. The wrapper and its reported child PID were both absent after the bounded
run, so this report leaves no started job running.

# Hook escalation evidence

## Scope

Changed the two tracked Bash blockers that match the incident: `leadv2-block-bash-heredoc.sh` and `leadv2-deny-floor.sh`. A private hook helper validates a one-command `LEADV2_HOOK_ESCALATE` reason, queries the journal path through `leadv2-journal.sh path`, and appends the event through that script. The new `test-hook-escalation.sh` self-registers through `run-all-triggers`.

The deny floor keeps `git reset --hard`, `git clean`, `git stash`, and `git worktree prune` closed when the new variable is present. The existing `CLAUDE_ALLOW_SHARED_GIT_DESTRUCTIVE` escape hatch was not changed.

Example recorded journal payload (the focused test asserts the full heredoc command and reason are present):

```text
- <UTC timestamp> [decision] hook_id=leadv2-block-bash-heredoc session_id=hook-escalation-test command=<full 2066-byte heredoc command> reason=recover blocked lane safely
```

## test-hook-escalation.sh — raw red output

```text
PASS  heredoc without escalation remains denied
FAIL  one-word reason rc=2 out=[leadv2-block-bash-heredoc] Bash command is 2066 bytes with a heredoc body.
Heredocs in Bash live in the transcript forever (~2066 chars × every future turn).

Use the Write tool instead:
  Write({ file_path: "/abs/path/file.md", content: "..." })

To override (rare): append "# bash-guard: allow" to the command.
FAIL  meaningful heredoc escalation rc=2 journal=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-hook-escalation.8bpwKK/docs/leadv2/tasks/hook-escalation-test/journal.md out=[leadv2-block-bash-heredoc] Bash command is 2066 bytes with a heredoc body.
Heredocs in Bash live in the transcript forever (~2066 chars × every future turn).

Use the Write tool instead:
  Write({ file_path: "/abs/path/file.md", content: "..." })

To override (rare): append "# bash-guard: allow" to the command.
FAIL  reset --hard rc=2 out=[leadv2-deny-floor] BLOCKED: command matches deny-floor rule 'git_reset_hard'.
git reset --hard is blocked — discards uncommitted work irreversibly. Use ask-lead.sh if this is intentional, or append '# deny-floor: allow' to override on a throwaway tree.

This floor applies even under Codex danger-full-access — it is not a review
heuristic, it is a hard pre-execution stop on irreversible operations.

If this is a genuine false positive:
  - append "# deny-floor: allow" to the command (rare, one-off), or
  - use ask-lead.sh to raise an off_limits/decision conflict for a durable fix.
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/leadv2-hook-escalation.8bpwKK/mutant/hooks/lib/leadv2-hook-escalation.sh'
```

This was the intended pre-implementation red run; the missing helper also prevented the mutation fixture from being created.

## test-hook-escalation.sh — raw green output

```text
PASS  heredoc without escalation remains denied
PASS  one-word reason remains denied
PASS  meaningful heredoc escalation passes and is journalled
PASS  reset --hard remains a closed non-escalatable class
PASS  MUTATION RED: removing reason validation lets one word through

5 passed, 0 failed
```

The mutation is performed in a copied hook tree inside the suite: removing the marked reason-validation branch makes the one-word case pass, while the real helper keeps it denied.

## Changed-scope runner — raw output

```text
$ bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed
[CORE-OFFLINE] scope=changed running 3 of 95 suites (base=main@c694480528, 4 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=3 total=95 base=main@c694480528 changed=4 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] running 3 suites across 4 shards

[CORE-OFFLINE] all plugin shell syntax
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=1 fail=0 missing=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-hook-escalation.sh (scope-selected ad-hoc)
PASS  heredoc without escalation remains denied
PASS  one-word reason remains denied
PASS  meaningful heredoc escalation passes and is journalled
PASS  reset --hard remains a closed non-escalatable class
PASS  MUTATION RED: removing reason validation lets one word through

5 passed, 0 failed
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=1 fail=0 missing=0

[CORE-OFFLINE] tests/test-bash-pre-dispatch.sh (scope-selected ad-hoc)
PASS echo_hi dispatcher verdict matches all 13 originals (ALLOW)
PASS echo_hi expected verdict ALLOW
PASS echo hi is a silent exit 0
PASS echo hi trace invokes only the 2 ALWAYS guards
PASS heredoc dispatcher verdict matches all 13 originals (BLOCK)
PASS heredoc expected verdict BLOCK
PASS heredoc block forwards the guard message on stderr
PASS codex_exec dispatcher verdict matches all 13 originals (BLOCK)
PASS codex_exec expected verdict BLOCK
PASS codex exec matches the standalone direct-exec guard verdict
PASS close_push dispatcher verdict matches all 13 originals (BLOCK)
PASS close_push expected verdict BLOCK
PASS close-ritual/git-push-shaped command forwards deny JSON
TIMING echo_hi runs=5 dispatcher=1226ms_total/245.2ms_avg originals=5690ms_total/1138.0ms_avg
ALL TESTS PASSED
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=1 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=0 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=serial pass=0 fail=0 missing=0

[CORE-OFFLINE] suites passed=3 failed=0 missing=0 known_red_skipped=0 repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4e78ef0dfc51
```

## Syntax and diff hygiene — raw output

```text
$ bash -n plugins/leadv2/hooks/leadv2-block-bash-heredoc.sh plugins/leadv2/hooks/leadv2-deny-floor.sh plugins/leadv2/hooks/lib/leadv2-hook-escalation.sh plugins/leadv2/scripts/tests/test-hook-escalation.sh
$ git diff --check
# both commands produced no stdout or stderr and exited 0
```

---

## Preserved earlier report content

# Refusal reason emitter

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

---

# Eight-level effort scale

`router_v2.effort_scale` is the sole ordered vocabulary: `none, minimal, low,
medium, high, xhigh, max, ultra`; `effort_ceiling` defaults to `ultra`. The
arbiter validates names, caps by scale index, and applies arm-local provider
projections. GLM's partial `low|high|max` projection rounds `xhigh` down to
`high`. The thinking journal now carries `effort=`.

## Arbiter raw output

```text
PASS: ultra safety effort is capped at high and names capped_from=ultra
PASS: high effort below an ultra ceiling remains uncapped
PASS: glm low|high|max projection rounds internal xhigh down to provider high
PASS: an unknown effort name rejects config and names the bad level
PASS: mutation control: string comparison reddens the xhigh-under-ultra projection case
SUMMARY: pass=31 fail=1
FAIL: (g-red) mutation did not flip the outcome — the control is not falsifiable
```

`(g-red)` is the pre-existing dispatcher fail-open negative control; every
effort-scale case above passed.

## Thinking and dispatch raw output

```text
PASS: both think_model_resolved lines include role, class, arm, model, reason, and effort
SUMMARY: 14 pass, 0 fail
PASS: standard build projects internal medium to glm provider low regardless of glm-family winner
PASS: codex arm receives --effort high in its own launch args (distinct from --tier)
PASS: sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)
PASS: the glm-family arm receives the resolved effort as a launcher flag, and does not crash
SUMMARY: pass=13 fail=0
```

## Mutation-control raw output

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-think-through-arbiter.sh file=plugins/leadv2/scripts/leadv2-router.sh
red_line=FAIL: journal lines missing/incomplete: think_model_resolved ... reason=arbiter_cheapest_capable
```

## Syntax checks

```text
PASS: bash -n changed shell files and effort suites
```


---

# PLUGIN-SELF-SUFFICIENT-TENANTS-ONLY-DELTA-01 — report

Row `61dedbec`. Invariant shipped: **the plugin is self-sufficient from its own
tree; a tenant may supply only a declared delta.** One guard extended, no
second mechanism built.

## What changed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-one-copy-convert.sh` | ROOTS → `key\|tenant\|canonical\|scope` quadruples; project-root pairs (check-only); DIVERGED + ROTTEN-EXCEPTION gate the check; UNUSED-EXCEPTION advisory; explicit cache/worktrees prune list; per-root visibility lines with the DEAD-ROOT marker; `--apply` and the `--revert` whole-tree fallback now strictly apply-scoped |
| `plugins/leadv2/ref/one-copy-exceptions.txt` | 9 new declarations (3× diverged `ref/leadv2-main-model.yaml`, 6× identical contract copies); header documents the `project/<repo>/<subroot>/<relpath>` key shape |
| `plugins/leadv2/scripts/tests/test-one-copy-tenant-delta.sh` | NEW suite, 13 cases (registered: `# run-all-triggers: leadv2-one-copy-convert one-copy-exceptions`) |
| `plugins/leadv2/scripts/tests/test-one-copy-drift.sh` | T3 now expects exit 1 (DIVERGED gates); `LEADV2_ONE_COPY_PROJECT_ROOTS=0` for hermeticity |
| 4 tracked `.pyc` | `git rm --cached` — caches are not comparison input and not tracked content (`__pycache__/` already ignored) |

## Roots added

- **Project roots** (scope=`check`): `<repo>/.claude/{scripts,agents,ref,config,contracts}`
  for every repo in `cross-repo-paths.yaml` — persona-engine, m3-market
  (`~/MythicalGames/m3-market`), respiro-ios. Repo list is READ from the yaml
  (same registry plugin-sync uses), never hardcoded; a repo without `.claude/<sub>`
  prints a `files=0` root line — skip, never refusal.
- **Plugin roots ref/config/contracts** are covered through those pairs (canonical
  side `plugins/leadv2/<sub>`).
- **Dead root named dead**: `~/.claude/leadv2-shared/scripts` has no readers
  since 2026-09-06 (everything under it is already a symlink). Kept — plugin-sync
  (b) still produces it and `--revert` manifests key on it — but every `--check`
  run prints `[DEAD-ROOT: no readers since 2026-09-06; ...]` on its root line.
  Silently watching the empty room is no longer possible.
- **Deliberately NOT added**: `~/.claude/leadv2-shared/contracts` as a shared
  pair. plugin-sync (b) produces it by design (link-only producer + gated shadow
  refresh) and owns its drift check (`test-plugin-sync-contracts-gate.sh`);
  adding the same root here would fight the producer. Its 5 identical real
  copies are plugin-sync's domain, not undeclared tenant drift.

## The three census shadows → rule

Census re-measured this lane (relative-path match, caches excluded) — worse
than the brief knew: **all three live repos** carry the shadows, m3-market
included, and a fourth file (`leadv2-shadow-proposal.schema.json`) rides along.

| Shadow | Found | Action |
|---|---|---|
| `ref/leadv2-main-model.yaml` | diverged real copy in persona-engine, respiro-ios AND m3-market | declared `project/<repo>/ref/...`; header says: port to a `.claude/leadv2-overrides/` delta or resync by hand, then retire the line |
| `contracts/leadv2-scorecard.schema.json` | identical copy in all 3 repos | declared `project/<repo>/contracts/...`; plain `--apply` candidate (retire line → founder-run `--apply` symlinks it) |
| `contracts/leadv2-shadow-proposal.schema.json` | identical copy in all 3 repos (census addendum) | same treatment |
| `ref/leadv2-routing.yaml` | — | NOT touched (line `414e61122454` owns it) |

No shadow remains undeclared. Repo `.claude/scripts` and `.claude/agents` trees
came out fully linked (628/403/382 and 3/3/3 files) — plugin-sync did its job
there; the guard now proves it continuously.

## Acceptance fixtures (suite `test-one-copy-tenant-delta.sh`, 13/13 green)

- **A1** real copy (identical → `REGRESSION`, diverged → `DIVERGED`) in a tenant
  tree is NAMED, exit 1 — T1/T1b.
- **A2 paired** same file, one exception-list line, nothing else changed →
  `EXPECTED-OVERRIDE`, exit 0 — T2.
- **A3** `__pycache__` (and lane-`worktrees/`) copies → pruned, exit 0 — T3.
- **A4** exception line whose canonical twin is gone → `ROTTEN-EXCEPTION`, exit 1 — T4.
- Edges: tenant-only file = info not violation (T5); symlink out of canonical =
  `BADLINK` (T6); repo without `.claude/` skipped with visible `files=0` (T7);
  declared-identical = advisory only (T8); DEAD-ROOT marker printed (T9);
  UNUSED exception advisory (T10); exception naming a repo absent from the yaml
  is inert (T11).

Sibling suites stay green: `test-one-copy-drift.sh` 8/8, `test-one-copy-drift-hook-postsync.sh` 7/7.

## Live verification (read-only)

Run against a `/tmp/livegate` canonical model (subtrees symlinked to the main
checkout + this lane's script/exceptions — byte-faithful to post-merge main):

- **Green with declarations**: `rc=0`, `tally: linked=2352 regression=0 badlink=0
  expected_override=9 diverged=0 rotten_exceptions=0 unused_exceptions=3`.
- **Paired red without them** (main's old exception list): `rc=1`, naming
  exactly the 9 shadows (3 DIVERGED + 6 REGRESSION).
- The SessionStart hook stays advisory (always exit 0); its filtered report
  carries the extended tally, so a diverged/rotten-only failure can no longer
  render as "0 regression(s)".

## Mutation control (negative control, brief-mandated)

`mutation-control/20260910T121204Z-86715.txt` — mutant: exception-list
consultation removed INSIDE `cmd_check` body
(`/^cmd_check()/,/^}/ s/if is_exception .../if false; then/`). Baseline rc=0 →
mutated rc=1, red line = paired fixture T2 leaking `DIVERGED`. Exactly the
brief's "убрать сверку с файлом исключений внутри тела функции".

## Known notes

- **Worktree artifact**: running `--check` from a lane worktree flags the live
  shared/repo symlinks as BADLINK because `CANONICAL_ROOT` resolves to the
  worktree while the links point into main. Production paths (hook via
  `~/.claude/plugins/local/leadv2` symlink, humans from main) resolve to main
  and are unaffected. Live proofs above used the main-canonical model.
- The 3 legacy `agents/*.md` exception lines now report UNUSED (tenant files
  were converted to symlinks 2026-09-09). Left in place — retiring them is a
  founder-visible call, not one to smuggle into this lane; the advisory makes
  them impossible to miss.

## Falsification set

- `bash -n` on every changed shell file: convert, both suites — SYNTAX-OK.
- No Python files changed (py_compile n/a).
- `tests/run-all.sh --scope changed`: see verdict below.

`tests/run-all.sh --scope changed` → **5 passed, 1 failed (core-offline
umbrella), 0 known-red**. The red is NOT this lane's:

- Inside the same run, ALL three one-copy suites passed (`test-one-copy-drift.sh`
  8/8, `test-one-copy-tenant-delta.sh` 13/13, postsync 7/7).
- The umbrella's failing cases — `P-h(a/b/g) prompt pin line MISSING`,
  `5b no host installs its own EXIT trap`, `NEGATIVE CONTROL 1: mutated
  arbiter still passed`, `(g) live repo not found (set LEADV2_DOD_LIVE_REPO)` —
  are byte-identical in the CONCURRENT lane `414e61122454`'s core-offline run
  (foreign runner confirmed via per-pid lsof cwd, alive 15:20–15:45+ while
  this lane's run spanned 15:12–15:47; the
  core-offline-reds-under-concurrent-runners pattern). Two lanes with
  disjoint diffs producing the same failure set = shared baseline/environment
  red, not a regression from this diff. Follow-up belongs to the baseline-reds
  owner, not this row.

Red/green pair for the behavior change (the brief's mandate):

- RED (mutant, exception consultation removed inside `cmd_check`):
  `MUTATION-CONTROL ok ... red_line=FAIL: T2 ... DIVERGED` (artifact
  `mutation-control/20260910T121204Z-86715.txt`).
- GREEN (restored): `test-one-copy-tenant-delta.sh ── 13 passed, 0 failed ──`,
  `test-one-copy-drift.sh ── 8 passed, 0 failed ──`,
  `test-one-copy-drift-hook-postsync.sh ── 7 passed, 0 failed ──`,
  live gate `rc=0` (2352 linked, 9 EXPECTED-OVERRIDE) vs paired live red
  `rc=1` (exactly the 9 shadows) without the declarations.
