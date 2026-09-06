# D2-M4 (2/17) — hooks/leadv2-worktree-enforce.sh

## Change

Same conversion pattern as (1/17): the "is there a live /leadv2 task"
per-session `os.kill(pid, 0)` loop over `active.yaml` (ESRCH/EPERM
collapsed) replaced with one `leadv2-lane-liveness.sh --all --json` call.
Liveness binary resolved via `$(dirname "$0")/../scripts/...` — the same
pattern `leadv2-idle-lead-guard.sh` already uses, more robust than
project-root-relative guessing since hooks are invoked through a symlink.

## Test-writing gotcha found (not a production bug)

The hook's own `ACTIVE_YAML` candidate order checks `$PWD/docs/leadv2/
active.yaml` BEFORE `$CLAUDE_PROJECT_ROOT/docs/leadv2/active.yaml`. My
first test draft set `CLAUDE_PROJECT_ROOT` to the fixture root but left the
test script's own `$PWD` wherever the test runner happened to be invoked
from — the hook silently found and used the REAL live project's
`active.yaml` instead of the fixture, and C1 exercised the wrong data
entirely (looked like a real repo's actual live lane, not my EPERM
fixture). Fixed by `cd`-ing into the fixture root before invoking the hook.
Separately, the fixture's own git-repo tmpdir sits under `/tmp` or
`/var/folders`, both hard-whitelisted by the hook's own always-allow rule
(`/tmp/*|/private/tmp/*|/var/folders/*`) — the file path under test must be
a path that does NOT live under the fixture root itself (used a fabricated
`/Users/fixture/fake-main-repo/somefile.py` string; the hook never checks
the file exists).

Also ran the peer-caught check (`grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)'
<file> | sort | uniq -d`) on this file — no duplicate function definitions.

## New tests

`test-worktree-enforce-liveness.sh`: C1 (EPERM pid 1 live task still blocks
a main-repo code edit, rc=2) and C2 (genuinely dead/ESRCH pid does not
block, rc=0). 2/2.

## Mandatory negative control (mutation-control-proven)

Mutated the liveness-consuming condition to `if False:` — RED exactly on
C1 (`baseline_rc=0`, `mutated_rc=1`).

## Commit

`191b8ad5`.
