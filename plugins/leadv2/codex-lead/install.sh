#!/bin/bash
# install.sh — idempotent installer for the Codex-lead pilot tooling.
#
# Runs OUTSIDE this repo (writes to $HOME/.codex/ and a target project repo)
# but ships INSIDE it — this script writes nothing under ~/Projects/leadv2.
#
# Usage:
#   install.sh [<target-repo-path>]     # default: $HOME/Projects/persona-engine
#
# Exit codes:
#   0   ran to completion (individual steps may print ACTION REQUIRED)
#   3   target repo path does not exist
#   4   ~/.codex/config.toml unwritable, or fails a TOML parse-check
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_REPO="${1:-$HOME/Projects/persona-engine}"
CODEX_DIR="$HOME/.codex"
PROMPTS_SRC="$SCRIPT_DIR/prompts"
AGENTS_BRIEF_SRC="$REPO_ROOT/plugins/leadv2/docs/codex-lead-AGENTS-pilot.md"

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

# --- 4. ~/.codex/config.toml repowise MCP block -----------------------------
CONFIG_TOML="$CODEX_DIR/config.toml"
mkdir -p "$CODEX_DIR"

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

exit 0
