# D2 — pre-brief evidence: liveness needs a PID, and the suite must catch BOTH false answers

Measured on 2026-09-03 by three lead sessions independently. Carry all of this into the D2 brief as
**named acceptance criteria**, not as background. Every claim below was produced by running the
thing, not by reading code.

## Three methods were tried. Two of them lie, in opposite directions.

### 1. Narrow `ps` — false ZERO

`ps aux | grep -F "worktrees/<lane-name>"`

| lane | narrow | free |
|---|---|---|
| six wave-3 lanes (session fb) | **0 for all six** — one of them was writing its stream that same second | 4 and 2 on two |
| LANE-MERGE-SILENTLY-REVERTS-MAIN-01 (c2) | 0 | **4** |
| TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 (c2) | 0 | 1 |
| CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 (c2) | 2 | 3 |

A lane's processes do not all carry the lane name next to `worktrees/`. Seven lanes were declared
dead by this pattern. The verdict happened to be right that time; the method was not.

### 2. Free `ps` — false LIFE, and this one is worse

`ps aux | grep -F "<lane-name>"` also matches the dispatcher itself and helper processes that carry
the lane name in their arguments. Session 36 showed `ps` on the `developer-dispatch-*` label
returning zero against the same free=4.

Measured cost, same session, minutes later: the free pattern reported QUOTA-BINDING-WINDOW as having
1 process and CLASSIFIER-CALLS-SAFETY as having 5. By PID (method 3) QUOTA-BINDING was **dead**. A
dead lane that looks alive is never resumed — nobody goes looking for it. **False life is more
dangerous than false zero**, and a fix that only removes the false zero replaces one error with the
other.

### 3. PID from the dispatcher + `kill -0` — the one that holds

The dispatcher already prints its own answer:

```
worker_spawned by=router model=sonnet task=<sig> handle=PID=<pid> LABEL=developer-dispatch-<sig>-<ts> ...
```

Take the PID from there and ask the kernel. This does not depend on the shape of any command line.
Session 36 ran it against four workers with four distinct signatures, no collisions. Live result at
18:35Z: `54e6f32d` alive (82405), `ca26c56e` alive (44702), `ac7b08fc` alive (25767), `79a9c5b7`
dead, `97669e50` dead — where the free pattern had claimed the last one alive.

Note when reading old handle lines: a lane may have several recorded PIDs across resumes. **Any one
of them alive means the lane is alive**; only "every recorded PID is dead" means dead. Testing just
the newest line you happen to find gives a stale answer.

## A shell trap the implementation will hit

In zsh, an unquoted `$pids` does **not** word-split. `for p in $pids; do kill -0 "$p"; done` iterates
one blob containing every PID and newline, every `kill -0` fails, and the function reports **every
lane dead** — a fourth false zero, produced in this very investigation. Pipe through
`while read -r p` (or `${=pids}`), and make the suite cover it.

## Acceptance criteria for D2's suite — both halves are mandatory

The suite must catch **both** lies. Checking only one converts the bug into its mirror image.

1. **False zero.** Fixture: a live worker whose command line carries the lane name WITHOUT an
   adjacent `worktrees/`. The function must report ALIVE.
2. **False life.** Fixture: a process that mentions the lane name in its arguments but is not the
   worker — a dispatcher or a helper. The function must report NOT alive.
3. **Mirror case.** A genuinely dead lane reports dead, so the fix cannot degrade to "always alive".
4. **Multi-PID case.** A lane with several recorded handles, only one of them alive, reports ALIVE.

A suite that asserts "an alive lane on a conveniently-named fixture reports alive" would have passed
through this entire incident unchanged. It proves nothing.

**Negative control:** the mutation goes INSIDE the liveness function's body — revert it to the narrow
`ps` pattern — and the suite must go red. Proof is the `baseline_rc` / `mutated_rc` pair plus the
literal red suite line. Then revert and show green again, pasting both exit codes.

**Registration:** add the suite to `EXTRA_SUITE_MAP` in `tests/run-all.sh` and prove `--scope changed`
selects it. Of the 23 suites the plan assumed, the runner can currently reach 9; an unregistered
suite rots silently and a green suite CI never runs is worth nothing.

## Scope note

D2 is "one verdict about liveness". The deliverable is not a good function — it is **one pinned
implementation that every caller uses**. If leads keep writing their own `ps` invocation, D2 is not
delivered however good the function is.
