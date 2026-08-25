#!/usr/bin/env python3
"""leadv2-claude-profile-pick.py — CLAUDE-MULTIPROFILE-QUOTA-02 scorer.

Reads one record per line on stdin (emitted by leadv2-claude-profile-select.sh
after it has probed each registry entry independently):

    <label>\t<config_dir>\t<credential_source>\t<base64 probe JSON | ->

Scores each record independently: score = max(five_hour_pct, seven_day_pct)
(worst-window utilisation) of the account the probe marked active; anything
unreadable or status!=ok scores the 101 sentinel (source=unknown).  One
profile's failure never affects another — a record that cannot be parsed
simply scores unknown, it never blanks the run.

Picks the LOWEST score; ties are broken by input (= registry) order, so the
selection is fully deterministic.  Prints exactly one line:

    profile=<label> config_dir=<path> score=<n> source=live|unknown \
    reason=<reason> candidates=<n> cred=<credential_source>

Privacy: config_dir is printed here because it exists ONLY on this stdout and
is consumed by the caller (claude-subsession.sh); the caller journals the label
alone.  Pure module: no env, no filesystem, no network — every input arrives
on stdin, which is what makes T10 (determinism) testable in isolation.
"""
import base64
import json
import sys

UNKNOWN = 101


def score_record(record):
    """Return (score:int, source:"live"|"unknown") for one probe record."""
    label, config_dir, cred, payload_b64 = record
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
        return UNKNOWN, "unknown"
    values = []
    for key in ("five_hour_pct", "seven_day_pct"):
        try:
            values.append(float(account.get(key)))
        except (TypeError, ValueError):
            pass
    if not values:
        return UNKNOWN, "unknown"
    return int(round(max(values))), "live"


def main():
    records = []
    for raw in sys.stdin:
        parts = raw.rstrip("\n").split("\t")
        if len(parts) != 4:
            continue
        records.append(parts)
    if not records:
        print("profile=- reason=single_profile")
        return
    scored = [(score_record(r), i, r) for i, r in enumerate(records)]
    (score, source), _order, record = min(scored, key=lambda t: (t[0][0], t[1]))
    # The minimum can only be a 101 when EVERY record is unknown.
    reason = "all_unknown" if score >= UNKNOWN else "worst_window"
    print("profile=%s config_dir=%s score=%d source=%s reason=%s candidates=%d cred=%s"
          % (record[0], record[1], score, source, reason, len(records), record[2]))


if __name__ == "__main__":
    main()
