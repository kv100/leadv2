#!/bin/bash
# leadv2-codex-status.sh — statusline substitute for the Codex-lead pilot.
# Codex has no statusline surface, so this renders the same information the
# Claude statusline shows (~/.claude/burn/statusline.sh: "cc 32%·7d/4d12h ·
# cx 97%·wk/6d14h · glm 99%·wk/6d16h") plus lane count and active task, from
# leadv2-quota-live.sh (the in-plugin quota producer — NOT
# ~/.claude/burn/quota-fragment.sh, which is user-local and outside this
# plugin's runtime path; see CODEX-LEAD-FULL-01 prepass §1b).
#
# Fail-open by design: a failed read renders "?" for that field, never "0%"
# (leadv2-quota-live.sh's own contract), and this script's own exit code is
# 0 unless argv is wrong.
#
# Usage: leadv2-codex-status.sh [-h|--help]
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
QUOTA_LIVE="$REPO_ROOT/plugins/leadv2/scripts/leadv2-quota-live.sh"
STATUS_SURFACE="$REPO_ROOT/plugins/leadv2/scripts/leadv2-status-surface.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf 'usage: leadv2-codex-status.sh\n' >&2
  exit 0
fi
if [[ $# -gt 0 ]]; then
  printf 'usage: leadv2-codex-status.sh\n' >&2
  exit 2
fi

TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout 8"

QJSON=""
if [[ -x "$QUOTA_LIVE" || -r "$QUOTA_LIVE" ]]; then
  QJSON="$($TIMEOUT_BIN bash "$QUOTA_LIVE" json 2>/dev/null)"
fi

QUOTA_LINE="$(python3 - "$QJSON" <<'PYEOF'
import json, sys

raw = sys.argv[1]


def fmt(pct, hours):
    if pct is None:
        return "?"
    try:
        h = float(hours)
        if h >= 24:
            d, r = divmod(h, 24)
            reset = "%dd%dh" % (d, r)
        else:
            reset = "%dh" % round(h)
    except Exception:
        reset = "?"
    try:
        return "%s%%/%s" % (int(round(float(pct))), reset)
    except Exception:
        return "?"


def anthropic_field(d):
    try:
        acc = (d.get("accounts") or [{}])[0]
        bw = d.get("binding_window") or "seven_day"
        block = acc.get(bw) or {}
        return fmt(block.get("pct"), block.get("hours_to_reset"))
    except Exception:
        return "?"


def glm_field(d):
    try:
        bw = d.get("binding_window") or "weekly"
        block = d.get(bw) or {}
        return fmt(block.get("pct"), block.get("hours_to_reset"))
    except Exception:
        return "?"


def codex_field(d):
    try:
        w = (d.get("windows") or [{}])[0]
        return fmt(w.get("used_percent"), w.get("hours_to_reset"))
    except Exception:
        return "?"


try:
    data = json.loads(raw) if raw else {}
except Exception:
    data = {}

cc = "?"
cx = "?"
glm = "?"
try:
    a = data.get("anthropic") or {}
    if a.get("status") == "ok":
        cc = anthropic_field(a)
except Exception:
    pass
try:
    c = data.get("codex") or {}
    if c.get("status") == "ok":
        cx = codex_field(c)
except Exception:
    pass
try:
    g = data.get("glm") or {}
    if g.get("status") == "ok":
        glm = glm_field(g)
except Exception:
    pass

print("cc %s · cx %s · glm %s" % (cc, cx, glm))
PYEOF
)"

LANES="?"
TASK="—"
if [[ -x "$STATUS_SURFACE" || -r "$STATUS_SURFACE" ]]; then
  ONELINE="$($TIMEOUT_BIN bash "$STATUS_SURFACE" --oneline 2>/dev/null)"
  if [[ -n "$ONELINE" ]]; then
    if [[ "$ONELINE" =~ lanes\ ([0-9]+) ]]; then
      LANES="${BASH_REMATCH[1]}"
    else
      LANES=0
    fi
    if [[ "$LANES" != "0" ]]; then
      FIRST="$(printf '%s' "$ONELINE" | sed -n 's/.*lanes [0-9]*: *//p' | awk -F' \\| ' '{print $1}' | awk '{print $1}')"
      [[ -n "$FIRST" ]] && TASK="$FIRST"
    else
      TASK="—"
    fi
  else
    LANES=0
    TASK="—"
  fi
fi

printf '%s | lanes %s | task %s\n' "$QUOTA_LINE" "$LANES" "$TASK"
exit 0
