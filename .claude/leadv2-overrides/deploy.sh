#!/usr/bin/env bash
# .claude/leadv2-overrides/deploy.sh — leadv2 plugin repo (its own deploy).
# LEADV2-HOOK-CACHE-DEPLOY-01, round 2. The plugin repo's "deploy" IS a plugin
# cache refresh, because Claude Code resolves the plugin through
# installed_plugins.json installPath (a versioned COPY), and
# `claude plugin update leadv2@leadv2-local` no-ops when plugin.json's version
# string is unchanged. Measured 2026-09-02 (round-2 probes, full trail in
# leadv2-plugin-cache-sync.sh header):
#   evidence: repo hooks.json marked "PROBE-UPDATE" with version left at 0.5.7,
#     `claude plugin update leadv2@leadv2-local` → "✔ leadv2 is already at the
#     latest version (0.5.7)"; cache hooks/hooks.json sha256 9b9abf5c…923 and
#     mtime 1788303608 identical before/after; `grep -c PROBE-UPDATE` in the
#     cache → 0 (the edit was never copied).
#   evidence: with installPath=~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0
#     recorded while the tree had moved on, the update command still reported
#     0.5.7 latest and touched nothing — the no-op does not heal stale copies.
# Live-from-repo, needs NO sync: hook/command/agent script BODIES — settings
# overrides CLAUDE_PLUGIN_ROOT to ~/.claude/plugins/local/leadv2/plugins/leadv2,
# which readlink resolves to this repo's plugins/leadv2 (evidence: probe hook
# printed origin=$0 = the plugins/local/… path and fired from the repo file,
# 2026-09-02). Needs sync: everything Claude Code reads OUT of the cache copy —
# at minimum hooks/hooks.json (the hook LIST: events, matchers, command
# strings) and .claude-plugin/plugin.json (identity). UNVERIFIED by direct
# probe (would require mutating the live cache): that the hook list is parsed
# only from the cache copy — consistent with all artifacts above, and the
# round-1 defect (a landed hooks.json change invisible until restart-with-copy)
# is only explicable if it is.
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
SYNC="${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh"
if [[ ! -f "${SYNC}" ]]; then
  echo "BLOCK: ${SYNC} not found — deploy cannot refresh the plugin cache" >&2
  exit 1
fi

LEADV2_PLUGIN_SRC="${PROJECT_ROOT}/plugins/leadv2" bash "${SYNC}"

echo "NOTE: the hook LIST (hooks.json) loads from the cache on the NEXT session — restart claude to pick up this deploy."
