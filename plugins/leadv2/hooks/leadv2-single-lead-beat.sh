#!/usr/bin/env bash
# hooks/leadv2-single-lead-beat.sh — PULSE-IN-SINGLE-LEAD-01
#
# The founder pulse (BROAD_STATUS_READY) used to be emitted only from
# the supervisor loop's beat branch (retired 2026-08-17, SUPERVISOR-DELETE-01;
# never ran in single-lead mode anyway). Single-lead mode never runs that
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
# BEAT-LOOP-ORPHANS-01: worker evidence — the transcript path is the third
# signal (after LEADV2_WORKER_ARM / LEADV2_SUBSESSION_ROLE) the session-kind
# predicate consumes.
TRANSCRIPT_PATH="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('transcript_path', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
# A headless worker session never drives the founder beat: exit 0 silently
# before any state is touched (no alive-stamp, no GC, no deliver, no trigger).
# `unknown` arms fail-open but is journaled next to the trigger below.
_LEAD_GUARD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/leadv2-hook-session-kind.sh"
LEAD_KIND="unknown"
if [[ -f "$_LEAD_GUARD_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_LEAD_GUARD_LIB"
  LEAD_KIND="$(leadv2_hook_session_kind "$TRANSCRIPT_PATH" 2>/dev/null || printf 'unknown')"
  [[ "$LEAD_KIND" == "lead" || "$LEAD_KIND" == "worker" || "$LEAD_KIND" == "unknown" ]] || LEAD_KIND="unknown"
  if [[ "$LEAD_KIND" == "worker" ]]; then
    exit 0
  fi
fi
SESSION_ID="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('session_id', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
# SAFE_SID: sanitize to a filename-safe token, truncate 64 chars. Empty when
# no session_id was on stdin — the fallback shared watermark below then
# applies, same as before this lane (BROAD-STATUS-RELAY-SCOPE-01).
SAFE_SID="$(printf -- '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
SAFE_SID="${SAFE_SID:0:64}"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
  RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
  PULSE_BEAT_SH="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-beat.sh"
  BEAT_OWNER_SH="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-beat-owner.sh"
else
  _LV2_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RESOLVER="${_LV2_D}/../scripts/leadv2-state-path.sh"
  PULSE_BEAT_SH="${_LV2_D}/../scripts/leadv2-pulse-beat.sh"
  BEAT_OWNER_SH="${_LV2_D}/../scripts/leadv2-beat-owner.sh"
fi
[[ -x "$RESOLVER" ]] || exit 0
if [[ -f "$BEAT_OWNER_SH" ]]; then
  # shellcheck source=/dev/null
  source "$BEAT_OWNER_SH"
else
  printf -- '[single-lead-beat] beat-owner resolver missing: %s\n' "$BEAT_OWNER_SH" >&2
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$CWD_FROM_INPUT}"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$RESOLVER" --no-link supervise-loop.log 2>/dev/null || true)"
[[ -z "$LOG_FILE" ]] && LOG_FILE="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"

STATE_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "$RESOLVER" --no-link root 2>/dev/null || true)"
[[ -z "$STATE_DIR" ]] && STATE_DIR="${PROJECT_ROOT}/docs/leadv2"
# BROAD-STATUS-RELAY-SCOPE-01: per-session watermarks (R1) — the first
# session to fire a hook must not consume the beat for every other session.
# When session_id was absent from stdin, fall back to the pre-scope shared
# names so an old/degraded hook payload keeps today's behaviour.
if [[ -n "$SAFE_SID" ]]; then
  DELIVERED_FILE="${STATE_DIR}/.pulse-delivered.${SAFE_SID}"
  BODY_HASH_FILE="${STATE_DIR}/.pulse-body-hash.${SAFE_SID}"
else
  DELIVERED_FILE="${STATE_DIR}/.pulse-delivered"
  BODY_HASH_FILE="${STATE_DIR}/.pulse-body-hash"
fi
# M5: the `find -delete` sweep used to run on every single hook fire
# (PostToolUse included) -- gate it behind a once-per-day stamp so the
# 99.99% path is pure-bash with no `find` at all.
GC_DAY_FILE="${STATE_DIR}/.pulse-gc-day"
TODAY="$(date +%Y%m%d 2>/dev/null || true)"
LAST_GC_DAY=""
[[ -f "$GC_DAY_FILE" ]] && LAST_GC_DAY="$(cat "$GC_DAY_FILE" 2>/dev/null || true)"
if [[ -n "$TODAY" && "$TODAY" != "$LAST_GC_DAY" ]]; then
  printf -- '%s' "$TODAY" > "${GC_DAY_FILE}.tmp.$$" 2>/dev/null \
    && mv -f "${GC_DAY_FILE}.tmp.$$" "$GC_DAY_FILE" 2>/dev/null || true
  find "$STATE_DIR" -maxdepth 1 \
    \( -name '.pulse-delivered.*' -o -name '.pulse-body-hash.*' -o -name '.pulse-session.*' \) \
    -mtime +7 -delete 2>/dev/null || true
fi

# HIGH-1: stamp this session's own liveness on EVERY fire, before role
# resolution -- the resolver's owner-freshness check depends on this file
# existing and being recent for whichever session currently owns the beat.
if [[ -n "$SAFE_SID" ]]; then
  SESSION_ALIVE_FILE="${STATE_DIR}/.pulse-session.${SAFE_SID}"
  printf -- '%s' "$(date +%s 2>/dev/null || echo 0)" > "${SESSION_ALIVE_FILE}.tmp.$$" 2>/dev/null \
    && mv -f "${SESSION_ALIVE_FILE}.tmp.$$" "$SESSION_ALIVE_FILE" 2>/dev/null || true
fi

BEAT_S="${LEADV2_SINGLE_LEAD_BEAT_S:-1800}"
[[ "$BEAT_S" =~ ^[0-9]+$ ]] || BEAT_S=1800
ROLE="unresolved"
if command -v leadv2_beat_role >/dev/null 2>&1; then
  export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"
  ROLE="$(leadv2_beat_role "$SAFE_SID" "$STATE_DIR" "$BEAT_S" 2>/dev/null || true)"
  [[ "$ROLE" == "owner" || "$ROLE" == "guest" ]] || ROLE="unresolved"
fi

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
        if [[ "$ROLE" == "guest" ]]; then
          # Exactly one line, no ready-line body, no BROAD_STATUS_READY
          # bytes — so the task-anchor's verbatim-relay rule cannot latch.
          CTX="${AT} [BROAD_STATUS] at=${AT} path=docs/leadv2/founder-status.md — full status in owning session (RELAY=none); do not read founder-status.md; relay only this line. The relay is an aside, not the turn's work: execute any founder command in this same turn after it — never end the turn on the relay alone."
        else
          CTX="${READY_LINE}
RELAY=full — paste docs/leadv2/founder-status.md verbatim; compare its line-1 stamp with the beat above before relaying.
The relay is an aside, not the turn's work: if the founder's message contains a command or task, execute it in this same turn after the relay — never end the turn on the relay alone."
        fi
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
# BEAT-LOOP-ORPHANS-01: stamp the live lead's transcript path so the loop's
# owner-transcript staleness check (mechanism 2) has a liveness signal that
# does not depend on any pid arithmetic. Only for a resolved `lead` session —
# a worker's own transcript is not what keeps the LEAD's beat loop alive.
if [[ "$LEAD_KIND" == "lead" && -n "$TRANSCRIPT_PATH" ]]; then
  OWNER_TRANSCRIPT_FILE="${STATE_DIR}/.beat-owner-transcript"
  printf -- '%s' "$TRANSCRIPT_PATH" > "${OWNER_TRANSCRIPT_FILE}.tmp.$$" 2>/dev/null \
    && mv -f "${OWNER_TRANSCRIPT_FILE}.tmp.$$" "$OWNER_TRANSCRIPT_FILE" 2>/dev/null || true
fi
if [[ "$LEAD_KIND" == "unknown" ]]; then
  # Fail-open arming by a session the predicate could not classify — one
  # journal line so the heuristic gap is visible (BEAT-LOOP-ORPHANS-01).
  leadv2_loop_arm_journal "${STATE_DIR}/loop-arm-journal.log" single-lead-beat-hook unknown
fi
if [[ -x "$PULSE_BEAT_SH" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" LEADV2_BEAT_OWNER_SESSION="$SAFE_SID" \
    bash "$PULSE_BEAT_SH" --check >/dev/null 2>&1 &
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
