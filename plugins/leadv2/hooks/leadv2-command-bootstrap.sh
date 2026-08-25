#!/usr/bin/env bash
# leadv2-command-bootstrap.sh — SessionStart hook. Makes the bare `/leadv2`
# command exist in whatever repo this session opened in.
#
# WHY (founder, 2026-08-25: "я хочу чтобы в любом проекте я просто написал
# /leadv2 и просто запускать работу"): the plugin's own command is namespaced,
# so a repo that has never been adopted offers `/leadv2-audit` and
# `/leadv2-learn` but NO bare `/leadv2` — the one everybody actually types. That
# command has always come from a PROJECT file, `.claude/commands/leadv2.md`,
# which nothing created automatically. platform had none; and because the full
# adoption pass lives at Step 0 INSIDE that command, a repo without it could
# never bootstrap itself — chicken and egg.
#
# This hook breaks the cycle the same way leadv2-install-dispatcher.sh installs
# `lv2`: at SessionStart, ensure the command file exists. It is a SYMLINK to
# canonical, never a copy — a copy is exactly how persona-engine's /leadv2 rotted
# into a months-old fork ("Fable main", a retired supervisor) while canonical
# moved on. Repo-specific behaviour belongs in
# .claude/leadv2-overrides/extensions.md, which the command reads at Step 0.5.
#
# It installs ONE file and nothing else. Full adoption (script farm, agents, env,
# state dir) still happens at Step 0 the first time the founder types /leadv2 —
# so merely opening an unrelated repo does not litter it.
#
# Never overwrites: an existing real file is a deliberate local fork (respiro-ios
# has a legitimate iOS one) and is left alone, silently.
# Silent on success. Never fails the session.
set -uo pipefail

src="${CLAUDE_PLUGIN_ROOT:-}/commands/leadv2.md"
repo="${CLAUDE_PROJECT_DIR:-$PWD}"
dst="${repo}/.claude/commands/leadv2.md"

[ -f "$src" ] || exit 0
[ -d "$repo" ] || exit 0

# Already a symlink: heal it only if it dangles or points somewhere else.
if [ -L "$dst" ]; then
  cur="$(readlink "$dst" 2>/dev/null || true)"
  if [ "$cur" = "$src" ] && [ -e "$dst" ]; then exit 0; fi
  if [ ! -e "$dst" ]; then rm -f "$dst" 2>/dev/null || exit 0; fi
fi

# A real file is a local fork — never touch it.
[ -f "$dst" ] && [ ! -L "$dst" ] && exit 0

mkdir -p "${repo}/.claude/commands" 2>/dev/null || exit 0
if [ -L "$dst" ]; then rm -f "$dst" 2>/dev/null || exit 0; fi
ln -s "$src" "$dst" 2>/dev/null || exit 0

printf '/leadv2 is now available in %s (command linked to canonical; type /leadv2 to finish adoption)\n' "$(basename "$repo")"
exit 0
