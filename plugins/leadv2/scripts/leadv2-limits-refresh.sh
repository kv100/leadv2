#!/usr/bin/env bash
# leadv2-limits-refresh.sh — SWIFTBAR-LIVE-01 per-provider TTL'd limits cache
# writer. Runs (usually detached, non-blocking) to refresh one <provider>.kv
# file per provider under LEADV2_LIMITS_CACHE_DIR. The render path
# (leadv2-status-surface.sh render_limits) only ever READS these files -- it
# never blocks the 10s SwiftBar tick on a network/keychain call.
#
# Usage: leadv2-limits-refresh.sh [--provider glm|claude|codex|kimi|all] [--force]
#
# kv file format (first '=' splits; unknown keys ignored, forward-compat):
#   state=ok|unknown|unavailable|unauthenticated
#   value=<already-rendered display string>
#   stamped=<epoch>
#   ttl=<seconds>
#   detail=<one-line text, optional>
#
# A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01: `unknown` is a state distinct
# from `unavailable`. `unavailable` means this script never got an answer at
# all (helper missing/crashed/timed out) -- there is nothing to report but
# absence. `unknown` means the reader (leadv2-quota-read.py) DID answer and
# said it could not measure the provider (e.g. codex HTTP 401 on token
# refresh) -- `detail` then carries the reader's own error, plus a named
# remedy when the reader identified one (codex needs_login -> "run: codex
# login"). Neither state may ever render as, or decay into, a plausible
# percentage -- see leadv2-status-surface.sh's _print_limit_line.
#
# A transition INTO `unknown` (glm or codex) also appends one
# [SUPERVISE-URGENT] QUOTA_UNKNOWN line to the existing pulse log (the same
# seam leadv2-writes-overlap.sh uses), so a dead probe surfaces as an active
# alarm via render_alarms()'s "urgent: N (4h)" count, not only a passive
# render change a human has to go looking for. Edge-triggered on the
# previous .kv state, not fired every refresh tick, to avoid log spam
# across a sustained outage.
#
# Env:
#   LEADV2_LIMITS_CACHE_DIR   default: ~/.claude/cache/leadv2-limits.d
#   LEADV2_LIMITS_TTL_GLM/CLAUDE/CODEX/KIMI   override per-provider TTL seconds
#   LEADV2_QUOTA_LIVE_SH       override path to leadv2-quota-live.sh (tests)
#   LEADV2_RATELIMIT_PROBE_SH  override path to leadv2-ratelimit-probe.sh (tests)
#   LEADV2_STATUS_CODEX_LOCKOUT override path to codex-lockout.state -- read
#                               by leadv2-codex-lockout.sh (N7E-SURFACE-
#                               DISAGREES), the SAME file codex-task.sh's
#                               launch gate consults. Live again: the codex
#                               row now checks lockout memory first, before
#                               the live-quota read.
#   LEADV2_CODEX_LOCKOUT_SH    override path to leadv2-codex-lockout.sh (tests)
#   LEADV2_LIMITS_SNAPSHOT_COMPAT  legacy snapshot path for one-time seed
#                                  (default ~/.claude/cache/leadv2-limits-snapshot.txt)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_LIVE="${LEADV2_QUOTA_LIVE_SH:-${SCRIPT_DIR}/leadv2-quota-live.sh}"
PROBE="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPT_DIR}/leadv2-ratelimit-probe.sh}"
CODEX_LOCKOUT_SH="${LEADV2_CODEX_LOCKOUT_SH:-${SCRIPT_DIR}/leadv2-codex-lockout.sh}"
CACHE_DIR="${LEADV2_LIMITS_CACHE_DIR:-${HOME}/.claude/cache/leadv2-limits.d}"
BURN_DB="${LEADV2_BURN_DB:-${HOME}/.claude/burn/history.db}"
SNAPSHOT_COMPAT="${LEADV2_LIMITS_SNAPSHOT_COMPAT:-${HOME}/.claude/cache/leadv2-limits-snapshot.txt}"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(pwd)}}}"
STATE_PATH_SH="${LEADV2_STATE_PATH_SH:-${SCRIPT_DIR}/leadv2-state-path.sh}"

PROVIDER="all"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="${2:-all}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    *)          printf 'Usage: leadv2-limits-refresh.sh [--provider glm|claude|codex|kimi|all] [--force]\n' >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE_DIR" 2>/dev/null || true

_ttl_for() {
  case "$1" in
    glm)    printf '%s' "${LEADV2_LIMITS_TTL_GLM:-90}" ;;
    claude) printf '%s' "${LEADV2_LIMITS_TTL_CLAUDE:-90}" ;;
    codex)  printf '%s' "${LEADV2_LIMITS_TTL_CODEX:-300}" ;;
    kimi)   printf '%s' "${LEADV2_LIMITS_TTL_KIMI:-86400}" ;;
    *)      printf '90' ;;
  esac
}

_write_kv() {
  # $1=provider $2=state $3=value $4=detail
  local provider="$1" state="$2" value="$3" detail="${4:-}" f tmp now ttl
  f="${CACHE_DIR}/${provider}.kv"
  tmp="${f}.tmp.$$"
  now="$(date +%s)"
  ttl="$(_ttl_for "$provider")"
  {
    printf 'state=%s\n' "$state"
    printf 'value=%s\n' "$value"
    printf 'stamped=%s\n' "$now"
    printf 'ttl=%s\n' "$ttl"
    printf 'detail=%s\n' "$detail"
  } > "$tmp"
  mv -f "$tmp" "$f"
}

_prev_kv_state() {
  # $1=provider -- last-written state, "" if no .kv yet. Read BEFORE
  # _write_kv overwrites the file, so callers can edge-trigger on transition.
  local provider="$1" f
  f="${CACHE_DIR}/${provider}.kv"
  [ -f "$f" ] || return 0
  sed -n 's/^state=//p' "$f" | head -1
}

_fire_quota_unknown_pulse() {
  # A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01 req 3: an unknown reading gets
  # an ACTIVE signal too, not just a passive render change -- reusing the
  # EXISTING [SUPERVISE-URGENT] pulse-log seam (same pattern as
  # leadv2-writes-overlap.sh's notify block), already surfaced on the human
  # status line via render_alarms()'s "urgent: N (4h)" count. No new
  # notification mechanism. Fires only on the transition INTO unknown --
  # callers gate this on _prev_kv_state so a sustained outage doesn't spam
  # one line per refresh tick (TTL as low as 90s).
  local provider="$1" detail="$2" pulse_log
  pulse_log="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"
  if [ -x "$STATE_PATH_SH" ]; then
    pulse_log="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link supervise-loop.log 2>/dev/null || printf '%s' "$pulse_log")"
  fi
  printf -- '%s [SUPERVISE-URGENT] QUOTA_UNKNOWN provider=%s detail=%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$provider" "$detail" >> "$pulse_log" 2>/dev/null || true
}

_lock_and_run() {
  # $1=provider $2=refresher-function-name
  local provider="$1" fn="$2" lock lock_age
  lock="${CACHE_DIR}/.lock.${provider}"
  if [ "$FORCE" -eq 0 ] && mkdir "$lock" 2>/dev/null; then
    : # acquired
  elif [ -d "$lock" ]; then
    lock_age=999999
    if command -v stat >/dev/null 2>&1; then
      lock_age=$(( $(date +%s) - $( [[ "$(uname -s)" == "Darwin" ]] && stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0) ))
    fi
    if [ "$lock_age" -lt 180 ]; then
      return 0
    fi
    rmdir "$lock" 2>/dev/null || true
    mkdir "$lock" 2>/dev/null || return 0
  else
    mkdir "$lock" 2>/dev/null || true
  fi
  "$fn"
  rmdir "$lock" 2>/dev/null || true
}

_refresh_glm() {
  local json pct reset st err val detail
  json=""
  if [ -x "$QUOTA_LIVE" ]; then
    json="$(bash "$QUOTA_LIVE" --no-cache glm 2>/dev/null || true)"
  fi
  st="unavailable"; val=""
  if [ -n "$json" ]; then
    read -r st pct reset err <<EOF
$(LEADV2_LR_JSON="$json" python3 -c '
import json, os
try:
    d = json.loads(os.environ["LEADV2_LR_JSON"])
    if d.get("status") == "ok":
        w = d.get("weekly") or {}
        print("ok", w.get("pct", ""), w.get("reset_iso", ""), "-")
    else:
        # See A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01 note in _refresh_codex:
        # the reader answered and said unknown -- keep that a third state, not
        # a synonym for "helper never ran".
        e = str(d.get("error") or "probe failed").replace(" ", "_") or "probe_failed"
        print("unknown", "-", "-", e)
except Exception:
    print("unavailable", "-", "-", "-")
' 2>/dev/null || printf 'unavailable  \n')
EOF
  fi
  if [ "$st" = "ok" ] && [ -n "$pct" ]; then
    val="weekly ${pct}% (сброс ${reset}) [live]"
    _write_kv glm ok "$val" ""
  elif [ "$st" = "unknown" ]; then
    detail="$(printf '%s' "$err" | tr '_' ' ')"
    detail="${detail:-probe failed}"
    [ "$(_prev_kv_state glm)" != "unknown" ] && _fire_quota_unknown_pulse glm "$detail"
    _write_kv glm unknown "" "$detail"
  else
    _write_kv glm unavailable "" "z.ai quota read failed (leadv2-quota-live.sh glm)"
  fi
}

_refresh_claude() {
  local kv_raw st five_pct seven_pct five_reset seven_reset detail val
  if [ -x "$PROBE" ]; then
    bash "$PROBE" >/dev/null 2>&1 || true
  fi
  kv_raw=""
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$BURN_DB" ]; then
    kv_raw="$(sqlite3 "$BURN_DB" "SELECT value FROM kv WHERE key='rate_limit_anthropic' ORDER BY rowid DESC LIMIT 1;" 2>/dev/null || true)"
  fi
  if [ -z "$kv_raw" ]; then
    _write_kv claude unavailable "" "no rate_limit_anthropic kv row yet (probe never ran)"
    return 0
  fi
  read -r st five_pct five_reset seven_pct seven_reset detail <<EOF
$(LEADV2_LR_KV="$kv_raw" python3 -c '
import json, os
try:
    d = json.loads(os.environ["LEADV2_LR_KV"])
    state = d.get("state", "unavailable")
    if state != "ok":
        print("unauthenticated" if state == "unauthenticated" else "unavailable",
              "", "", "", "", (d.get("detail") or "probe reported non-ok state").replace(" ", "_"))
    else:
        def fmt(t):
            if not t: return ""
            return t.split("T")[1][:5] if "T" in t else t
        print("ok", d.get("five_hour_pct",""), fmt(d.get("five_hour_reset_iso","")),
              d.get("seven_day_pct",""), fmt(d.get("seven_day_reset_iso","")), "-")
except Exception as e:
    print("unavailable", "", "", "", "", "parse_error")
' 2>/dev/null || printf 'unavailable      parse_error\n')
EOF
  detail="$(printf '%s' "$detail" | tr '_' ' ')"
  if [ "$st" = "ok" ] && [ -n "$five_pct" ]; then
    if [ -n "$seven_pct" ]; then
      val="5h ${five_pct}% (сброс ${five_reset}) · weekly ${seven_pct}% (сброс ${seven_reset})"
    else
      val="5h ${five_pct}% (сброс ${five_reset})"
    fi
    _write_kv claude ok "$val" ""
  elif [ "$st" = "unauthenticated" ]; then
    _write_kv claude unauthenticated "" "нет валидного OAuth-токена для probe → ~/ccswitch.sh"
  else
    _write_kv claude unavailable "" "${detail:-anthropic quota probe failed}"
  fi
}

_refresh_codex() {
  # N7E-SURFACE-DISAGREES: lockout memory dominates -- it refuses
  # unconditionally, so it is checked FIRST, before any live-quota read. This
  # is the same source codex-task.sh's launch gate consults (codex-task.sh:98,
  # 271-286); leadv2-codex-lockout.sh duplicates the parse (bonded by
  # tests/test-codex-lockout-agreement.sh) since codex-task.sh is off limits
  # this lane. `state=ok` on a lockout is correct: `ok` means "we know the
  # answer" (a lockout is known), `unavailable` means "we could not read".
  local lk lk_until
  lk=""
  if [ -x "$CODEX_LOCKOUT_SH" ]; then
    lk="$(bash "$CODEX_LOCKOUT_SH" 2>/dev/null || true)"
  fi
  case "$lk" in
    locked\ *)
      lk_until="${lk#locked }"
      _write_kv codex ok "lockout до ${lk_until}" ""
      return 0
      ;;
  esac

  local json st used reset err remedy val detail
  json=""
  if [ -x "$QUOTA_LIVE" ]; then
    json="$(bash "$QUOTA_LIVE" --no-cache codex 2>/dev/null || true)"
  fi
  st="unavailable"
  if [ -n "$json" ]; then
    read -r st used reset err remedy <<EOF
$(LEADV2_LR_JSON="$json" python3 -c '
import json, os
try:
    d = json.loads(os.environ["LEADV2_LR_JSON"])
    if d.get("status") == "ok":
        w = (d.get("windows") or [{}])[0]
        print("ok", "1" if w.get("limit_reached") else "0", w.get("reset_iso", ""), "-", "-")
    else:
        # A-DEAD-INSTRUMENT-MUST-ANNOUNCE-ITSELF-01: the reader answered
        # (it is not "no attempt made") and said it could not measure --
        # this is the THIRD state (unknown), never collapsed into the
        # generic "unavailable" a caller reaches when the helper itself
        # never ran. Carry the real error and, when the reader named a
        # remedy (401-on-refresh -> needs_login), carry that too so the
        # render side can say what fixes it instead of just "unknown".
        e = str(d.get("error") or "probe failed").replace(" ", "_") or "probe_failed"
        r = "codex_login" if d.get("needs_login") else "-"
        print("unknown", "-", "-", e, r)
except Exception:
    print("unavailable", "-", "-", "-", "-")
' 2>/dev/null || printf 'unavailable  \n')
EOF
  fi
  case "$st" in
    ok)
      if [ "$used" = "1" ]; then
        val="lockout до ${reset}"
      else
        val="доступен"
      fi
      _write_kv codex ok "$val" ""
      ;;
    unknown)
      # State is `unknown`, distinct from `unavailable`: the probe ANSWERED
      # and said it could not measure (e.g. HTTP 401 on token refresh) --
      # never rendered as a plausible percentage, and the remedy (when the
      # reader named one) travels with it instead of being silently dropped.
      err="$(printf '%s' "$err" | tr '_' ' ')"
      remedy="$(printf '%s' "$remedy" | tr '_' ' ')"
      detail="${err:-probe failed}"
      [ "$remedy" != "-" ] && [ -n "$remedy" ] && detail="${detail} — run: ${remedy}"
      [ "$(_prev_kv_state codex)" != "unknown" ] && _fire_quota_unknown_pulse codex "$detail"
      _write_kv codex unknown "" "$detail"
      ;;
    *)
      _write_kv codex unavailable "" "codex quota read failed (leadv2-quota-live.sh codex)"
      ;;
  esac
}

_refresh_kimi() {
  _write_kv kimi ok "quota API отсутствует (free-tier TokenRouter)" ""
}

# One-time compat seed from the legacy snapshot file, read-only, never
# deletes it. Only used when a provider's .kv is still missing entirely.
_seed_from_legacy() {
  local provider="$1" f
  f="${CACHE_DIR}/${provider}.kv"
  [ -f "$f" ] && return 0
  [ -f "$SNAPSHOT_COMPAT" ] || return 0
  case "$provider" in
    glm)
      local gline gwk
      gline="$(grep '^  glm weekly' "$SNAPSHOT_COMPAT" 2>/dev/null | head -1 || true)"
      gwk="$(printf '%s' "$gline" | sed -n 's/.*(live, z.ai): \([0-9][0-9]*\)%.*/\1/p')"
      [ -n "$gwk" ] && _write_kv glm ok "weekly ${gwk}% (legacy seed) [live]" "seeded from legacy snapshot"
      ;;
  esac
}

case "$PROVIDER" in
  glm)    _lock_and_run glm _refresh_glm ;;
  claude) _lock_and_run claude _refresh_claude ;;
  codex)  _lock_and_run codex _refresh_codex ;;
  kimi)   [ -f "${CACHE_DIR}/kimi.kv" ] || _lock_and_run kimi _refresh_kimi ;;
  all)
    _lock_and_run glm _refresh_glm
    _lock_and_run claude _refresh_claude
    _lock_and_run codex _refresh_codex
    [ -f "${CACHE_DIR}/kimi.kv" ] || _lock_and_run kimi _refresh_kimi
    ;;
  *) printf 'Usage: leadv2-limits-refresh.sh [--provider glm|claude|codex|kimi|all] [--force]\n' >&2; exit 2 ;;
esac

for p in glm claude codex kimi; do
  _seed_from_legacy "$p"
done

exit 0
