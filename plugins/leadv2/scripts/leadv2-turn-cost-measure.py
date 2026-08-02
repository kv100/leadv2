#!/usr/bin/env python3
"""Measure per-turn context cost from Claude session transcripts.

Derives the three context-tier turn-thresholds for hooks/leadv2-compact-warn.sh.

Per-turn context size at a founder turn =
    input_tokens + cache_read_input_tokens + cache_creation_input_tokens
taken from the NEXT assistant record following that founder turn (that is the
request whose context *reflects* having loaded the turn's state). A founder
turn is a `type=="user"` record whose message.content is NOT a tool_result
list (i.e. genuine human/async input, not a tool return).

Two-parameter linear model on the filtered interactive sample:
    b = median context at turn 1 (session-start baseline)
    m = median per-turn slope, fit over turns 1..P, P = p90 of per-session max-turn
    C = working ceiling = p95 of per-session peak context

Tier turn-thresholds = the turn at which median context crosses a fraction of C:

    T(x) = ceil( (x*C - b) / m )

    mild x=0.45   aggressive x=0.65   emergency x=0.80

The fractions are a RULE, not picked numbers:
  0.45 = still over half the window free, trimming is cheap and non-disruptive
  0.65 = under a third free, cheap trimming no longer closes the gap
  0.80 = one large tool result from the wall

Filter: only interactive sessions (max_turn >= 10). Headless 1-turn subagent
runs dominate the tree by count and would otherwise yield n~2 per bucket and a
garbage median. Print n per turn bucket and refuse to derive below a stated
minimum; on a too-thin sample, fall back to fractions of the DOCUMENTED context
ceiling with the same rule, labelled as such.

Usage: leadv2-turn-cost-measure.py [--root DIR] [--min-turn N] [--documented-ceiling TOKENS]
       DIR defaults to ~/.claude/projects
"""
from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def _is_founder_turn(user_rec: dict) -> bool:
    """A user record is a founder turn iff its content is NOT a tool_result list."""
    msg = user_rec.get("message") or {}
    content = msg.get("content")
    if isinstance(content, list):
        # tool_result records are content=[{"type":"tool_result", ...}]
        return False
    # string content (or anything else) = genuine input
    return True


def _ctx_of(usage: dict) -> int:
    if not usage:
        return 0
    return (
        (usage.get("input_tokens") or 0)
        + (usage.get("cache_read_input_tokens") or 0)
        + (usage.get("cache_creation_input_tokens") or 0)
    )


def scan_session(path: Path) -> tuple[list[int], int] | None:
    """Return (per-founder-turn context sizes, peak context) or None if unreadable.

    Turn N's context = the FIRST assistant request after founder turn N (that is
    the request whose context reflects having loaded turn N's state). Peak context
    is the max over ALL assistant records in the session.
    """
    try:
        fh = path.open("r", encoding="utf-8", errors="replace")
    except Exception:
        return None

    turn_ctx: dict[int, int] = {}   # turn_number -> context (first assistant after it)
    global_turn = 0
    pending = False
    peak = 0
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            rtype = rec.get("type")
            if rtype == "user" and _is_founder_turn(rec):
                global_turn += 1
                pending = True
            elif rtype == "assistant":
                usage = (rec.get("message") or {}).get("usage")
                ctx = _ctx_of(usage or {})
                if ctx > peak:
                    peak = ctx
                if pending:
                    turn_ctx[global_turn] = ctx
                    pending = False
    if not turn_ctx:
        return None
    # dense list indexed by turn number (1-based)
    out = [turn_ctx.get(i, 0) for i in range(1, global_turn + 1)]
    return out, peak


def percentile(sorted_vals: list, p: float) -> float:
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    k = (len(sorted_vals) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(sorted_vals[int(k)])
    return float(sorted_vals[f] + (sorted_vals[c] - sorted_vals[f]) * (k - f))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--min-turn", type=int, default=10,
                    help="interactive-session filter: per-session max_turn >= this")
    ap.add_argument("--documented-ceiling", type=int, default=1000000,
                    help="documented context window for fallback derivation")
    ap.add_argument("--min-sessions-at-30", type=int, default=10,
                    help="refuse to derive unless >= this many sessions reach turn 30")
    ap.add_argument("--min-bucket", type=int, default=20,
                    help="slope fit uses only turn buckets with >= this many sessions "
                         "(excludes the giant-session-dominated tail where compaction "
                         "resets make per-turn context non-monotonic)")
    args = ap.parse_args()

    root = Path(args.root).expanduser()
    files = sorted(root.rglob("*.jsonl"))
    total_files = len(files)

    per_session_turns: list[list[int]] = []
    per_session_peak: list[int] = []
    interactive_turn_ctx: dict[int, list[int]] = defaultdict(list)

    per_session_slopes: list[float] = []
    EARLY = 12  # turns 1..EARLY define each session's pre-compact linear region

    for f in files:
        res = scan_session(f)
        if res is None:
            continue
        turn_ctx, peak = res
        per_session_turns.append(turn_ctx)
        per_session_peak.append(peak)
        if len(turn_ctx) >= args.min_turn:
            for idx, ctx in enumerate(turn_ctx, start=1):
                interactive_turn_ctx[idx].append(ctx)
            # per-session early-region slope (genuine linear growth, pre-compact)
            pts = [(i, turn_ctx[i - 1]) for i in range(1, min(EARLY + 1, len(turn_ctx) + 1))
                   if turn_ctx[i - 1] > 0]
            if len(pts) >= 4:
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                mx = sum(xs) / len(xs)
                my = sum(ys) / len(ys)
                num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
                den = sum((x - mx) ** 2 for x in xs)
                if den > 0:
                    s = num / den
                    if 1000 < s < 60000:  # sane per-turn growth band
                        per_session_slopes.append(s)

    n_sessions = len(per_session_turns)
    max_turns = [len(t) for t in per_session_turns]
    median_max = statistics.median(max_turns) if max_turns else 0

    print("=" * 72)
    print("LEADV2 TURN-COST MEASUREMENT")
    print("=" * 72)
    print(f"root scanned              : {root}")
    print(f"transcripts found         : {total_files}")
    print(f"sessions parsed (usable)  : {n_sessions}")
    print(f"median per-session max-turn: {median_max}")
    print(f"interactive filter        : max_turn >= {args.min_turn}")
    n_interactive = sum(1 for t in max_turns if t >= args.min_turn)
    print(f"interactive sessions kept : {n_interactive}")

    # per-turn bucket medians on the interactive sample
    print("\nper-turn context (interactive sample only):")
    print(f"{'turn':>6} {'n':>6} {'median':>12} {'p75':>12}")
    for turn in sorted(interactive_turn_ctx):
        vals = sorted(interactive_turn_ctx[turn])
        if not vals:
            continue
        med = int(statistics.median(vals))
        p75 = int(percentile(vals, 0.75))
        print(f"{turn:>6} {len(vals):>6} {med:>12,} {p75:>12,}")

    # P = p90 of per-session max-turn in interactive sample
    interactive_max = sorted(t for t in max_turns if t >= args.min_turn)
    P = int(percentile(interactive_max, 0.90)) if interactive_max else 0
    print(f"\nP (p90 of interactive max-turn): {P}")

    # refusal check: sessions reaching turn 30
    n_at_30 = len(interactive_turn_ctx.get(30, []))
    # also count distinct interactive sessions with >=30 turns
    n_sess_30 = sum(1 for t in max_turns if t >= 30)
    print(f"sessions reaching turn 30 : {n_sess_30}")

    thin = n_sess_30 < args.min_sessions_at_30

    # b = median context at turn 1 (interactive)
    t1 = sorted(interactive_turn_ctx.get(1, []))
    b = int(statistics.median(t1)) if t1 else 0

    # slope m: MEDIAN of per-session early-region slopes.
    #
    # Why per-session, not a fit on aggregate per-turn medians over turns 1..P:
    # the upper tail of the interactive sample is dominated by sessions that have
    # ALREADY compacted (the 80-turn guard fires, /compact runs, context resets to
    # ~baseline). Their per-turn context at turn N is low and non-monotonic, so an
    # aggregate fit over the full 1..P range yields a NEGATIVE slope (verified:
    # m=-120 over 1..127) — it describes post-compact sessions, not growth.
    #
    # The defensible unit of growth is the PER-SESSION slope over its own early
    # pre-compact linear region (turns 1..12, where cache + added context climb
    # near-linearly and no compaction has occurred). Taking the median across
    # sessions is robust to the few giant multi-compact outliers. This slope
    # predicts how fast context climbs toward the ceiling BEFORE any compaction
    # intervenes — exactly the regime the tier guard must warn in.
    if len(per_session_slopes) >= 10:
        m = statistics.median(per_session_slopes)
    else:
        m = 0.0
    slopes_sorted = sorted(per_session_slopes)

    # C = p95 of per-session peak (interactive sample peaks)
    interactive_peaks = sorted(
        pk for turns, pk in zip(per_session_turns, per_session_peak)
        if len(turns) >= args.min_turn
    )
    C = int(percentile(interactive_peaks, 0.95)) if interactive_peaks else 0

    print("\n" + "-" * 72)
    print("DERIVED PARAMETERS")
    print("-" * 72)

    fractions = {"mild": 0.45, "aggressive": 0.65, "emergency": 0.80}
    rule_note = (
        "0.45 = still over half the window free, trimming is cheap and "
        "non-disruptive; 0.65 = under a third free, cheap trimming no longer "
        "closes the gap; 0.80 = one large tool result from the wall."
    )

    if thin:
        print(f"SAMPLE TOO THIN (only {n_sess_30} sessions reach turn 30; "
              f"need >= {args.min_sessions_at_30}).")
        print("Missing: more long interactive sessions to fit a stable slope.")
        print("FALLBACK: deriving from DOCUMENTED context ceiling.")
        C_use = args.documented_ceiling
        # b/m still used if available; if m<=0 use a coarse slope estimate
        if m <= 0:
            print("Slope m unavailable; using a coarse default slope of "
                  "documented-ceiling/60 per turn to make thresholds defined.")
            m_use = C_use / 60.0
        else:
            m_use = m
        print(f"  documented ceiling C  : {C_use:,}")
        print(f"  baseline b (turn 1)   : {b:,}"
              + ("" if t1 else "  [no turn-1 data; b=0]"))
        print(f"  slope m (tok/turn)    : {m_use:,.0f}")
        print(f"  T(x) = ceil((x*{C_use:,} - {b:,}) / {m_use:,.0f})")
        print(f"\nFRACTION RULE: {rule_note}\n")
        for name, x in fractions.items():
            target = x * C_use
            T = math.ceil((target - b) / m_use) if m_use > 0 else 0
            if T < 1:
                T = 1
            print(f"  LEADV2_COMPACT_TIER_{name.upper():<10} = {T:>4}"
                  f"   (x={x}, target={int(target):,})")
        print("\nNOTE: these are FALLBACK thresholds from the documented ceiling,")
        print("not from a measured slope. Re-run after more interactive sessions.")
        return 0

    print(f"  b = median context at turn 1 : {b:,}")
    print(f"  m = median per-session slope : {m:,.0f} tok/turn  "
          f"(n={len(slopes_sorted)} sessions, turns 1..{EARLY}; "
          f"p25={int(percentile(slopes_sorted, 0.25)):,}, "
          f"p75={int(percentile(slopes_sorted, 0.75)):,})")
    print(f"  C = p95 of per-session peak  : {C:,}  "
          f"(p99={int(percentile(interactive_peaks, 0.99)):,}, "
          f"max={max(interactive_peaks) if interactive_peaks else 0:,})")
    print(f"  T(x) = ceil((x*C - b) / m)")
    print(f"\nFRACTION RULE (authored, not picked): {rule_note}\n")
    for name, x in fractions.items():
        target = x * C
        T = math.ceil((target - b) / m) if m > 0 else 0
        if T < 1:
            T = 1
        print(f"  LEADV2_COMPACT_TIER_{name.upper():<10} = {T:>4}"
              f"   (x={x}, target={int(target):,}; "
              f"({int(target):,} - {b:,}) / {m:,.0f} = {T})")
    print("\nRe-runnable: thresholds are recomputed from this script's output.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
