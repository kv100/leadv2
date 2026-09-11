# Measured by the lead, 2026-09-11 — the floor is our apparatus, not MCP

Paired probes, same repo (`persona-engine`), same model (haiku), same one-word prompt, same
`.mcp.json`. First-turn context = `cache_read + cache_creation + input` from the response's own
usage record, so cache warmth changes the price but not the count.

| run | first-turn context | how |
|---|---:|---|
| headless `claude -p`, `ENABLE_TOOL_SEARCH=auto:50` (repo default) | **56,422** | `--output-format json` |
| headless `claude -p`, `ENABLE_TOOL_SEARCH=` (unset) | **56,424** | identical otherwise |
| headless `claude -p`, MCP servers removed (`--strict-mcp-config --mcp-config '{"mcpServers":{}}'`) | **67,676** | identical otherwise |
| this interactive lead session (`b37e2cc6`, opus, 2,397 responses) | **157,216** | its own transcript |

## Three findings, and two of them contradict BRIEF-03

1. **Unsetting `ENABLE_TOOL_SEARCH` moved the floor by 2 tokens.** The predicted saving was
   ~10,000/turn from deferring MCP schemas. It is not there on this path. Either the schemas are
   already deferred at `auto:50`, or the repo `.claude/settings.json` `env` block overrides the
   process environment so the probe never changed the effective value. **Both are unresolved; the
   change must not be made on the strength of the 10k figure.**

2. **Removing every MCP server made the floor 11,266 tokens LARGER, not ~10k smaller.** The
   plausible mechanism is that tool-search deferral engages when the tool count is high and
   disengages when it is low, so a small tool set is loaded inline in full while a large one is
   replaced by a name list. If that is right, MCP servers are not additive at the floor and
   "drop the MCP servers" is exactly backwards. Unverified mechanism; the number is reproduced.

3. **The apparatus, not MCP, is the floor.** Same repo, same `.mcp.json`: headless 56,422 vs
   interactive 157,216 — a gap of **100,794 tokens** that is entirely hooks, skills, CLAUDE.md,
   MEMORY.md, and SessionStart/UserPromptSubmit injection, paid on every turn of every interactive
   session. That is 34% of the 297k average context, and 64% of a fresh session's context.

## Against the founder's condition

He offered 400k as the auto-compact threshold *if* session start is not 130-150k occupied. It is
**157,216** here — above his bar. Reaching 130k needs ~27k removed from the apparatus; the
headless 56k is the floor of what this client will do in this repo at all.

## What this retires

- "Unset `ENABLE_TOOL_SEARCH`, save ~10k/turn" — not supported. Do not ship it as a saving.
- "MCP schemas are ~10k of the floor" — not supported as a *removable* 10k; removing the servers
  costs 11k.
- The round-2 floor table's repo comparison (m3-market 59,876 vs persona-engine up to 277,454) was
  attributing to MCP a gap that this probe puts in the apparatus.
