---
name: leadv2
description: Run the Codex-native lead control plane while the external dispatcher owns write workers.
---

## Usage

## Native control plane

Use native `spawn_agent(fork_turns)`, `followup_task`, `send_message`, `wait_agent`, `interrupt_agent`, and `list_agents`. `codex fork` branches founder chat; it is not worker dispatch.

The external dispatcher/worktrees are the only write-worker and Claude/GLM path. Native agents are bounded read-heavy exploration, triage, or independent review unless a project explicitly permits shared writes. Default isolated agents to `fork_turns: none`; use `all` only when founder context is required.

## Capacity and founder updates

Set capacity from available native slots, provider health, dependencies, and write-set collisions—not fixed WIP=1. Independent read work may overlap; conflicting writes stay serialized through the external dispatcher.

Keep founder messages token-efficient:

IN PROGRESS: active lane, constraint, evidence.

NEXT: immediate action or blocker.
