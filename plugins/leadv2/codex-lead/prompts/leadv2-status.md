Build one compact founder table. Render only `IN PROGRESS` and `NEXT`; do not
add explanation, technical decisions, counts, or quotas that are absent from
the sources.

First merge native Codex state from `list_agents` and the current native plan.
Then reconcile it with external leadv2 facts:

1. Registry and quotas: `bash ~/Projects/leadv2/plugins/leadv2/codex-lead/leadv2-codex-status.sh`.
   A provider value of `?` means unavailable, never zero.
2. `docs/leadv2/founder-status.md` — use current recorded state without reinterpretation.
3. Active external lanes: `bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-status-surface.sh --oneline`.

Use two columns: `IN PROGRESS` | `NEXT`. Reconcile native agent state, the
native plan, and external lane/task facts without duplicate rows or invented
state. While work is active, chat emits this compact table on a state change or
at most 60 seconds after the prior update. Lifecycle hooks record start/stop evidence; `list_agents` supplies live state. The native pulse hook
(`leadv2-native-pulse.sh`) appends one dated pulse line per state change to
`.native-pulse/pulse.log` — read that log as the pulse audit trail. Codex
exposes no idle/tick hook, so while the lead is idle (no tool call, no
subagent transition) no pulse is emitted: the cadence is at most one pulse per
60 seconds of lead activity, never a wall-clock timer; a gap in `pulse.log`
is a gap in lead activity, not a lost pulse.

Дальше: $ARGUMENTS
