#!/usr/bin/env python3
"""leadv2-lockout-classify.py — classify a failed arm by failure class.

PROVIDER-LOCKOUT-FALSE-BLOCK-01. Pure stdin -> stdout classifier, no side
effects, ALWAYS exits 0 (a classification failure must never become a dispatch
failure OR a lockout -- the caller treats `unclassified` as "record nothing",
so fail-open here means NO penalty, never an accidental one).

Contract:
  stdin:  the arm's final output text (a launcher's stdout+stderr tail; may be empty).
  argv:   --site postspawn|launcher_refusal|standdown   (required)
          --refusal-reason R   quota-shaped reason forces class provider_refusal
          --probe-rc N         non-zero + empty stdin => launcher_never_started
          --floor-minutes N / --max-minutes N   optional extra clamp, as today's
                               leadv2-quota-error-parse.py (absent => the class
                               table's own env/default minutes and cap govern)
  stdout: exactly one line "<class>|<minutes>|<evidence_marker>"
          class ∈ launcher_never_started|worker_killed|infra_transient|
                  provider_refusal|unclassified
          minutes = the class's BASE minutes (env-overridable, capped by the
          class cap) -- the caller applies strikes escalation and any
          provider-stated time on top; 0 for unclassified (= record nothing).
  exit:   always 0; any internal exception => "unclassified|0|error".

Precedence is top-down and DELIBERATELY inverts the old quota-first rule: a
kill/infra marker outranks a quota marker, because the 2026-08-17 05:49Z
incident was exactly a killed worker whose 60-line tail still carried one
earlier, survived `429` retry line -- and _quota_shaped matching that line
benched GLM for 24h (see leadv2-dispatch-code.sh _quota_shaped / F3 in the
design). A short false lockout self-heals in minutes; a long false one costs
a working day.
"""

import argparse
import os
import re
import sys

# Mirror of _quota_shaped in leadv2-quota-refuse land (leadv2-dispatch-code.sh):
# the PRIMARY quota-refusal pattern set, used as-is per design §3 (non-goal:
# changing the pattern set itself).
_QUOTA_SHAPED_RE = re.compile(
    r"usage limit|quota (exceeded|exhausted|reached)|rate limit(ed)?|"
    r"out of (credits|tokens|quota)|insufficient (credits|quota|balance)|"
    r"too many requests|(^|[^0-9])429([^0-9]|$)|you.?ve hit your (usage|rate) limit",
    re.IGNORECASE)

# The bash caller's refusal-reason vocabulary (_maybe_record_quota_lockout's
# case guard) -- a reason from this set is quota-shaped by construction.
_REFUSAL_REASON_RE = re.compile(r"^(quota|quota_gate|quota_exhausted|rate_limit)", re.IGNORECASE)

# (class, [markers], env-override, default_minutes, cap_minutes). First
# matching class wins -- order IS the precedence.
_CLASSES = (
    ("launcher_never_started",
     [r"command not found", r"no such file or directory", r"permission denied"],
     "LEADV2_LOCKOUT_MIN_LAUNCHER", 10, 30),
    ("worker_killed",
     [r"\bkilled\b", r"\bsigkill\b", r"\bsigterm\b", r"\bterminated\b",
      r"signal 9\b", r"signal 15\b", r"out of memory", r"\boom\b",
      r"bus error", r"segmentation fault"],
     "LEADV2_LOCKOUT_MIN_KILLED", 10, 60),
    ("infra_transient",
     [r"econnreset", r"econnrefused", r"etimedout", r"unexpected eof",
      r"connection closed", r"\btunnel\b", r"\b502\b", r"\b503\b", r"\b504\b",
      r"\bdns\b"],
     "LEADV2_LOCKOUT_MIN_INFRA", 15, 60),
)


def _env_int(name, default):
    raw = os.environ.get(name)
    if raw:
        try:
            v = int(raw)
            if v >= 1:
                return v
        except (TypeError, ValueError):
            pass
    return default


def _provider_refusal_cap(site):
    """provider_refusal is the only site-dependent cap: minutes-scale at
    postspawn (untrusted after-enqueue evidence), hours-scale when the
    launcher itself refused pre-spawn or a stand-down was asserted."""
    if site == "postspawn":
        return _env_int("LEADV2_LOCKOUT_CAP_POSTSPAWN", 60)
    return _env_int("LEADV2_QUOTA_LOCKOUT_MAX_MINUTES", 4320)


def classify(text, site, refusal_reason="", probe_rc=0):
    """-> (class, minutes, evidence). Never raises."""
    try:
        low = text or ""
        # 1. launcher never started: probe failed AND there is no output at all.
        if probe_rc and str(probe_rc) != "0" and not low.strip():
            return ("launcher_never_started", _minutes_for("launcher_never_started", site),
                    "probe_rc_%s_empty_output" % probe_rc)
        # 2. marker classes, top-down precedence.
        for cls, markers, env_name, default_min, cap in _CLASSES:
            for pat in markers:
                m = re.search(pat, low, re.IGNORECASE)
                if m:
                    return (cls, _minutes_for(cls, site), m.group(0).strip().lower())
        # 3. provider refusal: quota-shaped reason wins outright; else the
        #    tail itself must be quota-shaped (the unchanged pattern set).
        if refusal_reason and (_REFUSAL_REASON_RE.match(refusal_reason)
                               or _QUOTA_SHAPED_RE.search(refusal_reason)):
            return ("provider_refusal", _minutes_for("provider_refusal", site), "refusal_reason")
        if _QUOTA_SHAPED_RE.search(low):
            return ("provider_refusal", _minutes_for("provider_refusal", site), "quota_shaped")
        return ("unclassified", 0, "none")
    except Exception:
        return ("unclassified", 0, "error")


def _minutes_for(cls, site):
    if cls == "provider_refusal":
        base = _env_int("LEADV2_QUOTA_LOCKOUT_MINUTES", 30)
        cap = _provider_refusal_cap(site)
    else:
        for c, _m, env_name, default_min, cap in _CLASSES:
            if c == cls:
                base = _env_int(env_name, default_min)
                break
        else:
            return 0
    return max(1, min(base, cap))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True,
                    choices=["postspawn", "launcher_refusal", "standdown"])
    ap.add_argument("--refusal-reason", default="")
    ap.add_argument("--probe-rc", default="0")
    ap.add_argument("--floor-minutes", type=int, default=0)
    ap.add_argument("--max-minutes", type=int, default=0)
    args = ap.parse_args(argv)

    try:
        text = sys.stdin.read()
    except Exception:
        text = ""

    try:
        cls, minutes, evidence = classify(text, args.site, args.refusal_reason, args.probe_rc)
        if args.floor_minutes and args.floor_minutes >= 1:
            minutes = max(minutes, args.floor_minutes)
        if args.max_minutes and args.max_minutes >= 1:
            minutes = min(minutes, args.max_minutes)
        if cls == "unclassified":
            minutes = 0
    except Exception:
        cls, minutes, evidence = "unclassified", 0, "error"
    sys.stdout.write("%s|%d|%s\n" % (cls, minutes, evidence))
    return 0


if __name__ == "__main__":
    sys.exit(main())
