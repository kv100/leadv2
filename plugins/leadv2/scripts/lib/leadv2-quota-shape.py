#!/usr/bin/env python3
"""leadv2-quota-shape.py — single source of truth for the live quota payload shape.

C-1 (LANE-CONCURRENCY-IN-PLUGIN), 2026-08-02. The backlog-pump's old `_quota_ok`
read `usable_now`/`remaining_pct` at the TOP level of each provider bucket; those
keys live INSIDE each provider's binding window, so the gate fell through every
loop and refused unconditionally — `pump_refused reason=quota_floor floor=10pct`
all night while all three providers sat at 33–84 % remaining. This module reads
the shape `leadv2-quota-live.sh json` actually emits, per provider, by binding
window — mirroring `leadv2-router-v2.py:bucket_usable_now()` (the live router's
own resolver), never inventing a fourth interpretation.

Importable AND CLI-callable so bash 3.2 (the deployed shell) can use it without
inlining a python heredoc. Fail-open is preserved from today: an
unparseable/unreachable payload PASSES (a quota-reader outage must not become a
total dispatch outage). The difference from today is that a *reachable* provider
now actually produces a verdict.

Per-provider extraction (loop is over whatever buckets the payload contains —
no hardcoded provider allow/deny list):

    glm       -> payload[payload["binding_window"]]["remaining_pct"]
    codex     -> the window whose kind == binding_window, then remaining_pct
                 (limit_reached True or allowed False -> that bucket is 0,
                  hard-refused — a provider that says "stop" is not rescued by a
                  stale healthy-looking percentage)
    anthropic -> active account -> account[account["binding_window"]]["remaining_pct"]
                 (account status != "ok" -> unknown, not 0)
"""

import argparse
import json
import sys


def _num(v):
    """Coerce v to a finite float, or None if not a real number.

    NaN/inf are rejected (math.isfinite) so _render's round() can never throw
    and a corrupt percentage is treated as unknown -> fail-open, not a crash.
    """
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        f = float(v)
        import math
        return f if math.isfinite(f) else None
    return None


def binding_window_of(bucket_payload):
    """The binding-window dict for one provider payload, or None.

    None covers "not a dict", "status != ok" (for the bucket-level status), and
    "no binding window resolved" — all unknown, never fabricated as 0.
    """
    if not isinstance(bucket_payload, dict):
        return None
    binding = bucket_payload.get("binding_window")
    if not binding:
        return None
    provider = bucket_payload.get("provider")
    if provider == "glm":
        win = bucket_payload.get(binding)
        return win if isinstance(win, dict) else None
    if provider == "codex":
        windows = bucket_payload.get("windows") or []
        win = next((w for w in windows if isinstance(w, dict) and w.get("kind") == binding), None)
        return win
    if provider == "anthropic":
        accounts = bucket_payload.get("accounts") or []
        active = next((a for a in accounts if isinstance(a, dict) and a.get("active")), None)
        if not active or active.get("status") != "ok":
            return None
        acct_binding = active.get("binding_window")
        if not acct_binding:
            return None
        win = active.get(acct_binding)
        return win if isinstance(win, dict) else None
    # Unknown provider: fall back to a binding-window-shaped dict if present.
    win = bucket_payload.get(binding)
    return win if isinstance(win, dict) else None


def bucket_remaining_pct(bucket_payload):
    """remaining_pct of this provider's binding window, or None.

    None when status != "ok", no binding window resolves, or the value is not a
    number — never a fabricated 0.

    Special case (codex): `limit_reached` True or `allowed` False means the
    provider is refusing further work. That returns 0.0 (hard-refuse this
    bucket), NOT None — a real "stop" signal is a real verdict.
    """
    if not isinstance(bucket_payload, dict):
        return None
    if bucket_payload.get("status") != "ok":
        return None
    if bucket_payload.get("provider") == "codex":
        if bucket_payload.get("limit_reached") is True or bucket_payload.get("allowed") is False:
            return 0.0
    win = binding_window_of(bucket_payload)
    if win is None:
        return None
    return _num(win.get("remaining_pct"))


def headroom(payload_json):
    """All three (or whatever) buckets -> {bucket: pct_or_None}."""
    try:
        d = json.loads(payload_json)
    except Exception:
        return {}
    if not isinstance(d, dict):
        return {}
    out = {}
    for name, bucket in d.items():
        if not isinstance(bucket, dict):
            continue
        out[name] = bucket_remaining_pct(bucket)
    return out


def _render(pct):
    if pct is None:
        return "unknown"
    return "%d%%" % round(pct)


def gate(floor, payload_json):
    """exit 0 if any bucket's binding-window remaining_pct >= floor.

    exit 1 if all RESOLVED buckets are below floor. exit 0 (fail-open) if the
    payload is unparseable or every bucket is unknown. Returns (verdict_str,
    exit_code). Always prints one line to stdout.
    """
    hr = headroom(payload_json)
    if not hr:
        # Unparseable / empty / no buckets at all -> fail-open.
        print("glm=unknown codex=unknown anthropic=unknown floor=%s verdict=pass" % _render(floor))
        return 0
    resolved = {k: v for k, v in hr.items() if v is not None}
    parts = []
    # Stable, readable ordering: show the known providers first, then others.
    canonical = ("glm", "codex", "anthropic")
    ordered = [b for b in canonical if b in hr] + [b for b in hr if b not in canonical]
    for b in ordered:
        parts.append("%s=%s" % (b, _render(hr[b])))
    floor_s = _render(floor)
    if not resolved:
        # Every bucket unknown (e.g. all providers status != ok) -> fail-open.
        print("%s floor=%s verdict=pass" % (" ".join(parts), floor_s))
        return 0
    passing = any(v >= floor for v in resolved.values())
    verdict = "pass" if passing else "refuse"
    print("%s floor=%s verdict=%s" % (" ".join(parts), floor_s, verdict))
    return 0 if passing else 1


def _stdin_payload():
    return sys.stdin.read()


def main(argv=None):
    p = argparse.ArgumentParser(description="leadv2 quota payload shape reader")
    sub = p.add_subparsers(dest="cmd")

    g = sub.add_parser("gate", help="emit a pass/refuse verdict for a floor")
    g.add_argument("--floor", type=float, required=True)
    g.add_argument("--json-file", help="path to a quota-live json payload")
    g.add_argument("--stdin", action="store_true", help="read payload from stdin")

    h = sub.add_parser("headroom", help="print bucket -> remaining_pct")
    h.add_argument("--json-file", help="path to a quota-live json payload")
    h.add_argument("--stdin", action="store_true", help="read payload from stdin")

    args = p.parse_args(argv)

    if args.cmd in ("gate", "headroom"):
        if args.json_file:
            try:
                with open(args.json_file, encoding="utf-8") as fh:
                    payload = fh.read()
            except Exception:
                if args.cmd == "gate":
                    print("glm=unknown codex=unknown anthropic=unknown floor=%s verdict=pass"
                          % _render(args.floor))
                    return 0
                return 0
        elif args.stdin:
            payload = _stdin_payload()
        else:
            payload = _stdin_payload()
        if args.cmd == "gate":
            return gate(args.floor, payload)
        hr = headroom(payload)
        if not hr:
            print("{}")
            return 0
        print(" ".join("%s=%s" % (k, _render(v)) for k, v in hr.items()))
        return 0

    p.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
