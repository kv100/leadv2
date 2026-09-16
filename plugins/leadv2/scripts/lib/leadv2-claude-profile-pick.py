#!/usr/bin/env python3
"""leadv2-claude-profile-pick.py — CLAUDE-MULTIPROFILE-QUOTA-02 scorer.

Reads one record per line on stdin (emitted by leadv2-claude-profile-select.sh
after it has probed each registry entry independently):

    <label>\t<config_dir>\t<credential_source>\t<base64 probe JSON | ->\t<identity>\t<cooling 0|1>

`cooling` (TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01) is "1" only when the
selector's OWN cooldown marker says this profile's last live probe returned
a CONFIRMED API error (e.g. an expired credential -> http 401) and the
cooldown window has not yet elapsed -- never for "we simply have no data
yet" (budget exhausted, timeout, malformed JSON). This is what keeps
`unknown != unusable` from degrading into `unknown == hammer it forever`:
an ordinary unknown still COMPETES for selection (UNKNOWN_TRIABLE, below),
but a profile actively cooling after a confirmed failure scores strictly
worse than everything else (UNKNOWN_COOLING) so it is not picked again on
the very next round.

`identity` (T12) is `<subscriptionType>/<email-or-na>` derived by the selector
from the credential itself, never from the label -- it is what actually gets
reported, since a registry label can drift from the account the credential
now serves (a relabeled/re-logged-in slot).

`stale_age_s`/`stale_b64` (429-METER-VERDICT-01 half two, columns 8/9) are
attached by the selector ONLY when the live read was unmeasurable (a
throttled meter, parse failure, budget kill -- never a credential verdict
and never an ok read) and a last-known-good sidecar exists for the identity.
They carry the newest payload whose status was ok.  When NO record is
live-readable, those records re-rank from the stale payload's own numbers
with source=stale (a label, never a live reading) instead of falling through
to demotion order -- measured 2026-09-12: both identities 429, the selector
fell to rank_by=none and self-slot demotion picked the account the founder's
panel showed at 80% over the one at 0%.  A stale-known number still loses to
any live-readable record (stale ranking engages only in the no-live branch),
a cooling record is never rescued by its own stale numbers, and the §1.3
demote-yield margin applies to stale usable_now exactly as to live -- a
stale-but-known gap can trigger the same yield.

`demote` (W1-BALANCER-COVERS-EVERY-ARM-01 §1.3, founder 2026-09-09) is "1"
only on the record whose config_dir IS the config dir of the session doing
the dispatching (the lead's own account -- the one whose window the probe
UNDERESTIMATES, because the lead's spend lands in it with lag, so it looks
freer than it is). The demoted record is ranked LAST but never excluded:
ordering is a TIER on top of the existing score, never a score rewrite --
0 = normal, 1 = demoted, 2 = cooling -- so the session's own account still
wins whenever every other candidate is worse (confirmed-cooling, or no other
candidate at all) and a single live account never stalls work. Reported
`consumed_pct=` stays the raw window pct; the demotion is visible in the
`demoted=<label>` output field, printed ONLY when a demote column is present
in the input, so every legacy 6-column caller and fixture keeps a
byte-identical output line.

TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01: the old single UNKNOWN=101 sentinel
made an unknown-scored profile lose to EVERY live-scored profile regardless
of how exhausted the live one actually was (a profile at 99% used still
"won" over one that was simply never successfully probed) -- an idle,
0%-used account could go unused forever just because its window did not
parse. Now split in two: UNKNOWN_TRIABLE (100) competes fairly -- it loses
only to a live profile with genuine free quota (pct < 100), never to one
that is itself fully exhausted; UNKNOWN_COOLING (101) is strictly worse
than anything, reserved for a profile whose most recent live probe
returned a CONFIRMED error and is still within its cooldown window (see
`cooling` above) -- so a broken credential does not get retried, and does
not get selected, on the very next round either.

Ranks each record on its binding window's `usable_now` -- remaining
percentage-points per hour, MORE is better
(BALANCER-RANKS-BY-THE-WRONG-NUMBER-AND-PRINTS-A-MISLEADING-ONE-01, f1
finding 2: the old raw-pct ranking only agreed with availability by
coincidence -- 56%-used/113h-to-reset beat 67%-used/20h-to-reset even
though the latter has several times the usable capacity per hour).
leadv2-quota-read.py already computes, per account, which of
five_hour/seven_day will constrain it first (`binding_window` = the window
with the LOWEST usable_now); this picker ranks accounts by that window's
OWN usable_now, highest first.  A record whose binding window carries no
readable usable_now (older probe output, or a hermetic fixture predating
the window objects) falls back to the pre-D2 proxy -- ordering on the
window's own pct, lower first, worst-of-both when there is no binding
window -- so legacy callers and fixtures keep exactly the selection they
had.  A measured usable rate always outranks the pct proxy (its order key
-usable_now is <= 0 while every pct is >= 0).  Anything unreadable or
status!=ok ranks on the 100/101 sentinel (source=unknown), NEVER as a zero
(f1 finding 4: a 429 account must not masquerade as 0%-consumed/free
quota).  One profile's failure never affects another -- a record that
cannot be parsed simply ranks unknown, it never blanks the run.

Picks the LOWEST order key; ties are broken by input (= registry) order,
so the selection is fully deterministic.  Prints exactly one line:

    profile=<label> config_dir=<path> rank_by=usable_now_max|consumed_pct_min|none \
    consumed_pct=<n|-> usable_now=<u|-> source=live|unknown reason=<reason> \
    candidates=<n> cred=<credential_source> identity=<identity> \
    binding=<window>:consumed_pct=<p>[,usable_now=<u>] \
    windows=<label>:<window>=<pct>[,usable_now=<u>]|...

`rank_by=` names WHAT was compared and in which direction (f1 finding 3:
the old `score=67` was a consumed percentage presented as a score, so the
number's direction was unreadable from the line).  `binding=` names the
WINNER's own scoring window with both of its numbers labeled.  `windows=`
lists every candidate's window, pct and usable_now (D2.4: "a routing
decision that cannot be read back from claude-profile.log did not
happen") -- `-` marks a candidate with no live/parseable window (unknown
rank).

Privacy: config_dir is printed here because it exists ONLY on this stdout and
is consumed by the caller (claude-subsession.sh); the caller journals the label
alone. `identity` carries subscriptionType/email only -- never a token.
Pure module: no env, no filesystem, no network — every input arrives
on stdin, which is what makes T10 (determinism) testable in isolation.
"""
import base64
import json
import os
import sys

UNKNOWN_TRIABLE = 100
UNKNOWN_COOLING = 101
UNKNOWN = UNKNOWN_COOLING  # back-compat alias -- keep the old name resolvable


def _num(value):
    """Return value as float, or None for missing/bool/non-numeric."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def score_payload(payload):
    """Rank ONE probe payload -> (order_key, source, window, pct, usable_now,
    weekly_usable_now).

    source is "live" only when the payload itself is a readable window;
    otherwise "unknown" and the caller picks the sentinel.  Shared by the
    live read (score_record) and the last-known-good fallback (half two), so
    a stale payload ranks by exactly the same arithmetic as a live one.

    order_key IS the availability comparison (lower ranks first); every key
    is a tuple so live and unknown keys always compare:
      five-hour reserve readable (FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-
        ACCOUNT-CHOICE-01, founder 2026-09-16) -> (-five_hour
        remaining_pct, -seven_day usable_now).  The five-hour window is
        compared as a RESERVE (remaining percentage), never divided by
        hours-to-reset: it answers "how much work can this account absorb
        now".  The weekly window keeps the rate metric -- the near-reset
        burn rule is the founder's and stays -- as the tiebreak, so two
        accounts never rank against each other on different windows;
      live + readable usable_now, no five-hour reserve (legacy binding
        path) -> (-usable_now,) (MORE remaining pct-points per hour ranks
        FIRST -- f1 #2);
      live, no readable rate     -> (the window's consumed pct,) (pre-D2
        proxy, lower first -- legacy payloads keep their old order);
      unknown (NEVER 0 -- f1 #4) -> decided by the caller's sentinel.
    """
    account = None
    if isinstance(payload, dict):
        accounts = payload.get("accounts") or []
        # The relevant account is the one the probe marked active (the
        # keychain path pins it via LEADV2_ANTHROPIC_ACTIVE_SERVICE); a
        # single-account payload (the file: source) is its own active account.
        account = next((a for a in accounts if isinstance(a, dict) and a.get("active")), None)
        if account is None and len(accounts) == 1 and isinstance(accounts[0], dict):
            account = accounts[0]
    if not (isinstance(payload, dict) and payload.get("status") == "ok"
            and isinstance(account, dict) and account.get("status") == "ok"):
        return UNKNOWN_TRIABLE, "unknown", None, None, None, None
    # FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01 (founder
    # 2026-09-16): the "burn it when the reset is near" rule was ordered for
    # the WEEKLY quota only.  The five-hour window decides how much work an
    # account can absorb now and is compared as a reserve (remaining pct),
    # never as a rate -- remaining/168 vs remaining/5 is not commensurable,
    # which is why binding_window (lowest usable_now) was seven_day in every
    # normal state and the five-hour number never reached this comparison.
    _fh = account.get("five_hour")
    fh_reserve = _num(_fh.get("remaining_pct")) if isinstance(_fh, dict) else None
    _sd = account.get("seven_day")
    weekly_usable = _num(_sd.get("usable_now")) if isinstance(_sd, dict) else None
    if fh_reserve is not None:
        # Keep the probe's binding-window fields as display metadata.  They
        # are not the account-to-account order key below, but retaining them
        # keeps the diagnostic surface about the probe itself (and legacy
        # callers) accurate.
        binding = account.get("binding_window")
        binding_window = account.get(binding) if binding in ("five_hour", "seven_day") else None
        binding_usable = (_num(binding_window.get("usable_now"))
                          if isinstance(binding_window, dict) else None)
        try:
            binding_pct = float(account.get(binding + "_pct"))
        except (TypeError, ValueError):
            binding_pct = fh_pct = None
        try:
            fh_pct = float(account.get("five_hour_pct"))
        except (TypeError, ValueError):
            fh_pct = 100.0 - fh_reserve
        # Tiebreak is the weekly rate (founder's allocation key, unchanged
        # units); -1.0 ranks a missing weekly reading below any known one
        # (rates are >= 0).
        return ((-fh_reserve, -(weekly_usable if weekly_usable is not None else -1.0)),
                "live", binding or "five_hour",
                binding_pct if binding_pct is not None else fh_pct,
                binding_usable if binding_usable is not None else weekly_usable,
                weekly_usable)
    binding = account.get("binding_window")
    if binding in ("five_hour", "seven_day"):
        window = account.get(binding)
        usable = window.get("usable_now") if isinstance(window, dict) else None
        if isinstance(usable, (int, float)) and not isinstance(usable, bool):
            try:
                u = float(usable)
                pct = float(account.get(binding + "_pct"))
                return (-u,), "live", binding, pct, u, weekly_usable
            except (TypeError, ValueError):
                pass
        try:
            pct = float(account.get(binding + "_pct"))
            return (pct,), "live", binding, pct, None, weekly_usable
        except (TypeError, ValueError):
            pass  # fall through to worst-of-both below
    values = []
    for key in ("five_hour_pct", "seven_day_pct"):
        try:
            values.append(float(account.get(key)))
        except (TypeError, ValueError):
            pass
    if not values:
        return UNKNOWN_TRIABLE, "unknown", None, None, None, None
    worst = max(values)
    return (worst,), "live", "worst_of_both", worst, None, None


def score_record(record):
    """Return (order_key, source, window, pct, usable_now) for one record.

    Same contract as score_payload, plus the record-level sentinel: an
    unreadable live read is UNKNOWN_TRIABLE, or UNKNOWN_COOLING when the
    selector's cooldown marker says the last live probe returned a confirmed
    credential verdict.  The sentinel keys are 1-tuples so they compare
    against every live key shape.
    """
    label, config_dir, cred, payload_b64 = record[:4]
    cooling = len(record) > 5 and record[5] == "1"
    unknown_key = (UNKNOWN_COOLING,) if cooling else (UNKNOWN_TRIABLE,)
    payload = None
    try:
        payload = json.loads(base64.b64decode(payload_b64).decode())
    except Exception:
        payload = None
    key, source, window, pct, usable, weekly = score_payload(payload)
    if source != "live":
        return unknown_key, "unknown", None, None, None, None
    return key, source, window, pct, usable, weekly


def _fmt_pct(pct):
    return "-" if pct is None else str(int(round(pct)))


def _fmt_u(u):
    return "-" if u is None else "%.3f" % u


def main():
    records = []
    for raw in sys.stdin:
        parts = raw.rstrip("\n").split("\t")
        if len(parts) == 4:
            parts = parts + ["unknown/na"]  # pre-T12 caller (no identity column)
        if len(parts) == 5:
            parts = parts + ["0"]  # pre-cooldown caller (no cooling column)
        if len(parts) == 6:
            parts = parts + ["0"]  # pre-demote caller (no demote column, §1.3)
        if len(parts) == 7:
            # pre-half-two caller (no stale_age_s/stale_b64 columns)
            parts = parts + ["-", "-"]
        if len(parts) != 9:
            continue
        records.append(parts)
    if not records:
        print("profile=- reason=single_profile")
        return

    def _tier(rec):
        """Rank tier (§1.3): 0 normal, 1 demoted (the dispatching session's
        own account -- ranked last, never excluded), 2 cooling. Tier 2 below
        tier 1 keeps the cooldown's own promise: a slot that just failed a
        live probe is not re-picked merely to avoid the lead's window."""
        if rec[5] == "1":
            return 2
        if len(rec) > 6 and rec[6] == "1":
            return 1
        return 0

    scored = [(score_record(r), i, r) for i, r in enumerate(records)]
    tiers = [_tier(r) for r in records]

    # 429-METER-VERDICT-01 half two: when NO record is live-readable, rank
    # from what was last known instead of falling through to demotion order.
    # Records whose live read was unmeasurable may carry a last-known-good
    # payload (columns 8/9); re-score those from the sidecar with
    # source="stale".  A live record anywhere keeps the decision on live
    # numbers only (stale never competes with a live reading), and a cooling
    # record is never rescued -- a confirmed credential verdict makes its
    # stale numbers describe a credential that may no longer exist.
    _live_any = any(s[0][1] == "live" for s in scored)
    if not _live_any:
        for _i, _r in enumerate(records):
            if tiers[_i] == 2 or len(_r) < 9 or _r[8] in ("-", ""):
                continue
            try:
                _spayload = json.loads(base64.b64decode(_r[8]).decode())
            except Exception:
                continue
            _k, _src, _w, _p, _u, _wk = score_payload(_spayload)
            if _src == "live":
                scored[_i] = ((_k, "stale", _w, _p, _u, _wk), scored[_i][1], scored[_i][2])

    # SELF-SLOT-DEMOTION-YIELDS-01 (founder 2026-09-12). The demotion above
    # corrects for ONE thing -- the dispatching session's own spend reaching
    # the probe window late, so its account reads freer than it is. That lag
    # is bounded by the lead's own recent burn, a few points of a window; it
    # must not outrank a large, real capacity gap. Observed 2026-09-12:
    # personal usable_now=0.609 was demoted and work usable_now=0.224 won,
    # and the dispatched arm came back rate_limited at seven_day=0.80.
    # Cooling (tier 2) never yields: a failed live probe is a fact about the
    # account, not a measurement artifact.
    try:
        _margin = float(os.environ.get(
            "LEADV2_CLAUDE_DEMOTE_YIELD_MARGIN", "0.15"))
    except (TypeError, ValueError):
        _margin = 0.15
    _yielded = []

    def _usable_of(idx):
        # SELF-SLOT-DEMOTION-YIELDS-01 units restatement (founder 2026-09-12
        # order, margin 0.15 UNCHANGED): the margin compares the WEEKLY rate
        # (seven_day usable_now, pct-points/hour) so every record enters the
        # comparison in the same units -- FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-
        # ACCOUNT-CHOICE-01 made the ranked quantity a five-hour RESERVE for
        # some records, which would silently rescale a founder-set margin.
        # weekly_usable falls back to the ranked usable only where they are
        # the same number (legacy seven_day-binding records).
        u = scored[idx][0][5]
        if (u is None or isinstance(u, bool) or not isinstance(u, (int, float))) \
                and scored[idx][0][2] == "seven_day":
            u = scored[idx][0][4]
        if isinstance(u, bool) or not isinstance(u, (int, float)):
            return None
        return float(u)

    _normal = [i for i in range(len(records)) if tiers[i] == 0]
    _demoted = [i for i in range(len(records)) if tiers[i] == 1]
    _yield_reason = "gap"
    if _normal and _demoted and _margin >= 0:
        _best_normal = [u for u in (_usable_of(i) for i in _normal)
                        if u is not None]
        if _best_normal:
            _bn = max(_best_normal)
            for _i in _demoted:
                _u = _usable_of(_i)
                if _u is not None and _u - _bn > _margin:
                    tiers[_i] = 0
                    _yielded.append(records[_i][0])
        elif not _live_any and any(_usable_of(i) is not None
                                   for i in _demoted):
            # Half two composition with SELF-SLOT-DEMOTION-YIELDS-01: no
            # normal carries ANY known number (live or stale) -- the choice
            # is a stale-but-known demoted slot vs a fresh nothing.  The
            # demotion corrects a few points of window lag; it must not
            # outvote last-known availability wholesale.  Yield.  Gated on
            # no-live-records so a live readable normal keeps W1 §1.3
            # semantics exactly (an unknown still beats a demoted live
            # slot there -- a founder-drawn line, not mine to move).
            _yield_reason = "no_known_normal"
            for _i in _demoted:
                if _usable_of(_i) is not None:
                    tiers[_i] = 0
                    _yielded.append(records[_i][0])
    # min over (tier, order_key, registry order) -- fully deterministic.
    # order_key (score_record) IS the availability comparison: -usable_now
    # for live records with a readable rate (highest usable_now first, f1
    # #2), the consumed pct for pct-only legacy records (lowest first --
    # byte-identical to the old selection whenever no record carries
    # usable_now), the 100/101 sentinel for unknown ones.  The tier still
    # ranks ahead of the number, so a demoted/cooling profile loses
    # regardless of its usable_now.
    pick = min(range(len(records)), key=lambda i: (tiers[i], scored[i][0][0], i))
    (order_key, source, window, pct, usable, weekly), _order, record = scored[pick]
    _reserve_ranked = isinstance(order_key, tuple) and len(order_key) == 2
    _reserve_live = [s[0][0] for s in scored
                     if s[0][1] in ("live", "stale")
                     and isinstance(s[0][0], tuple) and len(s[0][0]) == 2]
    # If every comparable reserve is identical, the weekly rate alone made
    # the decision; say that rather than claiming the reserve broke the tie.
    _reserve_tie_only = (_reserve_ranked and len(_reserve_live) > 1
                         and len({key[0] for key in _reserve_live}) == 1)
    _sole_live = source == "live" and sum(s[0][1] == "live" for s in scored) == 1
    # The minimum can only reach UNKNOWN_TRIABLE when EVERY record is unknown.
    if source == "unknown":
        reason = "all_unknown"
    elif source == "stale":
        reason = "last_known"  # ranked from the last-known-good sidecar, not live
    elif _reserve_ranked and not (_reserve_tie_only or _sole_live):
        # FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01: the winner was
        # gated on the five-hour reserve with the weekly rate as tiebreak.
        reason = "five_hour_reserve"
    elif window in ("five_hour", "seven_day"):
        reason = "binding_window"
    else:
        reason = "worst_window"
    # f1 #3: rank_by names WHAT ordered the winner and in which direction,
    # so the numbers printed beside it can never be read backwards (the old
    # bare score=67 was a consumed percentage posing as a score).
    if source == "unknown":
        rank_by = "none"              # nothing numeric was compared
    elif _reserve_ranked and not (_reserve_tie_only or _sole_live):
        # more five-hour reserve first, weekly usable_now rate breaks ties
        rank_by = "five_hour_reserve_max"
    elif usable is not None:
        rank_by = "usable_now_max"    # more remaining pct-points/hour first
    else:
        rank_by = "consumed_pct_min"  # legacy fallback: less consumed first
    usable_str = _fmt_u(usable)
    if pct is None:
        binding_field = "-:-"
    else:
        binding_field = "%s:consumed_pct=%d" % (window or "-", int(round(pct)))
        if usable is not None:
            # Name the metric: under five_hour the printed rate is the
            # WEEKLY tiebreak, never the window's own (superseded) rate.
            _label = "weekly_usable_now" if window == "five_hour" else "usable_now"
            binding_field += "," + _label + "=" + usable_str
    windows_field = "|".join(
        "%s:%s=%s%s%s" % (
            r[0], w or "-", _fmt_pct(p),
            "" if u is None else (
                (",weekly_usable_now=" if (isinstance(_k, tuple) and len(_k) == 2
                                           and w == "five_hour")
                 else ",usable_now=") + _fmt_u(u)),
            ",stale" if src == "stale" else "")
        for (_k, src, w, p, u, _wk), _o, r in scored
    )
    # §1.3: printed ONLY when a demote column is present and matched a
    # candidate -- absent means "no demotion in play", which keeps the line
    # byte-identical for every legacy caller and fixture.
    demoted_labels = [r[0] for r in records if len(r) > 6 and r[6] == "1"]
    demoted_field = " demoted=%s" % demoted_labels[0] if demoted_labels else ""
    if _yielded:
        # gap yield keeps the exact legacy shape; the half-two no-known-normal
        # yield prints margin=- plus its reason -- no numeric gap was compared.
        demoted_field += " demote_yielded=%s margin=%s" % (
            _yielded[0], _margin if _yield_reason == "gap" else "-")
        if _yield_reason != "gap":
            demoted_field += " yield_reason=%s" % _yield_reason
    # Half two: the winner's numbers came from the last-known-good sidecar --
    # say HOW old it is so a stale reading is never mistaken for a live one.
    stale_field = ""
    if source == "stale" and len(record) > 7 and record[7] not in ("-", ""):
        stale_field = " stale_age_s=%s" % record[7]
    print("profile=%s config_dir=%s rank_by=%s consumed_pct=%s usable_now=%s source=%s reason=%s candidates=%d cred=%s identity=%s "
          "binding=%s windows=%s%s%s"
          % (record[0], record[1], rank_by, _fmt_pct(pct), usable_str, source, reason,
             len(records), record[2], record[4],
             binding_field, windows_field, demoted_field, stale_field))


if __name__ == "__main__":
    main()
