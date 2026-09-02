#!/usr/bin/env bash
# scripts/leadv2-spawn-rate.sh — STATUS-CHURN-01 acceptance instrument.
#
# Prints, for the last N minutes (default 15), child-process starts per
# minute by script name plus p50/p95 wall time -- the before/after numbers
# for the "one status snapshot per cadence" fix. Two sources, combined:
#
#   1. status_snapshot journal lines written by
#      scripts/lib/leadv2-status-cache.sh (hit|miss|recompute, one per call)
#      -- gives exact call counts per producer AND, for `recompute` events,
#      real compute wall time is NOT in the journal (the journal only knows
#      about the cache layer, not the process runtime), so wall time comes
#      from source 2.
#   2. `ps` sampling every 10s while this script runs, bucketed by the
#      leading `leadv2-*` script-name token of each matching command line --
#      this is the same sampling method the ticket's own read-only samples
#      used (66-92% of a core each, short-lived).
#
# Usage:
#   leadv2-spawn-rate.sh [--window-min N] [--sample-secs N] [--no-live-sample]
#
# --no-live-sample skips the `ps` polling loop (useful for a quick journal-only
# read, or in a test harness where a live 15-minute sample is not available).
#
# Bash 3.2 compatible: no associative arrays. Per-name buckets are kept in
# parallel-indexed lists (NAMES[] / COUNTS[] / SAMPLES[]) with a linear
# lookup -- the name cardinality here is a handful of scripts, so O(n^2) is
# fine and stays portable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}}"
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

WINDOW_MIN=15
SAMPLE_SECS=10
DO_LIVE_SAMPLE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window-min) WINDOW_MIN="$2"; shift 2 ;;
    --sample-secs) SAMPLE_SECS="$2"; shift 2 ;;
    --no-live-sample) DO_LIVE_SAMPLE=0; shift ;;
    --journal) JOURNAL_OVERRIDE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

JOURNAL_PATH="${JOURNAL_OVERRIDE:-$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link status-snapshot-journal.jsonl 2>/dev/null)}"

echo "== leadv2-spawn-rate: journal-derived call counts (status_snapshot cache layer) =="
if [[ -n "$JOURNAL_PATH" && -f "$JOURNAL_PATH" ]]; then
  python3 - "$JOURNAL_PATH" "$WINDOW_MIN" <<'PY'
import json
import sys
import time
from collections import defaultdict

path, window_min = sys.argv[1], float(sys.argv[2])
cutoff = time.time() - window_min * 60.0
by_producer = defaultdict(lambda: {"hit": 0, "miss": 0, "recompute": 0})
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("event") != "status_snapshot":
                continue
            if d.get("ts", 0) < cutoff:
                continue
            producer = d.get("producer", "unknown")
            kind = d.get("kind", "unknown")
            by_producer[producer][kind] = by_producer[producer].get(kind, 0) + 1
except FileNotFoundError:
    pass

if not by_producer:
    print("  (no status_snapshot journal lines in the last %.0f min)" % window_min)
else:
    print("  %-32s %8s %8s %10s %14s" % ("producer", "hit", "miss", "recompute", "calls/min"))
    total_calls = 0
    for producer in sorted(by_producer):
        counts = by_producer[producer]
        calls = counts.get("hit", 0) + counts.get("miss", 0) + counts.get("recompute", 0)
        total_calls += calls
        print("  %-32s %8d %8d %10d %14.2f" % (
            producer, counts.get("hit", 0), counts.get("miss", 0),
            counts.get("recompute", 0), calls / window_min,
        ))
    print("  ---")
    print("  TOTAL cache calls/min across all producers: %.2f" % (total_calls / window_min))
PY
else
  echo "  (no journal found at ${JOURNAL_PATH:-<unresolved>} -- run with the cache in use, or pass --journal <path>)"
fi

echo
if [[ "$DO_LIVE_SAMPLE" -eq 0 ]]; then
  echo "== live ps sampling skipped (--no-live-sample) =="
  exit 0
fi

echo "== live ps sampling: leadv2-* child-process starts, every ${SAMPLE_SECS}s for ${WINDOW_MIN} min =="
SAMPLE_LOG="$(mktemp)"
trap 'rm -f "$SAMPLE_LOG"' EXIT
END_TS=$(( $(date +%s) + WINDOW_MIN * 60 ))
while [[ "$(date +%s)" -lt "$END_TS" ]]; do
  NOW_TS="$(date +%s)"
  # etimes = elapsed seconds since start -- used as a rough per-sample wall
  # time proxy for short-lived scans (this is a snapshot, not a true
  # per-process start/end trace; see header comment).
  ps -Ao comm=,etimes= 2>/dev/null | grep -E 'leadv2-(broad-status|status-collector|lanes-snapshot|lane-liveness|lane-status-line-tail|pulse-beat|lane-detail)' | while read -r comm etimes; do
    base="$(basename "$comm" 2>/dev/null || echo "$comm")"
    printf '%s %s %s\n' "$NOW_TS" "$base" "$etimes" >> "$SAMPLE_LOG"
  done
  sleep "$SAMPLE_SECS"
done

python3 - "$SAMPLE_LOG" "$WINDOW_MIN" <<'PY'
import sys
from collections import defaultdict

path, window_min = sys.argv[1], float(sys.argv[2])
by_name = defaultdict(list)
try:
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 3:
                continue
            _, name, etimes = parts
            try:
                by_name[name].append(float(etimes))
            except Exception:
                continue
except FileNotFoundError:
    pass

if not by_name:
    print("  (no leadv2-* processes observed in this sampling window)")
else:
    print("  %-32s %10s %10s %10s" % ("script", "samples", "p50(s)", "p95(s)"))
    for name in sorted(by_name):
        vals = sorted(by_name[name])
        n = len(vals)
        p50 = vals[int(0.50 * (n - 1))]
        p95 = vals[int(0.95 * (n - 1))]
        print("  %-32s %10d %10.2f %10.2f" % (name, n, p50, p95))
    print()
    print("  Note: 'samples' counts ps-poll observations of a live process,")
    print("  not distinct process starts (a long-lived process is sampled")
    print("  repeatedly); this matches the ticket's own read-only ps-instant")
    print("  methodology, not a wrapper-instrumented exec count.")
PY
