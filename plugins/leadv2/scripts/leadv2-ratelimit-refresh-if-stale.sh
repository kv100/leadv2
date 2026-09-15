#!/usr/bin/env bash
# leadv2-ratelimit-refresh-if-stale.sh — QUOTA-PROVIDER-SIGNAL-GOES-STALE-01
#
# The gauge (leadv2-quota-status.sh) already prefers the kv row
# `rate_limit_anthropic` (Anthropic's own rate_limit_info) over its heuristic
# cap -- but only while that row is fresher than its own freshness window.
# Nothing refreshed it on a cadence, so in normal operation it decayed past
# the window and every reader silently fell back to a heuristic calibrated
# once, on 2026-08-17, on a max_20x account -- now ~4x too generous on the
# default_claude_max_5x accounts both slots read as. Founder decision
# 2026-09-15: make the provider signal STAY readable; do not retune the caps.
#
# This is the refresh-on-read seam: a reader (leadv2-quota-status.sh) calls
# this, unconditionally, before it reads the kv row. Cheap when fresh (one
# sqlite3 SELECT, no lock, no subprocess) -- it only pays the cost of an
# actual probe run once per LEADV2_RATELIMIT_FRESH_SECS window.
#
# Three properties, each with its own test + negative control
# (tests/test-ratelimit-refresh-if-stale.sh):
#   1. No stampede: an atomic `mkdir` lock. Up to 8 lanes can call this
#      concurrently; exactly one runs the probe, the rest see the lock held
#      and return immediately (they read whatever is already there --
#      correct either way, since the winner is about to make it fresh).
#   2. A failed refresh must not look like a fresh reading: the row's PRE-
#      refresh bytes are snapshotted before the probe runs. If the probe's
#      OWN write leaves `status` != "ok" (its unauth() fallback -- no
#      credential, quota-live.sh crashed, malformed JSON, ...), this script
#      restores the pre-refresh row verbatim (or deletes it, if there was no
#      prior row) so `captured_epoch` never advances on a failure. A reader
#      then sees exactly what it would have seen had the refresh never been
#      attempted -- never "there was nothing to read" being confused with
#      "I could not read it".
#   3. No daemon: this is a plain script called from an existing read path.
#      Nothing to install, nothing to remove.
#
# Never touches leadv2-ratelimit-probe.sh's own kv-write contract -- that
# contract is relied on by leadv2-limits-refresh.sh's SwiftBar-facing
# _refresh_claude (which reads `state`, not freshness) and by
# tests/test-leadv2-ratelimit-probe.sh. This script only ever intervenes
# AFTER the probe has already written, and only to undo a failed attempt.
#
# Usage: leadv2-ratelimit-refresh-if-stale.sh
# Env:
#   LEADV2_BURN_DB               default: ~/.claude/burn/history.db
#   LEADV2_RATELIMIT_PROBE_SH    override path to leadv2-ratelimit-probe.sh (tests)
#   LEADV2_RATELIMIT_FRESH_SECS  default 600 -- MUST match the reader's own
#                                 freshness window (leadv2-quota-status.sh
#                                 RL_FRESH_SECS) or the two will disagree
#                                 about what "fresh" means.
#   LEADV2_RATELIMIT_LOCK_DIR    default: ~/.claude/cache/leadv2-limits.d
#   LEADV2_RATELIMIT_LOCK_STALE_SECS  default 60 -- a lock dir older than
#                                 this is presumed orphaned (crashed holder)
#                                 and stolen; the probe itself is a single
#                                 short-lived process, so 60s is generous.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SH="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPT_DIR}/leadv2-ratelimit-probe.sh}"
BURN_DB="${LEADV2_BURN_DB:-${HOME}/.claude/burn/history.db}"
FRESH_SECS="${LEADV2_RATELIMIT_FRESH_SECS:-600}"
LOCK_DIR="${LEADV2_RATELIMIT_LOCK_DIR:-${HOME}/.claude/cache/leadv2-limits.d}"
LOCK_STALE_SECS="${LEADV2_RATELIMIT_LOCK_STALE_SECS:-60}"
KEY="rate_limit_anthropic"

command -v sqlite3 >/dev/null 2>&1 || exit 0

_kv_read() {  # -> raw JSON value, or "" if absent
  sqlite3 "$BURN_DB" "SELECT value FROM kv WHERE key='$KEY' ORDER BY rowid DESC LIMIT 1;" 2>/dev/null || true
}

_kv_epoch() {  # $1=raw -> captured_epoch, or "" if unparseable
  printf '%s' "$1" | sed -n 's/.*"captured_epoch"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1
}

_kv_status() {  # $1=raw -> status, or "" if unparseable
  printf '%s' "$1" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_is_fresh() {  # $1=raw -> 0 fresh, 1 not
  local raw="$1" status epoch now
  [ -n "$raw" ] || return 1
  status="$(_kv_status "$raw")"
  [ "$status" = "ok" ] || return 1
  epoch="$(_kv_epoch "$raw")"
  case "$epoch" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date -u +%s)"
  [ $(( now - epoch )) -lt "$FRESH_SECS" ]
}

# 0. Already fresh? Nothing to do -- the common case, cheap.
OLD_RAW="$(_kv_read)"
if _is_fresh "$OLD_RAW"; then
  exit 0
fi

# 1. No stampede -- atomic mkdir lock, one refresh not eight.
mkdir -p "$LOCK_DIR" 2>/dev/null || true
LOCK="${LOCK_DIR}/.lock.ratelimit-kv"
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_age=999999
  if command -v stat >/dev/null 2>&1; then
    lock_age=$(( $(date +%s) - $( [ "$(uname -s)" = "Darwin" ] && stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  fi
  if [ "$lock_age" -lt "$LOCK_STALE_SECS" ]; then
    # Someone else is refreshing right now -- don't wait, don't stampede.
    exit 0
  fi
  # Orphaned lock (holder crashed mid-refresh) -- steal it.
  rmdir "$LOCK" 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# Double-check under the lock: another lane may have refreshed while we
# were racing for it.
OLD_RAW="$(_kv_read)"
if _is_fresh "$OLD_RAW"; then
  exit 0
fi

# 2. Run the probe. It writes the kv row itself (see its own header) --
#    on ANY outcome, success or failure, per its existing contract.
[ -x "$PROBE_SH" ] && bash "$PROBE_SH" >/dev/null 2>&1
: # probe failures are swallowed by design (its own contract) -- we judge
  # the row it left behind, not its exit code.

NEW_RAW="$(_kv_read)"
NEW_STATUS="$(_kv_status "$NEW_RAW")"

if [ "$NEW_STATUS" = "ok" ]; then
  # Real, fresh, usable capture -- leave it exactly as the probe wrote it.
  exit 0
fi

# Failed refresh (no credential resolved / quota-live.sh crashed / malformed
# JSON / ...): the probe still wrote a row with a NEW captured_epoch -- undo
# that so a failed refresh never looks like a fresh one. Restore the
# pre-refresh row verbatim if one existed, else leave the row fully absent
# (exactly as if this refresh attempt had never run).
if [ -n "$OLD_RAW" ]; then
  LEADV2_RRS_OLD="$OLD_RAW" python3 - "$BURN_DB" <<'PYEOF' 2>/dev/null || true
import os, sqlite3, sys
db = sys.argv[1]
old = os.environ["LEADV2_RRS_OLD"]
conn = sqlite3.connect(db, timeout=5)
try:
    conn.execute("PRAGMA busy_timeout=3000")
    conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)", (old,))
    conn.commit()
finally:
    conn.close()
PYEOF
else
  python3 - "$BURN_DB" <<'PYEOF' 2>/dev/null || true
import sqlite3, sys
db = sys.argv[1]
conn = sqlite3.connect(db, timeout=5)
try:
    conn.execute("PRAGMA busy_timeout=3000")
    conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("DELETE FROM kv WHERE key='rate_limit_anthropic'")
    conn.commit()
finally:
    conn.close()
PYEOF
fi

exit 0
