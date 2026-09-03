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

## Two more false answers, added 2026-09-03 after the machine-saturation measurement

### Ninth: `kill -0` reports a live process dead when permission is denied

From herdr, via c2. `kill(pid, 0)` fails for two different reasons and the shell collapses them into
one non-zero exit code:

- `ESRCH` — no such process. **Dead.**
- `EPERM` — the process exists but belongs to another user. **Alive, and unreachable.**

`kill -0 "$p"` in bash returns non-zero for both. So the pinned function, written the obvious way,
answers "dead" for a live process it merely cannot signal. This is a false zero hiding inside the
method that was chosen precisely to eliminate false zeros.

**Acceptance case, mandatory:** a fixture PID whose signal is refused with `EPERM` must be reported
**ALIVE**. Distinguish the two errnos rather than testing truthiness — a suite that only covers
`ESRCH` passes today and ships the bug.

### Tenth: starvation timeout reads as death

Measured the same evening. Load 188–248 on a 10-core machine, memory 64% free — CPU contention, not
OOM. Workers were spawned successfully (`rc=0` genuine, PID real), got no CPU, hit their own timeout,
and exited. From outside, that is byte-identical to "the lane died".

This does not change the liveness verdict itself — a timed-out worker really is dead — but it changes
what the verdict **means**, and D3 consumes this verdict to decide whether to rescue and resume.
Resuming a starved lane onto a saturated machine reproduces the starvation. Whatever D2 returns must
carry enough for a caller to tell "died holding work" from "never got scheduled": at minimum the exit
cause, so D3 does not treat the two identically.

### Eleventh: the anti-silence pulse reads "no journal" as "not alive"

Observed live, 2026-09-03T19:26Z. The pulse published:

```
[ПУЛЬС 19:26Z] live=0: … D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF=нет-журнала; …
```

At that same moment the D3 worker's dispatcher-printed PID (72076) answered `kill -0`. The lane was
alive. The pulse's method is "does this lane have a journal file", and a worker that has spawned but
not yet written its first journal line has none — so a healthy lane in its first minutes is published
as `live=0`.

This one matters beyond the count, because it is a **caller with its own opinion**, not a bad probe
in isolation. D2's deliverable is not a good function; it is *one pinned implementation that every
caller uses*. The pulse is precisely a caller that grew its own verdict, and it is the surface the
founder reads. While it keeps its own method, D2 can ship a perfect function and the number the
founder sees will still be wrong.

**Acceptance addition:** the pulse must consume D2's pinned function. Grep for every site that
decides liveness — journal presence, stream mtime, `ps` patterns, registry fields — and either
convert it or list it in the closure as a known remaining caller. A census of callers is part of the
deliverable; without it "one verdict" is an aspiration.

### Twelfth: `set -o pipefail` turns a correct check into a wrong answer

From c2, found in its own status generator and fixed at `c482bde99`. Three bugs sat in one function
at once; this is the one that matters for D2's implementation.

Under `set -o pipefail`, a pipeline like

```sh
kill -0 "$pid" 2>/dev/null | grep -q something
```

inherits the failure of **any** stage, so the pipeline's exit status carries `kill`'s result even
when the intended answer comes from the last stage. A successful match therefore reads as a failure,
and in c2's generator the effect was that **every genuine death was reported as "unknown"**.

The lesson for D2 is not "avoid pipefail" — it is that the pinned function must **not decide liveness
inside a pipeline at all**. Call `kill -0` on its own, capture `$?` into a variable immediately, and
branch on that variable. Any shell construct that lets another command's status reach the same exit
code is a fourth way to get a false answer out of a correct check.

The other two bugs in that same function are worth naming because they are D2's own subject matter:
it defaulted to **"dead" when no record existed** (absence read as death — the fifth false answer,
already recorded above), and it reported a **reused PID as alive**. The second one is not yet covered
by any acceptance case here:

**Acceptance addition — PID reuse.** A recorded PID that has been recycled by the OS to an unrelated
process must not report the lane alive. Pair the PID with something that dies with the worker — its
start time, or its command-line signature — and assert a fixture where the recorded PID now belongs
to a different process reports **not alive**.

### Fourteenth: the recorded PID is alive but is not a worker

Measured 2026-09-03 on CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01, which could not be re-dispatched
at all: every attempt answered `REFUSE placement: lane_is_live`, with the age counter climbing
(`starting:60`, then `starting:163`) rather than expiring.

The registry row carried `pid: 79117`. `kill -0 79117` returned **0** — the process was genuinely
alive. But `ps -p 79117 -o command=` showed `claude --dangerously-skip-permissions`: an **interactive
session**, not a `claude -p` worker. No `claude -p` existed in that lane's worktree at all.

This is the sharpest case in the list, because every rule agreed and the answer was still wrong. We
spent the evening replacing field-reads and `ps` patterns with "ask the kernel about the PID". Here
the kernel was asked, answered correctly, and the conclusion was false — because the wrong process
had been recorded. **Liveness is not "is this PID alive"; it is "is this PID a live worker for this
lane".**

Two further corruptions in the same row, both worth asserting against: its `worktree` field pointed
at the main repo rather than the lane worktree, and two different `session_id` rows carried the
**same** pid 79117 — one interactive session owning several lanes at once.

**Acceptance additions:**

1. A recorded PID belonging to an interactive session (or any process that is not this lane's
   worker) must report **not alive** for that lane. Pair the PID with its process kind, not only its
   start time — start time defends against reuse, kind defends against this.
2. A PID appearing as owner of more than one lane is a contradiction; the function must not report
   both lanes alive on it.

**Measurement trap in the same row:** `started_at` is stored in UTC while `pid_birth` is in LOCAL
time. Comparing them directly yields a process that appears to have been born after the lane it
owns started. Normalise before comparing, and never derive a liveness conclusion from that pair
without doing so.

### Fifteenth: a duplicate row makes release structurally impossible, and the counter hides it

Root cause of the fourteenth case, found by c2 at `leadv2-dispatch-code.sh:4555`. The ownership check
on the release path begins:

```python
rows = [rows with this task_id]
if len(rows) != 1:
    sys.exit(2)
```

The lane had **two** rows. That single condition is enough: the session/pid comparison below it is
never reached. So with duplicate rows, release is impossible **for anyone**, regardless of who owns
them. The climbing `starting:60` → `starting:163` counter was not a grace period slowly expiring — it
was a lane that never even attempted release, displaying elapsed time as if it were progress.

**Acceptance addition:** duplicate rows for one lane must be an **error in themselves**. Today they
silently convert a lane into a permanent one. A liveness function must not report a lane live on the
strength of rows it cannot even parse into a single owner; and a PID owning more than one lane is a
contradiction, not two live lanes.

**A counter that only counts up is not evidence of a process.** `starting:N` reads as "still coming
up", which is why three dispatch attempts were spent waiting for it. Any age display on a stuck path
should say what it is waiting for, not merely how long it has waited.

### Sixteenth: the unregister API silently targets the wrong repo

Also from c2, hit while fixing the above. `leadv2_active_unregister` without `LEADV2_PROJECT_ROOT`
resolves to persona-engine rather than the plugin repo. The first call **returned success**, rendered
an unrelated `LEAD_V2_STATE.md`, and removed nothing — the two rows were still there.

It was caught only because the result was checked rather than the exit code. This is the same shape
as the census probe that returned `0/821` from the wrong directory, and as reading a stale copy of a
status file: **a tool that misses its target reports success**. Any registry helper used in a fixture
must assert the post-state, never the return code.
