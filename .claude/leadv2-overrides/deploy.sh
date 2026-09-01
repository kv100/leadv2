#!/usr/bin/env bash
# .claude/leadv2-overrides/deploy.sh — leadv2 plugin repo (its own deploy).
# LEADV2-HOOK-CACHE-DEPLOY-01: the plugin repo's "deploy" IS the hook cache —
# Claude Code loads hooks from ~/.claude/plugins/cache/leadv2-local/leadv2/
# <ver>/ (a copy), and `claude plugin update` no-ops for a directory-source
# marketplace when the version string did not change. So after every land,
# refresh that copy; hooks/commands/agents go live on the NEXT session.
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
SYNC="${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh"
if [[ ! -f "${SYNC}" ]]; then
  echo "BLOCK: ${SYNC} not found — deploy cannot refresh the plugin cache" >&2
  exit 1
fi

LEADV2_PLUGIN_SRC="${PROJECT_ROOT}/plugins/leadv2" bash "${SYNC}"

echo "NOTE: plugin hooks/commands/agents load from the cache on the NEXT session — restart claude to pick up this deploy."
