# R2 — compaction/context-editing research

For an interactive Claude Code session, launch it from a shell containing:

```sh
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=82
claude
```

The [environment-variable reference](https://code.claude.com/docs/en/env-vars) defines
the first as the token capacity used for compaction (default 200K/1M, capped by the
model window), and the second as a 1–100 percentage of that capacity (default about
95%; higher values do not help). It states no minimum version. Crucially, [issue
#63186](https://github.com/anthropics/claude-code/issues/63186) reproduces that a
`settings.json` `env` entry reaches subprocesses but is ignored by the interactive
app's compaction logic. Use the launching shell/launcher; do not rely on project
settings. This is version-sensitive: [#82761](https://github.com/anthropics/claude-code/issues/82761)
reports a later regression even with the process variable set.

No primary Claude Code source documents a `--autocompact <auto|tokens>` CLI flag or
its precedence. The [commands reference](https://code.claude.com/docs/en/commands)
documents `/compact`; [#78318](https://github.com/anthropics/claude-code/issues/78318)
documents `/autocompact auto` (a slash command), not that flag. Treat the requested
flag and “microcompact” as unverified/uncontrollable. `/rewind` truncates to a prior
cached prefix, while `/compact` summarizes and rebuilds a shorter cache; `/clear` or
a fresh session starts empty. Therefore adopt `/rewind`, use `/compact` at natural
boundaries, and use `/clear` between unrelated tasks. Source: [Claude Code caching
docs](https://code.claude.com/docs/en/prompt-caching).

Server-side `clear_tool_uses_20250919` and `clear_thinking_20251015` are API beta
strategies requiring `context-management-2025-06-27`; the [platform documentation](https://platform.claude.com/docs/en/build-with-claude/context-editing)
shows `client.beta.messages.create` and says editing occurs server-side. [#44521](https://github.com/anthropics/claude-code/issues/44521)
is a feature request, not support evidence. Answer: **no supported Claude Code use
today**; a binary `USE_API_CONTEXT_MANAGEMENT` string does not establish wiring.

Tool clearing invalidates the cached prefix; the platform doc recommends
`clear_at_least`. [Pricing](https://platform.claude.com/docs/en/about-claude/pricing)
sets 5-minute cache writes at 1.25× and reads at 0.1× base input. If N cleared tokens
force an N-token rewrite, break-even after R reads is 1.25N ≤ 0.1NR: R ≥ 12.5,
i.e. 13 whole reads within TTL. Otherwise clearing loses money. The separate bill for
the compaction summarisation call is not publicly exposed; docs only say it reads the
existing cache.

450K is not a meaningful step: 467,627 → 450,000 is 3.77%, while the 146,092 floor
and 1,343-token/response growth put it inside noise. The measured candidate that
actually changes the sawtooth is ~164K; reject 450K absent an A/B proof. Disposition:
shell overrides **trial**; settings `env`, CLI flag, microcompact **reject**; API
editing **trial only in a direct API client**; `/rewind`, selective `/compact`, and
between-task `/clear` **adopt**. Numeric community observations: #34332 ~76K on 1M,
#53801 ~195K, #64773 reached 72% despite a 60% setting—useful warnings, not guarantees.
