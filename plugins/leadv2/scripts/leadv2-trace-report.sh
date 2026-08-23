#!/usr/bin/env bash
# leadv2-trace-report.sh — reader for LEADV2_TRACE=1 NDJSON traces (Mission B,
# docs/handoff/dispatch-f72c8c9c). Prints per-span p50/p95/max/count and a
# per-trace lane total, plus a noise-floor footer for spans whose typical
# duration is dominated by the instrument's own cost.
#
# Usage: leadv2-trace-report.sh [<trace-dir-or-file>] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_BIN="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR}/leadv2-state-path.sh}"

JSON=0
TARGET=""
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    *) TARGET="$a" ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  TARGET="$("$STATE_PATH_BIN" --no-link traces 2>/dev/null || true)"
fi

if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
  echo "[trace-report] no trace data found at '${TARGET:-<unresolved>}'" >&2
  exit 1
fi

python3 - "$TARGET" "$JSON" <<'PYEOF'
import json, os, sys, glob

target, json_mode = sys.argv[1], sys.argv[2] == "1"

if os.path.isdir(target):
    files = sorted(glob.glob(os.path.join(target, "*.ndjson")))
else:
    files = [target]

spans = {}          # span -> list of durations_ms
instrument = {}      # span -> list of instrument_ns
unterminated = {}    # span -> count of begins without a matching end
lane_totals = {}     # trace_id -> total duration_ms of the "lane" span
child_totals = {}    # trace_id -> sum of all non-lane span durations
malformed = 0
open_spans = {}       # trace_id -> stack depth heuristic (per span name)

for f in files:
    try:
        fh = open(f, "r", errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except (ValueError, TypeError):
                malformed += 1
                continue
            span = rec.get("span", "?")
            dur = rec.get("duration_ms")
            instr = rec.get("instrument_ns", 0)
            tid = rec.get("trace_id", "?")
            if not isinstance(dur, (int, float)):
                malformed += 1
                continue
            spans.setdefault(span, []).append(dur)
            instrument.setdefault(span, []).append(instr or 0)
            if span == "lane":
                lane_totals[tid] = lane_totals.get(tid, 0) + dur
            else:
                child_totals[tid] = child_totals.get(tid, 0) + dur

def percentile(sorted_vals, pct):
    n = len(sorted_vals)
    if n == 0:
        return None
    if n < 5:
        return sorted_vals[-1]
    idx = max(0, min(n - 1, int(round(pct / 100.0 * n)) - 1))
    return sorted_vals[idx]

report = {"spans": {}, "traces": {}, "malformed_lines": malformed}

for span, vals in sorted(spans.items()):
    vals_sorted = sorted(vals)
    n = len(vals_sorted)
    p50 = percentile(vals_sorted, 50)
    p95 = percentile(vals_sorted, 95)
    vmax = vals_sorted[-1]
    instr_avg = sum(instrument.get(span, [0])) / max(1, len(instrument.get(span, [1])))
    report["spans"][span] = {
        "count": n,
        "p50_ms": round(p50, 3) if p50 is not None else None,
        "p95_ms": round(p95, 3) if p95 is not None else None,
        "max_ms": round(vmax, 3),
        "instrument_ms_avg": round(instr_avg / 1e6, 3),
        "raw_sample": n < 5,
    }

for tid in sorted(set(list(lane_totals.keys()) + list(child_totals.keys()))):
    report["traces"][tid] = {
        "lane_ms": round(lane_totals.get(tid, 0), 3),
        "child_span_ms_sum": round(child_totals.get(tid, 0), 3),
    }

noise_floor = []
for span, s in report["spans"].items():
    p50 = s["p50_ms"]
    instr_ms = s["instrument_ms_avg"]
    if p50 is not None and instr_ms > 0 and p50 < 10 * instr_ms:
        noise_floor.append(span)

if json_mode:
    print(json.dumps(report, indent=2, sort_keys=True))
else:
    print(f"{'span':<20} {'count':>6} {'p50_ms':>10} {'p95_ms':>10} {'max_ms':>10} {'instr_ms':>10}")
    for span, s in sorted(report["spans"].items()):
        note = " (raw)" if s["raw_sample"] else ""
        print(f"{span:<20} {s['count']:>6} {s['p50_ms']:>10} {s['p95_ms']:>10} {s['max_ms']:>10} {s['instrument_ms_avg']:>10}{note}")
    print()
    print(f"{'trace_id':<28} {'lane_ms':>12} {'child_span_ms_sum':>18}  unattributed_ms")
    for tid, t in sorted(report["traces"].items()):
        unattributed = round(t["lane_ms"] - t["child_span_ms_sum"], 3) if t["lane_ms"] else None
        print(f"{tid:<28} {t['lane_ms']:>12} {t['child_span_ms_sum']:>18}  {unattributed}")
    print()
    if malformed:
        print(f"malformed_lines: {malformed} (skipped, not fatal)")
    if noise_floor:
        print("measurement below instrument noise floor; do not draw conclusions for: " + ", ".join(sorted(noise_floor)))
PYEOF
