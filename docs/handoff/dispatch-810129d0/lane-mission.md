Product implementation task dispatch-810129d0. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# FORK-RUNS-A-SESSION-01 — architect prepass

Scoped implementation design. No code written here.

## 1. What was verified (not assumed)

| Claim in the mission | Verified state | Source |
|---|---|---|
| Fork is used only for fragments | True. Fork is documented as a context-inheriting spawn for "plan synthesis, judging a fork, a fix-round" — a *step*, never a session. | `plugins/leadv2/commands/leadv2.md:147-160` |
| Phase 3 Gate 1 needs the founder | Already solved for headless lanes. `leadv2-ask.sh` writes the question to the **control plane** `questions/` dir (resolved by `leadv2-state-path.sh`, outside any worktree) and blocks until `leadv2-answer.sh` / `/leadv2 reply`. It also has a `--no-block` mode. | `leadv2-ask.sh` header + `:131` |
| Phase 6 deploy calls `ExitWorktree`, lead-only | True, and the *reason* is specific: delegating `ExitWorktree`/`git worktree remove` to a subagent spawns hooks against a deleted CWD → `ENOENT: posix_spawn '/bin/sh'`. It is a CWD-lifecycle ban, not a privilege ban. | `commands/leadv2.md:213`, `docs/phases.md:344` |
| Phase 8 close writes shared state a concurrent lead also writes | True, and already mitigated for N parallel lanes: `leadv2-state-atomic-write.sh`, `leadv2-active-registry.sh`, `leadv2-tasks-clobber-guard.sh`, `active.yaml.lock`, `.merge.lock`. | script inventory |
| A worktree lane *requires* the `EnterWorktree` tool | **False, and this is the design's hinge.** `leadv2-lane-worktree.sh` exists precisely because headless children never reliably call `EnterWorktree` (SD-LANES-HAVE-NO-WORKTREE-01). It creates the identical path/branch (`.claude/worktrees/<id>`, `worktree-<id>`), and `leadv2-deploy-merge.sh` already resolves `worktree-<id>` for landing. | `leadv2-lane-worktree.sh:14-37` |

## 2. The honest boundary

A fork can own **Phases 0–8**, with **three carve-outs handed back to the lead**. It cannot own them by imitating the lead; it owns them by taking the *bash* path that already exists for headless lanes.

| Phase | Fork owns? | Why / mechanism |
|---|---|---|
| 0 Intake | Yes, minus worktree entry | Lane created by `leadv2-lane-worktree.sh ensure` (bash). **Carve-out A.** |
| 1 Classify | Yes | Pure reasoning over inherited context — the fork's strongest case. |
| 2 Plan | Yes | Spawns its own role agents; Codex/GLM arms are external processes and were never forkable anyway. |
| 3 Gate 1 | Yes, asks — founder answers through the lead's surface | `leadv2-ask.sh --no-block` + bounded poll. Question lands in control-plane `questions/`, already rendered by `/leadv2 questions` and the status surface. No new founder surface. |
| 4 Build | Yes | Absolute paths under the lane root. |
| 5 Review | Yes | Unchanged gates. |
| 6 Deploy | Yes | Commit inside the lane, land via `leadv2-deploy-merge.sh` (rebase + FF-only + push). **The fork never entered a tool worktree, so there is nothing to `ExitWorktree` from.** The ban is honoured by disjointness, not by exception. |
| 7 Verify | Yes | `verify-probe.sh` against the live signal. |
| 8 Close | Writes yes; reaping and daemon-spawn no | All Phase-8 writes go through the same locked scripts N parallel lanes already use. `leadv2-worktree-cleanup.sh` (**carve-out B**) and `leadv2-self-spawn.sh` (**carve-out C**) stay with the lead. |

**Carve-outs, stated for the report:**
- **A — worktree lifecycle.** A fork never calls `EnterWorktree`, `ExitWorktree`, or `cd`. It shares the session's CWD with the lead; changing it would move the lead. Lane creation is the lead's preflight; the fork addresses every file by absolute path.
- **B — worktree reaping.** Removing a directory while the parent session may hold a path under it is the same ENOENT class the `ExitWorktree` ban guards. Lead-only, in postflight.
- **C — daemon self-spawn.** A fork spawning the next session would spawn it inside the lead's session. Lead-only.

Everything else the fork owns outright. Nothing is skipped: no gate is relaxed, no review bypassed.

## 3. Files (exact)

| File | Change | Notes |
|---|---|---|
| `plugins/leadv2/scripts/leadv2-fork-session.sh` | **create** | Three ops: `preflight <task-id>` (ensure lane, register `active.yaml`, write `<handoff>/<id>/fork-lane.env` with `LANE_ROOT`/`CONTROL_PLANE`/`TASK_ID`, print lane root); `ask <task-id> "<q>" [--option "l\|d"]…` (wraps `leadv2-ask.sh --no-block` + poll loop capped at 540 s, exit 0 = answered/prints label, exit 3 = still pending so the fork re-invokes — keeps every Bash call under the 600 s tool ceiling); `postflight <task-id>` (worktree cleanup + optional self-spawn — carve-outs B and C). |
| `plugins/leadv2/prompts/fork-session-mission.md` | **create** | The fork's mission template: phase sequence, absolute-path rule, the never-call list (`EnterWorktree`, `ExitWorktree`, `cd`, `leadv2-worktree-cleanup.sh`, `leadv2-self-spawn.sh`, `reset --hard`, `clean`, `stash`), the `ask` protocol, deliverable path. |
| `plugins/leadv2/commands/leadv2.md` | **edit** | New short section "Fork-owned session (FORK-RUNS-A-SESSION-01)" after the Fork-spawns block at `:147`: the boundary table, the three carve-outs, preflight→spawn→postflight shape. Restate — do not weaken — the `:213` ban as "a fork never enters a tool worktree". |
| `plugins/leadv2/docs/phases.md` | **edit** | Phase 6 (`:344`) and Phase 0 (`:87`) each get one sentence: the bash-lane variant a fork-owned session takes, and why it satisfies the ban. |
| `plugins/leadv2/scripts/tests/test-fork-session.sh` | **create** | Covers: preflight idempotency; `fork-lane.env` contents; `ask` exit 3 on pending / exit 0 + label on answered; `postflight` refuses to reap a lane with uncommitted changes; every op is a no-op-safe re-run. |

Untouched by design: `leadv2-ask.sh`, `leadv2-answer.sh`, `leadv2-lane-worktree.sh`, `leadv2-deploy-merge.sh`, `leadv2-phase8-close.sh`, `leadv2-state-atomic-write.sh`. The whole point is that the fork path reuses them unmodified.

## 4. Data flow — one fork-owned task

1. Lead: `leadv2-fork-session.sh preflight <id>` → lane root + `fork-lane.env`.
2. Lead: `Agent(subagent_type="fork", run_in_background=true, prompt=<fork-session-mission.md with id + lane root>)`.
3. Fork: Phases 0–2 inside the lane, absolute paths only.
4. Fork: Phase 3 → `leadv2-fork-session.sh ask <id> …`; on exit 3, re-invokes; on exit 0, proceeds with the chosen label.
5. Fork: Phases 4–5 → build + review gates unchanged.
6. Fork: Phase 6 → commit in lane, `leadv2-deploy-merge.sh`.
7. Fork: Phase 7 → `verify-probe.sh`.
8. Fork: Phase 8 → locked state writes + `leadv2-phase8-close.sh`; stops at `phase8-passed.flag`.
9. Lead: `leadv2-fork-session.sh postflight <id>` → reap + optional self-spawn.

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Fork changes session CWD, moving the lead mid-task | Absolute paths only; `cd` on the never-call list; `preflight` prints an absolute lane root and the mission template forbids relative addressing. |
| `leadv2-ask.sh` default 900 s block exceeds the 600 s Bash tool cap → fork dies mid-Gate-1 | `ask` op uses `--no-block` + a 540 s bounded poll and exit 3 for "still pending". |
| Fork and a concurrent lead both write `active.yaml`/journals | Same locks as N parallel lanes (`active.yaml.lock`, clobber guard, atomic write). No new lock introduced; if the fork hits a lock it retries, it never bypasses. |
| `postflight` reaps a lane the fork left dirty | `postflight` refuses on uncommitted changes and exits non-zero, leaving the worktree on disk for inspection (mirrors Phase 6 circuit-break behaviour). |
| Fork cannot spawn `Agent` subagents (inherited-tool uncertainty) | Unverified in this prepass. Fallback already exists: `claude-subsession.sh` / `leadv2-dispatch-code.sh` as external processes. Implementation must probe this on the real pass and record the answer in the report. |
| Fork costs lead-model tokens (forks ignore `model=`) | Documented, not fixed: a fork-owned session is an Opus-cost session. Mechanical sub-steps still route to fresh haiku/sonnet agents. |
| The report claims phases it did not actually run | The one real pass is the gate; a phase with no artifact is reported as handed back, not as owned. |

## 6. Non-goals

- No framework, no generalised "fork orchestrator", no new phase.
- No change to `leadv2-ask.sh`, `leadv2-answer.sh`, `leadv2-deploy-merge.sh`, `leadv2-lane-worktree.sh`, or any gate script.
- No relaxation of the `ExitWorktree` delegation ban, the review gate, or the shared-tree `reset --hard`/`clean`/`stash` prohibition.
- No touching `docs/leadv2/open-threads.md`.
- No new founder-facing surface — Gate 1 reuses the existing control-plane `questions/` channel.
- No provider work: Codex/GLM/Kimi runners are out of scope; forks are Claude-only by construction.
- No retrofit of existing closed tasks.

## 7. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/handoff/FORK-RUNS-A-SESSION-01/report.md exists and its first table
      lists every phase 0 through 8 with either "fork" or "lead" in the owner
      column, and a one-line reason for each "lead" row.
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: >
      For the one real pass, docs/handoff/<pass-task-id>/ contains the
      plan/build/review deliverables the fork produced, and the report names
      that task id.
    authored_at: 2026-08-16T00:00:00Z
  - surface: log_line
    observable: >
      The pass task's journal at docs/leadv2/tasks/<pass-task-id>/journal.md
      shows phase entries running from Phase 0 through the last phase the fork
      owned, in order, with no gap where a phase was skipped.
    authored_at: 2026-08-16T00:00:00Z
  - surface: rendered_line
    observable: >
      During the pass, the Gate-1 question raised by the fork appears in the
      founder's `/leadv2 questions` listing as a pending question for the pass
      task, and disappears from that listing once answered.
    authored_at: 2026-08-16T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-fork-session.sh, plugins/leadv2/scripts/tests/test-fork-session.sh, plugins/leadv2/prompts/fork-session-mission.md, plugins/leadv2/commands/leadv2.md, plugins/leadv2/docs/phases.md

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — FORK-RUNS-A-SESSION-01: a fork should be able to run a whole `/leadv2` session, Phase 0→8

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`. Track 5.4, **founder-ordered**, never
advanced.

Today a fork is used for fragments — a review, a judgement, a synthesis — and the lead stays the only
thing that can carry a task from intake to close. That makes the founder's attention the scarce
resource: every session needs a lead in the loop, and when the lead's context fills, the work stops.
The order is that a fork should be able to run the whole thing: Phase 0 intake through Phase 8 close,
inheriting the session's context rather than starting cold.

## Establish the honest boundary first

Before building, determine and state which phases a fork **can** own today and which it cannot,
with the reason for each. Likely obstacles, to confirm rather than assume:

- Phase 3 Gate 1 wants founder input — how does a fork ask, and who sees the question?
- Phase 6 deploy calls `ExitWorktree`, which the lead is required to call directly.
- Phase 8 close writes shared state (`active.yaml`, board, journals) that a concurrent lead also writes.

A design that pretends these do not exist will fail at exactly the moment it is trusted.

## Then build the smallest real thing

Not a framework: the narrowest path by which a fork carries one task end to end, with the phases it
cannot own explicitly delegated back and **named in the report**. If the honest answer is that a fork
can own Phases 0–5 and must hand back at deploy, that is a real and useful result — say so plainly
rather than faking the last three phases.

## How to prove it

Run one task through it. Not a description of how it would work — an actual pass, with the artifacts
it produced. A design document alone does not close this.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Do not weaken any gate to make the fork's path shorter. A fork that skips review is worse than no
  fork.

## Deliverable
The implementation, the one real pass with its artifacts, and
`docs/handoff/FORK-RUNS-A-SESSION-01/report.md` naming which phases a fork owns, which it hands back,
and why. End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-810129d0" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.