#!/usr/bin/env python3
"""Compares Δquota-pct/token across Anthropic's two nested meters (5h, 7d),
for ONE account, on the SAME intervals -- the check
ANTHROPIC-PRICE-OR-A-REASON-WE-CANNOT-HAVE-ONE-01 item 3 asked for: does the
target variable a drain-weights fit reads (one window's percentage) move at
a consistent rate per token, or does it depend on which window, how close
that window is to reset, or which meter is currently binding?

This is a comparison tool, not a fitter: it prints ratios and rates, never a
weight, and never touches router_v2.cost.

rate_limit_history stores five_hour_pct AND seven_day_pct on every row (both
meters are read every snapshot regardless of which one is currently
`binding_window`), so unlike leadv2-drain-weights.py this tool does not need
a --window flag: both series come from the same rows, so a paired
per-interval comparison is possible without re-sampling.

Method, and its limits (reported, never hidden):
  - An interval is dropped from the paired comparison if the 5h window reset
    inside it (five_hour_reset_epoch changed) -- a resetting window's Δpct
    is not a rate, exactly per leadv2-drain-weights.py's dropped_reset logic,
    just applied to the 5h column specifically (the 7d column has its own,
    much rarer, reset check via seven_day_pct never observed to go negative
    in the fixtures this tool was built against).
  - "clean" intervals additionally require tokens > 0: a zero-token interval
    can never contribute a per-token rate.
  - zero_token_nonzero_delta counts intervals where THIS account attributed
    no tokens at all yet at least one of the two percentages still moved --
    the shared-account confound item 4 of the mission names explicitly.
    other_account_explains counts how many of those are covered by another
    account_key's turn_events in the same wall-clock span (0 means the
    movement has no attribution anywhere in this database, from any known
    account -- a real unattributed-drain measurement, not an assumption).

Usage: leadv2-anthropic-window-compare.py [--db PATH] [--account KEY]
  --account defaults to the derived live key (sha256_8(realpath(CLAUDE_CONFIG_DIR))).
  --db defaults to ~/.claude/burn/history.db (or $LEADV2_BURN_DB).

Output: one k=v summary line, then a per-window rate line for 5h and 7d,
then a ratio line, then up to 3 time-to-reset tertile bucket lines (only
when enough clean intervals exist), then the unattributed-drain line.
"""
import bisect
import datetime
import importlib.util
import os
import sqlite3
import statistics
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
_spec = importlib.util.spec_from_file_location(
    "leadv2_quota_read", os.path.join(HERE, "leadv2-quota-read.py"))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
account_key_for_config_dir = _mod.account_key_for_config_dir

MIN_CLEAN_FOR_TERTILES = 6


def _ts_to_epoch(ts):
    try:
        return datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _tokens_in_range(events_sorted_epochs, events_sorted, e0, e1):
    lo = bisect.bisect_right(events_sorted_epochs, e0)
    hi = bisect.bisect_right(events_sorted_epochs, e1)
    return sum(t for _e, t in events_sorted[lo:hi]), events_sorted[lo:hi]


def main(argv):
    db, account = None, None
    args = argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--db" and i + 1 < len(args):
            db = args[i + 1]
            i += 2
        elif args[i] == "--account" and i + 1 < len(args):
            account = args[i + 1]
            i += 2
        else:
            print("usage: leadv2-anthropic-window-compare.py [--db PATH] [--account KEY]",
                  file=sys.stderr)
            return 2
    if not account:
        account = account_key_for_config_dir(
            os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
    if not db:
        db = os.path.expanduser(
            os.environ.get("LEADV2_BURN_DB", "~/.claude/burn/history.db"))
    if not os.path.exists(db):
        print("account=%s NOT-ENOUGH-DATA (db absent: %s)" % (account, db))
        return 0

    conn = sqlite3.connect(db, timeout=5)
    try:
        conn.execute("PRAGMA busy_timeout=3000")
        snaps = conn.execute(
            "SELECT captured_epoch, five_hour_pct, seven_day_pct, five_hour_reset_epoch "
            "FROM rate_limit_history WHERE account_key=? AND state='ok' "
            "AND five_hour_pct IS NOT NULL AND seven_day_pct IS NOT NULL "
            "ORDER BY captured_epoch", (account,)).fetchall()
        own_events = []
        all_events = []
        try:
            for ts, _m, inp, outp, acct in conn.execute(
                    "SELECT ts, model, input, output, account_key FROM turn_events"):
                e = _ts_to_epoch(ts)
                if e is None:
                    continue
                tok = int(inp or 0) + int(outp or 0)
                all_events.append((e, acct, tok))
                if acct == account:
                    own_events.append((e, tok))
        except sqlite3.Error as exc:
            print("account=%s NOT-ENOUGH-DATA (turn_events unreadable: %s)" % (account, exc))
            return 0
    finally:
        conn.close()

    own_events.sort()
    other_events = sorted((e, t) for e, a, t in all_events if a != account)
    own_epochs = [e for e, _t in own_events]
    other_epochs = [e for e, _t in other_events]

    seen, clean_snaps = set(), []
    for e, p5, p7, r5 in snaps:
        if e in seen:
            continue
        seen.add(e)
        clean_snaps.append((e, p5, p7, r5))

    intervals_total = 0
    tokened_intervals = 0
    clean_rows = []       # (e0, e1, tok, d5, d7, ttr5)
    zero_tok_rows = []    # (e0, e1, d5, d7)
    for (e0, p50, p70, r50), (e1, p51, p71, r51) in zip(clean_snaps, clean_snaps[1:]):
        intervals_total += 1
        tok, _span = _tokens_in_range(own_epochs, own_events, e0, e1)
        d5, d7 = p51 - p50, p71 - p70
        reset5 = r51 != r50
        if tok == 0:
            if d5 != 0 or d7 != 0:
                zero_tok_rows.append((e0, e1, d5, d7))
            continue
        tokened_intervals += 1
        if reset5 or d5 < 0 or d7 < 0:
            continue
        ttr5 = (r50 - e0) if r50 is not None else None
        clean_rows.append((e0, e1, tok, d5, d7, ttr5))

    print("account=%s intervals_total=%d tokened_intervals=%d clean_intervals=%d "
          "zero_token_nonzero_delta=%d"
          % (account, intervals_total, tokened_intervals, len(clean_rows), len(zero_tok_rows)))

    if len(clean_rows) < 1:
        print("clean_intervals<1 NOT-ENOUGH-DATA for a window-rate comparison")
    else:
        r5 = [d5 / tok for _e0, _e1, tok, d5, _d7, _ttr in clean_rows]
        r7 = [d7 / tok for _e0, _e1, tok, _d5, d7, _ttr in clean_rows]
        print("window=5h clean=%d mean_pct_per_token=%.10g stdev=%.10g"
              % (len(r5), statistics.mean(r5), statistics.pstdev(r5) if len(r5) > 1 else 0.0))
        print("window=7d clean=%d mean_pct_per_token=%.10g stdev=%.10g"
              % (len(r7), statistics.mean(r7), statistics.pstdev(r7) if len(r7) > 1 else 0.0))

        ratios = [a / b for a, b in zip(r5, r7) if b != 0]
        if ratios:
            print("ratio_5h_over_7d n=%d mean=%.6g stdev=%.6g min=%.6g max=%.6g"
                  % (len(ratios), statistics.mean(ratios),
                     statistics.pstdev(ratios) if len(ratios) > 1 else 0.0,
                     min(ratios), max(ratios)))
        else:
            print("ratio_5h_over_7d n=0 NOT-ENOUGH-DATA (no interval had d7!=0)")

        ttr_rows = [r for r in clean_rows if r[5] is not None]
        if len(ttr_rows) >= MIN_CLEAN_FOR_TERTILES:
            ttr_sorted = sorted(ttr_rows, key=lambda r: r[5])
            n = len(ttr_sorted)
            third = n // 3
            buckets = (("near_reset", ttr_sorted[:third]),
                       ("mid", ttr_sorted[third:2 * third]),
                       ("far_from_reset", ttr_sorted[2 * third:]))
            for name, b in buckets:
                tok_sum = sum(r[2] for r in b)
                d5_sum = sum(r[3] for r in b)
                d7_sum = sum(r[4] for r in b)
                print("ttr_bucket=%s n=%d tokens=%d d5pct_per_token=%.10g d7pct_per_token=%.10g"
                      % (name, len(b), tok_sum,
                         d5_sum / tok_sum if tok_sum else float("nan"),
                         d7_sum / tok_sum if tok_sum else float("nan")))
        else:
            print("ttr_buckets NOT-ENOUGH-DATA (need >=%d clean intervals with a known "
                  "five_hour_reset_epoch, have %d)" % (MIN_CLEAN_FOR_TERTILES, len(ttr_rows)))

    if zero_tok_rows:
        explained = 0
        for e0, e1, _d5, _d7 in zero_tok_rows:
            other_tok, _span = _tokens_in_range(other_epochs, other_events, e0, e1)
            if other_tok > 0:
                explained += 1
        print("unattributed_drain zero_token_intervals=%d explained_by_other_account=%d "
              "unexplained=%d" % (len(zero_tok_rows), explained,
                                   len(zero_tok_rows) - explained))
    else:
        print("unattributed_drain zero_token_intervals=0")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
