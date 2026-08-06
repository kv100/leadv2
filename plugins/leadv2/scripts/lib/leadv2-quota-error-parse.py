#!/usr/bin/env python3
"""leadv2-quota-error-parse.py — parse a quota-refusal timestamp out of free text.

CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01. Pure stdin -> stdout parser, no
side effects, ALWAYS exits 0 (a parse failure must never become a dispatch
failure -- the caller falls back to its own flat default when this prints
nothing).

Contract:
  stdin:  free-form refusal/error text (a launcher's stdout+stderr tail).
  argv:   --floor-minutes N (default 30) --max-minutes N (default 4320)
  stdout: a single line "ISO|source" where ISO is YYYY-MM-DDTHH:MM:SSZ and
          source is one of:
            provider_time          -- parsed, already within [floor, max]
            provider_time_clamped  -- parsed, but floor- or ceiling-clamped
          OR nothing at all when no time could be parsed (caller computes its
          own flat default and uses source=default).

Parsing order (first match wins):
  1. ISO-8601 already in the text.
  2. Human absolute date ("Aug 8th, 2026 8:49 AM", "August 8, 2026 08:49").
  3. Relative ("in 3 hours", "try again in 45 minutes", "resets in 2h13m").
  4. Bare time-of-day ("8:49 AM", no date) -> next occurrence from now.

Any of 1/2/4 with NO timezone in the source text is treated as LOCAL time
(via time.localtime/mktime) and converted to UTC. If that instant is in the
past relative to now, 24h is added once; if still in the past, the match is
treated as unparsable and parsing falls through to the next strategy (or to
"nothing parseable" if none match).
"""

import argparse
import re
import sys
import time
from datetime import datetime, timedelta, timezone


def _local_to_utc(dt_naive):
    """Naive local datetime -> naive UTC datetime, via time.mktime."""
    epoch = time.mktime(dt_naive.timetuple())
    return datetime.utcfromtimestamp(epoch)


def _resolve_local_with_past_guard(dt_naive, now_utc):
    """Convert a naive local datetime to UTC; if it lands in the past, add 24h
    once. If STILL in the past, return None (unparsable)."""
    utc_dt = _local_to_utc(dt_naive)
    if utc_dt < now_utc:
        utc_dt = utc_dt + timedelta(hours=24)
        if utc_dt < now_utc:
            return None
    return utc_dt


_ISO_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2})?)(Z|[+-]\d{2}:?\d{2})?"
)


def parse_iso8601(text, now_utc):
    m = _ISO_RE.search(text)
    if not m:
        return None
    date_s, time_s, tz_s = m.group(1), m.group(2), m.group(3)
    if len(time_s) == 5:
        time_s = time_s + ":00"
    if tz_s:
        # Explicit tz in the text -- already unambiguous; normalize to UTC.
        iso = "%sT%s%s" % (date_s, time_s, tz_s.replace("Z", "+00:00"))
        try:
            dt = datetime.fromisoformat(iso)
        except Exception:
            return None
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    # No tz in the text -- treat as local, per the module contract.
    try:
        naive = datetime.strptime("%sT%s" % (date_s, time_s), "%Y-%m-%dT%H:%M:%S")
    except Exception:
        return None
    return _resolve_local_with_past_guard(naive, now_utc)


_ORDINAL_RE = re.compile(r"(\d+)(st|nd|rd|th)\b", re.IGNORECASE)

_ABS_DATE_FORMATS = (
    "%b %d, %Y %I:%M %p",
    "%B %d, %Y %I:%M %p",
    "%b %d, %Y %H:%M",
    "%B %d, %Y %H:%M",
    "%b %d %Y %I:%M %p",
    "%B %d %Y %I:%M %p",
)

# Matches e.g. "Aug 8th, 2026 8:49 AM" / "August 8, 2026 08:49" -- month name,
# day (with optional ordinal, stripped before strptime), year, time.
_ABS_DATE_SCAN_RE = re.compile(
    r"([A-Za-z]{3,9}\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4}\s+\d{1,2}:\d{2}(?:\s*[APap][Mm])?)"
)


def parse_absolute_date(text, now_utc):
    m = _ABS_DATE_SCAN_RE.search(text)
    if not m:
        return None
    candidate = _ORDINAL_RE.sub(r"\1", m.group(1))
    candidate = candidate.replace(".", "").strip()
    for fmt in _ABS_DATE_FORMATS:
        try:
            naive = datetime.strptime(candidate, fmt)
        except Exception:
            continue
        return _resolve_local_with_past_guard(naive, now_utc)
    return None


def parse_relative(text, now_utc):
    # "resets in 2h13m" / "2h 13m" style combined offset.
    m = re.search(r"(\d+)\s*h\s*(\d+)\s*m\b", text, re.IGNORECASE)
    if m:
        return now_utc + timedelta(hours=int(m.group(1)), minutes=int(m.group(2)))
    m = re.search(r"in\s+(\d+)\s*(?:hours?|hrs?|h)\b", text, re.IGNORECASE)
    if m:
        return now_utc + timedelta(hours=int(m.group(1)))
    m = re.search(r"in\s+(\d+)\s*(?:minutes?|mins?|m)\b", text, re.IGNORECASE)
    if m:
        return now_utc + timedelta(minutes=int(m.group(1)))
    return None


_BARE_TIME_RE = re.compile(r"\b(\d{1,2}):(\d{2})\s*([APap][Mm])?\b")


def parse_bare_time(text, now_utc):
    m = _BARE_TIME_RE.search(text)
    if not m:
        return None
    hour = int(m.group(1))
    minute = int(m.group(2))
    ampm = (m.group(3) or "").lower()
    if ampm == "pm" and hour != 12:
        hour += 12
    elif ampm == "am" and hour == 12:
        hour = 0
    if hour > 23 or minute > 59:
        return None
    now_local = datetime.now()
    naive = now_local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return _resolve_local_with_past_guard(naive, now_utc)


def parse_quota_time(text, now_utc=None):
    """Returns a naive UTC datetime, or None if nothing parseable."""
    if now_utc is None:
        now_utc = datetime.utcnow()
    for parser in (parse_iso8601, parse_absolute_date, parse_relative, parse_bare_time):
        try:
            dt = parser(text, now_utc)
        except Exception:
            dt = None
        if dt is not None:
            return dt
    return None


def clamp(dt, now_utc, floor_minutes, max_minutes):
    """Returns (clamped_dt, source)."""
    floor_dt = now_utc + timedelta(minutes=floor_minutes)
    max_dt = now_utc + timedelta(minutes=max_minutes)
    if dt < floor_dt:
        return floor_dt, "provider_time_clamped"
    if dt > max_dt:
        return max_dt, "provider_time_clamped"
    return dt, "provider_time"


def render(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--floor-minutes", type=int, default=30)
    ap.add_argument("--max-minutes", type=int, default=4320)
    args = ap.parse_args(argv)

    try:
        text = sys.stdin.read()
    except Exception:
        text = ""

    now_utc = datetime.utcnow()
    try:
        dt = parse_quota_time(text, now_utc)
    except Exception:
        dt = None

    if dt is None:
        # Nothing parseable -- print nothing; caller applies its own default.
        return 0

    try:
        clamped, source = clamp(dt, now_utc, args.floor_minutes, args.max_minutes)
        sys.stdout.write("%s|%s\n" % (render(clamped), source))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
