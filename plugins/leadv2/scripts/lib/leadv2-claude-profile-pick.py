#!/usr/bin/env python3
"""leadv2-claude-profile-pick.py — CLAUDE-MULTIPROFILE-QUOTA-02 scorer.

Reads one record per line on stdin (emitted by leadv2-claude-profile-select.sh
after it has probed each registry entry independently):

    <label>\t<config_dir>\t<credential_source>\t<base64 probe JSON | ->\t<identity>

`identity` (T12) is `<subscriptionType>/<email-or-na>` derived by the selector
from the credential itself, never from the label -- it is what actually gets
reported, since a registry label can drift from the account the credential
now serves (a relabeled/re-logged-in slot).

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

UNKNOWN = 101


def score_record(record):
    """Return (score:int, source:"live"|"unknown", window:str|None, pct:float|None)."""
    label, config_dir, cred, payload_b64 = record[:4]
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
        return UNKNOWN, "unknown", None, None
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
        return UNKNOWN, "unknown", None, None
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
        if len(parts) != 5:
            continue
        records.append(parts)
    if not records:
        print("profile=- reason=single_profile")
        return
    scored = [(score_record(r), i, r) for i, r in enumerate(records)]
    (score, source, window, pct), _order, record = min(scored, key=lambda t: (t[0][0], t[1]))
    # The minimum can only be a 101 when EVERY record is unknown.
    if score >= UNKNOWN:
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
    print("profile=%s config_dir=%s score=%d source=%s reason=%s candidates=%d cred=%s identity=%s "
          "binding=%s windows=%s"
          % (record[0], record[1], score, source, reason, len(records), record[2], record[4],
             binding_field, windows_field))


if __name__ == "__main__":
    main()
