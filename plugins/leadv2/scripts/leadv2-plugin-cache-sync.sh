#!/usr/bin/env bash
# leadv2-plugin-cache-sync.sh — LEADV2-HOOK-CACHE-DEPLOY-01.
#
# Claude Code does NOT load hooks/commands/agents from this repo: it loads
# them from the versioned plugin cache (~/.claude/plugins/cache/leadv2-local/
# leadv2/<ver>/ — a real COPY), and `claude plugin update` no-ops for a
# directory-source marketplace when the version string did not change. A fix
# that lands on main therefore stays un-live until the cache copy is
# refreshed by hand. This script makes that refresh mechanical: it finds the
# ACTIVE cache dir, rsyncs the repo's plugins/leadv2 tree into it with
# --delete, records the repo HEAD in <cache>/.synced-from, and prints one
# grep-able line: `synced=<n> cache=<path> repo_head=<sha>`.
#
# Active cache-dir resolution, in order:
#   1. <plugins-meta>/installed_plugins.json — the leadv2@* entry's
#      installPath. AUTHORITATIVE: this is the path Claude Code actually
#      loads from (it wins even when other version dirs exist).
#   2. Fallback: the highest version dir under
#      <cache-root>/leadv2-local/leadv2/ (numeric-aware: 0.10.0 > 0.9.0).
#
# Env (for tests / non-default installs):
#   LEADV2_PLUGIN_CACHE_ROOT  cache root (default ~/.claude/plugins/cache)
#   LEADV2_PLUGIN_SRC         source tree (default <git-toplevel-of-$0>/plugins/leadv2)
#   LEADV2_PLUGIN_META        installed_plugins.json path
#                             (default <dirname cache-root>/installed_plugins.json)
#
# CACHE-REFUSAL mirrors leadv2-plugin-sync.sh (PLUGIN-CACHE-THIRD-COPY-
# REVERTS-FIXES-01): a cache-invoked sync would treat the stale copy as the
# source of truth and push staleness back out.
#
# Exclusions (protected from --delete): hooks.bak-* (manual backups made
# inside the live cache — never destroy a backup silently), .synced-from
# (this script's own marker), .git/.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${SELF_DIR}" in
  "${HOME}"/.claude/plugins/cache/*)
    printf -- 'REFUSING: invoked from the plugin cache (%s) — run from the git-tracked repo tree (see leadv2-plugin-sync.sh CACHE-REFUSAL).\n' "${SELF_DIR}" >&2
    exit 3
    ;;
esac

CACHE_ROOT="${LEADV2_PLUGIN_CACHE_ROOT:-${HOME}/.claude/plugins/cache}"
META_JSON="${LEADV2_PLUGIN_META:-$(dirname "${CACHE_ROOT}")/installed_plugins.json}"

SRC_GIT="$(git -C "${SELF_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
PLUGIN_SRC="${LEADV2_PLUGIN_SRC:-${SRC_GIT:+${SRC_GIT}/plugins/leadv2}}"
if [[ -z "${PLUGIN_SRC}" || ! -d "${PLUGIN_SRC}" ]]; then
  printf -- 'BLOCK: source plugin tree not found: %s (set LEADV2_PLUGIN_SRC)\n' "${PLUGIN_SRC:-<unset>}" >&2
  exit 1
fi

# ── 1. Authoritative: installed_plugins.json installPath ────────────────────
CACHE_DIR=""
if [[ -f "${META_JSON}" ]]; then
  CACHE_DIR="$(python3 - "${META_JSON}" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for k, v in d.get("plugins", {}).items():
        if k.startswith("leadv2@"):
            print(v[0]["installPath"]); break
except Exception:
    pass
PY
)" || true
fi

# ── 2. Fallback: highest numeric version dir under the cache root ───────────
if [[ -z "${CACHE_DIR}" || ! -d "${CACHE_DIR}" ]]; then
  _base="${CACHE_ROOT}/leadv2-local/leadv2"
  _best="$(ls -1 "${_base}" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
  if [[ -n "${_best}" && -d "${_base}/${_best}" ]]; then
    CACHE_DIR="${_base}/${_best}"
  fi
fi

if [[ -z "${CACHE_DIR}" || ! -d "${CACHE_DIR}" ]]; then
  printf -- 'BLOCK: no leadv2 plugin cache dir found (looked in %s and %s/leadv2-local/leadv2)\n' "${META_JSON}" "${CACHE_ROOT}" >&2
  exit 1
fi

REPO_HEAD="$(git -C "${PLUGIN_SRC}" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "${REPO_HEAD}" ]]; then
  printf -- 'BLOCK: source tree is not a git repo (cannot record repo_head): %s\n' "${PLUGIN_SRC}" >&2
  exit 1
fi

_ITEMIZE="$(mktemp)"
trap 'rm -f "${_ITEMIZE}"' EXIT
# The cache dir IS a full copy of plugins/leadv2 (verified 2026-09-02:
# agents codex-skills commands config contracts data docs examples hooks
# prompts ref scripts skills templates tests workflows + .claude-plugin), so
# one whole-tree rsync is the sync — per-subdir loops would silently miss
# whatever the cache gains later.
rsync -a --delete \
  --exclude='hooks.bak-*' \
  --exclude='.synced-from' \
  --exclude='.git/' \
  --itemize-changes \
  "${PLUGIN_SRC}/" "${CACHE_DIR}/" >"${_ITEMIZE}" || {
  printf -- 'BLOCK: rsync failed syncing %s -> %s\n' "${PLUGIN_SRC}" "${CACHE_DIR}" >&2
  exit 1
}
N_SYNCED="$(grep -c '^>f' "${_ITEMIZE}" || true)"
printf '%s\n' "${REPO_HEAD}" >"${CACHE_DIR}/.synced-from"
printf 'synced=%s cache=%s repo_head=%s\n' "${N_SYNCED}" "${CACHE_DIR}" "${REPO_HEAD}"
