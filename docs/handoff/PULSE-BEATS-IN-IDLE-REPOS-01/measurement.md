# PULSE-BEATS-IN-IDLE-REPOS-01 — the mechanism, measured

**The beat's gate is not broken. Its input lies.** Measured 2026-09-05, minutes
after a reboot that killed every process on this machine.

## What the beat's own reader answers, per repo, right now

The same call the loop makes (`leadv2-lane-heartbeat.sh status --all --json`),
counted the way `_live_lane_count` counts it:

| repo | rows | counted live | shape |
|---|---|---|---|
| leadv2 | 33 | **26** | list |
| persona-engine | 5 | **4** | list |
| respiro-ios | 0 | 0 | list — a REAL zero |
| m3-market | — | — | repo not present |

Every process was killed by the reboot, so 30 of those "live" lanes are not
running. The instrument answers both poles — a real zero in one repo, non-zero in
two — so it is not stuck.

## Why the reader says so, in its own words

Breakdown in leadv2: `dead` 7, `running_stale` 25, `running` 1. Of the 26 counted
live, **24 carry `pid: None`**, and the registry's own `reason` field states the
case exactly:

```
heartbeat age 1440.4m > 25m threshold, no local pid to confirm (non-local arm)
```

1440 minutes is 24 hours. A row whose heartbeat is a day old and which has **no
pid to confirm** is classified `running_stale`, and
`leadv2-single-lead-beat-loop.sh:216-238` counts `running_stale` as live by
design — "a lane whose heartbeat aged past the stale threshold … is
alive-but-slow, precisely when the founder most needs the pulse".

That intent is right for minutes and wrong for a day. The loop then behaves
perfectly correctly on a false premise: `_live_lane_count` returns 26, the zero
streak never starts, and an idle repo beats forever.

Only **2** of the 26 have a pid that resolves at all.

## What this rules out

* Not a missing gate — the loop gates on `>= 1` live lane.
* Not the reader-error fail-open ("blind is not empty"): the reader is not blind
  here. It parses, it answers, and its answer is a confident, specific, wrong
  non-zero.
* Not `ZERO_MAX`: three consecutive real zeros would stop the loop, but a real
  zero never arrives.

A fix that makes the loop "stop beating" would be aimed at the wrong half, and
would break the case that must keep working.

## The paired negative, stated before any change

The row's own requirement, and it is available concretely today:

* **must keep beating** — the 2 rows in leadv2 whose pid resolves. Any change
  that stops the beat for those is wrong regardless of how quiet it makes the
  idle case.
* **must stop beating** — the 24 rows with `pid: None` at an age of 1440m.
* **must remain a real zero** — respiro-ios, 0 rows, which must not become
  "unknown" and start beating.

A fix measured only on the idle repo passes on a beat that was already off.

## Where the fix belongs — not this file, and not mine

The defect is in the **classification**, one level below the beat: a row with no
pid to confirm and an age far beyond the stale threshold is not `alive-but-slow`,
it is *unconfirmable*, and it should carry a verdict the beat does not count as
live (`unknown_stale`), preserving `running_stale` for the recent case it was
written for.

That is `leadv2-lane-heartbeat.sh` (lane state) and possibly the counting line in
`leadv2-single-lead-beat-loop.sh` — neither is in this session's declared zone
(`config/leadv2-routing.yaml`, `leadv2-dispatch-code.sh`, the phase engines), and
an earlier standing instruction pinned an observation window on the beat loop.
Handed to the owner with the measurement rather than edited across the boundary.

**Suggested bound, so the owner need not re-derive it:** confirmable staleness
stays live; unconfirmable staleness (`pid: None`) beyond a small multiple of the
25m threshold does not. At 1440m the current rows are 57× over.
