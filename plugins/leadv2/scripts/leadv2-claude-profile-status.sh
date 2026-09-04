#!/usr/bin/env bash
# leadv2-claude-profile-status.sh — TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 D3
#
# The multi-profile selector (leadv2-claude-profile-select.sh) is fail-open
# everywhere by design: opt-out unset, missing/malformed registry, fewer than
# two valid entries, or an exhausted probe budget all silently fall back to
# the single inherited account. That is the right default AND it means "we
# silently went back to one account" is the expected failure mode, not an
# exotic one. Today the only trace is `candidates=` buried in a per-dispatch
# claude-profile.log nobody reads. This script answers, in one run: are both
# accounts live and being used RIGHT NOW, and has recent routing quietly
# degraded to one account.
#
# Two checks, independent of each other:
#   1. LIVE — runs the real selector this instant (same code path
#      claude-subsession.sh uses) and reports its candidate count.
#   2. RECENT — scans this repo's own docs/handoff/*/claude-profile.log for
#      how many of the last N dispatch records show a degraded selection
#      (candidates=1, single-profile fallback, or no selector line at all).
#      Scope: THIS repo's own handoff history only (each repo dispatches and
#      journals independently even though the account registry is shared
#      user-level) — run it from the repo you want visibility into, or point
#      LEADV2_CLAUDE_PROFILE_STATUS_HANDOFF_DIR at another repo's docs/handoff.
#
# Exit code: 0 when both checks are healthy, 1 when either is degraded, 2 on
# a usage/environment fault (never on ordinary fail-open — same convention as
# the selector and its gates: a fault reports "unknown", it never claims
# health it could not verify).
#
# Root resolution: git, never ../ hops (this repo's own standing rule —
# GATE-WRONG-ROOT-FALSE-DEAD-01). This script is itself a per-file symlink
# into every consumer repo's .claude/scripts/, so `dirname "${BASH_SOURCE[0]}"`
# is a REAL directory in whichever repo invoked it even though the file
# inside it is a symlink; `git rev-parse --show-toplevel` from there returns
# that repo's own root, not leadv2's.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECT_BIN="${LEADV2_CLAUDE_PROFILE_STATUS_SELECT_BIN:-$SCRIPT_DIR/leadv2-claude-profile-select.sh}"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
HANDOFF_DIR="${LEADV2_CLAUDE_PROFILE_STATUS_HANDOFF_DIR:-${REPO_ROOT:+$REPO_ROOT/docs/handoff}}"
RECENT_N="${LEADV2_CLAUDE_PROFILE_STATUS_RECENT_N:-50}"

degraded=0
faulted=0

# ---- 1. LIVE -----------------------------------------------------------
check_live() { # sets global: degraded, faulted (may raise either to 1)
  if [[ "${LEADV2_CLAUDE_MULTIPROFILE:-}" != "1" ]]; then
    echo "live:    OFF -- LEADV2_CLAUDE_MULTIPROFILE is not \"1\" in this shell; every dispatch launched from it runs single-account (inert by design, not a fault)"
    return
  fi
  if [[ ! -r "$SELECT_BIN" ]]; then
    echo "live:    UNKNOWN -- selector not found at $SELECT_BIN"
    faulted=1
    return
  fi
  local live_out cands
  live_out="$(LEADV2_CLAUDE_MULTIPROFILE=1 bash "$SELECT_BIN" 2>/dev/null)"
  cands="$(printf '%s' "$live_out" | sed -n 's/.*candidates=\([0-9][0-9]*\).*/\1/p')"
  if [[ -z "$live_out" ]]; then
    echo "live:    OFF -- selector produced no line (opt-out or inert path)"
  elif [[ "$cands" -ge 2 ]] 2>/dev/null; then
    echo "live:    OK -- $live_out"
  elif [[ "$live_out" == profile=-\ reason=* ]]; then
    local reason="${live_out#profile=- reason=}"
    echo "live:    DEGRADED -- fell back ($reason): $live_out"
    degraded=1
  else
    echo "live:    DEGRADED -- candidates=${cands:-0} (need >=2 for two-account routing): $live_out"
    degraded=1
  fi
}

# ---- 2. RECENT -----------------------------------------------------------
check_recent() { # sets global: degraded, faulted (may raise either to 1)
  if [[ -z "$REPO_ROOT" ]]; then
    echo "recent:  UNKNOWN -- not inside a git repo, cannot locate docs/handoff"
    faulted=1
    return
  fi
  if [[ ! -d "$HANDOFF_DIR" ]]; then
    echo "recent:  UNKNOWN -- no $HANDOFF_DIR in this repo yet (no dispatches recorded)"
    return
  fi
  # Newest-first, bounded to RECENT_N so this never scales with the archive.
  # No xargs: an archive with hundreds of handoff dirs overflows its arg list
  # on some platforms; a plain -print0 | while read loop has no such limit.
  local logs
  logs="$(
    find "$HANDOFF_DIR" -maxdepth 2 -name 'claude-profile.log' -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do
          mt="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)"
          printf '%s\t%s\n' "${mt:-0}" "$f"
        done \
      | sort -rn | head -n "$RECENT_N" | cut -f2-
  )"
  local scanned=0 ok=0 deg=0 last_deg="" log line
  while IFS= read -r log; do
    [[ -n "$log" ]] || continue
    scanned=$((scanned + 1))
    line="$(tail -1 "$log" 2>/dev/null)"
    if printf '%s' "$line" | grep -qE 'candidates=[2-9]'; then
      ok=$((ok + 1))
    else
      deg=$((deg + 1))
      last_deg="$log: $line"
    fi
  done <<EOF_LOGS
$logs
EOF_LOGS
  if [[ "$scanned" -eq 0 ]]; then
    echo "recent:  UNKNOWN -- no claude-profile.log files under $HANDOFF_DIR"
  elif [[ "$deg" -eq 0 ]]; then
    echo "recent:  OK -- $ok/$scanned of the last $scanned dispatches selected with candidates>=2"
  else
    local pct=$(( deg * 100 / scanned ))
    echo "recent:  DEGRADED -- $deg/$scanned of the last $scanned dispatches (${pct}%) did not see two live candidates"
    echo "         last: $last_deg"
    degraded=1
  fi
}

echo "=== leadv2 claude multi-profile status ==="
check_live
check_recent
echo "==="
if [[ "$faulted" -eq 1 ]]; then
  echo "VERDICT: UNKNOWN (environment fault above -- not a health claim)"
  exit 2
elif [[ "$degraded" -eq 1 ]]; then
  echo "VERDICT: DEGRADED -- two-account routing is not fully in effect right now"
  exit 1
else
  echo "VERDICT: OK -- both accounts live and in active use"
  exit 0
fi
