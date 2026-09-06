"""leadv2_pid_alive.py — ONE liveness-collapse rule, ONE inode.

`os.kill(pid, 0)` has THREE answers: rc (no exception) -> alive;
`ProcessLookupError` (ESRCH) is the ONLY proof of death; `PermissionError`
(EPERM) means the process EXISTS, owned by another user -- alive, never
dead. Any other `OSError` is unclassifiable ("unknown"), and per the
contract `lib/leadv2-lane-state.sh::proc_verdict`/`alive()` and
`leadv2-orphan-reaper.sh::_owner_death_state` already carry, unknown must
never look like death -- it never gates a kill or a restart. This module's
callers are boolean-only ("is this row's pid alive, yes/no"), so unknown
collapses to True (alive), the same direction lane-state.sh's
`alive(row) = verdict(row) != 'dead'` already collapses it.

ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01: five independent copies
of this predicate existed in leadv2-active-registry.sh (lines ~322, ~1576,
~1664, ~1827, ~2117 at the time of the fix), all still catching
`PermissionError` as death (`except (..., ProcessLookupError,
PermissionError): return False`) -- an EPERM-owned live foreign worker was
read as dead in both directions: undercounted in `check_limits`'s admission
filter (the hard cap could be exceeded) and misread as a dead incumbent in
the writeset-conflict check `_lv2_ws_dead` (a live conflicting lane could be
waved through into the same worktree). This module is the replacement for
all five.

Import contract (R4, same shape as `leadv2_pid_birth.py`): callers inside a
`python3 - ... <<'PYEOF'` heredoc do

    sys.path.insert(0, os.environ.get("LEADV2_AR_LIB_DIR", ""))
    from leadv2_pid_alive import pid_alive

and MUST fall back to an inline copy of the SAME three-way logic when the
import fails (a drifted `.claude/scripts/` copy without `lib/`) -- degrade,
never crash a registry read.
"""

import os


def pid_alive(pid_val) -> bool:
    """True unless pid_val is provably a dead process (ESRCH).

    EPERM (process exists, foreign-owned) and any other unclassifiable
    OSError both count as alive -- unknown must never look like death.
    """
    try:
        pid = int(pid_val)
    except (TypeError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False        # ESRCH -- the only proof of death
    except PermissionError:
        return True         # EPERM -- process exists, alive, owned elsewhere
    except OSError:
        return True         # unclassifiable -- never treat as dead
    return True
