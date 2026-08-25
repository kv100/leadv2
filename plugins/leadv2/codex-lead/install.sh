#!/bin/bash
# install.sh — idempotent installer for the Codex-lead tooling.
#
# Runs OUTSIDE this repo (writes to $HOME/.codex/ and a target project repo)
# but ships INSIDE it — this script writes nothing under ~/Projects/leadv2.
#
# Plugin path (preferred, codex-cli >= 0.145): register the local marketplace
# leadv2-local and install plugin leadv2 — skills, the lv2guard PreToolUse
# hook, and the repowise MCP launcher all ship through the plugin. Fallback
# path (CLI without plugin support): prompt pack + a repowise block in
# config.toml, exactly as before.
#
# Usage:
#   install.sh [<target-repo-path>]     # default: $HOME/Projects/persona-engine
#
# Exit codes:
#   0   ran to completion (individual steps may print ACTION REQUIRED)
#   3   target repo path does not exist
#   4   ~/.codex/config.toml unwritable, or fails a TOML parse-check
#
# Test seam: LEADV2_CODEX_BIN=<prog> replaces the codex CLI (never a bare
# `codex` — a test with a redirected $HOME must not mutate the real
# ~/.codex/config.toml).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_REPO="${1:-$HOME/Projects/persona-engine}"
CODEX_DIR="$HOME/.codex"
PROMPTS_SRC="$SCRIPT_DIR/prompts"
AGENTS_BRIEF_SRC="$REPO_ROOT/plugins/leadv2/docs/codex-lead-AGENTS-pilot.md"
CODEX_BIN="${LEADV2_CODEX_BIN:-codex}"
MARKETPLACE_DIR="$SCRIPT_DIR/marketplace"
MARKETPLACE_NAME="leadv2-local"
PLUGIN_ID="leadv2@$MARKETPLACE_NAME"

SENTINEL_BEGIN="# BEGIN leadv2-codex-lead repowise (managed by plugins/leadv2/codex-lead/install.sh)"
SENTINEL_END="# END leadv2-codex-lead repowise"

if [[ ! -d "$TARGET_REPO" ]]; then
  printf 'install.sh: target repo path does not exist: %s\n' "$TARGET_REPO" >&2
  exit 3
fi

toml_parses() {
  python3 -c "
import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)  # no tomllib available: skip the check rather than block install
with open(sys.argv[1], 'rb') as f:
    tomllib.load(f)
" "$1" 2>/dev/null
}

# --- copy-or-report helper: unchanged / updated(+.bak) --------------------
sync_file() {
  local src="$1" dst="$2"
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    printf 'installed %s\n' "$dst"
    return 0
  fi
  if cmp -s "$src" "$dst"; then
    printf 'unchanged %s\n' "$dst"
    return 0
  fi
  cp "$dst" "$dst.bak"
  cp "$src" "$dst"
  printf 'updated %s (backup: %s.bak)\n' "$dst" "$dst"
  return 0
}

# --- 1. prompt pack ----------------------------------------------------------
mkdir -p "$CODEX_DIR/prompts"
if [[ -d "$PROMPTS_SRC" ]]; then
  for f in "$PROMPTS_SRC"/*.md; do
    [[ -f "$f" ]] || continue
    sync_file "$f" "$CODEX_DIR/prompts/$(basename "$f")"
  done
fi

# --- 2. AGENTS-pilot brief into the target repo's ref/ ----------------------
if [[ -f "$AGENTS_BRIEF_SRC" ]]; then
  mkdir -p "$TARGET_REPO/.claude/ref"
  sync_file "$AGENTS_BRIEF_SRC" "$TARGET_REPO/.claude/ref/90-codex-lead-pilot.md"
fi

# --- 3. verify (never write) the @import line in the target AGENTS.md ------
TARGET_AGENTS="$TARGET_REPO/AGENTS.md"
if [[ -f "$TARGET_AGENTS" ]] && grep -qF '@import .claude/ref/90-codex-lead-pilot.md' "$TARGET_AGENTS"; then
  printf '%s: @import line present\n' "$TARGET_AGENTS"
else
  printf 'ACTION REQUIRED: append this line to %s:\n  @import .claude/ref/90-codex-lead-pilot.md\n' "$TARGET_AGENTS"
fi

# --- 4. plugin path (preferred) ---------------------------------------------
CONFIG_TOML="$CODEX_DIR/config.toml"
# rc 4 contract covers an UNUSABLE ~/.codex, not just an unparseable
# config.toml: if the dir cannot be created, or exists but is unwritable
# (and config.toml is absent, so nothing could ever be written), fail now —
# a later silent write failure would report success with nothing installed
# (round-1 cross-provider review, major).
if ! mkdir -p "$CODEX_DIR" 2>/dev/null; then
  printf 'install.sh: cannot create %s
' "$CODEX_DIR" >&2
  exit 4
fi
if [[ -d "$CODEX_DIR" && ! -w "$CODEX_DIR" && ! -f "$CONFIG_TOML" ]]; then
  printf 'install.sh: %s is not writable and %s does not exist
' "$CODEX_DIR" "$CONFIG_TOML" >&2
  exit 4
fi

USE_PLUGIN=0
if [[ -d "$MARKETPLACE_DIR" ]] && "$CODEX_BIN" plugin --help >/dev/null 2>&1; then
  if [[ -f "$CONFIG_TOML" ]] && ! toml_parses "$CONFIG_TOML"; then
    printf 'install.sh: %s does not parse as TOML — refusing to touch it\n' "$CONFIG_TOML" >&2
    exit 4
  fi

  # 4a. marketplace registration (different-root conflict is never re-pointed)
  MARKETPLACE_OK=0
  EXISTING_ROOT=""
  if [[ -f "$CONFIG_TOML" ]]; then
    EXISTING_ROOT="$(awk -v m="$MARKETPLACE_NAME" '
      $0 == "[marketplaces." m "]" { in_mkt = 1; next }
      in_mkt && /^source = / { sub(/^source = "/, ""); sub(/"$/, ""); print; exit }
      /^\[/ { in_mkt = 0 }
    ' "$CONFIG_TOML")"
  fi
  MARKETPLACE_ABS="$(cd "$MARKETPLACE_DIR" && pwd -P)"
  if [[ -n "$EXISTING_ROOT" && "$EXISTING_ROOT" != "$MARKETPLACE_ABS" ]]; then
    printf 'ACTION REQUIRED: marketplace %s already registered at a different root:\n  registered: %s\n  this tree:  %s\n  resolve by hand (codex plugin marketplace remove %s) — not re-pointed silently\n' \
      "$MARKETPLACE_NAME" "$EXISTING_ROOT" "$MARKETPLACE_ABS" "$MARKETPLACE_NAME"
  elif [[ -n "$EXISTING_ROOT" ]]; then
    printf 'marketplace %s: unchanged (%s)\n' "$MARKETPLACE_NAME" "$EXISTING_ROOT"
    MARKETPLACE_OK=1
  else
    if "$CODEX_BIN" plugin marketplace add "$MARKETPLACE_DIR" >/dev/null 2>&1; then
      printf 'marketplace %s: added (%s)\n' "$MARKETPLACE_NAME" "$MARKETPLACE_ABS"
      MARKETPLACE_OK=1
    else
      printf 'ACTION REQUIRED: `codex plugin marketplace add %s` failed — install the plugin by hand, or re-run for the prompt-pack fallback (installed below)\n' "$MARKETPLACE_DIR"
    fi
  fi

  # 4b. plugin install (skipped when already registered in config.toml)
  if [[ "$MARKETPLACE_OK" == "1" ]]; then
    if [[ -f "$CONFIG_TOML" ]] && grep -qF "[plugins.\"$PLUGIN_ID\"]" "$CONFIG_TOML"; then
      printf 'plugin: unchanged %s\n' "$PLUGIN_ID"
      USE_PLUGIN=1
    elif "$CODEX_BIN" plugin add "$PLUGIN_ID" >/dev/null 2>&1 && \
         grep -qF "[plugins.\"$PLUGIN_ID\"]" "$CONFIG_TOML" 2>/dev/null; then
      printf 'plugin: installed %s\n' "$PLUGIN_ID"
      USE_PLUGIN=1
    else
      printf 'ACTION REQUIRED: `codex plugin add %s` did not register — install by hand or use the prompt-pack fallback (installed below)\n' "$PLUGIN_ID"
    fi
  fi
fi

if [[ "$USE_PLUGIN" == "1" ]]; then
  printf 'plugin: skills + lv2guard PreToolUse hook + repowise MCP launcher installed as %s\n' "$PLUGIN_ID"
  printf 'plugin: one-time trust required — launch codex, accept "Trust all and continue" for the leadv2 hooks (or pass --dangerously-bypass-hook-trust)\n'
else
  printf 'plugin: CLI has no plugin support — installed prompt pack instead\n'
fi

# --- 5. ~/.codex/config.toml repowise MCP block (fallback path only) --------
# On the plugin path the plugin's .mcp.json owns the repowise declaration;
# writing the block too would leave two repowise servers racing for one name.
if [[ "$USE_PLUGIN" != "1" ]]; then
REPOWISE_BLOCK="$SENTINEL_BEGIN
[mcp_servers.repowise]
command = \"$TARGET_REPO/.repowise/repowise-mcp.sh\"
args = []
$SENTINEL_END"

if [[ ! -f "$CONFIG_TOML" ]]; then
  printf '%s\n' "$REPOWISE_BLOCK" > "$CONFIG_TOML"
  printf 'config.toml: created with repowise block\n'
elif [[ ! -w "$CONFIG_TOML" ]]; then
  printf 'install.sh: %s is not writable\n' "$CONFIG_TOML" >&2
  exit 4
else
  if ! toml_parses "$CONFIG_TOML"; then
    printf 'install.sh: %s does not parse as TOML — refusing to touch it\n' "$CONFIG_TOML" >&2
    exit 4
  fi
  if grep -qF "$SENTINEL_BEGIN" "$CONFIG_TOML"; then
    # Managed block already present — replace it in place only if it drifted.
    cp "$CONFIG_TOML" "$CONFIG_TOML.bak"
    CHANGED="$(python3 - "$CONFIG_TOML" "$SENTINEL_BEGIN" "$SENTINEL_END" "$REPOWISE_BLOCK" <<'PYEOF'
import sys
path, begin, end, block = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    lines = f.readlines()
out = []
in_block = False
for line in lines:
    if line.rstrip('\n') == begin:
        in_block = True
        out.append(block + '\n')
        continue
    if in_block:
        if line.rstrip('\n') == end:
            in_block = False
        continue
    out.append(line)
new_text = ''.join(out)
with open(path) as f:
    old_text = f.read()
if new_text != old_text:
    with open(path, 'w') as f:
        f.write(new_text)
    print('changed')
else:
    print('unchanged')
PYEOF
)"
    if [[ "$CHANGED" == "changed" ]]; then
      if ! toml_parses "$CONFIG_TOML"; then
        cp "$CONFIG_TOML.bak" "$CONFIG_TOML"
        printf 'install.sh: update produced invalid TOML — rolled back\n' >&2
        exit 4
      fi
      printf 'config.toml: repowise block updated (backup: %s.bak)\n' "$CONFIG_TOML"
    else
      rm -f "$CONFIG_TOML.bak"
      printf 'config.toml: repowise block unchanged\n'
    fi
  elif grep -qE '^\[mcp_servers\.repowise\]' "$CONFIG_TOML"; then
    printf 'config.toml: repowise already configured by hand — left untouched\n'
  else
    cp "$CONFIG_TOML" "$CONFIG_TOML.bak"
    printf '\n%s\n' "$REPOWISE_BLOCK" >> "$CONFIG_TOML"
    if ! toml_parses "$CONFIG_TOML"; then
      cp "$CONFIG_TOML.bak" "$CONFIG_TOML"
      printf 'install.sh: append produced invalid TOML — rolled back\n' >&2
      exit 4
    fi
    printf 'config.toml: repowise block added (backup: %s.bak)\n' "$CONFIG_TOML"
  fi
fi
fi  # end fallback-only config.toml block

# --- 6. tmux statusline (opt-in; never auto-installed) ----------------------
# CODEX-TMUX-STATUSLINE-01: this installer must not mutate any tmux config —
# only point at the dedicated opt-in installer.
STATUSLINE_INSTALL="$SCRIPT_DIR/statusline/install-tmux-statusline.sh"
if [[ -f "$STATUSLINE_INSTALL" ]]; then
  printf 'tmux statusline: opt-in — to add the leadv2 bottom bar: %s\n' "$STATUSLINE_INSTALL"
fi

exit 0
