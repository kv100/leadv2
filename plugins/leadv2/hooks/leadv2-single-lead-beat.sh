#!/usr/bin/env bash
# hooks/leadv2-single-lead-beat.sh — PULSE-IN-SINGLE-LEAD-01
#
# The founder pulse (BROAD_STATUS_READY) used to be emitted only from
# leadv2-supervise-loop.sh's beat branch. Single-lead mode never runs that
# loop, so no supervisor is running to compose or announce a status. This
# hook is the single-lead replacement, wired to UserPromptSubmit and
# PostToolUse(.*) so it runs on the lead's own working cadence instead of a
# wall-clock daemon (see docs/single-lead-pulse.md §"why hook-clock").
#
# Two steps, ALWAYS in this order:
#   1. DELIVER — tail the last BROAD_STATUS_READY/FAILED line already
#      written to supervise-loop.log by a PRIOR beat and, if it names a
#      beat that hasn't been relayed to this session yet AND the artifact
#      body actually changed, inject it as additionalContext. Idempotent by
#      construction (dedupe on at= + a content hash of founder-status.md
#      minus its stamp line) — never touches leadv2-broad-status.sh, which
#      is out of scope for this lane.
#   2. TRIGGER — if due (throttle elapsed, no live supervise loop), kick off
#      scripts/leadv2-pulse-beat.sh --check in the background so the NEXT
#      hook fire has something fresh to deliver.
#
# Deliver runs before trigger so a beat composed by the previous fire always
# reaches the founder before this fire tries to start a new one.
#
# Kill-switch: LEADV2_SINGLE_LEAD_BEAT=0 -- exit 0 immediately, nothing else
# touched. This is the one-step rollback for the whole feature.
set -uo pipefail
trap 'exit 0' ERR

[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
CWD_FROM_INPUT="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('cwd', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
[[ -z "$CWD_FROM_INPUT" ]] && CWD_FROM_INPUT="$PWD"
HOOK_EVENT="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('hook_event_name', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
[[ -z "$HOOK_EVENT" ]] && HOOK_EVENT="UserPromptSubmit"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
  RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
  PULSE_BEAT_SH="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-beat.sh"
else
  _LV2_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RESOLVER="${_LV2_D}/../scripts/leadv2-state-path.sh"
  PULSE_BEAT_SH="${_LV2_D}/../scripts/leadv2-pulse-beat.sh"
fi
[[ -x "$RESOLVER" ]] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$CWD_FROM_INPUT}"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$RESOLVER" --no-link supervise-loop.log 2>/dev/null || true)"
[[ -z "$LOG_FILE" ]] && LOG_FILE="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"

STATE_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "$RESOLVER" --no-link root 2>/dev/null || true)"
[[ -z "$STATE_DIR" ]] && STATE_DIR="${PROJECT_ROOT}/docs/leadv2"
DELIVERED_FILE="${STATE_DIR}/.pulse-delivered"
BODY_HASH_FILE="${STATE_DIR}/.pulse-body-hash"

FOUNDER_STATUS_PATH="${LEADV2_FOUNDER_STATUS_PATH:-${PROJECT_ROOT}/docs/leadv2/founder-status.md}"

# ── 1. DELIVER ───────────────────────────────────────────────────────────
CTX=""
if [[ -f "$LOG_FILE" ]]; then
  READY_LINE="$(grep -E '\[SUPERVISE-URGENT\] BROAD_STATUS_(READY|FAILED) ' "$LOG_FILE" 2>/dev/null | tail -n1)"
  if [[ -n "$READY_LINE" ]]; then
    AT="$(printf -- '%s' "$READY_LINE" | sed -n 's/.* at=\([^ ]*\).*/\1/p')"
    DELIVERED_AT=""
    [[ -f "$DELIVERED_FILE" ]] && DELIVERED_AT="$(cat "$DELIVERED_FILE" 2>/dev/null || true)"
    if [[ -n "$AT" && "$AT" != "$DELIVERED_AT" ]]; then
      BODY_HASH=""
      if [[ -f "$FOUNDER_STATUS_PATH" ]]; then
        BODY_HASH="$(tail -n +2 "$FOUNDER_STATUS_PATH" 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}')"
        [[ -z "$BODY_HASH" ]] && BODY_HASH="$(tail -n +2 "$FOUNDER_STATUS_PATH" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
      fi
      PREV_BODY_HASH=""
      [[ -f "$BODY_HASH_FILE" ]] && PREV_BODY_HASH="$(cat "$BODY_HASH_FILE" 2>/dev/null || true)"
      if [[ -n "$BODY_HASH" && "$BODY_HASH" != "$PREV_BODY_HASH" ]]; then
        CTX="$READY_LINE"
        printf -- '%s' "$BODY_HASH" > "${BODY_HASH_FILE}.tmp.$$" 2>/dev/null \
          && mv -f "${BODY_HASH_FILE}.tmp.$$" "$BODY_HASH_FILE" 2>/dev/null || true
      fi
      # Either way — body changed or not — this beat is now the delivered
      # watermark, so an unchanged body is never re-hashed on every turn.
      printf -- '%s' "$AT" > "${DELIVERED_FILE}.tmp.$$" 2>/dev/null \
        && mv -f "${DELIVERED_FILE}.tmp.$$" "$DELIVERED_FILE" 2>/dev/null || true
    fi
  fi
fi

# ── 2. TRIGGER ───────────────────────────────────────────────────────────
if [[ -x "$PULSE_BEAT_SH" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$PULSE_BEAT_SH" --check >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

if [[ -n "$CTX" ]]; then
  if [[ "$HOOK_EVENT" == "UserPromptSubmit" ]]; then
    jq -n --arg evt "$HOOK_EVENT" --arg ctx "$CTX" '{
      hookSpecificOutput: {
        hookEventName: $evt,
        additionalContext: $ctx
      }
    }' 2>/dev/null || printf -- '{"hookSpecificOutput":{"hookEventName":%s,"additionalContext":%s}}' \
      "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$HOOK_EVENT")" \
      "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$CTX")"
  else
    # PostToolUse: flat additionalContext, no hookSpecificOutput wrapper
    # (same shape as leadv2-auto-status.sh / leadv2-bg-watchdog-enforce.sh).
    jq -n --arg ctx "$CTX" '{additionalContext: $ctx}' 2>/dev/null \
      || printf -- '{"additionalContext":%s}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$CTX")"
  fi
fi

exit 0
