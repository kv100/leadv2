#!/usr/bin/env bash
# leadv2-quota-window-history.sh — QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01 D6/D7
#
# Secondary consumer of rate_limit_history (written by leadv2-ratelimit-probe.sh).
# The arbiter's hot-path read is a single indexed row lookup per account_key
# (see the probe script's header for that contract); this script is for
# retrospective comparison — e.g. did the 2026-09-15 Max 20x -> Max 5x
# downgrade actually move which window binds for the SAME account_key.
#
# Second consumer: TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01's independent-
# quota assumption. TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 answers "are these
# two Claude accounts independent" at the level of IDENTITY (distinct
# accountUuid) — an inference. This table answers it at the level of
# CONSUMPTION: with rate_limit_history partitioned by account_key, a spend on
# one account that leaves the other account's five_hour_pct/seven_day_pct
# unmoved is readable directly from recorded probes via `--account KEY`
# (already implemented below — ACCOUNT_FILTER on account_key, applied to
# every query in the pipeline), with no experiment staged.
#
# Usage: leadv2-quota-window-history.sh [--days N] [--account KEY] [--json]
# Env:   LEADV2_BURN_DB  default: ~/.claude/burn/history.db
#
# Prints a coverage line, then falls back to "INSUFFICIENT HISTORY -- <n>
# samples over <d>d" (exit 0) when span < 7 days or samples < 50 — never a
# confident-looking table from a laptop that has barely run.

set -euo pipefail

BURN_DB="${LEADV2_BURN_DB:-${HOME}/.claude/burn/history.db}"
DAYS=14
ACCOUNT=""
JSON_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      DAYS="${2:-}"; shift 2 ;;
    --days=*)
      DAYS="${1#--days=}"; shift ;;
    --account)
      ACCOUNT="${2:-}"; shift 2 ;;
    --account=*)
      ACCOUNT="${1#--account=}"; shift ;;
    --json)
      JSON_MODE=1; shift ;;
    -h|--help)
      echo "usage: leadv2-quota-window-history.sh [--days N] [--account KEY] [--json]" >&2
      exit 0 ;;
    *)
      echo "leadv2-quota-window-history.sh: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*)
    echo "leadv2-quota-window-history.sh: --days must be a non-negative integer, got '${DAYS}'" >&2
    exit 2
    ;;
esac

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "leadv2-quota-window-history.sh: sqlite3 not found" >&2
  exit 1
fi

if [ ! -f "$BURN_DB" ]; then
  echo "no history yet (no burn db at ${BURN_DB})"
  exit 0
fi

HAS_TABLE="$(sqlite3 "$BURN_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='rate_limit_history';" 2>/dev/null || true)"
if [ -z "$HAS_TABLE" ]; then
  echo "no history yet (rate_limit_history table absent)"
  exit 0
fi

ACCOUNT_FILTER=""
if [ -n "$ACCOUNT" ]; then
  ESC_ACCOUNT="$(printf '%s' "$ACCOUNT" | sed "s/'/''/g")"
  ACCOUNT_FILTER="AND account_key = '${ESC_ACCOUNT}'"
fi

COVERAGE="$(sqlite3 -separator '|' "$BURN_DB" "
SELECT COUNT(*), COALESCE(MIN(captured_epoch),0), COALESCE(MAX(captured_epoch),0)
  FROM rate_limit_history
 WHERE captured_epoch >= strftime('%s','now') - (${DAYS} * 86400) ${ACCOUNT_FILTER};
")"

SAMPLES="$(printf '%s' "$COVERAGE" | cut -d'|' -f1)"
MIN_EP="$(printf '%s' "$COVERAGE" | cut -d'|' -f2)"
MAX_EP="$(printf '%s' "$COVERAGE" | cut -d'|' -f3)"

SPAN_D=0
if [ "$MIN_EP" != "0" ] && [ "$MAX_EP" != "0" ]; then
  SPAN_D=$(( (MAX_EP - MIN_EP) / 86400 ))
fi

if [ "$SPAN_D" -lt 7 ] || [ "$SAMPLES" -lt 50 ]; then
  echo "INSUFFICIENT HISTORY — ${SAMPLES} samples over ${SPAN_D}d"
  exit 0
fi

echo "coverage: ${SAMPLES} samples, ${SPAN_D}d span (min_epoch=${MIN_EP} max_epoch=${MAX_EP})"

# Dwell cap 1800s = 2x the probe's default heartbeat (900s, see
# leadv2-ratelimit-probe.sh LEADV2_RATELIMIT_HISTORY_HEARTBEAT_S) — the
# anti-lying clause: a laptop asleep 12h must not score as 12h of dwell in
# whichever window was binding right before sleep.
QUERY="
WITH s AS (
  SELECT captured_epoch, state, account_key, binding_window, five_hour_pct, seven_day_pct,
         CASE binding_window
           WHEN 'five_hour' THEN five_hour_pct
           WHEN 'seven_day' THEN seven_day_pct
           ELSE NULL
         END AS window_pct,
         LEAD(captured_epoch) OVER (PARTITION BY account_key ORDER BY captured_epoch) AS next_epoch
    FROM rate_limit_history
   WHERE captured_epoch >= strftime('%s','now') - (${DAYS} * 86400) ${ACCOUNT_FILTER}
), w AS (
  SELECT *, MIN(COALESCE(next_epoch - captured_epoch, 0), 1800) AS dwell
    FROM s WHERE state = 'ok'
), agg AS (
  SELECT account_key,
         COALESCE(binding_window,'(none)')                             AS window,
         COUNT(*)                                                      AS samples,
         SUM(dwell)                                                    AS dwell_s,
         ROUND(100.0*SUM(dwell)/NULLIF(SUM(SUM(dwell)) OVER (PARTITION BY account_key),0),1) AS dwell_pct
    FROM w GROUP BY account_key, window
)
-- Peak-with-timestamp per (account_key, window): a correlated nested
-- SELECT * FROM (SELECT ... ORDER BY <pct> DESC, captured_epoch DESC LIMIT 1)
-- per output row -- NEVER an un-nested ORDER BY/LIMIT on a compound SELECT,
-- which binds to the whole compound instead of one branch (bug trap this
-- comment exists to name).
SELECT agg.account_key, agg.window, agg.samples, agg.dwell_s, agg.dwell_pct,
       (SELECT peak_pct FROM (
          SELECT window_pct AS peak_pct FROM w
           WHERE w.account_key = agg.account_key
             AND COALESCE(w.binding_window,'(none)') = agg.window
           ORDER BY w.window_pct DESC, w.captured_epoch DESC LIMIT 1
       ))                                                               AS peak_pct,
       (SELECT peak_epoch FROM (
          SELECT captured_epoch AS peak_epoch FROM w
           WHERE w.account_key = agg.account_key
             AND COALESCE(w.binding_window,'(none)') = agg.window
           ORDER BY w.window_pct DESC, w.captured_epoch DESC LIMIT 1
       ))                                                               AS peak_epoch
  FROM agg ORDER BY agg.account_key, agg.dwell_s DESC;
"

if [ "$JSON_MODE" -eq 1 ]; then
  sqlite3 -json "$BURN_DB" "$QUERY"
else
  sqlite3 -header -column "$BURN_DB" "$QUERY"
fi
