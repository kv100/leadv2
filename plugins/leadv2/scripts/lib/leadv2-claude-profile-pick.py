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
import sys

UNKNOWN_TRIABLE = 100
UNKNOWN_COOLING = 101
UNKNOWN = UNKNOWN_COOLING  # back-compat alias -- keep the old name resolvable


def score_record(record):
    """Return (order_key, source, window, pct, usable_now).

    order_key IS the availability comparison (lower ranks first):
      live + readable usable_now -> -usable_now (MORE remaining pct-points
        per hour ranks FIRST -- f1 #2);
      live, no readable rate     -> the window's consumed pct (pre-D2
        proxy, lower first -- legacy payloads keep their old order);
      unknown (NEVER 0 -- f1 #4) -> UNKNOWN_TRIABLE, or UNKNOWN_COOLING.
    """
    label, config_dir, cred, payload_b64 = record[:4]
    cooling = len(record) > 5 and record[5] == "1"
    unknown_key = UNKNOWN_COOLING if cooling else UNKNOWN_TRIABLE
    payload = None
    try:
        payload = json.loads(base64.b64decode(payload_b64).decode())
    except Exception:
        payload = None
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
        return unknown_key, "unknown", None, None, None
    binding = account.get("binding_window")
    if binding in ("five_hour", "seven_day"):
        window = account.get(binding)
        usable = window.get("usable_now") if isinstance(window, dict) else None
        if isinstance(usable, (int, float)) and not isinstance(usable, bool):
            try:
                u = float(usable)
                pct = float(account.get(binding + "_pct"))
                return -u, "live", binding, pct, u
            except (TypeError, ValueError):
                pass
        try:
            pct = float(account.get(binding + "_pct"))
            return pct, "live", binding, pct, None
        except (TypeError, ValueError):
            pass  # fall through to worst-of-both below
    values = []
    for key in ("five_hour_pct", "seven_day_pct"):
        try:
            values.append(float(account.get(key)))
        except (TypeError, ValueError):
            pass
    if not values:
        return unknown_key, "unknown", None, None, None
    worst = max(values)
    return worst, "live", "worst_of_both", worst, None


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
        if len(parts) != 7:
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
    # min over (tier, order_key, registry order) -- fully deterministic.
    # order_key (score_record) IS the availability comparison: -usable_now
    # for live records with a readable rate (highest usable_now first, f1
    # #2), the consumed pct for pct-only legacy records (lowest first --
    # byte-identical to the old selection whenever no record carries
    # usable_now), the 100/101 sentinel for unknown ones.  The tier still
    # ranks ahead of the number, so a demoted/cooling profile loses
    # regardless of its usable_now.
    pick = min(range(len(records)), key=lambda i: (tiers[i], scored[i][0][0], i))
    (order_key, source, window, pct, usable), _order, record = scored[pick]
    # The minimum can only reach UNKNOWN_TRIABLE when EVERY record is unknown.
    if source == "unknown":
        reason = "all_unknown"
    elif window in ("five_hour", "seven_day"):
        reason = "binding_window"
    else:
        reason = "worst_window"
    # f1 #3: rank_by names WHAT ordered the winner and in which direction,
    # so the numbers printed beside it can never be read backwards (the old
    # bare score=67 was a consumed percentage posing as a score).
    if source == "unknown":
        rank_by = "none"              # nothing numeric was compared
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
            binding_field += ",usable_now=" + usable_str
    windows_field = "|".join(
        "%s:%s=%s%s" % (r[0], w or "-", _fmt_pct(p),
                        "" if u is None else ",usable_now=" + _fmt_u(u))
        for (_k, src, w, p, u), _o, r in scored
    )
    # §1.3: printed ONLY when a demote column is present and matched a
    # candidate -- absent means "no demotion in play", which keeps the line
    # byte-identical for every legacy caller and fixture.
    demoted_labels = [r[0] for r in records if len(r) > 6 and r[6] == "1"]
    demoted_field = " demoted=%s" % demoted_labels[0] if demoted_labels else ""
    print("profile=%s config_dir=%s rank_by=%s consumed_pct=%s usable_now=%s source=%s reason=%s candidates=%d cred=%s identity=%s "
          "binding=%s windows=%s%s"
          % (record[0], record[1], rank_by, _fmt_pct(pct), usable_str, source, reason,
             len(records), record[2], record[4],
             binding_field, windows_field, demoted_field))


if __name__ == "__main__":
    main()
