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
#   state=ok|unavailable|unauthenticated
#   value=<already-rendered display string>
#   stamped=<epoch>
#   ttl=<seconds>
#   detail=<one-line text, optional>
#
# Env:
#   LEADV2_LIMITS_CACHE_DIR   default: ~/.claude/cache/leadv2-limits.d
#   LEADV2_LIMITS_TTL_GLM/CLAUDE/CODEX/KIMI   override per-provider TTL seconds
#   LEADV2_QUOTA_LIVE_SH       override path to leadv2-quota-live.sh (tests)
#   LEADV2_RATELIMIT_PROBE_SH  override path to leadv2-ratelimit-probe.sh (tests)
#   LEADV2_STATUS_CODEX_LOCKOUT override path to codex-lockout.state (unused
#                               now that codex reads leadv2-quota-live.sh --
#                               kept only as a legacy-compat detail note)
#   LEADV2_LIMITS_SNAPSHOT_COMPAT  legacy snapshot path for one-time seed
#                                  (default ~/.claude/cache/leadv2-limits-snapshot.txt)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_LIVE="${LEADV2_QUOTA_LIVE_SH:-${SCRIPT_DIR}/leadv2-quota-live.sh}"
PROBE="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPT_DIR}/leadv2-ratelimit-probe.sh}"
CACHE_DIR="${LEADV2_LIMITS_CACHE_DIR:-${HOME}/.claude/cache/leadv2-limits.d}"
BURN_DB="${LEADV2_BURN_DB:-${HOME}/.claude/burn/history.db}"
SNAPSHOT_COMPAT="${LEADV2_LIMITS_SNAPSHOT_COMPAT:-${HOME}/.claude/cache/leadv2-limits-snapshot.txt}"

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

_lock_and_run() {
  # $1=provider $2=refresher-function-name
  local provider="$1" fn="$2" lock lock_age
  lock="${CACHE_DIR}/.lock.${provider}"
  if [ "$FORCE" -eq 0 ] && mkdir "$lock" 2>/dev/null; then
    : # acquired
  elif [ -d "$lock" ]; then
    lock_age=999999
    if command -v stat >/dev/null 2>&1; then
      lock_age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0) ))
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
  local json pct reset st val
  json=""
  if [ -x "$QUOTA_LIVE" ]; then
    json="$(bash "$QUOTA_LIVE" --no-cache glm 2>/dev/null || true)"
  fi
  st="unavailable"; val=""
  if [ -n "$json" ]; then
    read -r st pct reset <<EOF
$(LEADV2_LR_JSON="$json" python3 -c '
import json, os
try:
    d = json.loads(os.environ["LEADV2_LR_JSON"])
    if d.get("status") != "ok":
        print("unavailable", "", "")
    else:
        w = d.get("weekly") or {}
        print("ok", w.get("pct", ""), w.get("reset_iso", ""))
except Exception:
    print("unavailable", "", "")
' 2>/dev/null || printf 'unavailable  \n')
EOF
  fi
  if [ "$st" = "ok" ] && [ -n "$pct" ]; then
    val="weekly ${pct}% (сброс ${reset}) [live]"
    _write_kv glm ok "$val" ""
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
  local json st used reset val
  json=""
  if [ -x "$QUOTA_LIVE" ]; then
    json="$(bash "$QUOTA_LIVE" --no-cache codex 2>/dev/null || true)"
  fi
  st="unavailable"
  if [ -n "$json" ]; then
    read -r st used reset <<EOF
$(LEADV2_LR_JSON="$json" python3 -c '
import json, os
try:
    d = json.loads(os.environ["LEADV2_LR_JSON"])
    if d.get("status") != "ok":
        print("unavailable", "", "")
    else:
        w = (d.get("windows") or [{}])[0]
        print("ok", "1" if w.get("limit_reached") else "0", w.get("reset_iso", ""))
except Exception:
    print("unavailable", "", "")
' 2>/dev/null || printf 'unavailable  \n')
EOF
  fi
  if [ "$st" = "ok" ]; then
    if [ "$used" = "1" ]; then
      val="lockout до ${reset}"
    else
      val="доступен (lockout истёк $(date -u +%Y-%m-%dT%H:%M:%SZ))"
    fi
    _write_kv codex ok "$val" ""
  else
    _write_kv codex unavailable "" "codex quota read failed (leadv2-quota-live.sh codex)"
  fi
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
