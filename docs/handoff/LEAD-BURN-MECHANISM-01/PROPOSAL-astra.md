# LEAD-BURN-MECHANISM-01 — astra proposal

## Blocked: the requested hook-only ranking has no nonzero, supportable result

I reproduced the six-session transcript census exactly: 24,793 assistant messages; 11,356 zero-tool messages; 13,437 one-tool messages; 0 multi-tool messages; 13,437 calls. The matching DB rows still total 14,931 turns and 4,599,285,391 CR. Boundary: those are different counters.

The live `hooks.json` supplies `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, and `Stop`; it supplies no pre-assistant-message event. `PreToolUse` receives a tool only after the model has emitted the one-tool assistant message. A denial therefore cannot batch that already-paid turn; it creates a corrective turn. `Stop` can read the transcript (`leadv2-lead-prose-guard.sh` does), but also fires after the text is generated. Neither can remove any of the 11,356 or 13,437 observed turns.

## Candidate mechanisms (all zero verified removals on current surfaces)

1. **Notification digest at the producer — 0 verified; 693 upper bound.** `UserPromptSubmit` exists, and `leadv2-idle-notification-filter.sh` already denies content-free idle notices before model submission. Its own source records that the InboxPoller requeues the denied item, so it currently removes zero. The implementable mechanism must be the InboxPoller/notification producer writing a digest and emitting only critical failures. That producer surface is not in `plugins/leadv2`; proposing a hook edit would be false. Failure mode: digesting a failure/decision strands work; fail open for any non-idle payload.

2. **Multi-tool emission gate — 0 verified; 6,718 mathematical ceiling.** Pairing all 13,437 calls would reduce messages to 6,719, but the census contains no independence or dependency labels. A `PreToolUse:.*` N-streak denial would misfire on serial commands and pay an extra corrective turn. No hook can turn the already-emitted first call into a parallel sibling.

3. **Text-only suppressor — 0 verified; 11,356 unreachable.** `Stop` sees the text only after generation; no listed event sees it before generation. A Stop retry can only add work. This needs a runtime/model-emitter control, not a plugin hook.

## Falsification artifact

`sqlite3 'file:/Users/kostiantyn.vlasenko/.claude/burn/history.db?mode=ro&immutable=1' '.tables'` returned the live tables. The brief's overall Opus row has moved: **28,246** turns and **8,582,770,142 CR** (not 28,198 / 8,567M). Do not approve a build until the prompt is expanded to permit the notification producer or model-emitter surface; otherwise a nonzero turns-removed claim would be invented.
