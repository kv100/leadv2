#!/usr/bin/env bash
# tests/test-quota-read-anthropic-liveness.sh — D3, TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01
#
# leadv2-quota-read.py's read_anthropic() used to gate its live usage call on
# `accessToken and expiresAt and expiresAt > now_ms`, excluding an account from
# `accounts` entirely -- before ever attempting the call -- whenever the
# keychain's expiresAt looked stale. Measured live 2026-09-03: expiresAt was in
# the past on EVERY ONE of six registered keychain entries, including the one
# actively serving a running session (the CLI refreshes the access token
# in-process without ever rewriting expiresAt back to Keychain), so the field
# is not a reliable liveness signal in this environment. The only thing that
# can prove a credential is dead is trying to use it.
#
# This suite hermetically drives read_anthropic() (no real keychain, no real
# network: _keychain_services/_read_keychain/http_json are monkeypatched, same
# technique as tests/test-smart-routing-v2-t1-t3.py) and proves:
#   T1: an account whose expiresAt is hours in the past, but whose live usage
#       call succeeds, still comes back status=ok with real percentages -- the
#       stale field never short-circuits the attempt.
#   T2: an account with NO accessToken at all is still excluded (there really
#       is nothing to try).
#   T3: an account whose live call genuinely fails (401) still comes back
#       unknown, not ok and not a crash -- the fix does not turn "expiresAt
#       stale" into "assume it's fine without checking".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
READER="${LEADV2_TEST_QUOTA_READ_PY:-${SCRIPTS_ROOT}/leadv2-quota-read.py}"

if [[ ! -f "${READER}" ]]; then
  echo "FAIL: reader not found at ${READER}" >&2
  exit 1
fi

python3 - "${READER}" <<'PY'
import importlib.util
import json
import sys
import time

reader_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("quota_reader_liveness", reader_path)
quota_reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quota_reader)

failures = []


def check(label, cond, detail=""):
    if cond:
        print("[TEST] PASS: %s" % label)
    else:
        failures.append(label)
        print("[TEST] FAIL: %s -- %s" % (label, detail))


now_ms = int(time.time() * 1000)
past_ms = now_ms - 3600_000
future_ms = now_ms + 3600_000

orig_services = quota_reader._keychain_services
orig_keychain = quota_reader._read_keychain
orig_http = quota_reader.http_json


def restore():
    quota_reader._keychain_services = orig_services
    quota_reader._read_keychain = orig_keychain
    quota_reader.http_json = orig_http


# --- T1: stale expiresAt, but the account is actually reachable -------------
quota_reader._keychain_services = lambda: {"Claude Code-credentials"}
quota_reader._read_keychain = lambda service: {
    "claudeAiOauth": {
        "accessToken": "never-printed",
        "expiresAt": past_ms,
        "subscriptionType": "max",
        "rateLimitTier": "max_20x",
    }
}


def fake_http_ok(_url, headers=None, **_kwargs):
    return 200, json.dumps({
        "five_hour": {"utilization": 30, "resets_at": "2099-01-01T00:00:00Z"},
        "seven_day": {"utilization": 40, "resets_at": "2099-01-07T00:00:00Z"},
    })


quota_reader.http_json = fake_http_ok
result = quota_reader.read_anthropic()
check("T1a: stale expiresAt does not block the call -- status=ok",
      result.get("status") == "ok", "status=%r" % result.get("status"))
accts = result.get("accounts") or []
check("T1b: exactly one account reached the live call", len(accts) == 1, "accounts=%r" % accts)
if accts:
    check("T1c: account itself reports status=ok (not excluded pre-probe)",
          accts[0].get("status") == "ok", "account=%r" % accts[0])
    check("T1d: real percentages came back (five_hour_pct=30)",
          accts[0].get("five_hour_pct") == 30, "account=%r" % accts[0])
restore()

# --- T2: no accessToken at all -- nothing to try, correctly excluded --------
quota_reader._keychain_services = lambda: {"Claude Code-credentials"}
quota_reader._read_keychain = lambda service: {
    "claudeAiOauth": {"expiresAt": future_ms, "subscriptionType": "max"}
}
called = {"n": 0}


def fake_http_should_not_run(*_a, **_kw):
    called["n"] += 1
    return 200, "{}"


quota_reader.http_json = fake_http_should_not_run
result = quota_reader.read_anthropic()
check("T2a: no accessToken -> no accounts reached", result.get("accounts") == [],
      "result=%r" % result)
check("T2b: no accessToken -> the live call is never attempted", called["n"] == 0,
      "calls=%d" % called["n"])
restore()

# --- T3: expiresAt stale, but the credential really is dead (401) ----------
quota_reader._keychain_services = lambda: {"Claude Code-credentials"}
quota_reader._read_keychain = lambda service: {
    "claudeAiOauth": {
        "accessToken": "never-printed",
        "expiresAt": past_ms,
        "subscriptionType": "max",
    }
}


def fake_http_401(_url, headers=None, **_kwargs):
    import urllib.error
    raise urllib.error.HTTPError("https://api.anthropic.com/api/oauth/usage", 401,
                                  "unauthorized", {}, None)


quota_reader.http_json = fake_http_401
result = quota_reader.read_anthropic()
accts = result.get("accounts") or []
check("T3a: a genuinely dead token still reaches the call (attempted, not assumed fine)",
      len(accts) == 1, "accounts=%r" % accts)
if accts:
    check("T3b: a genuinely dead token still lands on status=unknown",
          accts[0].get("status") == "unknown", "account=%r" % accts[0])
restore()

if failures:
    print("[TEST] Results: FAIL=%d (%s)" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("[TEST] Results: all liveness checks green")
sys.exit(0)
PY
