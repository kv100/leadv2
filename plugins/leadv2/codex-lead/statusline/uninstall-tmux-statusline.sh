#!/bin/bash
# uninstall-tmux-statusline.sh — removes what install-tmux-statusline.sh added.
#
# Removes the generated activation conf and the status cache by default; with
# --tmux-conf PATH additionally strips ONLY the sentinel-delimited managed
# block from that file, leaving every non-managed line byte-identical (backup
# .bak on change). The one blank line the installer puts before the block goes
# with it; nothing else is touched. Never guesses a tmux config path — a wrong removal in the
# user's tmux.conf is worse than leaving one block behind.
#
# Usage:
#   uninstall-tmux-statusline.sh [--tmux-conf PATH]
#
# Exit codes:
#   0   ran to completion
#   2   bad arguments
#   4   --tmux-conf target exists but is unwritable
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/leadv2"
CONF_OUT="$CONF_DIR/tmux-statusline.conf"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/leadv2/tmux-statusline"

SENTINEL_BEGIN="# BEGIN leadv2 tmux statusline (managed by plugins/leadv2/codex-lead/statusline/install-tmux-statusline.sh)"
SENTINEL_END="# END leadv2 tmux statusline"

usage() {
  printf 'usage: uninstall-tmux-statusline.sh [--tmux-conf PATH]\n' >&2
}

TMUX_CONF=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmux-conf)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      TMUX_CONF="$2"; shift 2 ;;
    --tmux-conf=*)
      TMUX_CONF="${1#--tmux-conf=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      printf 'uninstall-tmux-statusline.sh: unknown argument: %s\n' "$1" >&2
      usage; exit 2 ;;
  esac
done

# --- 1. strip the managed block (explicit --tmux-conf only) ----------------
if [[ -n "$TMUX_CONF" ]]; then
  if [[ -f "$TMUX_CONF" ]]; then
    if grep -qF "$SENTINEL_BEGIN" "$TMUX_CONF"; then
      if [[ ! -w "$TMUX_CONF" ]]; then
        printf 'uninstall-tmux-statusline.sh: %s is not writable\n' "$TMUX_CONF" >&2
        exit 4
      fi
      TMP_CONF="$(mktemp "${TMPDIR:-/tmp}/leadv2-tmux-conf.XXXXXX")" || exit 4
      # Drop the block and, only when directly preceded by one, the blank
      # line the installer added before it. Everything else byte-identical.
      STRIP_RC=0
      python3 - "$TMUX_CONF" "$TMP_CONF" "$SENTINEL_BEGIN" "$SENTINEL_END" <<'PYEOF' || STRIP_RC=$?
import sys
src, dst, begin, end = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(src) as f:
    lines = f.readlines()
out = []
inblk = False
for line in lines:
    if line.rstrip('\n') == begin:
        inblk = True
        if out and out[-1].strip() == '':
            out.pop()  # the installer's separator blank line
        continue
    if inblk:
        if line.rstrip('\n') == end:
            inblk = False
        continue
    out.append(line)
if inblk:
    sys.exit(1)  # unbalanced block: refuse rather than write half a file
with open(dst, 'w') as f:
    f.writelines(out)
PYEOF
      if [[ "$STRIP_RC" != "0" ]]; then
        rm -f "$TMP_CONF"
        printf 'uninstall-tmux-statusline.sh: managed block in %s is unbalanced — not touched\n' "$TMUX_CONF" >&2
        exit 4
      fi
      if diff -q "$TMP_CONF" "$TMUX_CONF" >/dev/null 2>&1; then
        printf 'tmux.conf: no managed block in %s\n' "$TMUX_CONF"
        rm -f "$TMP_CONF"
      else
        cp "$TMUX_CONF" "$TMUX_CONF.bak"
        if mv "$TMP_CONF" "$TMUX_CONF"; then
          printf 'tmux.conf: managed block removed from %s (backup: %s.bak)\n' "$TMUX_CONF" "$TMUX_CONF"
        else
          rm -f "$TMP_CONF"
          printf 'uninstall-tmux-statusline.sh: cannot update %s\n' "$TMUX_CONF" >&2
          exit 4
        fi
      fi
    else
      printf 'tmux.conf: no managed block in %s\n' "$TMUX_CONF"
    fi
  else
    printf 'tmux.conf: %s does not exist — nothing to strip\n' "$TMUX_CONF"
  fi
fi

# --- 2. remove our own assets ----------------------------------------------
if [[ -f "$CONF_OUT" ]]; then
  rm -f "$CONF_OUT" "$CONF_OUT.bak" && printf 'conf: removed %s\n' "$CONF_OUT"
else
  printf 'conf: %s not present\n' "$CONF_OUT"
fi
if [[ -d "$CACHE_DIR" ]]; then
  rm -rf "$CACHE_DIR" && printf 'cache: removed %s\n' "$CACHE_DIR"
else
  printf 'cache: %s not present\n' "$CACHE_DIR"
fi

printf '\n'
if [[ -n "$TMUX_CONF" ]]; then
  printf 'Reload to clear the running server status:\n'
  printf '  tmux source-file %s\n' "$TMUX_CONF"
  printf '  tmux set -g status-right "#S"   # or your previous status-right\n'
else
  printf 'If a managed block was added to a tmux config, remove it with:\n'
  printf '  %s --tmux-conf <path-to-tmux-conf>\n' "$0"
fi
exit 0
