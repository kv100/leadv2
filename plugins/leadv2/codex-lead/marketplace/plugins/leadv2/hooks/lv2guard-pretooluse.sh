#!/bin/bash
# lv2guard-pretooluse.sh — Codex PreToolUse adapter for the leadv2 deny floor.
#
# Wire contract (recorded empirically against codex-cli 0.145.0-alpha.1,
# CODEX-LEAD-PLUGIN-01 probe artifacts, not assumed):
#   stdin : {"tool_name":"Bash","tool_input":{"command":"<cmd string>"},...}
#   stdout: EMPTY + exit 0        = allow (the ONLY allow shape; emitting
#           permissionDecision:"allow" or "ask" is a runtime rejection)
#           deny JSON + exit 0    = block; reason must be non-empty
#   exit 2 + stderr               = block with feedback (documented path)
#   any other non-zero exit       = runtime treats the hook as Failed and the
#           tool PROCEEDS (probed: exit 7 -> "PreToolUse Failed" -> command
#           ran) — so this adapter must never crash on the deny path.
#
# Hook commands resolve relative to the SESSION cwd, not the plugin root, so
# hooks.json invokes this script via the $CLAUDE_PLUGIN_ROOT indirection the
# runtime injects for plugin hooks (probed; PLUGIN_ROOT is also set).
set -u

MATCH_CAP_BYTES=65536
UNRECOG_LOG="${CODEX_HOME:-$HOME/.codex}/lv2guard-unrecognized.log"
GUARD_FALLBACK_REASON="lv2guard: refused (no reason captured)"

# json_escape: pure-bash JSON string escaping. The DENY EMITTER MUST NOT
# DEPEND ON python3 (or any external tool): a deny that fails to emit is an
# empty stdout + rc 0, which the runtime reads as ALLOW — exactly the
# fail-open hole the round-1 cross-provider review blocked on. tr is used
# opportunistically to strip residual control chars; if unavailable the
# already-escaped string is emitted as-is (reason non-emptiness preserved).
json_escape() {
  local s="$1" stripped
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  if stripped="$(printf '%s' "$s" | tr -d '\000-\037' 2>/dev/null)" && [[ -n "$stripped" || -z "$s" ]]; then
    printf '%s' "$stripped"
  else
    printf '%s' "$s"
  fi
}

emit_deny() {
  # $1 = reason (must be non-empty; runtime rejects empty reasons).
  # Pure bash: printf is a builtin, so this emits even with a broken PATH.
  local reason="${1:-$GUARD_FALLBACK_REASON}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$reason")"
  exit 0
}

log_unrecognized() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$UNRECOG_LOG" 2>/dev/null || true
}

INPUT="$(cat 2>/dev/null || true)"

# --- parse stdin: not-JSON is a deny, not a silent hole ----------------------
PARSED="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("__BADJSON__")
    sys.exit(0)
ti = d.get("tool_input")
cmd = ti.get("command") if isinstance(ti, dict) else None
if not isinstance(cmd, str) or cmd == "":
    print("__NOCMD__")
    sys.exit(0)
sys.stdout.write(cmd)
' 2>/dev/null || true)"

if [[ -z "$PARSED" ]]; then
  PARSED="__BADJSON__"
fi
if [[ "$PARSED" == "__BADJSON__" ]]; then
  log_unrecognized "BAD_JSON tool_input-unreadable"
  emit_deny "lv2guard: unreadable PreToolUse payload — every tool call is refused until the payload is parseable again"
fi
if [[ "$PARSED" == "__NOCMD__" ]]; then
  log_unrecognized "NO_COMMAND shape-not-guardable"
  exit 0
fi

CMD="$PARSED"
if [[ ${#CMD} -gt $MATCH_CAP_BYTES ]]; then
  log_unrecognized "TRUNCATED ${#CMD} bytes -> $MATCH_CAP_BYTES"
  CMD="${CMD:0:$MATCH_CAP_BYTES}"
fi

# --- resolve lv2guard.sh: env override, in-place tree, host checkout --------
GUARD=""
if [[ -n "${LEADV2_CODEX_LV2GUARD:-}" ]]; then
  if [[ -f "$LEADV2_CODEX_LV2GUARD" ]]; then
    GUARD="$LEADV2_CODEX_LV2GUARD"
  else
    emit_deny "lv2guard: LEADV2_CODEX_LV2GUARD=$LEADV2_CODEX_LV2GUARD does not exist — fix or unset the override (a typo'd override silently degrading to a different guard would be worse than this stop)"
  fi
fi
if [[ -z "$GUARD" ]]; then
  # Plugin referenced in place:
  # .../codex-lead/marketplace/plugins/leadv2/hooks -> 4 up = codex-lead/
  CAND="$(dirname "$0")/../../../../lv2guard.sh"
  [[ -f "$CAND" ]] && GUARD="$CAND"
fi
if [[ -z "$GUARD" ]]; then
  # Plugin snapshotted into ~/.codex/plugins/cache/<mkt>/leadv2/<ver>: the
  # plugin deliberately ships NO copy of lv2guard.sh or the yamls (one-copy
  # rule) — resolve the host checkout instead.
  CAND="$HOME/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh"
  [[ -f "$CAND" ]] && GUARD="$CAND"
fi
if [[ -z "$GUARD" ]]; then
  emit_deny "lv2guard.sh not resolvable — set LEADV2_CODEX_LV2GUARD=/path/to/lv2guard.sh (expected \$HOME/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh)"
fi

# --- adjudicate: rc 0 = allow, rc 97 = deny, rc 2 = guard usage bug ---------
ERR_OUT="$(bash "$GUARD" --check -c "$CMD" 2>&1 >/dev/null)"; GUARD_RC=$?

case "$GUARD_RC" in
  0) exit 0 ;;
  97)
    # Prefer the guard's own message; the runtime requires a non-empty reason.
    REASON="$(printf '%s' "$ERR_OUT" | tr -d '\r' | grep -v '^\s*$' | tail -n +2 | head -n 10 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    [[ -z "$REASON" ]] && REASON="$(printf '%s' "$ERR_OUT" | head -n 10 | tr '\n' ' ')"
    [[ -z "$REASON" ]] && REASON="${GUARD_FALLBACK_REASON#lv2guard: }"
    emit_deny "lv2guard: $REASON"
    ;;
  2)
    emit_deny "lv2guard: guard usage error (adapter bug — rc 2 from lv2guard --check)"
    ;;
  *)
    emit_deny "lv2guard: guard exited rc=$GUARD_RC (unexpected — failing closed; see $GUARD)"
    ;;
esac
