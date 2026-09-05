# The lead's ACTIVE TASK is set by a dead row — mechanism, verified 2026-09-02

An earlier note in this session blamed "a subagent's bash call in an arbitrary worktree". That was
wrong. The real path is shorter and worse.

`plugins/leadv2/hooks/leadv2-pulse-json.sh:103-107` — LAST RESORT of the task_id chain:

```bash
_active="$PROJ_ROOT/docs/leadv2/active.yaml"
tid="$(awk '/^[[:space:]]*-[[:space:]]+task_id[[:space:]]*:/{... print $3; exit}' "$_active")"
```

It takes the **first** `task_id` in the file and never looks at `dead_at`, `lane_events`, or
`deregistered`. In persona-engine that file held two rows, both for `PHASE-PATH-REPRO-01`, both
carrying `dead_at` and `event: deregistered / detail: dispatcher_exit`, written 14:16 and 14:18.

Consequence, observed continuously for ~40 minutes: every Bash call the LEAD made rewrote
`docs/handoff/PHASE-PATH-REPRO-01/pulse.json` with the lead's own `session_id`; the anchor
injector read it back and told the lead `ACTIVE TASK: PHASE-PATH-REPRO-01 | phase: spawning`.
Deleting the handoff dir does not help — the next Bash call recreates it from the same dead row.
The anti-silence pulse printed `live=0: PHASE-PATH-REPRO-01=нет-журнала` twice in one line: it
knew there were no live lanes and still named the lane, twice, once per dead row.

Two defects, not one:
1. **The resolver accepts a dead row.** A row with `dead_at` set is not a candidate. First-non-dead,
   or no id at all — an absent anchor is strictly better than a false one.
2. **Wrong registry.** `$PROJ_ROOT/docs/leadv2/active.yaml` is the repo-local file; the live control
   plane is `~/.claude/leadv2-state/leadv2/active.yaml`. The repo copy in persona-engine was stale
   by hours while eight real lanes ran in `~/Projects/leadv2`. This is the same single-repo
   assumption that makes `post-compact-reground.sh` read the wrong tree.

Negative control: put a single dead row in a scratch `active.yaml`, fire the hook, assert the
written `pulse.json` carries no task_id; restore the `exit`-on-first-match awk and the probe goes red.

Cleared by hand 2026-09-02T14:55Z (`sessions: []`, backup in the session scratchpad) — a hand-clear
is not a fix; it will come back on the next dispatcher exit.
