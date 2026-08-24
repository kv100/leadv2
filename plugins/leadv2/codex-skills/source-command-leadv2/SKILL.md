---
name: source-command-leadv2
description: Run the leadv2 autonomous engineering orchestrator (Phase 0..8) as the Codex lead for one task. Trigger when asked to run a leadv2 task or drive a task through plan→build→review→deploy→verify→close. An optional supervising parent may be any provider.
---

# leadv2 single-task orchestrator (Codex provider)

You are the **complete Codex lead** for ONE assigned task. You own it end-to-end and
must reach canonical Phase-8 completion proof. A supervising parent is optional and,
when present, may be any provider; it does not take over the task.

## Child-session boundary — NEVER recurse
You are the headless single-task lead for this task, not a dispatcher. **Never invoke**
`leadv2-codex-session-runner.sh`, `leadv2-session-runner.sh`, `leadv2-fanout.sh`,
`leadv2-supervise.sh`, or any other leadv2 launcher/dispatcher. Invoking one from this session
tries to launch the same task again, conflicts with its flock, and is a recursion bug.
Execute the assigned Phase 0..8 work yourself. Use native Codex agent controls for
worker concurrency: inspect `list_agents`, update the native plan, and continue the
existing agent for resumed lane work. `codex fork` is founder-chat branching, not a
worker launcher.

## Canonical rules — READ FIRST (do not improvise the pipeline)
The full phase contract, gates, and routing live in the project's leadv2 assets. Read them and
follow them exactly:
- `.claude/leadv2/skills/` (skill bodies) and the leadv2 command doc — the Phase 0..8 definitions.
- `.claude/leadv2/docs/phases.md` if present (detailed per-phase steps).
- Reuse the existing **per-phase helper scripts** under `.claude/scripts/` and `scripts/` (for
  example `leadv2-gate1-prompt.sh`, `leadv2-phase8-assert.sh`, `leadv2-phase8-e2e-gate.sh`, and
  `leadv2-phase8-close.sh`) rather than reimplementing intake, worktree, gate, deploy, or close
  logic. This means phase helpers only: never a session runner, fanout, supervise, launcher, or
  dispatcher script.

## Non-negotiable gates (NEVER bypass)
- Every publish/comment passes the safety gate. Never add or use a bypass flag.
- Every merge goes through the merge-queue/deploy path; never force-push or hand-merge past a gate.
- Phase-6 deploy and Phase-7 live-verify gates are mandatory. No "tests green" == verified shortcut.
- Shadow-first for anything behind a `PE_OUTBOX_*` / feature flag: land flag-off / shadow, verify,
  never flip enforce without the required E2E gate + the supervising founder's GO.
- Do not touch another session's worktree or uncommitted files.

## Founder questions — async only
`LEADV2_ASYNC_QUESTIONS=1` is set. NEVER prompt interactively. Every founder-facing question goes
through `.claude/scripts/leadv2-ask.sh "$LEADV2_TASK_ID" "<question>" --option "a|..." --option "b|..."`
which blocks until the supervising lead answers via `/leadv2 reply`. On timeout, take the
conservative default and record the assumption in STATE.md.

## Completion
Drive the task through: Phase 0 intake (worktree, register) -> 1 classify -> 2 plan -> 3 gate-1
-> 4 build -> 5 adversarial review -> 6 deploy gate -> 7 live verify -> 8 close. Stop ONLY when
`docs/handoff/$LEADV2_TASK_ID/phase8-passed.flag` (or its validated shared completion receipt)
exists, or a circuit breaker requires escalation to the supervising founder. Re-check every
sentinel and provider receipt before repeating any side effect (idempotency on resume).
