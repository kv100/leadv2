# Falsification verdict: no-build survives; Astra's evidence does not

Reproduction used `file:/Users/kostiantyn.vlasenko/.claude/burn/history.db?mode=ro&immutable=1`. The six sessions remain 14,931 DB turns / 4,599,285,391 CR; the seven-day Opus row has moved to 28,327 turns / 8,613,159,226 CR. The raw JSONL-record census also reproduces 24,793 / 11,356 / 13,437 / 0, but attack 5 shows why it is invalid.

1. **Event list: false/incomplete.** The live plugin manifest has ten events, not four. Claude Code 2.1.268 and its [hook reference](https://code.claude.com/docs/en/hooks) enumerate 33: SessionStart, Setup, UserPromptSubmit, UserPromptExpansion, PreToolUse, PermissionRequest, PermissionDenied, PostToolUse, PostToolUseFailure, PostToolBatch, Notification, MessageDisplay, SubagentStart, SubagentStop, TaskCreated, TaskCompleted, Stop, StopFailure, TeammateIdle, InstructionsLoaded, ConfigChange, CwdChanged, DirectoryAdded, FileChanged, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, PreModelSwitch, PostModelSwitch, Elicitation, ElicitationResult, SessionEnd. MessageDisplay fires during streaming but is display-only; PostToolBatch is between model calls but can only halt the loop. Neither rewrites an API response.

2. **Already paid: true.** Transcript `fe5013...jsonl:120-123` records a denied Bash under one usage-bearing request, then a Write correction under a different usage-bearing request. Across the six sessions, 375 permission-rule denials led to 356 one-tool and 19 zero-tool next responses: zero batched corrections. “Same human turn” is not “same billed API response.”

3. **Arithmetic: Astra omitted it.** For a latent batch of `B`, deny plus corrective batch costs 2 responses instead of `B`; savings=`B-2`. Break-even is `B=2`; positive at `B>=3`. The corrected data reaches it: 1,338 singleton runs have length >=3 (maximum 156), but dependencies are unknown, so 9,198 is only an inadmissible upper bound, not verified savings.

4. **Stop: Astra's result holds.** Stop fires after the completed response. `decision:block` or `additionalContext` continues with another response; it does not replace transcript text already generated/billed. The existing prose guard returns universal `continue:false`, which stops processing entirely; it is not regeneration or suppression.

5. **Unchecked assertion: the census unit.** JSONL splits one API message across records sharing `message.id`/`requestId`. Aggregating by `message.id` yields exactly 14,931 messages: 1,572 zero-tool (10.5%), 13,285 one-tool, and 74 multi-tool (72x2, 2x4). Thus 45.8% text-only and 0% batching are false.

**Decision:** the deny/Stop hook direction is dead for build now: Stop cannot save prior responses, and 0/375 real denials batched. Re-measure by message ID before designing another mechanism.
