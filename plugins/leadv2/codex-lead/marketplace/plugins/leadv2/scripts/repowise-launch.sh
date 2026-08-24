#!/bin/bash
# repowise-launch.sh — host-global launcher for the per-repo repowise MCP.
#
# A plugin is host-global, so a per-target-repo absolute path cannot be baked
# into .mcp.json (the fallback installer path writes exactly such a path into
# ~/.codex/config.toml). This launcher resolves the server at spawn time by
# walking $PWD upward; if no repo around the cwd has one, it prints one stderr
# line naming the start directory and exits 0 (an MCP server that starts and
# exits is preferable to a hard config error in every non-repowise session,
# but the absence is no longer silent).
set -u

if [[ -n "${LEADV2_REPOWISE_MCP:-}" ]]; then
  if [[ -f "$LEADV2_REPOWISE_MCP" ]]; then
    exec bash "$LEADV2_REPOWISE_MCP" "$@"
  fi
  # H6/M3 (MERGED-BATCH-FIXROUND-01): an override that cannot be honoured
  # must be audible, not silently ignored in favour of the walk.
  printf '[repowise-launch] LEADV2_REPOWISE_MCP=%s is not a readable file — override ignored, falling back to the $PWD walk\n' "$LEADV2_REPOWISE_MCP" >&2
fi

START_DIR="$PWD"
DIR="$PWD"
while [[ "$DIR" != "/" ]]; do
  if [[ -f "$DIR/.repowise/repowise-mcp.sh" ]]; then
    exec bash "$DIR/.repowise/repowise-mcp.sh" "$@"
  fi
  DIR="$(dirname "$DIR")"
done

# H6/M3 (MERGED-BATCH-FIXROUND-01): a silent exit-0 made repowise absent for
# the whole session with no message anywhere. Name the start directory so the
# next session makes the actual resolution observable.
printf '[repowise-launch] no .repowise/repowise-mcp.sh found walking up from %s — repowise MCP unavailable for this session\n' "$START_DIR" >&2
exit 0
