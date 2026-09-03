# D3 — pre-brief evidence: death-proof and work-rescue must be ONE transition

Written 2026-09-03 from a live incident plus session 36's root-cause of D4. Carry into the D3 brief
as constraints, not context.

## The incident D3 exists to prevent

Five wave-3 lanes lost their workers at ~17:54:44Z when the parent Claude Code session exited. Each
had substantial work — 573, 464, 335, 189 and 143 insertions — sitting **uncommitted** in its
worktree. Nothing wrote a terminal record, nothing checkpointed, and the registry went on counting
all five as live. Two independent consequences followed, and D3 owns both:

1. A dead lane kept its slot in the lead-session lane cap and **refused its own resume**
   (`dispatch_refused reason=lead_session_lane_cap` for a lane with zero live processes).
2. The work survived only because a lead noticed and committed it by hand. The SessionStart sweeper
   deletes worktrees with no unmerged commits; another few minutes and roughly 1,700 lines were gone.

## Why no checkpoint fired — session 36's root cause, and it is the load-bearing fact

All three existing checkpoint mechanisms run **inside the dying process tree**:

- `leadv2_worker_commit_epilogue` — `lib/leadv2-worker-epilogue.sh:85`, five call sites, **no signal
  trap anywhere**;
- `pc_stop_gate_autocommit` — `leadv2-dispatch-product-close.sh:1909`, and additionally disables
  itself when `_PC_SCOPE_WRITES_CSV` is empty;
- the turn-limit safety net.

`SIGKILL` takes all three at once, and there is no outside actor — no cron, no daemon — to
checkpoint on their behalf. **The mechanism was not missing; it lived inside the thing that dies.**

## The constraint this puts on D3

"Prove the worker dead" and "rescue its work" must be **one transition, driven from outside the
lane's process tree** — never two independent steps, and never a step the dying process performs.

If the terminal record is written by the same process that is dying, D3 reproduces today's failure
exactly: a lane with a real diff gets stamped `no_work`, because the only actor that could have
noticed the diff is the one that just died. That is not a hypothetical — it is why the lead refused
to merge five lanes today. Their worktrees were clean and their commits non-empty, which reads as
"finished", and was in fact "killed mid-task, then rescued by hand".

Concretely, the funnel must:

1. Decide death from **outside**: the PID the dispatcher printed (`handle=PID=<pid>`) plus `kill -0`
   — never mtime, never a registry field, never a `ps` pattern. See
   `docs/handoff/D2-SINGLE-LIVENESS-VERDICT/brief-pre-evidence.md`; D3 must **consume D2's pinned
   function**, not grow its own second opinion. A lane is alive while any recorded PID is alive.
2. In the same transition, before writing anything terminal, **inspect the worktree** and commit
   whatever is uncommitted, marked plainly as a rescue — never reviewed, never tested, not
   mergeable as-is.
3. Only then write the terminal state, and it must distinguish **`died-with-work`** from
   **`no_work`**. Never write `no_work` for a lane whose worktree has a diff. Today's incident is
   the acceptance case.
4. Free the lane's cap slot at the same moment, so the lane can be resumed. A dead lane that blocks
   its own resume is the self-deadlock this whole funnel exists to end.

## Acceptance for D3's suite

- **`no_work` is never written over a real diff.** Fixture: kill a lane worker with `SIGKILL` (so no
  epilogue and no trap can run) while its worktree holds uncommitted changes; assert the funnel
  produces `died-with-work`, that a rescue commit exists carrying those changes, and that
  `git diff --diff-filter=D --name-only main...HEAD` — three dots — is empty.
- **The rescue is not performed by the dying process.** Assert it still happens under `SIGKILL`,
  which no trap survives; a suite that kills with `SIGTERM` proves nothing, because a trap could
  have caught it.
- **The cap slot is freed**: after the funnel runs, a resume of that same lane is accepted rather
  than refused with `lead_session_lane_cap`.
- **Mirror case**: a lane that genuinely finished with a clean tree and no diff still gets its
  ordinary terminal state, so the fix cannot degrade to "always rescue".

**Negative control:** the mutation goes INSIDE the funnel's body — make the terminal write happen
before the worktree inspection — and the suite must go red on the `died-with-work` case. Proof is
the `baseline_rc` / `mutated_rc` pair plus the literal red suite line; then revert and show green,
pasting both exit codes.

**Registration:** add the suite to `EXTRA_SUITE_MAP` in `tests/run-all.sh` and prove `--scope changed`
selects it. Of the 23 suites the plan assumed, the runner reaches 9; an unregistered suite rots
silently.

## Repo hygiene that applies to this brief itself

`.gitignore` ignores `docs/handoff/*/*` and allowlists only `report.md`, `brief*.md`, `round*-red`.
A file placed under `docs/handoff/<id>/` looks saved and is not: four wave-3 briefs lived on local
disk only until a lead noticed. Name artifacts `brief*.md`, use `git add -f`, and confirm with
`git ls-files` by eye.
