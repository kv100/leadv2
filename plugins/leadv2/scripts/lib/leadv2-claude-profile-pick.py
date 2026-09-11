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
`score=` stays the raw window pct; the demotion is visible in the
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

Scores each record independently, preferring the account's own `binding_window`
(TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 D2): leadv2-quota-read.py already
computes, per account, which of five_hour/seven_day will actually constrain it
first (usable_now = remaining_pct / hours_to_reset -- lowest wins), because a
window sitting at a high raw pct but resetting in minutes is not the same risk
as one at the same pct that will not reset for days. Scoring on that window's
own pct means two accounts in symmetric-but-opposite states (5h=90%/weekly=20%
vs 5h=20%/weekly=90%) score differently, as they should, instead of both
collapsing to the same max(). When a payload has no binding_window (older probe
output, or a hermetic fixture predating this field) this falls back to the
original max(five_hour_pct, seven_day_pct) worst-of-both, so pre-D2 callers and
fixtures keep scoring exactly as before. Anything unreadable or status!=ok
scores the 101 sentinel (source=unknown). One profile's failure never affects
another — a record that cannot be parsed simply scores unknown, it never blanks
the run.

Picks the LOWEST score; ties are broken by input (= registry) order, so the
selection is fully deterministic.  Prints exactly one line:

    profile=<label> config_dir=<path> score=<n> source=live|unknown \
    reason=<reason> candidates=<n> cred=<credential_source> identity=<identity> \
    binding=<window>:<pct> windows=<label>:<window>=<pct>|<label>:<window>=<pct>...

`binding=` names the WINNER's own scoring window and pct. `windows=` lists
every candidate's window and pct (D2.4: "a routing decision that cannot be
read back from claude-profile.log did not happen") -- `-` marks a candidate
with no live/parseable window (unknown score).

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
    """Return (score:int, source:"live"|"unknown", window:str|None, pct:float|None)."""
    label, config_dir, cred, payload_b64 = record[:4]
    cooling = len(record) > 5 and record[5] == "1"
    unknown_score = UNKNOWN_COOLING if cooling else UNKNOWN_TRIABLE
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
        return unknown_score, "unknown", None, None
    binding = account.get("binding_window")
    if binding in ("five_hour", "seven_day"):
        try:
            pct = float(account.get(binding + "_pct"))
            return int(round(pct)), "live", binding, pct
        except (TypeError, ValueError):
            pass  # fall through to worst-of-both below
    values = []
    for key in ("five_hour_pct", "seven_day_pct"):
        try:
            values.append(float(account.get(key)))
        except (TypeError, ValueError):
            pass
    if not values:
        return unknown_score, "unknown", None, None
    worst = max(values)
    return int(round(worst)), "live", "worst_of_both", worst


def _fmt_pct(pct):
    return "-" if pct is None else str(int(round(pct)))


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
    # min over (tier, score, registry order) -- fully deterministic, and
    # byte-identical to the old (score, order) selection whenever no record
    # is demoted (every legacy input: tiers are all 0 or 2, and tier 2 was
    # already the strictly-worst 101 sentinel).
    pick = min(range(len(records)), key=lambda i: (tiers[i], scored[i][0][0], i))
    (score, source, window, pct), _order, record = scored[pick]
    # The minimum can only reach UNKNOWN_TRIABLE when EVERY record is unknown.
    if score >= UNKNOWN_TRIABLE:
        reason = "all_unknown"
    elif window in ("five_hour", "seven_day"):
        reason = "binding_window"
    else:
        reason = "worst_window"
    binding_field = "%s:%s" % (window or "-", _fmt_pct(pct))
    windows_field = "|".join(
        "%s:%s=%s" % (r[0], w or "-", _fmt_pct(p))
        for (sc, src, w, p), _o, r in scored
    )
    # §1.3: printed ONLY when a demote column is present and matched a
    # candidate -- absent means "no demotion in play", which keeps the line
    # byte-identical for every legacy caller and fixture.
    demoted_labels = [r[0] for r in records if len(r) > 6 and r[6] == "1"]
    demoted_field = " demoted=%s" % demoted_labels[0] if demoted_labels else ""
    print("profile=%s config_dir=%s score=%d source=%s reason=%s candidates=%d cred=%s identity=%s "
          "binding=%s windows=%s%s"
          % (record[0], record[1], score, source, reason, len(records), record[2], record[4],
             binding_field, windows_field, demoted_field))


if __name__ == "__main__":
    main()
