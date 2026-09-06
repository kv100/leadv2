#!/usr/bin/env bash
# leadv2-active-cache.sh — 5-second cache for active.yaml parsing (PO-064)
#
# Usage (source this file or call the function):
#   source ~/.claude/hooks/leadv2-active-cache.sh
#   leadv2_read_active_yaml "$ACTIVE_YAML_PATH"
#   # Sets global: ACTIVE_TASK_ID, ACTIVE_PHASE
#
# Cache: ~/.claude/state/leadv2/active.cache
#   Format (plain text, 2 lines): task_id\nphase
#
# Invalidation: age > 5s OR active.yaml newer than cache file.
# Thread-safe for concurrent hooks: atomic write via mktemp+mv.

LEADV2_STATE_DIR="${LEADV2_ACTIVE_CACHE_STATE_DIR:-${HOME}/.claude/state/leadv2}"
LEADV2_ACTIVE_CACHE="${LEADV2_STATE_DIR}/active.cache"
LEADV2_ACTIVE_CACHE_TTL=5   # seconds

leadv2_read_active_yaml() {
  local active_yaml="${1:-}"
  ACTIVE_TASK_ID=""
  ACTIVE_PHASE=""

  [[ -z "$active_yaml" || ! -f "$active_yaml" ]] && return 0

  # ── Check cache validity ────────────────────────────────────────────────────
  local use_cache=0
  if [[ -f "$LEADV2_ACTIVE_CACHE" ]]; then
    local cache_mtime yaml_mtime now
    # macOS stat: -f %m; Linux stat: -c %Y — support both
    if stat --version >/dev/null 2>&1; then
      # GNU stat (Linux)
      cache_mtime=$(stat -c %Y "$LEADV2_ACTIVE_CACHE" 2>/dev/null || echo 0)
      yaml_mtime=$(stat -c %Y "$active_yaml" 2>/dev/null || echo 0)
    else
      # BSD stat (macOS)
      cache_mtime=$(stat -f %m "$LEADV2_ACTIVE_CACHE" 2>/dev/null || echo 0)
      yaml_mtime=$(stat -f %m "$active_yaml" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    local age=$(( now - cache_mtime ))
    if [[ "$age" -lt "$LEADV2_ACTIVE_CACHE_TTL" && "$yaml_mtime" -le "$cache_mtime" ]]; then
      use_cache=1
    fi
  fi

  if [[ "$use_cache" -eq 1 ]]; then
    ACTIVE_TASK_ID="$(sed -n '1p' "$LEADV2_ACTIVE_CACHE" 2>/dev/null || echo "")"
    ACTIVE_PHASE="$(sed -n '2p' "$LEADV2_ACTIVE_CACHE" 2>/dev/null || echo "")"
    return 0
  fi

  # ── Cache miss: parse and re-cache ─────────────────────────────────────────
  # D2-M4: bare `os.kill(pid, 0)` has three answers, not two -- ESRCH is dead,
  # but EPERM means the pid EXISTS (owned by someone else, e.g. a leadv2
  # watcher reparented to ppid=1) and a bare kill(0)==0 also does not prove
  # the pid is THIS session's own worker (a recycled pid onto an interactive
  # claude session reads as alive for hours -- brief #9/#14). Route through
  # leadv2-lane-liveness.sh's --all --json (single batched call, same active
  # .yaml this function already reads) instead of a raw per-session kill(0)
  # loop: its pid_alive field already carries the ESRCH/EPERM split and the
  # process-kind check.
  local liveness_bin="${LEADV2_LANE_LIVENESS_BIN:-${LEADV2_PLUGIN_SCRIPTS_DIR:-}}"
  local liveness_json=""
  if [[ -z "${liveness_bin}" ]]; then
    # Resolve relative to this hook's own location: hooks/ sits beside
    # scripts/ under the plugin root.
    local _hook_dir; _hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    liveness_bin="${_hook_dir}/../scripts/leadv2-lane-liveness.sh"
  fi
  if [[ -x "${liveness_bin}" ]]; then
    local _proj_root; _proj_root="$(dirname "$(dirname "${active_yaml}")")"
    liveness_json="$(LEADV2_PROJECT_ROOT="${_proj_root}" bash "${liveness_bin}" \
      --project-root "${_proj_root}" --all --json 2>/dev/null || true)"
  fi
  local parse_out
  parse_out="$(python3 -c "
import yaml, sys, json
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
    s = d.get('sessions') or []
    alive_by_lane = {}
    liveness_raw = sys.argv[2]
    if liveness_raw:
        try:
            for row in (json.loads(liveness_raw).get('lanes') or []):
                if isinstance(row, dict) and row.get('lane'):
                    alive_by_lane[row['lane']] = bool(row.get('pid_alive'))
        except Exception:
            alive_by_lane = {}
    live = []
    for sess in s:
        pid = sess.get('pid')
        tid = sess.get('task_id')
        if not pid:
            live.append(sess)
            continue
        # No liveness answer for this lane (empty map, or lane not covered by
        # --all's enumeration) degrades to the OLD fail-open behavior --
        # never silently drop a session this function cannot verify.
        if tid not in alive_by_lane or alive_by_lane.get(tid):
            live.append(sess)
    if live:
        print(live[0].get('task_id', ''))
        print(live[0].get('phase', ''))
    else:
        print('')
        print('')
except Exception:
    print('')
    print('')
" "$active_yaml" "$liveness_json" 2>/dev/null || printf '\n')"

  ACTIVE_TASK_ID="$(printf '%s' "$parse_out" | sed -n '1p')"
  ACTIVE_PHASE="$(printf '%s' "$parse_out" | sed -n '2p')"

  # Atomic write to cache
  mkdir -p "$LEADV2_STATE_DIR"
  local tmp
  tmp="$(mktemp "${LEADV2_ACTIVE_CACHE}.XXXXXX")"
  printf '%s\n%s\n' "$ACTIVE_TASK_ID" "$ACTIVE_PHASE" > "$tmp"
  mv -f "$tmp" "$LEADV2_ACTIVE_CACHE"

  return 0
}

# If called directly (not sourced), print the cache contents for debugging
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -f "$LEADV2_ACTIVE_CACHE" ]]; then
    echo "cache_file: $LEADV2_ACTIVE_CACHE"
    echo "task_id: $(sed -n '1p' "$LEADV2_ACTIVE_CACHE")"
    echo "phase: $(sed -n '2p' "$LEADV2_ACTIVE_CACHE")"
  else
    echo "cache_file: not found"
  fi
fi
