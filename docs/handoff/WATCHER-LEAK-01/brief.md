# WATCHER-LEAK-IS-FAKE-LIVENESS-01 — orphan watchers are counted as work

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run.

**Class:** Standard. **Repo:** leadv2 plugin. File: `plugins/leadv2/scripts/leadv2-lane-watch-v2.sh`.

## The measurement, 2026-09-02

A process census on the lead's machine found **17 live `leadv2-lane-watch-v2.sh --loop` processes**:

- oldest **15h 47m**;
- **two per lane** on `FABLE-THINK-TIER-01` and `WORKER-MCP-ALL-ARMS-01`, each pair under a
  different `session_id`;
- **four pointing at deleted temp fixtures** — `/private/tmp/leadv2-phase-gate-*/repo2`,
  `.../glm-effort-fixture.*/repo`, `/private/tmp/leadv2-lpp-*/target` — i.e. suites had spawned
  real watchers into the real process table and left them there;
- two sharing one `session_id` (`b1efef2c`), 14 hours apart.

**The damage is not CPU.** The lead counted processes-per-worktree as "is this lane alive", saw
`procs=2`, and reported eight working lanes to the founder. **Every one of the eight was finished or
dead**; the "processes" were orphan watchers. A liveness signal that reports watchers as workers is
worse than no signal, because it is confidently wrong.

`SessionEnd` is supposed to disarm the watcher (`--arm-from-hook` / argv-verified kill). It plainly
did not for sessions long gone.

## Deliver

1. **A watcher dies with its session.** Find why `SessionEnd` disarming did not happen for these —
   crashed sessions, sessions killed with SIGKILL, hook never fired, argv-verification failing to
   match. Report which of these it actually was; do not guess a cause and patch for it.
2. **Self-termination as the backstop.** A watcher whose watched path no longer exists, or whose
   session is provably gone, exits by itself. A cleanup that depends only on an exit hook is a
   cleanup that leaks whenever the exit is abnormal — and abnormal exits are exactly when it matters.
3. **Never two on one lane.** One watcher per lane per session; a second registration replaces or
   refuses. State which you chose.
4. **Suites must not spawn real watchers.** Four of the seventeen came from test fixtures. Find how,
   and make a suite-spawned watcher either impossible or self-limiting. This is the one that will
   silently refill the process table otherwise.
5. **Liveness must not be process-count.** Say in the report what the correct signal is
   (worktree mtime? a worker's own heartbeat?) and make the watcher's own output distinguish
   "a worker is running" from "something with this path in its argv exists". The lead's misreport
   came from that conflation.

## Prove it
- Start a watcher, kill its session with SIGKILL (not a clean exit) → the watcher is gone within a
  bounded time. Paste the census before and after.
- Point a watcher at a path, delete the path → it exits. Paste it.
- Register twice for one lane → only one survives. Paste it.
- Run the suite that spawned fixture watchers → census shows none left behind. Paste it.
- **Negative control:** remove the self-termination check in a mktemp FULL copy whose baseline is
  proven green → the deleted-path case leaks again. Paste baseline and mutant runs. Insert the
  mutation INSIDE the function body.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.

## Housekeeping
The lead already killed the four dead-path watchers by hand on 2026-09-02. A hand-kill is not a fix;
they will come back. Do not count the current census as evidence of anything.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.
**Never kill a process you did not start** — argv-verify before any kill, and say in the report how
you verified.

## Done when
A SIGKILLed session leaves no watcher; a deleted path terminates its watcher; double registration is
impossible; suite runs leave none behind; the negative control leaks again against a green baseline;
and the report names what liveness actually is.
