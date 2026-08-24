---
name: leadv2
description: Run the Codex-native lead control plane while the external dispatcher owns write workers.
---

## Usage

The user's request text that follows the skill invocation is the task brief.

## Mandatory root gates

Read `~/Projects/persona-engine/.claude/ref/90-codex-lead-pilot.md` completely before acting, quote one line as bootstrap confirmation, then read the tails of `docs/leadv2/open-threads.md` and `docs/leadv2/founder-status.md`.

Run every side-effecting shell command through `bash ~/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh -c '<command>'`. Dispatch Claude/GLM write workers only through that guard and `~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh`; use `leadv2-review-run.sh` for review, `/leadv2-status` for compact status, and `/leadv2-close` only with its evidence gate complete.

Founder chat is Russian; documents are English.

## Native control plane

Use native `spawn_agent(fork_turns)`, `followup_task`, `send_message`, `wait_agent`, `interrupt_agent`, `list_agents`, and `update_plan` with their real typed schemas. `codex fork` branches founder chat; it is not worker dispatch.

The external dispatcher/worktrees are the only write-worker and Claude/GLM path. Native agents are bounded read-heavy exploration, triage, or independent review unless a project explicitly permits shared writes. Default isolated agents to `fork_turns: none`; use `all` only when founder context is required.

## Capacity and founder updates

Set capacity from available native slots, provider health, dependencies, and write-set collisions—not fixed WIP=1. Independent read work may overlap; conflicting writes stay serialized through the external dispatcher.

Keep founder messages token-efficient:

IN PROGRESS: active lane, constraint, evidence.

NEXT: immediate action or blocker.
