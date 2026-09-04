verdict: APPROVE
next_action: continue

Pulse becomes an event-driven hook on Codex's only live events (PreToolUse + SubagentStart/Stop), emitting on state-change or 60s-since-last — no fabricated timer.

- New `leadv2-native-pulse.sh`; `pulse.log` always, chat injection only if a step-0 live probe proves Codex renders hook context.
- Idle boundary documented: cadence bounds lead *activity*, not wall clock.
- Hermetic tests + manifest cache-bust; no Claude-side or app changes.

Full: full.md
