# D3 — terminal funnel with death proof

**Read the full brief in the repo, do not work from this file alone:**

- `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/brief.md` — the design.
- `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/brief-pre-evidence.md` — the incidents this
  exists to prevent, the acceptance cases, and two sections added after the last worker died. Read
  the last two sections first; they change the fixtures.
- `docs/handoff/D2-SINGLE-LIVENESS-VERDICT/brief-pre-evidence.md` — the liveness verdict you must
  consume. Thirteen documented false answers.

Both files are committed. A previous mission put all of this inline and the worker died three times
before committing anything; a brief in the repo survives a death, a mission in the arguments does not.

## Work already on this lane — continue from it, do not start over

Commit `577283e8` carries **382 rescued lines** in `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`
from a worker that died before committing. Read that diff first.

## What this lane must deliver, in one sentence

"Prove the worker dead" and "rescue its work" must be **one transition, driven from outside the
lane's own process tree** — never two steps, and never a step the dying process performs.

## Acceptance — the four fixtures

1. **`no_work` is never written over a real diff.** `SIGKILL` a worker (so no trap or epilogue can
   run) while its worktree holds uncommitted changes; assert `died-with-work`, a rescue commit
   carrying those changes, and that `git diff --diff-filter=D --name-only main...HEAD` — three dots
   — is empty. `SIGTERM` proves nothing here, because a trap could have caught it.
2. **Zero non-anchor commits plus a dirty tree** must also report `died-with-work`. This is the
   poorer case that actually happened, three times today, and fixture 1 does not exercise it. The
   worktree sweeper must treat such a lane as undeletable — "has unmerged commits" is itself a false
   zero, and it lives in the code that deletes.
3. **The cap slot is freed**: after the funnel runs, a resume of that lane is accepted rather than
   refused with `lead_session_lane_cap`.
4. **Mirror case**: a lane that genuinely finished, clean tree and no diff, still gets its ordinary
   terminal state — the fix must not degrade to "always rescue".

**Blocking:** D3 consumes D2's pinned liveness function. If this diff computes liveness anywhere
itself — a `ps` pattern, a PID walk, an mtime check, however small the helper — it fails review. Two
verdicts about liveness is the bug we are here to end.

## Negative control

Mutation goes **inside the funnel's body**: make the terminal write happen before the worktree
inspection. The suite must go red on the `died-with-work` case. Report the `baseline_rc` /
`mutated_rc` pair and the literal red line, then revert and show green with both exit codes. Never at
file top level — that reddens everything for the wrong reason and reads as a pass. Never `diff_hash`
as proof of a run.

Register the suite in `EXTRA_SUITE_MAP` in `tests/run-all.sh` and prove `--scope changed` selects it;
**append only**, two other lanes are editing that file. An unregistered suite rots silently.

## Commit immediately and often

Between a lane's start and its first commit it is indistinguishable from a lane that did nothing, and
the sweeper deletes lanes with no unmerged commits. Three lanes lost work in that window today, this
one among them. Make your first commit as soon as anything coherent exists, even partial.

Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session. Nothing goes
into `tests/known-red-suites.txt`; no assertion is weakened to reach green.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6134df79" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.