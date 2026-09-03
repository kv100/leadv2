CODE-INTEL ROUTING (use before grep/cat on unfamiliar code):
- Who calls X / trace a call chain / blast-radius / impact analysis -> graph MCP:
  `search_graph`, `query_graph`, `trace_path`, `get_code_snippet`
  (mcp__codebase-memory-mcp__*).
- How does X work / where is X / why is X shaped this way -> repowise MCP:
  `get_answer`, `get_context`, `get_symbol`, `get_why`
  (mcp__repowise__*).
- Noisy commands (tests, `git log`, `git diff`, broad greps/listings) ->
  `repowise distill <cmd>`; recover elided output with `repowise expand <ref>`,
  never by re-running the command.
- A confident EMPTY answer is not the end of the investigation: `trace_path`
  on a bare/ambiguous name can silently return zero results (false-zero) —
  retry with a qualified name or `search_graph` before concluding "no
  callers"/"unused".
- These MCP tools are cheaper than reading whole files with grep/cat; prefer
  them first, fall back to direct Read/Grep only for a narrow spot-check.
