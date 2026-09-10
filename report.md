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

## Mutation control

Pending committed-diff-bound artifact: this section is completed after the
first commit by mutating the same-account exit back to zero and rerunning the
focused suite.  The artifact and its raw output are added before the final
commit.
