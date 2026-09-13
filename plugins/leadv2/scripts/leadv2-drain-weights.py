#!/usr/bin/env python3
"""NNLS fit of Δquota-pct on per-model token counts, for ONE account.

QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01: the negative result that created the
lane (scratchpad, 2026-09-13: 5h kept=18, ALL weights 0.0000, R²=-0.743; 7d
kept=10, NOT ENOUGH DATA) was not a wrong method — the data could not carry
the question: the "active" account had never metered, and turn_events had no
account key. This tool re-runs the same fit on attributed data:
rate_limit_history supplies Δpct per interval for the LIVE account (the one
the session's config dir derives to — account_key_for_config_dir, imported
from leadv2-quota-read.py), turn_events.account_key (written by
leadv2-turn-account-attribute.py) supplies per-model token counts inside each
interval.

Method, and its known limits (reported, never hidden):
  - Intervals with Δpct < 0 are window resets and are dropped (counted).
  - Intervals with Δpct == 0 AND zero attributed tokens are idle and dropped
    (counted). A zero-Δ interval WITH tokens is KEPT: spend that did not move
    the window is real information.
  - Fable intervals are EXCLUDED from the fit and counted
    (fable_intervals_excluded): Fable has TWO limits (weekly_all AND a
    Fable-scoped weekly_scoped, in addition — not instead), and one
    seven_day_pct column cannot represent both; fitting them would let
    Fable's weight absorb error from an unmodelled window.
  - Quota is metered per PROVIDER, not per model: a lead+worker dispatch mix
    that uses two models in fixed proportion is collinear and NO amount of
    clean data separates them. max_abs_corr (largest |Pearson r| between
    model token columns) is printed beside R² so a low R² can be attributed
    to collinearity rather than blamed on volume.
  - 7d structural limit: turn_events retention is 48 HOURS
    (~/.claude/burn/lib.py:8 TURN_EVENTS_RETENTION_HOURS, enforced by
    aggregator.py's retention DELETE). A 7-day fit is underdetermined BY
    CONSTRUCTION until ~7 days of attributed history exist; below
    MIN_INTERVALS the answer is NOT-ENOUGH-DATA, named as such — never a
    number this file cannot defend.

Usage: leadv2-drain-weights.py [--window 5h|7d] [--db PATH] [--account KEY]
  --account defaults to the derived live key (sha256_8(realpath(CLAUDE_CONFIG_DIR))).

Output: one k=v line (kept= r2= weights= ...), then short human diagnostics.
"""
import bisect
import datetime
import importlib.util
import math
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
_spec = importlib.util.spec_from_file_location(
    "leadv2_quota_read", os.path.join(HERE, "leadv2-quota-read.py"))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
account_key_for_config_dir = _mod.account_key_for_config_dir

MIN_INTERVALS = 12
RETENTION_LIMIT_H = 48
RETENTION_SOURCE = "~/.claude/burn/lib.py:8 TURN_EVENTS_RETENTION_HOURS"

PCT_COL = {"5h": "five_hour_pct", "7d": "seven_day_pct"}


def _ts_to_epoch(ts):
    try:
        return datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _solve_spd(A, b):
    """Gaussian elimination with partial pivoting; None when singular."""
    n = len(A)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(M[r][col]))
        if abs(M[piv][col]) < 1e-13:
            return None
        M[col], M[piv] = M[piv], M[col]
        for r in range(col + 1, n):
            f = M[r][col] / M[col][col]
            if f:
                for c in range(col, n + 1):
                    M[r][c] -= f * M[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (M[r][n] - sum(M[r][c] * x[c] for c in range(r + 1, n))) / M[r][r]
    return x


def nnls(A, b, tol=1e-12, itmax=5000):
    """Lawson–Hanson active-set NNLS. A: m×n row list, b: len m -> len n."""
    m = len(b)
    n = len(A[0]) if m else 0
    if n == 0:
        return []
    AtA = [[sum(A[i][r] * A[i][c] for i in range(m)) for c in range(n)] for r in range(n)]
    Atb = [sum(A[i][r] * b[i] for i in range(m)) for r in range(n)]
    x = [0.0] * n
    passive = [False] * n
    for _ in range(itmax):
        w = [Atb[r] - sum(AtA[r][c] * x[c] for c in range(n)) for r in range(n)]
        cand = [r for r in range(n) if not passive[r] and w[r] > tol]
        if not cand:
            break
        j = max(cand, key=lambda r: w[r])
        passive[j] = True
        for _inner in range(10 * n + 10):
            S = [r for r in range(n) if passive[r]]
            s = _solve_spd([[AtA[r][c] for c in S] for r in S],
                           [Atb[r] for r in S])
            if s is None:
                # Singular passive submatrix: release the newest member.
                passive[j] = False
                x[j] = 0.0
                break
            if min(s) > tol:
                for idx, r in enumerate(S):
                    x[r] = s[idx]
                break
            alpha = min((x[r] / (x[r] - s[idx]))
                        for idx, r in enumerate(S) if s[idx] <= tol)
            for idx, r in enumerate(S):
                x[r] += alpha * (s[idx] - x[r])
            released = False
            for idx, r in enumerate(S):
                if abs(x[r]) <= tol:
                    x[r] = 0.0
                    passive[r] = False
                    released = True
            if not released or not any(passive):
                break
    return x


def _pearson(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    da = [v - ma for v in a]
    db = [v - mb for v in b]
    num = sum(da[i] * db[i] for i in range(len(a)))
    den = math.sqrt(sum(v * v for v in da) * sum(v * v for v in db))
    if den == 0:
        return None
    return num / den


def main(argv):
    window, db, account = "5h", None, None
    args = argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--window" and i + 1 < len(args):
            window = args[i + 1]
            i += 2
        elif args[i] == "--db" and i + 1 < len(args):
            db = args[i + 1]
            i += 2
        elif args[i] == "--account" and i + 1 < len(args):
            account = args[i + 1]
            i += 2
        else:
            print("usage: leadv2-drain-weights.py [--window 5h|7d] [--db PATH] "
                  "[--account KEY]", file=sys.stderr)
            return 2
    if window not in PCT_COL:
        print("window must be 5h or 7d", file=sys.stderr)
        return 2
    if not account:
        account = account_key_for_config_dir(
            os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
    if not db:
        db = os.path.expanduser(
            os.environ.get("LEADV2_BURN_DB", "~/.claude/burn/history.db"))
    if not os.path.exists(db):
        print("window=%s account=%s kept=0 threshold=%d NOT-ENOUGH-DATA (db absent: %s)"
              % (window, account, MIN_INTERVALS, db))
        return 0

    conn = sqlite3.connect(db, timeout=5)
    try:
        conn.execute("PRAGMA busy_timeout=3000")
        col = PCT_COL[window]
        snaps = conn.execute(
            "SELECT captured_epoch, %s FROM rate_limit_history "
            "WHERE account_key=? AND state='ok' AND %s IS NOT NULL "
            "ORDER BY captured_epoch" % (col, col), (account,)).fetchall()
        events = []
        try:
            for ts, model, inp, outp in conn.execute(
                    "SELECT ts, model, input, output FROM turn_events "
                    "WHERE account_key=?", (account,)):
                e = _ts_to_epoch(ts)
                if e is None:
                    continue
                events.append((e, str(model or "unknown"),
                               int(inp or 0) + int(outp or 0)))
        except sqlite3.Error as exc:
            reason = str(exc)
            if "account_key" in reason:
                reason = ("turn_events unattributed — no account_key column; "
                          "run leadv2-turn-account-attribute.py first")
            print("window=%s account=%s kept=0 threshold=%d NOT-ENOUGH-DATA "
                  "(turn_events unreadable: %s)" % (window, account, MIN_INTERVALS, reason))
            return 0
    finally:
        conn.close()

    # Dedupe same-epoch snapshots, then cut intervals between consecutive ones.
    seen_epoch, snaps_clean = set(), []
    for e, p in snaps:
        if e in seen_epoch:
            continue
        seen_epoch.add(e)
        snaps_clean.append((e, p))
    events.sort()

    intervals, dropped_reset, dropped_idle, fable_excluded = [], 0, 0, 0
    event_epochs = [e for e, _m, _t in events]
    for (e0, p0), (e1, p1) in zip(snaps_clean, snaps_clean[1:]):
        delta = p1 - p0
        # tokens in (e0, e1]: bisect_right excludes events at exactly e0
        # (the previous interval already owns them) and includes e1.
        lo = bisect.bisect_right(event_epochs, e0)
        hi = bisect.bisect_right(event_epochs, e1)
        span = events[lo:hi]
        by_model = {}
        for _e, model, tok in span:
            by_model[model] = by_model.get(model, 0) + tok
        if delta < 0:
            dropped_reset += 1
            continue
        if any("fable" in m.lower() for m in by_model):
            fable_excluded += 1
            continue
        tokens = sum(by_model.values())
        if delta == 0 and tokens == 0:
            dropped_idle += 1
            continue
        intervals.append((delta, by_model))

    kept = len(intervals)
    base = ("window=%s account=%s kept=%d threshold=%d "
            "dropped_reset=%d dropped_idle=%d fable_intervals_excluded=%d"
            % (window, account, kept, MIN_INTERVALS, dropped_reset,
               dropped_idle, fable_excluded))
    snapshots_note = "snapshots=%d" % len(snaps_clean)
    if kept < MIN_INTERVALS:
        if window == "7d":
            print("%s NOT-ENOUGH-DATA retention_limit_h=%d (%s; "
                  "a 7-day fit is underdetermined by construction until ~7 "
                  "days of attributed history exist) %s"
                  % (base, RETENTION_LIMIT_H, RETENTION_SOURCE, snapshots_note))
        else:
            print("%s NOT-ENOUGH-DATA %s" % (base, snapshots_note))
        return 0

    models = sorted({m for _d, bm in intervals for m in bm})
    y = [d for d, _bm in intervals]
    X = [[float(bm.get(m, 0)) for m in models] for _d, bm in intervals]
    w = nnls(X, y)
    pred = [sum(X[i][k] * w[k] for k in range(len(models))) for i in range(len(y))]
    mean_y = sum(y) / len(y)
    sst = sum((v - mean_y) ** 2 for v in y)
    sse = sum((y[i] - pred[i]) ** 2 for i in range(len(y)))
    r2 = (1 - sse / sst) if sst > 0 else float("nan")

    max_abs_corr, degenerate_pairs = 0.0, 0
    for a in range(len(models)):
        for b in range(a + 1, len(models)):
            ca = [X[i][a] for i in range(len(y))]
            cb = [X[i][b] for i in range(len(y))]
            r = _pearson(ca, cb)
            if r is None:
                degenerate_pairs += 1
            else:
                max_abs_corr = max(max_abs_corr, abs(r))

    weights = ",".join("%s=%.8f" % (m, w[k]) for k, m in enumerate(models)) or "-"
    print("%s r2=%.4f max_abs_corr=%.3f degenerate_pairs=%d weights=%s %s%s"
          % (base, r2, max_abs_corr, degenerate_pairs, weights, snapshots_note,
             (" retention_limit_h=%d (%s)" % (RETENTION_LIMIT_H, RETENTION_SOURCE)
              if window == "7d" else "")))
    for k, m in enumerate(models):
        print("  %-28s weight=%.8f Δpct per token  (per 1M tokens: %+.4f)"
              % (m, w[k], w[k] * 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
