# Floor decomposition — BLOCKED on missing attribution

**Method.** I opened `~/.claude/burn/history.db` immutable and took the first
`turn_events` row per session; its prefix total is `cc + cr + input`. This is
the only token counter available. It records a total, not the serialized
system prompt, tool schemas, hook payloads, or their provenance. I did not
convert bytes to tokens.

| component | tokens | evidence / conclusion |
|---|---:|---|
| persona-engine recorded first prefix | 277,454 | `cc=277454`, reproduced |
| m3-market recorded first prefixes | 112,087; 416,198 | `cc=112085/416196`, plus input 2 |
| MCP schemas, by server/tool | unmeasurable | counter has no schema-level attribution; persona configuration is out of this arm's worktree |
| built-in tools | unmeasurable | same missing provenance |
| project/user CLAUDE.md, MEMORY.md | unmeasurable | totals cannot isolate injected text |
| skill frontmatter (47--64) | unmeasurable | only the whole prefix is metered; this checkout has 42 plugin skill directories, not a usable persona count |
| SessionStart output / residual system prompt | unmeasurable | 14 SessionStart hooks are registered here, but no emitted-token ledger exists |

**Classification.** Nothing is proven *removable*. Conditional: MCP schemas,
skill catalog, and nonessential hook/doc/memory injections should be loaded on
demand. `ENABLE_TOOL_SEARCH=auto:50` is enabled here; the existing worker
slim-MCP/dynamic-prompt probe reports a cache-creation delta approximately zero
(and explicitly refuses default-on below 10k), so it establishes no saving.
Irreducible: built-in tools plus minimal task/cwd/safety instructions; their
token count is likewise unmeasured.

**Decision.** No numeric achievable floor is defensible yet. The only safe
bound is that a proposed change must be measured as a paired first-turn
`cc+cr+input` delta with an identical repo/config, and must log the serialized
prefix by component. Cost: that instrumentation and real billed paired
spawns; breakage risk: deferred tools/skills/hooks can remove a capability
before it is requested. Do not remove MCPs on this evidence.

**Unsupported brief number (blocker):** the asserted m3-market floor of
**59,876** is not reproducible from the current immutable DB: its two m3 first
events are 112,087 and 416,198. Therefore the 217k comparison is not a natural
experiment: MCP count, project instructions, hooks, skills, and session
environment all vary, and no component allocation follows from it.
