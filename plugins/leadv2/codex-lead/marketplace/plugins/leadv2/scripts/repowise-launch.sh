#!/bin/bash
# repowise-launch.sh — host-global launcher for the per-repo repowise MCP.
#
# A plugin is host-global, so a per-target-repo absolute path cannot be baked
# into .mcp.json (the fallback installer path writes exactly such a path into
# ~/.codex/config.toml). This launcher resolves the server at spawn time by
# walking $PWD upward; if no repo around the cwd has one, it exits 0 silently
# (an MCP server that starts and exits is preferable to a hard config error
# in every non-repowise session).
set -u

if [[ -n "${LEADV2_REPOWISE_MCP:-}" && -f "$LEADV2_REPOWISE_MCP" ]]; then
  exec bash "$LEADV2_REPOWISE_MCP" "$@"
fi

DIR="$PWD"
while [[ "$DIR" != "/" ]]; do
  if [[ -f "$DIR/.repowise/repowise-mcp.sh" ]]; then
    exec bash "$DIR/.repowise/repowise-mcp.sh" "$@"
  fi
  DIR="$(dirname "$DIR")"
done

exit 0
