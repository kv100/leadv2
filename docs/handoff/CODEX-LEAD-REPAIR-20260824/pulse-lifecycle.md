# CODEX-LEAD-PULSE-LIFECYCLE-01

Implement the missing Codex lifecycle/pulse contract in the marketplace plugin.

Premise (re-prove from the current tree and current Codex hooks documentation):
- The installed Codex plugin currently bundles only a `PreToolUse` hook.
- The full leadv2 implementation already has pulse/status mechanisms, but the Codex adaptation did not wire them into Codex lifecycle events.
- Codex supports plugin-bundled `SessionStart`, `PostToolUse`, and `Stop` command hooks. A hook is event-driven, not a wall-clock timer.
- A previous lane called PULSE-WAKE-01 has no live process or task evidence. Do not assume it delivered anything.

Required behavior:
1. Add a Codex-native lifecycle hook script and register only the lifecycle events actually needed.
2. Activate the behavior only for a real leadv2 root-lead session/repository; the globally enabled plugin must not trap unrelated Codex chats.
3. While the leadv2 root session has live lanes, a `Stop` event must prevent silent abandonment and return a bounded continuation instruction that makes the lead supervise in the foreground. Avoid a tight continuation loop.
4. When the 30-minute founder beat is due, reuse the canonical leadv2 pulse/status scripts and return compact model-visible context so the lead surfaces the status in chat. Do not invent a second status implementation or numbers.
5. On inactive/no-lane sessions, exit cleanly without continuing the turn.
6. Handle missing scripts/state, malformed hook JSON, and non-leadv2 cwd safely and observably.
7. Add behavioral tests for activation, inactive sessions, due pulse, not-due pulse, live-lane Stop continuation, no-live-lane Stop, and malformed input.
8. Keep output small enough for hook context and document the honest boundary: no Codex lifecycle hook can create a model chat message while no turn/event exists.

Non-goals:
- Do not change router policy, worker model selection, marketplace metadata, or the existing shell deny rules.
- Do not hand-edit installed cache under `~/.codex/plugins/cache`.

acceptance:
  surface: rendered_line
  observable: An active Codex root-lead session with a due beat shows one compact canonical founder status and cannot silently finish while a worker lane remains live; an unrelated Codex session is unaffected.
  authored_at: 2026-08-24T18:25:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks.json,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-pulse-hook.sh,plugins/leadv2/codex-lead/tests/test-codex-pulse-hook.sh
