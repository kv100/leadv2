#!/usr/bin/env python3
"""Shared lane classifier for leadv2-status-surface.sh.

Pure functions, no I/O, no environment reads, no imports beyond stdlib.
Loaded by both the lanes-table heredoc (_ss_lanes_py) and the single-lead
heredoc (render_single_lead) via exec(open(...).read(), globals()).

classify(facts) -> LaneClass dict is the ONE source of truth for what a lane
is.  Each renderer keeps its own discovery (different input sources), projects
what it found into a LaneFacts dict, and calls classify().  Neither renderer
may branch on ledger state, pid liveness, exit code or terminal token on its
own again.

The branch chain was lifted verbatim from add_row (:1440-1530 of
leadv2-status-surface.sh) and the queued branch from 89217a1.  Byte-identical
cause strings are the contract that keeps the existing suites green.
"""


# Dispatch reservation-ledger writer values (leadv2-dispatch-code.sh).
RES_LIVE_STATES = ("pending", "confirmed")
RES_KNOWN_STATES = RES_LIVE_STATES + ("queued", "reserved")


def age_label(secs):
    """Lanes-path age format: 0s/0m/0h."""
    if secs is None or secs < 0:
        secs = 0
    if secs < 60:
        return "%ds" % int(secs)
    if secs < 5400:
        return "%dm" % (int(secs) // 60)
    return "%dh" % (int(secs) // 3600)


def _is_terminal(status, ledger_state):
    """Mirror of is_terminal() from the lanes heredoc."""
    return status in ("complete", "failed", "cancelled") or \
        ledger_state in ("closed", "failed", "cancelled",
                         "landed", "parked", "refused", "dead", "no_work")


def classify(f):
    """Classify a lane from a LaneFacts dict.

    Returns: {"cls": str, "cause": str, "live": bool, "terminal": bool}

    cls is one of: live, queued, done, dead.
    Every field in *f* is optional; absent means "this renderer has no signal
    for it", which is different from "the signal says no".
    """
    kind = f.get("kind", "")
    now = f.get("now", 0)
    pid = f.get("pid")
    handle = f.get("handle", "")
    ledger_state = f.get("ledger_state", "")
    status = f.get("status", "")
    ec = f.get("exit_code")
    outcome = f.get("outcome", "")
    tcause = f.get("tcause", "")
    terminal_token = f.get("terminal_token", "")

    # ---- process liveness sub-signals (pre-computed by the renderer) ----
    _pid_alive_session = f.get("pid_alive_session", False)
    _pid_alive_handle = f.get("pid_alive_handle", False)
    _argv_alive = f.get("argv_alive", False)
    _close_alive = f.get("close_alive", False)
    _close_pid = f.get("close_pid")
    _close_fresh = f.get("close_fresh", False)
    _close_mtime = f.get("close_mtime")

    max_mtime = f.get("max_mtime")
    motion_mtime = f.get("motion_mtime")

    # ---- dispatch reservation signals (single-lead renderer only) ----
    arm = f.get("arm", "")
    res_state = f.get("res_state", "")
    res_age_s = f.get("res_age_s")
    res_ttl = f.get("res_ttl")
    _arm_assigned = bool(arm) and arm != "unknown"

    # ---- liveness rule (STANDING) — cause never empty, never "?" ----
    if _pid_alive_session:
        cause, cls = "live", "live"
    elif _pid_alive_handle:
        cause, cls = "live(pid %s)" % handle, "live"
    elif _argv_alive:
        cause, cls = "live(argv)", "live"
    elif _close_alive:
        cause, cls = "live(close pid %s)" % _close_pid, "live"
    elif max_mtime is not None and (now - max_mtime) < 120:
        cause, cls = "live(fresh)", "live"
    elif _close_fresh:
        cause = "gate(%s ago)" % age_label(now - _close_mtime)
        cls = "dead"
    elif ec not in (None, ""):
        try:
            eci = int(ec)
            if eci == 0:
                cause, cls = "done(exit=0)", "done"
            else:
                cause, cls = "dead(exit=%d)" % eci, "dead"
        except Exception:
            cause, cls = "dead(no-signal)", "dead"
    elif pid not in (None, "", 0):
        cause, cls = "dead(no-process)", "dead"
    elif res_state in RES_LIVE_STATES and _arm_assigned and not terminal_token \
            and (res_ttl is None or res_age_s is None or res_age_s <= res_ttl):
        cause, cls = "live(dispatch %s)" % res_state, "live"
    elif res_state in RES_LIVE_STATES and res_ttl is not None \
            and res_age_s is not None and res_age_s > res_ttl:
        cause, cls = "expired(%s)" % age_label(res_age_s), "dead"
    elif res_state and res_state not in RES_KNOWN_STATES:
        cause, cls = "foreign(state=%s)" % res_state, "dead"
    elif res_state in RES_LIVE_STATES and not _arm_assigned:
        cause, cls = "queued", "queued"
    elif kind == "worker" and ledger_state in ("pending", "queued", "reserved"):
        cause, cls = "queued", "queued"
    elif motion_mtime is not None:
        cause = "stale(%s silent)" % age_label(now - motion_mtime)
        cls = "dead"
    else:
        cause, cls = "dead(no-signal)", "dead"

    # ---- .outcome overlay (SWIFTBAR-LIVE-01 round 4) ----
    if cls in ("dead", "done"):
        if outcome == "completed":
            cause, cls = "done(completed)", "done"
        elif outcome == "died-with-work":
            cause, cls = "dead(work-left)", "dead"
        elif outcome == "died-clean":
            cause, cls = "dead(died-clean)", "dead"
        elif "?" not in cause:
            cause = cause + "?"

    # ---- N1-EMPTY-LANE-IS-NOT-A-PASS: no_work override ----
    if ledger_state == "no_work":
        _nw = (tcause or "empty-diff").replace("_", "-")
        cause, cls = "no-work(%s)" % _nw, "dead"

    terminal = _is_terminal(status, ledger_state) or (terminal_token != "")

    # ---- terminal last-resort-stale reinterpretation ----
    if terminal and cls == "dead" and cause.startswith("stale(") \
            and ledger_state != "no_work":
        cause = "done(%s)" % (ledger_state or status or "terminal")
        cls = "done"

    return {
        "cls": cls,
        "cause": cause,
        "live": cls == "live",
        "live_process": bool(_pid_alive_session or _pid_alive_handle or _argv_alive or _close_alive),
        "terminal": terminal,
        "unknown": cause.startswith("dead(no-signal)") and not res_state and not terminal_token
                   and pid in (None, "", 0) and ec in (None, "") and motion_mtime is None,
    }


def join_fields(parts, sep=" · "):
    """Join non-empty fields with *sep*.

    An empty/None field never renders its separator, so the output can never
    contain a doubled separator (e.g. '· ·'), a trailing separator,
    or a leading separator.
    """
    return sep.join(
        p for p in (
            str(x).strip() if x is not None else ""
            for x in parts
        ) if p
    )


def clip_name(s, n):
    """Truncate *s* to exactly *n* characters, with a U+2026 (…) marker.

    Any name the renderer shortened carries U+2026 (…).  A rendered name
    that ends in a digit or letter is therefore always the complete task id.
    """
    if len(s) <= n:
        return s
    return s[:n - 1] + "…"
