# D6-REGISTRY-LANE-OWNERSHIP-01 report

## Scope and landed files

Landed in pinned lane commit `7fabbc26` (on top of the earlier lane commit):

- `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh`
- `plugins/leadv2/scripts/tests/test-lead-session-identity.sh`

The resolver returns `lead-<durable_pid>-<birth_hash>` by sourcing and using
the existing `_lv2_durable_pid()` and `_lv2_pid_birth()` helpers. It falls back
to `direct` if resolution is unavailable.

The requested dispatcher change is **not landed** (another session owns that
file). Exact replacement for `leadv2-dispatch-code.sh:7071`:

```bash
local _lead_session_id="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(source "${SCRIPT_DIR}/lib/leadv2-lead-identity.sh"; leadv2_lead_session_id)}}"
```

CI does **not** select the new suite yet. Ready-to-paste `tests/run-all.sh`
`EXTRA_SUITE_MAP` row:

```text
leadv2-lead-identity.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
```

## Focused acceptance and stability

The cap acceptance is state-based: with `LEADV2_LANE_CAP=1`, register 1 for
one identity returned `0`, register 2 for that same identity returned `3`
(refused), and register 3 for the other identity returned `0` (permitted).
The suite also checks a matching-live owner, mismatched birth, dead owner, and
legacy `direct` row.

Raw initial RED output, before the hermetic `ps` fixture repair:

```text
[TEST] FAIL: distinct owners: got A='direct' B='direct'
[TEST] FAIL: cap proves defect dead: got lane1=0 lane2=0(want 3) lane3=0(want 0)
[TEST] FAIL: lead alive corroboration: live owner + matching birth got rc=1 (want 0)
[TEST] 3 passed, 3 failed
bash_rc=1
```

Raw GREEN output after the repair (Bash; zsh has the same six passes):

```text
[TEST] PASS: distinct owners: lead-80994-3106823476 != lead-80995-1798806760
[TEST] PASS: cap proves defect dead: lane1(same session)=0 lane2(same session)=3(refused) lane3(other session)=0
[TEST] PASS: lead alive corroboration: live owner + matching birth -> rc=0
[TEST] PASS: lead alive corroboration: recorded birth mismatch -> rc=1 (not alive)
[TEST] PASS: lead alive corroboration: dead owner reports not-alive (rc=1)
[TEST] PASS: legacy rows resolve: lane_count_live direct returned '0' without exception
[TEST] 6 passed, 0 failed
bash_rc=0
zsh_rc=0
```

Ten consecutive exit-code runs:

```text
bash: 0 0 0 0 0 0 0 0 0 0
zsh:  0 0 0 0 0 0 0 0 0 0
```

## Mutation control

Artifact: `docs/handoff/dispatch-33e16647/mutation-control/20260904T041726Z-37935.txt`

```text
suite=plugins/leadv2/scripts/tests/test-lead-session-identity.sh
file=plugins/leadv2/scripts/lib/leadv2-lead-identity.sh
anchor=s/id="lead-${pid}-${birth_hash}"/id="direct"/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: distinct owners: got A='direct' B='direct'
```

This mutation is inside `leadv2_lead_session_id()` and preserves shell parse;
the cap/state assertion remains red, so the failure is not a message-text-only
assertion. The artifact is produced by `leadv2-mutation-control.sh`, not a
diff-hash claim.

## Required self-checks

```text
bash -n plugins/leadv2/scripts/lib/leadv2-lead-identity.sh plugins/leadv2/scripts/tests/test-lead-session-identity.sh
bash_n_rc=0
zsh -n plugins/leadv2/scripts/lib/leadv2-lead-identity.sh plugins/leadv2/scripts/tests/test-lead-session-identity.sh
zsh_n_rc=0
```

`timeout 300 bash tests/run-all.sh --scope changed` began the always-on core
suite and emitted only:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D6-REGISTRY-LANE-OWNERSHIP-01/plugins/leadv2/scripts/tests/run-core-offline.sh
```

It did not provide a foreground completion receipt in this environment. This
is an ambient changed-scope runner non-completion; it is not represented as a
green test result.

## Live acceptance

UNVERIFIED: two independently working live sessions currently write at least
two distinct `lead_session_id` values to the shared registry. No registry
mutation or two-session live probe was authorized by this narrow lane.
